import SwiftUI

// MARK: - Heatmap Calendar View

struct HeatmapCalendarView: View {
    @StateObject private var viewModel = HeatmapCalendarViewModel()
    @State private var medicationEditorState: CycleTrackingMedicationEditorState?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayHeader
            calendarGrid
            selectedDayDetail
        }
        .background(Color.gsBackground)
        .task {
            await viewModel.fetchMonthData()
        }
        .sheet(item: $medicationEditorState) { editorState in
            NavigationStack {
                CycleTrackingMedicationFormView(editorState: editorState) {
                    Task {
                        await refreshCalendar(dateKey: editorState.defaultDateKey)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.navigateMonth(offset: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.gsEmerald)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(viewModel.monthTitle)
                .font(.headline)
                .foregroundColor(.gsText)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.navigateMonth(offset: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.gsEmerald)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.gsTextSecondary)
                    .frame(height: 20)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            // Leading empty cells for alignment
            ForEach(0..<viewModel.firstWeekday, id: \.self) { _ in
                Color.clear
                    .frame(height: 44)
            }

            // Day cells
            ForEach(viewModel.daysInMonth, id: \.self) { dateKey in
                dayCellView(dateKey: dateKey)
            }
        }
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.2), value: viewModel.currentMonth)
    }

    // MARK: - Day Cell

    private func dayCellView(dateKey: String) -> some View {
        let intensity = viewModel.intensityLevel(for: dateKey)
        let isSelected = viewModel.selectedDate == dateKey
        let isToday = viewModel.isToday(dateKey)
        let hasPurchase = viewModel.hasPurchases(for: dateKey)
        let hasMedication = viewModel.hasMedication(for: dateKey)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.toggleDateSelection(dateKey)
            }
        } label: {
            ZStack {
                // Background based on intensity
                RoundedRectangle(cornerRadius: 8)
                    .fill(intensityColor(level: intensity))

                VStack(spacing: 2) {
                    Text("\(viewModel.dayNumber(from: dateKey))")
                        .font(.caption.weight(isToday ? .bold : .regular))
                        .foregroundColor(intensity > 0 ? .white : .gsTextSecondary)

                    // Purchase indicator dot
                    if hasPurchase {
                        Circle()
                            .fill(Color.gsCyan)
                            .frame(width: 4, height: 4)
                    }
                }

                // Today ring
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gsEmerald, lineWidth: 1.5)
                }

                // Selection ring
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gsText, lineWidth: 2)
                }

                if hasMedication {
                    Circle()
                        .fill(Color.gsWarning)
                        .frame(width: 6, height: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 5)
                        .padding(.trailing, 5)
                }
            }
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Intensity Colors

    private func intensityColor(level: Int) -> Color {
        switch level {
        case 0:
            return Color.gsSurfaceRaised
        case 1:
            return Color.gsEmerald.opacity(0.2)
        case 2:
            return Color.gsEmerald.opacity(0.45)
        case 3:
            return Color.gsEmerald.opacity(0.7)
        case 4:
            return Color.gsEmerald
        default:
            return Color.gsSurfaceRaised
        }
    }

    // MARK: - Selected Day Detail

    @ViewBuilder
    private var selectedDayDetail: some View {
        if let dateKey = viewModel.selectedDate {
            DayDetailView(
                dateKey: dateKey,
                activity: viewModel.selectedDayActivity,
                detail: viewModel.selectedDayDetail,
                isLoadingDetail: viewModel.isLoadingDetail,
                detailError: viewModel.detailError,
                onLogMedication: { selectedDateKey in
                    presentMedicationEditor(dateKey: selectedDateKey, dose: nil)
                },
                onEditMedication: { dose, selectedDateKey in
                    presentMedicationEditor(dateKey: selectedDateKey, dose: dose)
                }
            )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.top, 12)
        }
    }

    private func presentMedicationEditor(dateKey: String, dose: CalendarMedicationDoseDTO?) {
        medicationEditorState = CycleTrackingMedicationEditorState(
            existingDose: dose,
            defaultDateKey: dateKey,
            defaultCycleId: dose?.cycleId
        )
    }

    private func refreshCalendar(dateKey: String) async {
        await viewModel.fetchMonthData()
        if viewModel.selectedDate == dateKey {
            await viewModel.fetchDayDetail(for: dateKey)
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            HeatmapCalendarView()
        }
        .background(Color.gsBackground)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
}
