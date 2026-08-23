import Foundation
import SwiftData

/// 买卖 / 分红 / 再投资 / 送股 / 手续费 / 拆合股流水（事实源）
@Model
final class TransactionRecord {
    @Attribute(.unique) var id: UUID
    var instrumentID: String
    var kindRaw: String
    var tradeDate: Date
    /// 权益登记日（分红/再投资/送股）；非分红类可为 tradeDate
    var recordDate: Date?
    var quantity: Decimal
    /// 登记日有效持仓（分红事件审计字段；0 时对分红类回退用 quantity）
    var sharesOnRecord: Decimal
    var price: Decimal
    var fee: Decimal
    var cashAmount: Decimal
    var splitRatio: Decimal
    /// 流水币种；空则按标的币种
    var currency: String
    var note: String
    var createdAt: Date

    init(
        instrumentID: String,
        kind: TransactionKind,
        tradeDate: Date,
        quantity: Decimal = 0,
        price: Decimal = 0,
        fee: Decimal = 0,
        cashAmount: Decimal = 0,
        splitRatio: Decimal = 1,
        note: String = "",
        recordDate: Date? = nil,
        sharesOnRecord: Decimal = 0,
        currency: String = ""
    ) {
        self.id = UUID()
        self.instrumentID = instrumentID
        self.kindRaw = kind.rawValue
        self.tradeDate = tradeDate
        self.recordDate = recordDate
        self.quantity = quantity
        self.sharesOnRecord = sharesOnRecord
        self.price = price
        self.fee = fee
        self.cashAmount = cashAmount
        self.splitRatio = splitRatio
        self.currency = currency
        self.note = note
        self.createdAt = .now
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .buy }
        set { kindRaw = newValue.rawValue }
    }

    /// 分红事件用于展示/校验的登记日持仓
    var effectiveSharesOnRecord: Decimal {
        if sharesOnRecord > 0 { return sharesOnRecord }
        if kind.isDividendEvent || kind == .bonusShare { return quantity }
        return 0
    }
}
