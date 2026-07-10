import Foundation

enum RetentionEligibility {
    static func expiredItems(
        in items: [CaptureItem],
        managedCaptureKeys: Set<String>,
        cutoff: Date
    ) -> [CaptureItem] {
        items.filter {
            managedCaptureKeys.contains($0.thumbnailCacheKey)
                && !$0.isPinned
                && $0.createdAt < cutoff
        }
    }
}
