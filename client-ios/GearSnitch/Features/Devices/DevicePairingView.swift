import SwiftUI

@MainActor
struct DevicePairingView: View {
    @Environment(\.dismiss) private var dismiss

    private let bleManager: BLEManager

    init(bleManager: BLEManager) {
        self.bleManager = bleManager
    }

    init() {
        self.init(bleManager: BLEManager.shared)
    }

    var body: some View {
        DevicePairingFlowView(bleManager: bleManager) { _ in
            dismiss()
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Pair Device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    bleManager.stopScanning()
                    dismiss()
                }
            }
        }
        .onDisappear {
            bleManager.stopScanning()
        }
    }
}
