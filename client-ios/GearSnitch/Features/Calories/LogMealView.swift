import SwiftUI

struct LogMealView: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: (() -> Void)?

    @State private var mealType = "breakfast"
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var sugar = ""
    @State private var isSaving = false
    @State private var error: String?

    private let mealTypes = ["breakfast", "lunch", "dinner", "snack"]

    var body: some View {
        Form {
            Section {
                Picker("Meal Type", selection: $mealType) {
                    ForEach(mealTypes, id: \.self) { type in
                        Text(type.capitalized).tag(type)
                    }
                }
                .foregroundColor(.gsText)

                HStack {
                    Text("Name")
                        .foregroundColor(.gsText)
                    TextField("e.g. Grilled Chicken", text: $name)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.gsEmerald)
                }

                HStack {
                    Text("Calories")
                        .foregroundColor(.gsText)
                    Spacer()
                    TextField("0", text: $calories)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.gsEmerald)
                        .frame(width: 80)
                    Text("kcal")
                        .foregroundColor(.gsTextSecondary)
                }
            } header: {
                Text("Meal Info")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                macroField(label: "Protein", text: $protein)
                macroField(label: "Carbs", text: $carbs)
                macroField(label: "Fat", text: $fat)
                macroField(label: "Fiber", text: $fiber)
                macroField(label: "Sugar", text: $sugar)
            } header: {
                Text("Macros (optional)")
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
                            Text("Log Meal")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.gsEmerald)
                .disabled(isSaving || name.isEmpty || calories.isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Log Meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func macroField(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gsText)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundColor(.gsEmerald)
                .frame(width: 60)
            Text("g")
                .foregroundColor(.gsTextSecondary)
        }
    }

    private func save() async {
        isSaving = true
        error = nil

        guard let cals = Double(calories) else {
            error = "Enter a valid calorie amount."
            isSaving = false
            return
        }

        let body = LogMealBody(
            name: name,
            calories: cals,
            protein: Double(protein),
            carbs: Double(carbs),
            fat: Double(fat),
            mealType: mealType
        )

        do {
            let _: EmptyData = try await APIClient.shared.request(APIEndpoint.Calories.logMeal(body))
            onSaved?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

#Preview {
    NavigationStack {
        LogMealView()
    }
    .preferredColorScheme(.dark)
}
