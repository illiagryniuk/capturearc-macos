import Foundation

enum ShelfHeaderMetrics {
    static let spacing: CGFloat = 8
    static let minimumTitleWidth: CGFloat = 64

    static func navigationBudget(width: CGFloat, actions: CGFloat, titleIdeal: CGFloat) -> CGFloat {
        max(0, width - actions - spacing * 2 - min(titleIdeal, minimumTitleWidth))
    }
}
