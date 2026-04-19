import SwiftUI

/// In-app privacy policy view. Displays the privacy policy as a scrollable document.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        sectionHeader("Last Updated", detail: "April 2026")

                        policySection("Overview") {
                            "\(AppConfig.appName) is designed with your privacy in mind. We minimize data collection and process as much as possible on your device."
                        }

                        policySection("Data We Collect") {
                            """
                            BrickVision collects minimal data:

                            \u{2022} Camera images: Processed on-device for brick scanning. Images are never uploaded unless you explicitly enable Cloud AI mode.
                            \u{2022} Analytics events: If you opt in, we collect anonymous usage events (e.g., scans started, builds viewed) to improve the app. No personally identifiable information is included.
                            \u{2022} Subscription status: Managed by Apple through StoreKit. We do not store payment information.
                            \u{2022} iCloud data: If you enable iCloud Sync, your inventories and settings are stored in your personal iCloud account, not on our servers.
                            """
                        }

                        policySection("Cloud AI Mode") {
                            """
                            When Cloud AI is enabled in Settings, scan images are sent to Azure AI Services for enhanced recognition. Images are:

                            \u{2022} Transmitted over encrypted HTTPS connections
                            \u{2022} Processed in real-time and not stored on Azure servers
                            \u{2022} Never used for model training without explicit consent
                            \u{2022} Subject to Microsoft's Azure AI privacy policy

                            You can disable Cloud AI at any time in Settings. The app works fully offline.
                            """
                        }

                        policySection("Children's Privacy (COPPA)") {
                            """
                            BrickVision does not require an account to use. We do not knowingly collect personal information from children under 13. The app is designed to be safe for all ages:

                            \u{2022} No account creation required
                            \u{2022} No social features that expose personal information
                            \u{2022} No advertising or ad tracking
                            \u{2022} No third-party data sharing
                            """
                        }
                    }

                    Group {
                        policySection("Data Storage") {
                            """
                            All app data (inventories, scan history, favorites) is stored locally on your device. If you enable iCloud Sync, data is additionally stored in your personal Apple iCloud account.

                            We do not operate servers that store your personal data.
                            """
                        }

                        policySection("Third-Party Services") {
                            """
                            \u{2022} Apple StoreKit: For subscription management
                            \u{2022} Apple iCloud: For optional data sync (user-controlled)
                            \u{2022} Azure AI Services: For optional cloud-based recognition (user-controlled)

                            No advertising networks, social media SDKs, or third-party analytics services are included.
                            """
                        }

                        policySection("Your Rights") {
                            """
                            \u{2022} Opt out of analytics at any time in Settings
                            \u{2022} Disable Cloud AI at any time in Settings
                            \u{2022} Delete all scan history in Settings
                            \u{2022} Disable iCloud Sync at any time in Settings
                            \u{2022} All local data can be removed by deleting the app
                            """
                        }

                        policySection("Contact") {
                            "For privacy questions or data requests, contact: privacy@brickvision.app"
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func policySection(_ title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview {
    PrivacyPolicyView()
}
#endif
