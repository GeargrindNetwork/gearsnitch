import SwiftUI

struct UpdateRequiredView: View {
    let state: ReleaseGateManager.BlockedReleaseState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.gsEmerald.opacity(0.14))
                    .frame(width: 120, height: 120)

                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.gsCyan, .gsEmerald],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.bottom, 32)

            Text("Update Required")
                .font(.title2.bold())
                .foregroundColor(.gsText)
                .padding(.bottom, 12)

            Text("This version of GearSnitch is no longer supported. Update the app to continue using the protected product experience.")
                .font(.body)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                releaseRow(label: "Installed", value: state.installedVersion)
                releaseRow(label: "Required", value: state.requiredVersion)

                if let serverVersion = state.serverVersion {
                    releaseRow(label: "Server", value: serverVersion)
                }
            }
            .padding(20)
            .background(Color.gsSurface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gsBorder, lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)

            if !state.releaseNotes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Release Notes")
                        .font(.headline)
                        .foregroundColor(.gsText)

                    ForEach(state.releaseNotes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color.gsEmerald)
                                .frame(width: 7, height: 7)
                                .padding(.top, 7)

                            Text(note)
                                .font(.subheadline)
                                .foregroundColor(.gsTextSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.gsSurface)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gsBorder, lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    openAppStore()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.app.fill")
                        Text("Update on the App Store")
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [.gsCyan, .gsEmerald],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }

                Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                    Text("Contact Support")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsEmerald)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.gsBackground.ignoresSafeArea())
    }

    private func releaseRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gsText)

            Spacer()

            Text(value)
                .foregroundColor(.gsTextSecondary)
        }
    }

    private func openAppStore() {
        guard let url = URL(string: AppConfig.appStoreURL) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    UpdateRequiredView(
        state: .init(
            installedVersion: "1.0.0",
            requiredVersion: "1.1.0",
            currentVersion: "1.1.0",
            releaseNotes: [
                "Refreshes the shared release metadata contract.",
                "Blocks unsupported clients below the minimum supported version."
            ],
            serverVersion: "1.1.0"
        )
    )
    .preferredColorScheme(.dark)
}
