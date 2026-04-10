import PassKit
import SwiftUI

// MARK: - Apple Pay Button

/// SwiftUI wrapper around `PKPaymentButton` for consistent Apple Pay button rendering.
struct ApplePayButton: UIViewRepresentable {

    let type: PKPaymentButtonType
    let style: PKPaymentButtonStyle
    let action: () -> Void

    init(
        type: PKPaymentButtonType = .buy,
        style: PKPaymentButtonStyle = .black,
        action: @escaping () -> Void
    ) {
        self.type = type
        self.style = style
        self.action = action
    }

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: type, paymentButtonStyle: style)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.didTapButton),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func didTapButton() {
            action()
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ApplePayButton(type: .buy, style: .black) {}
            .frame(height: 50)

        ApplePayButton(type: .checkout, style: .whiteOutline) {}
            .frame(height: 50)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
