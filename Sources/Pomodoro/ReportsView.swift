import SwiftUI
import Charts
import PomodoroCore

/// Reports of completed work sessions as a Swift Charts bar chart, with a
/// toggle between the last 14 days (daily) and the last 8 weeks (weekly sums).
///
/// All aggregation is performed by ``SessionLog`` via the view model; this
/// view only chooses a range and renders the returned buckets.
///
/// See the property-wrapper note in `PomodoroApp.swift` for the desugared
/// `ObservedObject` / `State` declarations.
struct ReportsView: View {
    private var _viewModel: ObservedObject<PomodoroViewModel>
    private var viewModel: PomodoroViewModel { _viewModel.wrappedValue }

    private enum Range: String, CaseIterable, Identifiable {
        case days = "14 days"
        case weeks = "8 weeks"
        var id: String { rawValue }
    }

    // Desugared `@State private var range: Range = .days`.
    private var _range = State<Range>(initialValue: .days)
    private var range: Range { _range.wrappedValue }

    init(viewModel: PomodoroViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    // Loaded lazily per render from the log; cheap for these window sizes.
    private var daily: [DayCount] { viewModel.dailyCounts(days: 14) }
    private var weekly: [WeekCount] { viewModel.weeklyCounts(weeks: 8) }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Range", selection: _range.projectedValue) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Report range")

            Text("Completed work sessions")
                .font(.caption)
                .foregroundStyle(.secondary)

            chart
                .frame(height: 160)
        }
    }

    @ViewBuilder private var chart: some View {
        if isEmpty {
            EmptyReportView()
        } else {
            switch range {
            case .days:
                Chart(daily, id: \.date) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Sessions", day.count)
                    )
                    .foregroundStyle(Color.red.gradient)
                    .accessibilityLabel(Self.dayFormatter.string(from: day.date))
                    .accessibilityValue("\(day.count) sessions")
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.narrow))
                        AxisTick()
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .accessibilityLabel("Completed work sessions per day over the last 14 days")
            case .weeks:
                Chart(weekly) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Sessions", week.count)
                    )
                    .foregroundStyle(Color.red.gradient)
                    .accessibilityLabel("Week of \(Self.dayFormatter.string(from: week.weekStart))")
                    .accessibilityValue("\(week.count) sessions")
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.narrow))
                        AxisTick()
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .accessibilityLabel("Completed work sessions per week over the last 8 weeks")
            }
        }
    }

    private var isEmpty: Bool {
        switch range {
        case .days: return daily.allSatisfy { $0.count == 0 }
        case .weeks: return weekly.allSatisfy { $0.count == 0 }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

/// Placeholder shown when there is no session data to chart.
private struct EmptyReportView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No completed sessions yet")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No completed work sessions to display")
    }
}
