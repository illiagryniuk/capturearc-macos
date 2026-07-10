import Foundation

public enum CaptureDateGroup: Hashable, Sendable {
    case today
    case yesterday
    case day(Date)
}

public struct CaptureSection: Identifiable, Hashable, Sendable {
    public let id: Date
    public let group: CaptureDateGroup
    public let items: [CaptureItem]

    public init(id: Date, group: CaptureDateGroup, items: [CaptureItem]) {
        self.id = id
        self.group = group
        self.items = items
    }
}

public enum CaptureGrouping {
    public static func sections(
        from items: [CaptureItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CaptureSection] {
        let sortedItems = items.sorted(by: newestFirst)
        let groupedItems = Dictionary(grouping: sortedItems) {
            calendar.startOfDay(for: $0.createdAt)
        }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)

        return groupedItems.keys.sorted(by: >).map { day in
            let group: CaptureDateGroup
            if calendar.isDate(day, inSameDayAs: today) {
                group = .today
            } else if let yesterday, calendar.isDate(day, inSameDayAs: yesterday) {
                group = .yesterday
            } else {
                group = .day(day)
            }

            return CaptureSection(id: day, group: group, items: groupedItems[day] ?? [])
        }
    }

    public static func newestFirst(_ lhs: CaptureItem, _ rhs: CaptureItem) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.fileURL.lastPathComponent.localizedStandardCompare(
            rhs.fileURL.lastPathComponent
        ) == .orderedAscending
    }
}
