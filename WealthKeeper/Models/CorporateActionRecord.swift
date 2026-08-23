import Foundation
import SwiftData

/// 行情服务返回的分红/拆股，可同步进本地流水
@Model
final class CorporateActionRecord {
    @Attribute(.unique) var id: String
    var instrumentID: String
    var kindRaw: String
    var exDate: Date
    /// 权益登记日；缺省时与 exDate 相同
    var recordDate: Date?
    /// 每股/每份分红金额，或拆股比例
    var value: Double
    var currency: String
    var source: String
    /// 登记日持仓数量（导入流水时写入）
    var sharesOnRecord: Double
    /// 实际分红金额（导入流水时写入）
    var cashAmount: Double
    /// cash / reinvest；空表示未区分（默认现金）
    var settlementRaw: String
    var importedAsTransaction: Bool
    var createdAt: Date

    init(
        instrumentID: String,
        kind: CorporateActionKind,
        exDate: Date,
        value: Double,
        currency: String,
        source: String,
        recordDate: Date? = nil,
        sharesOnRecord: Double = 0,
        cashAmount: Double = 0,
        settlement: DividendSettlement = .cash
    ) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: Calendar.current.startOfDay(for: exDate))
        self.id = "\(instrumentID):\(kind.rawValue):\(day)"
        self.instrumentID = instrumentID
        self.kindRaw = kind.rawValue
        self.exDate = exDate
        self.recordDate = recordDate ?? exDate
        self.value = value
        self.currency = currency
        self.source = source
        self.sharesOnRecord = sharesOnRecord
        self.cashAmount = cashAmount
        self.settlementRaw = settlement.rawValue
        self.importedAsTransaction = false
        self.createdAt = .now
    }

    var kind: CorporateActionKind {
        get { CorporateActionKind(rawValue: kindRaw) ?? .dividend }
        set { kindRaw = newValue.rawValue }
    }

    var settlement: DividendSettlement {
        get { DividendSettlement(rawValue: settlementRaw) ?? .cash }
        set { settlementRaw = newValue.rawValue }
    }

    var effectiveRecordDate: Date {
        recordDate ?? exDate
    }
}
