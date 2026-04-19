import SwiftUI

/// One-time consent sheet shown the first time a user starts scanning.
/// Sprint C — geolocation. We never auto-prompt again after the user makes
/// a choice (tracked via `ScanSettings.locationConsentPrompted`).
struct LocationConsentSheet: View {
    let onEnable: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text("Remember where you scan?")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("\(AppConfig.appName) can tag scans with their location so you can find pieces by place — like \u{201C}at my friend\u{2019}s house\u{201D} or \u{201C}the bin in the basement.\u{201D}")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 10) {
                consentRow(icon: "lock.shield",
                           text: "Stored only on your device.")
                consentRow(icon: "scope",
                           text: "Coordinates rounded to \u{007E}11\u{00A0}m for privacy.")
                consentRow(icon: "gear",
                           text: "Change anytime in Settings.")
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    onEnable()
                    dismiss()
                } label: {
                    Text("Enable Location")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Not Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(false)
        .onDisappear {
            // If they swiped to dismiss without choosing, treat as "not now"
            // so we don't keep prompting on every scan.
            onDismiss()
        }
    }

    private func consentRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

#Preview {
    LocationConsentSheet(onEnable: {}, onDismiss: {})
}
