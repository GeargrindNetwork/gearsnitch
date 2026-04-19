import SwiftUI

// MARK: - Dosing Calculator View
//
// Journal-only dosing worksheet. Every input is unit-tagged and every
// calculation is surfaced alongside a colored warning banner whenever
// a safety rule trips.
//
// **MEDICAL DISCLAIMER**: GearSnitch is a journal, not medical advice.
// Consult a qualified clinician before injecting anything. Dosing
// math is provided as-is with no warranty.

struct DosingCalculatorView: View {
    @StateObject private var viewModel = DosingCalculatorViewModel()
    @State private var showHistory = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                medicalDisclaimerBanner

                substancePicker

                if viewModel.hasExtremeCautionSubstance {
                    extremeCautionBanner
                }

                inputSection

                outputSection

                warningsSection

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

    private var medicalDisclaimerBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundColor(.gsWarning)

            Text("GearSnitch is a journal, not medical advice. Consult a qualified clinician before injecting anything. Dosing math is provided as-is with no warranty.")
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

    // MARK: - Extreme Caution Banner

    private var extremeCautionBanner: some View {
        let text = viewModel.selectedSubstance?.warningText
            ?? "EXTREME CAUTION! Controlled substance / investigational."
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.title3)
                .foregroundColor(.gsDanger)

            VStack(alignment: .leading, spacing: 4) {
                Text("EXTREME CAUTION!")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.gsDanger)
                Text(text)
                    .font(.caption)
                    .foregroundColor(.gsText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gsDanger.opacity(0.12))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gsDanger.opacity(0.6), lineWidth: 1.5)
        )
    }

    // MARK: - Substance Picker

    private var substancePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Substance")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

            Menu {
                Section("Peptides") {
                    ForEach(viewModel.library.peptides) { s in
                        substanceMenuItem(s)
                    }
                }
                Section("Steroids") {
                    ForEach(viewModel.library.steroids) { s in
                        substanceMenuItem(s)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.selectedSubstance?.name ?? "Custom")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gsText)

                        if let sub = viewModel.selectedSubstance {
                            Text("\(sub.class.displayName) — \(sub.intendedPurpose)")
                                .font(.caption2)
                                .foregroundColor(colorForSeverity(sub.warningSeverity))
                        }
                    }

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

            if let sub = viewModel.selectedSubstance {
                recommendedDoseBadge(for: sub)
            }
        }
        .cardStyle()
    }

    private func substanceMenuItem(_ s: Substance) -> some View {
        Button {
            viewModel.selectedSubstance = s
        } label: {
            HStack {
                Text(s.name)
                if viewModel.selectedSubstance?.id == s.id {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func recommendedDoseBadge(for substance: Substance) -> some View {
        let rec = substance.recommendedDose
        let range = rec.low == rec.high
            ? "\(formatted(rec.low)) \(rec.unit.rawValue)"
            : "\(formatted(rec.low))–\(formatted(rec.high)) \(rec.unit.rawValue)"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("Typical: \(range) • \(rec.frequency) • \(rec.route)")
                    .font(.caption2)
            }
            .foregroundColor(.gsTextSecondary)

            if let notes = rec.notes {
                Text(notes)
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func colorForSeverity(_ s: WarningSeverity) -> Color {
        switch s {
        case .standard: return .gsTextSecondary
        case .caution: return .gsWarning
        case .extremeCaution: return .gsDanger
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(spacing: 16) {
            numericFieldWithUnit(
                label: "Vial Concentration",
                value: $viewModel.vialConcentration,
                unit: $viewModel.vialConcentrationUnit,
                allowedUnits: [.mg, .mcg]
            )

            numericField(
                label: "Vial Volume (after reconstitution)",
                unit: "mL",
                value: $viewModel.vialVolumeMl
            )

            numericFieldWithUnit(
                label: "Desired Dose",
                value: $viewModel.desiredDose,
                unit: $viewModel.desiredDoseUnit,
                allowedUnits: [.mcg, .mg]
            )

            syringeSizePicker
        }
        .cardStyle()
    }

    private var syringeSizePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Syringe Size")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

            Picker("Syringe", selection: $viewModel.syringe) {
                ForEach(SyringeSize.allCases) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func numericFieldWithUnit(
        label: String,
        value: Binding<Double>,
        unit: Binding<DoseUnit>,
        allowedUnits: [DoseUnit]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

            HStack(spacing: 8) {
                TextField("0", value: value, format: .number)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundColor(.gsText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)

                // Inline unit dropdown — this is the founder-requested
                // "inline mg/mcg dropdown selector" control.
                Menu {
                    ForEach(allowedUnits) { u in
                        Button {
                            unit.wrappedValue = u
                        } label: {
                            HStack {
                                Text(u.rawValue)
                                if unit.wrappedValue == u {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(unit.wrappedValue.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gsText)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.gsTextSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gsBackground)
                    .cornerRadius(6)
                }
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
                Text(concentrationPerMlText)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            HStack(spacing: 16) {
                outputTile(
                    label: "Volume to Draw",
                    value: String(format: "%.3f", viewModel.drawVolumeMl),
                    unit: "mL"
                )

                outputTile(
                    label: "Syringe Ticks",
                    value: "\(viewModel.syringeTicks)",
                    unit: "ticks"
                )
            }

            Text(instructionLine)
                .font(.footnote.weight(.medium))
                .foregroundColor(.gsText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    private var concentrationPerMlText: String {
        let mcgPerMl = viewModel.concentrationPerMl
        if mcgPerMl >= 1000 {
            let mgPerMl = mcgPerMl / 1000
            return String(format: "%.2f mg/mL", mgPerMl)
        }
        return String(format: "%.0f mcg/mL", mcgPerMl)
    }

    private var instructionLine: String {
        "Draw \(viewModel.syringeTicks) ticks (\(String(format: "%.3f", viewModel.drawVolumeMl)) mL) from a \(viewModel.syringe.displayName) insulin syringe."
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

    // MARK: - Warnings

    @ViewBuilder
    private var warningsSection: some View {
        if !viewModel.warnings.isEmpty {
            VStack(spacing: 8) {
                ForEach(viewModel.warnings, id: \.self) { warning in
                    warningBanner(warning)
                }
            }
        }
    }

    private func warningBanner(_ warning: DosingWarning) -> some View {
        let (icon, color, title, body) = bannerContent(for: warning)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(color)
                Text(body)
                    .font(.caption)
                    .foregroundColor(.gsText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.6), lineWidth: 1)
        )
    }

    private func bannerContent(for warning: DosingWarning) -> (String, Color, String, String) {
        switch warning {
        case let .exceedsSyringeCapacity(draw, maxMl):
            return (
                "exclamationmark.octagon.fill",
                .gsDanger,
                "EXCEEDS SYRINGE CAPACITY",
                String(format: "Draw of %.3f mL exceeds the %0.1f mL syringe. Use a larger syringe or split the dose.", draw, maxMl)
            )
        case let .aboveRecommendedHigh(high, unit):
            return (
                "exclamationmark.triangle.fill",
                .gsWarning,
                "ABOVE RECOMMENDED DOSE",
                String(format: "Desired dose is above the recommended upper bound (%g %@).", high, unit.rawValue)
            )
        case let .belowPracticalPrecision(draw):
            return (
                "ruler",
                .gsWarning,
                "BELOW PRACTICAL MEASUREMENT",
                String(format: "Calculated draw volume of %.4f mL is below the 0.01 mL smallest tick on a standard insulin syringe. Consider diluting further.", draw)
            )
        case .invalidInputs:
            return (
                "questionmark.circle.fill",
                .gsTextSecondary,
                "INVALID INPUTS",
                "Enter a positive vial concentration, vial volume, and desired dose."
            )
        case let .unitMismatch(u):
            return (
                "arrow.left.arrow.right",
                .gsWarning,
                "UNIT NOT SUPPORTED",
                "This calculator converts between mg and mcg only. The selected substance uses \(u.rawValue) — enter your vial concentration in a matching unit and interpret the draw volume manually."
            )
        }
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
                Text("\(viewModel.syringeTicks) / \(viewModel.syringe.ticksPerFullBarrel) ticks")
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
                                        "\(entry.syringeUnits) ticks",
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

    // MARK: - Helpers

    private func formatted(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}

// MARK: - DosingWarning: Hashable

extension DosingWarning: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .exceedsSyringeCapacity:
            hasher.combine("exceeds")
        case .aboveRecommendedHigh:
            hasher.combine("aboveHigh")
        case .belowPracticalPrecision:
            hasher.combine("belowPrecision")
        case .invalidInputs:
            hasher.combine("invalid")
        case .unitMismatch:
            hasher.combine("unitMismatch")
        }
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
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gsTextSecondary.opacity(0.5))
                    .frame(width: plungerWidth, height: height * 0.6)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gsBorder, lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gsSurfaceRaised)
                        )

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
