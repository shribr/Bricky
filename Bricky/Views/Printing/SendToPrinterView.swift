import SwiftUI

/// Shared "Send to 3D Printer" screen for every model Bricky can export to
/// STL — a single scanned piece, a full build, or a Set Forge generated set.
/// Prepares a correctly sized, hardware-agnostic STL and hands it to the
/// system share sheet; Bricky never talks to a printer or slicer directly.
struct SendToPrinterView: View {
    @StateObject private var viewModel: SendToPrinterViewModel
    @Environment(\.dismiss) private var dismiss

    private struct ShareItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    /// - Parameter stlProvider: Produces the model's binary STL. Called once,
    ///   off the main thread is fine — it runs inside a `.task`.
    init(title: String, stlProvider: @escaping () throws -> Data) {
        _viewModel = StateObject(wrappedValue: SendToPrinterViewModel(title: title, stlProvider: stlProvider))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    modelCard
                    if viewModel.modelSizeMM != nil {
                        buildVolumeSection
                        scaleSection
                        fitStatus
                        slicerTip
                    } else if let error = viewModel.loadError {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView("Preparing model…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Send to 3D Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.modelSizeMM != nil {
                    exportFooter
                        .padding()
                        .background(.regularMaterial)
                }
            }
            .task { viewModel.loadIfNeeded() }
            .sheet(item: Binding(
                get: { viewModel.exportedURL.map(ShareItem.init) },
                set: { newValue in viewModel.exportedURL = newValue?.url }
            )) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    // MARK: - Model card

    private var modelCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "cube.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.legoBlue)
                .frame(width: 70, height: 70)
                .background(
                    LinearGradient(
                        colors: [Color(.secondarySystemGroupedBackground), Color(.tertiarySystemGroupedBackground)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Model")
                    .font(.headline)
                Text("Binary STL · millimeters")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let size = viewModel.modelSizeMM {
                    Text(sizeString(size))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Printer build volume

    private var buildVolumeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRINTER BUILD VOLUME")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                HStack {
                    Text("Printer Profile")
                    Spacer()
                    printerProfileMenu
                }
                .padding()
                Divider().padding(.leading)
                if viewModel.isCustomBedSelected {
                    customBedFields
                } else {
                    HStack {
                        Text("Width × Depth × Height")
                        Spacer()
                        Text(sizeString(viewModel.selectedBed.sizeMM))
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
            Text("Choose Custom for any other printer's build volume.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Right-aligned via the row's `Spacer`, not a fixed frame, so on wide
    /// screens (iPad, landscape) the menu sizes to its own content and every
    /// printer name is shown on one line. Only `.lineLimit(1)` guards against
    /// wrapping on the narrowest phones, where it truncates instead.
    private var printerProfileMenu: some View {
        Menu {
            ForEach(SendToPrinterViewModel.presets, id: \.name) { preset in
                Button {
                    viewModel.selectPreset(preset)
                } label: {
                    if !viewModel.isCustomBedSelected && viewModel.selectedBed.name == preset.name {
                        Label(preset.name, systemImage: "checkmark")
                    } else {
                        Text(preset.name)
                    }
                }
            }
            Button {
                viewModel.selectCustomBed()
            } label: {
                if viewModel.isCustomBedSelected {
                    Label("Custom Build Volume", systemImage: "checkmark")
                } else {
                    Text("Custom Build Volume")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.isCustomBedSelected ? "Custom" : viewModel.selectedBed.name)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .accessibilityLabel("Printer Profile: \(viewModel.isCustomBedSelected ? "Custom" : viewModel.selectedBed.name)")
    }

    private var customBedFields: some View {
        HStack(spacing: 12) {
            customField(label: "Width", value: $viewModel.customWidthMM)
            customField(label: "Depth", value: $viewModel.customDepthMM)
            customField(label: "Height", value: $viewModel.customHeightMM)
        }
        .padding()
    }

    private func customField(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                TextField(label, value: value, format: .number)
                    .keyboardType(.decimalPad)
                Text("mm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Model scale

    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MODEL SCALE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                scaleRow(title: "Original Size", isSelected: viewModel.useOriginalSize, trailing: "100%") {
                    viewModel.useOriginalSize = true
                }
                Divider().padding(.leading)
                scaleRow(
                    title: "Scale Down to Fit Bed",
                    isSelected: !viewModel.useOriginalSize,
                    trailing: viewModel.needsScalingOption ? "\(viewModel.fitScalePercent)%" : nil
                ) {
                    viewModel.useOriginalSize = false
                }
                .opacity(viewModel.needsScalingOption ? 1 : 0.4)
                .disabled(!viewModel.needsScalingOption)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
            Text("Scaling changes dimensions and LEGO compatibility.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func scaleRow(title: String, isSelected: Bool, trailing: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .foregroundStyle(Color.legoBlue)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.legoBlue : Color(.tertiaryLabel))
            }
            .padding()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fit status & slicer tip

    private var fitStatus: some View {
        Group {
            if viewModel.willFitAfterChoice {
                Label("Model fits the selected build volume", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Label(overageMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.legoOrange)
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    /// States exactly how far over the model is on its worst axis — e.g.
    /// "...by 12mm in height" — instead of a generic "doesn't fit". The
    /// per-axis overage this reads from comes from `PrintBed.overageMM(for:)`.
    private var overageMessage: String {
        let fallback = "Model exceeds the selected build volume — choose Scale Down to Fit Bed or a larger printer"
        guard let over = viewModel.overageMM else { return fallback }
        let axes: [(label: String, mm: Float)] = [("width", over.x), ("depth", over.y), ("height", over.z)]
        guard let worst = axes.max(by: { $0.mm < $1.mm }), worst.mm > 0 else { return fallback }
        let overMM = Int(worst.mm.rounded(.up))
        return "Model exceeds the \(viewModel.selectedBed.name) build volume by \(overMM)mm in \(worst.label) " +
            "— choose Scale Down to Fit Bed or a larger printer"
    }

    private var slicerTip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("In your slicer, check orientation, supports and fit.")
            Text("For \(viewModel.selectedBed.name): \(viewModel.selectedBed.slicerHint).")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.legoBlue.opacity(0.08)))
    }

    // MARK: - Export

    private var exportFooter: some View {
        VStack(spacing: 6) {
            Button {
                viewModel.exportForSharing()
            } label: {
                Group {
                    if viewModel.isExporting {
                        ProgressView()
                    } else {
                        Text("Open / Share STL")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .background(Color.legoBlue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .buttonStyle(.plain)
            .disabled(viewModel.isExporting)
            .accessibilityLabel("Open or share the printable STL file")

            Text("Save to Files or AirDrop to your slicer computer.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let error = viewModel.exportError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func sizeString(_ size: SIMD3<Float>) -> String {
        String(format: "%.0f × %.0f × %.0f mm", size.x, size.y, size.z)
    }
}
