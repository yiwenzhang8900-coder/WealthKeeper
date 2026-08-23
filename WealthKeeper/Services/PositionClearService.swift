import Foundation
import SwiftData

/// 清空持仓：只追加卖出/到期赎回流水，不删除标的与历史记录。
enum PositionClearService {
    /// 股票 / 基金：按当前市价（无行情则用成本）全量卖出。
    @MainActor
    static func clearSecurityHolding(
        instrumentID: String,
        quantity: Decimal,
        price: Decimal,
        context: ModelContext
    ) {
        guard quantity > 0 else { return }
        let px = price > 0 ? price : 0
        let tx = TransactionRecord(
            instrumentID: instrumentID,
            kind: .sell,
            tradeDate: .now,
            quantity: quantity,
            price: px,
            fee: 0,
            cashAmount: quantity * px,
            note: "清空持仓"
        )
        context.insert(tx)
        do {
            try context.save()
            PortfolioEngine.rebuildPositions(
                transactions: try context.fetch(FetchDescriptor<TransactionRecord>()),
                context: context
            )
        } catch {
            AppLog.error("clear security holding failed: \(error.localizedDescription)")
        }
    }

    /// 债券：主动卖出清仓，或到期赎回清仓。保留债券实体与历史流水。
    @MainActor
    static func clearBondHolding(
        _ item: BondHolding,
        mode: BondClearMode,
        context: ModelContext
    ) {
        let proceeds = max(item.currentValuation, item.cost)
        guard proceeds > 0 || item.faceValue > 0 else { return }

        let kind: ManualCapitalEventKind
        let note: String
        switch mode {
        case .sell:
            kind = .withdraw
            note = "卖出清仓"
        case .maturityRedeem:
            kind = .maturityRedeem
            note = "到期赎回清仓"
        }

        context.insert(
            ManualCapitalEvent(
                assetID: item.id,
                assetClass: .bond,
                kind: kind,
                amount: proceeds > 0 ? proceeds : item.cost,
                currency: item.currency,
                note: note
            )
        )
        item.faceValue = 0
        item.cost = 0
        item.marketValue = 0
        item.accruedInterest = 0
        item.updatedAt = .now
        do {
            try context.save()
        } catch {
            AppLog.error("clear bond holding failed: \(error.localizedDescription)")
        }
    }
}

enum BondClearMode {
    case sell
    case maturityRedeem
}
