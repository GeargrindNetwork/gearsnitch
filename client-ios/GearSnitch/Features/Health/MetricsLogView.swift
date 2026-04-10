import SwiftUI

struct MetricsLogView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var weight = ""
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var didSave = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Weight")
                        .foregroundColor(.gsText)
                    Spacer()
                    TextField("0", text: $weight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.gsEmerald)
                        .frame(width: 80)
                    Text("lbs")
                        .foregroundColor(.gsTextSecondary)
                }

                HStack {
                    Text("Height")
                        .foregroundColor(.gsText)
                    Spacer()
                    TextField("0", text: $heightFeet)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.gsEmerald)
                        .frame(width: 40)
                    Text("ft")
                        .foregroundColor(.gsTextSecondary)
                    TextField("0", text: $heightInches)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.gsEmerald)
                        .frame(width: 40)
                    Text("in")
                        .foregroundColor(.gsTextSecondary)
                }
            } header: {
                Text("Enter Your Measurements")
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
                            Text("Save")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.gsEmerald)
                .disabled(isSaving || (weight.isEmpty && heightFeet.isEmpty))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Log Metrics")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: didSave) { saved in
            if saved { dismiss() }
        }
    }

    private func save() async {
        isSaving = true
        error = nil

        var payloads: [HealthMetricPayload] = []
        let now = Date()

        if let w = Double(weight), w > 0 {
            payloads.append(HealthMetricPayload(
                type: "weight", value: w, unit: "lbs",
                startDate: now, endDate: now, source: "manual"
            ))
        }

        let feet = Double(heightFeet) ?? 0
        let inches = Double(heightInches) ?? 0
        let totalInches = (feet * 12) + inches
        if totalInches > 0 {
            let meters = totalInches * 0.0254
            payloads.append(HealthMetricPayload(
                type: "height", value: meters, unit: "m",
                startDate: now, endDate: now, source: "manual"
            ))
        }

        guard !payloads.isEmpty else {
            error = "Enter at least one measurement."
            isSaving = false
            return
        }

        do {
            let _: EmptyData = try await APIClient.shared.request(
                APIEndpoint.Health.sync(metrics: payloads)
            )
            didSave = true
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

#Preview {
    NavigationStack {
        MetricsLogView()
    }
    .preferredColorScheme(.dark)
}
