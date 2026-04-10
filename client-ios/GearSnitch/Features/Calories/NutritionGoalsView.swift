import SwiftUI

struct NutritionGoalsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var calorieTarget = "2000"
    @State private var proteinTarget = "150"
    @State private var carbsTarget = "250"
    @State private var fatTarget = "65"
    @State private var fiberTarget = "30"
    @State private var waterTargetMl = "3000"
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                goalField(label: "Calories", text: $calorieTarget, unit: "kcal")
                goalField(label: "Protein", text: $proteinTarget, unit: "g")
                goalField(label: "Carbs", text: $carbsTarget, unit: "g")
                goalField(label: "Fat", text: $fatTarget, unit: "g")
                goalField(label: "Fiber", text: $fiberTarget, unit: "g")
            } header: {
                Text("Daily Targets")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                goalField(label: "Water", text: $waterTargetMl, unit: "ml")
            } header: {
                Text("Hydration")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            if let error {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }
                .listRowBackground(Color.gsSurface)
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().tint(.black)
                        } else {
                            Text("Save Goals")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.gsEmerald)
                .disabled(isSaving)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Nutrition Goals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func goalField(label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gsText)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .foregroundColor(.gsEmerald)
                .frame(width: 70)
            Text(unit)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .frame(width: 30, alignment: .leading)
        }
    }

    private func save() async {
        isSaving = true
        error = nil

        let goals: [String: String] = [
            "calorieTarget": calorieTarget,
            "proteinTarget": proteinTarget,
            "carbsTarget": carbsTarget,
            "fatTarget": fatTarget,
            "fiberTarget": fiberTarget,
            "waterTargetMl": waterTargetMl,
        ]

        let body = UpdateUserBody(preferences: goals)

        do {
            let _: UserDTO = try await APIClient.shared.request(APIEndpoint.Users.updateMe(body))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

#Preview {
    NavigationStack {
        NutritionGoalsView()
    }
    .preferredColorScheme(.dark)
}
