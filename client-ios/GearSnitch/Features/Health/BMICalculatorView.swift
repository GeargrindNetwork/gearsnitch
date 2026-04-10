import SwiftUI

struct BMICalculatorView: View {
    @State private var weightLbs = ""
    @State private var heightFeet = ""
    @State private var heightInches = ""

    private var bmi: Double? {
        guard let weight = Double(weightLbs), weight > 0 else { return nil }
        let feet = Double(heightFeet) ?? 0
        let inches = Double(heightInches) ?? 0
        let totalInches = (feet * 12) + inches
        guard totalInches > 0 else { return nil }
        return (weight / (totalInches * totalInches)) * 703
    }

    private var bmiCategory: (String, Color) {
        guard let bmi else { return ("Enter your measurements", .gsTextSecondary) }
        switch bmi {
        case ..<18.5: return ("Underweight", .gsCyan)
        case 18.5..<25: return ("Normal", .gsSuccess)
        case 25..<30: return ("Overweight", .gsWarning)
        default: return ("Obese", .gsDanger)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Result display
                VStack(spacing: 12) {
                    if let bmi {
                        Text(String(format: "%.1f", bmi))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(bmiCategory.1)

                        Text(bmiCategory.0)
                            .font(.headline)
                            .foregroundColor(bmiCategory.1)
                    } else {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 48))
                            .foregroundColor(.gsTextSecondary)

                        Text(bmiCategory.0)
                            .font(.subheadline)
                            .foregroundColor(.gsTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .cardStyle()

                // Scale
                if bmi != nil {
                    bmiScale
                }

                // Input
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weight (lbs)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.gsTextSecondary)

                        TextField("e.g. 175", text: $weightLbs)
                            .keyboardType(.decimalPad)
                            .font(.title3)
                            .foregroundColor(.gsText)
                            .padding(12)
                            .background(Color.gsSurfaceRaised)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gsBorder, lineWidth: 1)
                            )
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Feet")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.gsTextSecondary)

                            TextField("5", text: $heightFeet)
                                .keyboardType(.numberPad)
                                .font(.title3)
                                .foregroundColor(.gsText)
                                .padding(12)
                                .background(Color.gsSurfaceRaised)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gsBorder, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Inches")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.gsTextSecondary)

                            TextField("10", text: $heightInches)
                                .keyboardType(.numberPad)
                                .font(.title3)
                                .foregroundColor(.gsText)
                                .padding(12)
                                .background(Color.gsSurfaceRaised)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gsBorder, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("BMI Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - BMI Scale

    private var bmiScale: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.gsCyan).frame(width: geometry.size.width * 0.25)
                        Rectangle().fill(Color.gsSuccess).frame(width: geometry.size.width * 0.25)
                        Rectangle().fill(Color.gsWarning).frame(width: geometry.size.width * 0.25)
                        Rectangle().fill(Color.gsDanger).frame(width: geometry.size.width * 0.25)
                    }
                    .frame(height: 8)
                    .cornerRadius(4)

                    // Indicator
                    if let bmi {
                        let position = min(max((bmi - 14) / 26, 0), 1)
                        Circle()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                            .shadow(radius: 2)
                            .offset(x: geometry.size.width * position - 7)
                    }
                }
            }
            .frame(height: 14)

            HStack {
                Text("< 18.5")
                Spacer()
                Text("18.5")
                Spacer()
                Text("25")
                Spacer()
                Text("30+")
            }
            .font(.caption2)
            .foregroundColor(.gsTextSecondary)
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    NavigationStack {
        BMICalculatorView()
    }
    .preferredColorScheme(.dark)
}
