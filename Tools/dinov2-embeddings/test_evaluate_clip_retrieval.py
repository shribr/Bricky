import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

import torch


MODULE_PATH = Path(__file__).resolve().parent / "evaluate_clip_retrieval.py"
SPEC = importlib.util.spec_from_file_location("evaluate_clip_retrieval", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load module spec for {MODULE_PATH}")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class EvaluateClipRetrievalTests(unittest.TestCase):
    def test_load_clip_index_matches_metadata(self):
        matrix, ids, meta = MODULE.load_clip_index(MODULE.DEFAULT_INDEX_DIR)
        self.assertEqual(matrix.shape, (meta["count"], meta["dim"]))
        self.assertEqual(len(ids), meta["count"])
        self.assertEqual(meta["model"], "Armaggheddon/clip-vit-base-patch32_lego-minifigure")
        self.assertGreater(meta["count"], 10000)

    def test_collect_queries_discovers_populated_suites(self):
        queries_by_suite, skipped = MODULE.collect_queries([
            "real_photos_eval",
            "bricklink_eval",
            "bricklink_images",
            "huggingface_captions",
        ])

        self.assertEqual(skipped, {})
        self.assertIn("real_photos_eval", queries_by_suite)
        self.assertIn("bricklink_eval", queries_by_suite)
        self.assertIn("bricklink_images", queries_by_suite)
        self.assertIn("huggingface_captions", queries_by_suite)

        self.assertGreater(len(queries_by_suite["real_photos_eval"]), 20)
        self.assertGreater(len(queries_by_suite["bricklink_eval"]), 150)
        self.assertGreater(len(queries_by_suite["bricklink_images"]), 150)
        self.assertGreater(len(queries_by_suite["huggingface_captions"]), 10000)

    def test_real_photo_queries_point_to_existing_files(self):
        queries_by_suite, _ = MODULE.collect_queries(["real_photos_eval"])
        real_photo_queries = queries_by_suite["real_photos_eval"]
        self.assertTrue(all(query.image_path.exists() for query in real_photo_queries))
        self.assertTrue(all(query.figure_id.startswith("fig-") for query in real_photo_queries))

    def test_unknown_suite_is_reported_as_skipped(self):
        queries_by_suite, skipped = MODULE.collect_queries(["does_not_exist"])
        self.assertEqual(queries_by_suite, {})
        self.assertEqual(skipped["does_not_exist"], "unknown suite")

    def test_write_summary_merges_partial_runs(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            report_dir = Path(temp_dir)
            MODULE.write_summary(report_dir, {
                "skipped": {},
                "real_photos_eval": {"suite": "real_photos_eval", "recall@1": 0.16},
            })
            MODULE.write_summary(report_dir, {
                "skipped": {},
                "bricklink_images": {"suite": "bricklink_images", "recall@1": 0.65},
            })

            summary = json.loads((report_dir / "clip_summary.json").read_text())
            self.assertEqual(summary["real_photos_eval"]["recall@1"], 0.16)
            self.assertEqual(summary["bricklink_images"]["recall@1"], 0.65)
            self.assertEqual(summary["last_run_suites"], ["bricklink_images"])

    @unittest.skipUnless(
        os.environ.get("BRICKY_RUN_MODEL_TESTS") == "1",
        "Set BRICKY_RUN_MODEL_TESTS=1 to run the CLIP model-backed smoke test.",
    )
    def test_clip_smoke_predictions_on_known_real_photos(self):
        queries_by_suite, _ = MODULE.collect_queries(["real_photos_eval"])
        queries = queries_by_suite["real_photos_eval"]
        target_variants = {
            "sw0201_clone_trooper_phase_one.jpeg": "fig-000058",
            "sp033_mtron_astronaut_a.jpeg": "fig-000065",
        }
        selected = [query for query in queries if query.variant in target_variants]
        self.assertEqual(len(selected), 2)

        matrix, ids, meta = MODULE.load_clip_index(MODULE.DEFAULT_INDEX_DIR)
        device = MODULE.choose_device("auto")
        model, processor = MODULE.load_model(meta["model"], device)
        matrix_t = torch.from_numpy(matrix).to(device)

        suite_report = MODULE.evaluate_suite(
            suite_name="smoke_real_photos",
            queries=selected,
            matrix_t=matrix_t,
            ids=ids,
            model=model,
            processor=processor,
            device=device,
            batch_size=2,
            detect_bbox=True,
        )

        self.assertEqual(suite_report["queries_scored"], 2)
        predictions = {row["variant"]: row for row in suite_report["predictions"]}
        for variant, expected_id in target_variants.items():
            self.assertIn(variant, predictions)
            self.assertEqual(predictions[variant]["top5"][0]["figure_id"], expected_id)


if __name__ == "__main__":
    unittest.main()