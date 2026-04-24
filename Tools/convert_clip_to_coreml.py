#!/usr/bin/env python3
"""
Convert the LEGO-specific CLIP model to CoreML format for on-device inference.

Model: Armaggheddon/clip-vit-base-patch32_lego-minifigure
- Fine-tuned CLIP ViT-B/32 on 12,966 LEGO minifigure images
- 512-D image embeddings (vs DINOv2's 384-D)
- MIT license

Outputs:
  - LegoClipVision.mlpackage  — image encoder (224×224 RGB → 512-D embedding)

Usage:
    python3 Tools/convert_clip_to_coreml.py
"""

import torch
import numpy as np
import coremltools as ct
from transformers import CLIPModel, CLIPProcessor
from pathlib import Path
import json

REPO_ROOT = Path(__file__).resolve().parent.parent
MODEL_NAME = "Armaggheddon/clip-vit-base-patch32_lego-minifigure"
OUTPUT_DIR = REPO_ROOT / "Bricky" / "Resources"


def main():
    print(f"Loading CLIP model: {MODEL_NAME}")
    model = CLIPModel.from_pretrained(MODEL_NAME)
    processor = CLIPProcessor.from_pretrained(MODEL_NAME)
    model.eval()

    # We only need the vision encoder for on-device use.
    # The text encoder is useful for zero-shot but too large for mobile.
    vision_model = model.vision_model
    visual_projection = model.visual_projection

    print(f"Vision model loaded. Embedding dim: {visual_projection.out_features}")

    # Create a wrapper that does: image -> vision_model -> projection -> L2-normalize
    class CLIPVisionEncoder(torch.nn.Module):
        def __init__(self, vision_model, visual_projection):
            super().__init__()
            self.vision_model = vision_model
            self.visual_projection = visual_projection

        def forward(self, pixel_values):
            vision_outputs = self.vision_model(pixel_values=pixel_values)
            # Use the pooled output (CLS token)
            pooled_output = vision_outputs.pooler_output
            # Project to shared embedding space
            image_embeds = self.visual_projection(pooled_output)
            # L2 normalize
            image_embeds = image_embeds / image_embeds.norm(dim=-1, keepdim=True)
            return image_embeds

    encoder = CLIPVisionEncoder(vision_model, visual_projection)
    encoder.eval()

    # Trace with a dummy input (CLIP uses 224×224)
    print("Tracing model with dummy input...")
    dummy_input = torch.randn(1, 3, 224, 224)
    with torch.no_grad():
        traced = torch.jit.trace(encoder, dummy_input)

    # Verify traced output
    with torch.no_grad():
        orig_out = encoder(dummy_input)
        traced_out = traced(dummy_input)
        diff = (orig_out - traced_out).abs().max().item()
        print(f"Trace verification — max diff: {diff:.8f}")
        assert diff < 1e-5, f"Trace mismatch: {diff}"

    # Convert to CoreML
    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, 224, 224),
                scale=1.0 / 255.0,  # Will be further normalized below
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[
            ct.TensorType(name="embedding", dtype=np.float32)
        ],
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
    )

    # Add metadata
    mlmodel.author = "Armaggheddon (fine-tuned), converted for Bricky"
    mlmodel.license = "MIT"
    mlmodel.short_description = (
        "CLIP ViT-B/32 fine-tuned on 12,966 LEGO minifigure images. "
        "Produces 512-D L2-normalized embeddings for minifigure identification."
    )
    mlmodel.version = "1.0"

    # Note: CLIP uses specific normalization (mean=[0.48145466, 0.4578275, 0.40821073],
    # std=[0.26862954, 0.26130258, 0.27577711]). We'll handle this in Swift since
    # CoreML ImageType scale only supports uniform scaling.
    # The model expects pixel values pre-normalized by the CLIP processor.

    output_path = OUTPUT_DIR / "LegoClipVision.mlpackage"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output_path))

    print(f"\nCoreML model saved to: {output_path}")
    
    # Validate
    print("Validating CoreML model...")
    loaded = ct.models.MLModel(str(output_path))
    spec = loaded.get_spec()
    print(f"  Input: {spec.description.input[0].name} — {spec.description.input[0].type.WhichOneof('Type')}")
    print(f"  Output: {spec.description.output[0].name}")
    print(f"  Model size: {sum(f.stat().st_size for f in output_path.rglob('*') if f.is_file()) / 1024 / 1024:.1f} MB")

    # Save normalization constants for Swift
    norm_info = {
        "model": MODEL_NAME,
        "input_size": 224,
        "embedding_dim": 512,
        "normalization": {
            "mean": [0.48145466, 0.4578275, 0.40821073],
            "std": [0.26862954, 0.26130258, 0.27577711]
        },
        "notes": "Image must be resized to 224x224, converted to RGB float [0,1], then normalized with mean/std before inference. Output is L2-normalized 512-D embedding."
    }
    norm_path = OUTPUT_DIR / "LegoClipVision_config.json"
    with open(norm_path, "w") as f:
        json.dump(norm_info, f, indent=2)
    print(f"Config saved to: {norm_path}")

    # Quick sanity: run a test image through both PyTorch and CoreML
    print("\nRunning end-to-end validation...")
    from PIL import Image
    test_img_dir = REPO_ROOT / "Tools" / "datasets" / "huggingface-lego-captions" / "images"
    test_images = list(test_img_dir.glob("*.jpg"))[:3]
    
    if test_images:
        for img_path in test_images:
            img = Image.open(img_path).convert("RGB")
            
            # PyTorch path
            inputs = processor(images=img, return_tensors="pt")
            with torch.no_grad():
                pt_embed = encoder(inputs["pixel_values"])
            pt_vec = pt_embed[0].numpy()
            
            print(f"  {img_path.name}: PyTorch embedding shape={pt_vec.shape}, "
                  f"norm={np.linalg.norm(pt_vec):.4f}, "
                  f"first 5 values: {pt_vec[:5]}")
    else:
        print("  No test images available (download HuggingFace dataset first)")

    print("\n✅ CLIP → CoreML conversion complete!")
    print(f"   Model: {output_path}")
    print(f"   Config: {norm_path}")


if __name__ == "__main__":
    main()
