import SwiftUI

// MARK: - WorkoutActivityPicker
//
// Lightweight reusable picker for `WorkoutActivityType`. Rendered as a
// vertically scrolling list of rows — each row shows the SF Symbol + display
// name. Selection is driven by a `Binding<WorkoutActivityType>` so the
// picker slots into both start-workout and edit-workout flows.
//
// This view is deliberately presentation-only; no networking or side effects.

struct WorkoutActivityPicker: View {

    @Binding var selection: WorkoutActivityType

    /// Optional subset of activities to surface (defaults to all cases).
    var activities: [WorkoutActivityType] = WorkoutActivityType.allCases

    var body: some View {
        List(activities) { activity in
            Button {
                selection = activity
            } label: {
                row(activity)
            }
            .listRowBackground(Color.gsSurface)
            .listRowSeparatorTint(Color.gsBorder)
        }
        .listStyle(.plain)
        .background(Color.gsBackground.ignoresSafeArea())
    }

    private func row(_ activity: WorkoutActivityType) -> some View {
        HStack(spacing: 14) {
            Image(systemName: activity.sfSymbol)
                .font(.title3)
                .foregroundColor(.gsEmerald)
                .frame(width: 40, height: 40)
                .background(Color.gsEmerald.opacity(0.12))
                .cornerRadius(10)

            Text(activity.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)

            Spacer()

            if activity == selection {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.gsEmerald)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(activity == selection ? [.isSelected] : [])
    }
}

#Preview {
    StatefulPreviewWrapper(WorkoutActivityType.running) { binding in
        WorkoutActivityPicker(selection: binding)
            .preferredColorScheme(.dark)
    }
}

// MARK: - Preview helper

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
