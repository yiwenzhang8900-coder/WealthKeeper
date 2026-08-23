import Foundation
import SwiftData

/// 由交易流水汇总出的当前持仓缓存
@Model
final class Position {
    @Attribute(.unique) var instrumentID: String
    var quantity: Decimal
    var averageCost: Decimal
    var totalCost: Decimal
    var realizedPnL: Decimal
    var totalDividends: Decimal
    var totalFees: Decimal
    var updatedAt: Date

    init(instrumentID: String) {
        self.instrumentID = instrumentID
        self.quantity = 0
        self.averageCost = 0
        self.totalCost = 0
        self.realizedPnL = 0
        self.totalDividends = 0
        self.totalFees = 0
        self.updatedAt = .now
    }
}
