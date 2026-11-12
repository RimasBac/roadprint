import SwiftUI
import RoadPrintCore

/// The trips of one calendar month.
struct TripMonth: Identifiable, Equatable {
    /// The first moment of the month.
    let id: Date
    let rows: [TripRowData]
}

extension TripRowData {
    /// Groups rows by calendar month. Months and rows keep the order they arrive in (newest first).
    static func byMonth(_ rows: [TripRowData], calendar: Calendar = .current) -> [TripMonth] {
        var order: [Date] = []
        var groups: [Date: [TripRowData]] = [:]
        for row in rows {
            let key = calendar.dateInterval(of: .month, for: row.date)?.start ?? row.date
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        return order.map { TripMonth(id: $0, rows: groups[$0] ?? []) }
    }
}

/// Every saved trip, by month (SCREENS.md P10). Tapping one opens it.
struct AllTripsView: View {
    let model: RecordingModel

    @Environment(\.appEnvironment) private var environment

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: RPSpace.xl) {
                if model.rows.isEmpty {
                    Text("No trips yet. Tap Start Trip before you roll.")
                        .font(RPType.body)
                        .foregroundStyle(Color.RP.textSecondary)
                        .accessibilityIdentifier("allTripsEmpty")
                }
                ForEach(TripRowData.byMonth(model.rows)) { month in
                    VStack(alignment: .leading, spacing: RPSpace.m) {
                        Text(month.id, format: .dateTime.month(.wide).year())
                            .font(RPType.cardTitle)
                            .tracking(RPType.cardTitleTracking)
                            .textCase(RPType.cardTitleCase)
                            .foregroundStyle(Color.RP.textSecondary)
                            .accessibilityAddTraits(.isHeader)
                        TripListView(rows: month.rows, unit: environment.profile.distanceUnit,
                                     rowIdentifier: "allTripsRow")
                    }
                }
            }
            .padding(RPSpace.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.RP.background.ignoresSafeArea())
        .navigationTitle("All trips")
        .navigationBarTitleDisplayMode(.inline)
    }
}
