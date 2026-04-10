import SwiftUI

struct DosingCalculatorView: View {
    @StateObject private var viewModel = DosingCalculatorViewModel()
    @State private var showHistory = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                disclaimerBanner

                substancePicker

                inputSection

                outputSection

                syringeVisual

                actionButtons
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Dosing Calculator")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showHistory) {
            doseHistorySheet
        }
    }

    // MARK: - Disclaimer

    private var disclaimerBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundColor(.gsWarning)

            Text("For research purposes only. Consult a healthcare professional.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gsWarning.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gsWarning.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Substance Picker

    private var substancePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Substance")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

            Menu {
                ForEach(Substance.allCases) { substance in
                    Button {
                        viewModel.selectedSubstance = substance
                    } label: {
                        HStack {
                            Text(substance.rawValue)
                            if viewModel.selectedSubstance == substance {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.selectedSubstance.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsText)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
                .padding(14)
                .background(Color.gsSurfaceRaised)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gsBorder, lineWidth: 1)
                )
            }

            Text(viewModel.selectedSubstance.info)
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .cardStyle()
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(spacing: 16) {
            numericField(
                label: "Vial Concentration",
                unit: viewModel.selectedSubstance.concentrationLabel,
                value: $viewModel.concentration
            )

            numericField(
                label: "Desired Dose",
                unit: viewModel.selectedSubstance.unitLabel,
                value: $viewModel.desiredDose
            )

            Toggle(isOn: $viewModel.isReconstituting) {
                Text("Reconstituting from powder")
                    .font(.subheadline)
                    .foregroundColor(.gsText)
            }
            .tint(.gsEmerald)

            if viewModel.isReconstituting {
                numericField(
                    label: "Reconstitution Volume",
                    unit: "mL",
                    value: $viewModel.reconstitutionVolume
                )
            }
        }
        .cardStyle()
    }

    private func numericField(label: String, unit: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

            HStack {
                TextField("0", value: value, format: .number)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundColor(.gsText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)

                Text(unit)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            .padding(12)
            .background(Color.gsSurfaceRaised)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gsBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Output Section

    private var outputSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("CALCULATION")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.gsTextSecondary)
                    .tracking(1)
                Spacer()
            }

            HStack(spacing: 16) {
                outputTile(
                    label: "Volume to Draw",
                    value: String(format: "%.3f", viewModel.volumeToInject),
                    unit: "mL"
                )

                outputTile(
                    label: "Syringe Units",
                    value: "\(viewModel.syringeUnits)",
                    unit: "units"
                )
            }
        }
        .cardStyle()
    }

    private func outputTile(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)

            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundColor(.gsEmerald)

            Text(unit)
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.gsEmerald.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Syringe Visual

    private var syringeVisual: some View {
        VStack(spacing: 8) {
            HStack {
                Text("SYRINGE FILL")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.gsTextSecondary)
                    .tracking(1)
                Spacer()
                Text("\(viewModel.syringeUnits) / 100 units")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            SyringeIndicator(fillFraction: viewModel.syringeFillFraction)
                .frame(height: 40)
        }
        .cardStyle()
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.saveDose()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Log Dose")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.gsEmerald)
                .cornerRadius(12)
            }

            Button {
                showHistory = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.gsSurfaceRaised)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gsBorder, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Dose History Sheet

    private var doseHistorySheet: some View {
        NavigationStack {
            Group {
                if viewModel.doseHistory.isEmpty {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "No Dose History",
                        description: "Logged doses will appear here."
                    )
                } else {
                    List {
                        ForEach(viewModel.doseHistory, id: \.id) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.substanceName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.gsText)

                                    Spacer()

                                    Text(entry.timestamp, style: .relative)
                                        .font(.caption2)
                                        .foregroundColor(.gsTextSecondary)
                                }

                                HStack(spacing: 16) {
                                    Label(
                                        String(format: "%.0f dose", entry.desiredDose),
                                        systemImage: "syringe"
                                    )
                                    Label(
                                        String(format: "%.3f mL", entry.volumeInjected),
                                        systemImage: "drop"
                                    )
                                    Label(
                                        "\(entry.syringeUnits) units",
                                        systemImage: "ruler"
                                    )
                                }
                                .font(.caption)
                                .foregroundColor(.gsTextSecondary)
                            }
                            .listRowBackground(Color.gsSurface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.gsBackground.ignoresSafeArea())
            .navigationTitle("Dose History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.doseHistory.isEmpty {
                        Button("Clear") {
                            viewModel.clearHistory()
                        }
                        .foregroundColor(.gsDanger)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showHistory = false
                    }
                    .foregroundColor(.gsEmerald)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Syringe Indicator

struct SyringeIndicator: View {
    let fillFraction: Double

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let barrelWidth = totalWidth * 0.85
            let needleWidth = totalWidth * 0.12
            let plungerWidth = totalWidth * 0.03
            let height = geometry.size.height

            HStack(spacing: 0) {
                // Plunger handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gsTextSecondary.opacity(0.5))
                    .frame(width: plungerWidth, height: height * 0.6)

                // Barrel
                ZStack(alignment: .leading) {
                    // Barrel outline
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gsBorder, lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gsSurfaceRaised)
                        )

                    // Fill level
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [fillColor.opacity(0.6), fillColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, barrelWidth * fillFraction))
                        .padding(2)

                    // Tick marks
                    HStack(spacing: 0) {
                        ForEach(0..<10, id: \.self) { i in
                            Spacer()
                            if i < 9 {
                                Rectangle()
                                    .fill(Color.gsTextSecondary.opacity(0.3))
                                    .frame(width: 1, height: i % 5 == 4 ? height * 0.5 : height * 0.3)
                            }
                        }
                        Spacer()
                    }
                }
                .frame(width: barrelWidth, height: height * 0.5)

                // Needle
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.gsTextSecondary.opacity(0.6), Color.gsTextSecondary.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: needleWidth, height: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var fillColor: Color {
        if fillFraction > 0.8 {
            return .gsDanger
        } else if fillFraction > 0.5 {
            return .gsWarning
        }
        return .gsEmerald
    }
}

#Preview {
    NavigationStack {
        DosingCalculatorView()
    }
    .preferredColorScheme(.dark)
}
