import SwiftUI
import PhotosUI

/// Sprint 5 / F6 — One-time wizard that captures the user's environmental
/// rendition of common LEGO colors so the recognition pipeline can adapt.
///
/// User picks a LegoColor → snaps/imports a photo of a known piece in that
/// color → we extract the average RGB inside a center crop → store it.
struct ColorCalibrationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ColorCalibrationStore.shared

    /// Colors offered for calibration (subset of LegoColor.allCases).
    private let colorsToCalibrate: [LegoColor] = [
        .red, .blue, .yellow, .green, .black, .white, .gray, .darkGray,
        .orange, .brown, .tan, .lime, .purple, .pink, .lightBlue
    ]

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickerColor: LegoColor?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Photograph a known LEGO piece in each color under your typical lighting. We'll average the center 20% of the image to record your environment's color rendition.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Calibrate Colors") {
                    ForEach(colorsToCalibrate, id: \.self) { color in
                        row(for: color)
                    }
                }

                if store.isCalibrated {
                    Section {
                        Button(role: .destructive) {
                            store.clearAll()
                        } label: {
                            Label("Clear All Calibration", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Color Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .photosPicker(isPresented: photosBinding, selection: $pickerItem, matching: .images)
            .task(id: pickerItem) { await processPicked() }
        }
    }

    private var photosBinding: Binding<Bool> {
        Binding(
            get: { pickerColor != nil && pickerItem == nil },
            set: { active in
                if !active { pickerColor = nil }
            }
        )
    }

    private func row(for color: LegoColor) -> some View {
        let sample = store.sample(for: color)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.legoColor(color))
                    .frame(width: 32, height: 32)
                if sample != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.legoGreen).frame(width: 16, height: 16))
                        .offset(x: 12, y: -12)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(color.rawValue)
                    .font(.subheadline.weight(.medium))
                if let sample {
                    Text("Captured " + sample.capturedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not calibrated")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if sample != nil {
                // Color swatch showing the user-captured rendition.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: sample!.uiColor))
                    .frame(width: 24, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
            }
            Button {
                pickerColor = color
            } label: {
                Image(systemName: "camera.fill")
                    .foregroundStyle(Color.legoBlue)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Picker handling

    private func processPicked() async {
        guard let item = pickerItem,
              let color = pickerColor,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            pickerItem = nil
            pickerColor = nil
            return
        }
        if let avg = ColorCalibrationWizardView.averageColor(from: image) {
            store.recordSample(for: color, uiColor: avg)
        }
        pickerItem = nil
        pickerColor = nil
    }

    // MARK: - Average color helper (center 20% crop)

    /// Average RGB from the center 20% of the image. Internal so tests can
    /// reach it.
    static func averageColor(from image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let cropW = max(1, width / 5)
        let cropH = max(1, height / 5)
        let cropX = (width - cropW) / 2
        let cropY = (height - cropH) / 2
        guard let cropped = cgImage.cropping(to: CGRect(x: cropX, y: cropY,
                                                        width: cropW, height: cropH))
        else { return nil }

        let bytesPerRow = cropW * 4
        var pixels = [UInt8](repeating: 0, count: cropW * cropH * 4)
        guard let ctx = CGContext(data: &pixels,
                                  width: cropW,
                                  height: cropH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: cropW, height: cropH))

        var rTotal: UInt64 = 0
        var gTotal: UInt64 = 0
        var bTotal: UInt64 = 0
        let pixelCount = cropW * cropH
        for i in 0..<pixelCount {
            let base = i * 4
            rTotal += UInt64(pixels[base])
            gTotal += UInt64(pixels[base + 1])
            bTotal += UInt64(pixels[base + 2])
        }
        let count = Double(pixelCount)
        return UIColor(
            red: CGFloat(Double(rTotal) / count / 255.0),
            green: CGFloat(Double(gTotal) / count / 255.0),
            blue: CGFloat(Double(bTotal) / count / 255.0),
            alpha: 1
        )
    }
}
