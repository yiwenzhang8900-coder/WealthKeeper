import Foundation
import SwiftData

@Model
final class CachedQuote {
    @Attribute(.unique) var instrumentID: String
    var symbol: String
    var marketRaw: String
    /// 未复权收盘价或基金净值
    var closeOrNAV: Decimal
    var currency: String
    /// 兼容字段：行情时间
    var asOf: Date
    var previousClose: Decimal
    var isStale: Bool
    var updatedAt: Date

    /// 交易所时区交易日 yyyy-MM-dd
    var marketDate: String = ""
    var exchangeTimeZone: String = ""
    var quoteTimestamp: Date
    var isOfficialClose: Bool = false

    init(
        instrumentID: String,
        symbol: String,
        market: Market,
        closeOrNAV: Decimal,
        currency: String,
        asOf: Date,
        previousClose: Decimal = 0,
        isStale: Bool = false,
        marketDate: String = "",
        exchangeTimeZone: String = "",
        quoteTimestamp: Date? = nil,
        isOfficialClose: Bool = false
    ) {
        self.instrumentID = instrumentID
        self.symbol = symbol
        self.marketRaw = market.rawValue
        self.closeOrNAV = closeOrNAV
        self.currency = currency
        self.asOf = asOf
        self.previousClose = previousClose
        self.isStale = isStale
        self.updatedAt = .now
        self.marketDate = marketDate.isEmpty
            ? TradingCalendar.marketDateString(for: asOf, market: market)
            : marketDate
        self.exchangeTimeZone = exchangeTimeZone.isEmpty
            ? TradingCalendar.timeZoneID(for: market)
            : exchangeTimeZone
        self.quoteTimestamp = quoteTimestamp ?? asOf
        self.isOfficialClose = isOfficialClose
    }

    var market: Market {
        get { Market(rawValue: marketRaw) ?? .cnA }
        set { marketRaw = newValue.rawValue }
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var id: String
    /// 展示本位币；计算统一先折 CNY
    var baseCurrency: String
    var lastMarketRefresh: Date?
    var autoImportCorporateActions: Bool
    /// JSON：{"USD":{"rateToCNY":"7.2450"},"HKD":{"rateToCNY":"0.9270"},"CNY":{"rateToCNY":"1"}}
    var fxJSON: String
    var lastFXRefresh: Date?
    var fxSource: String = ""
    var useMockMarketData: Bool = false
    /// 最近一次行情诊断（不含持仓隐私）
    var lastMarketDiag: String = ""

    init() {
        self.id = "default"
        self.baseCurrency = "CNY"
        self.lastMarketRefresh = nil
        self.autoImportCorporateActions = true
        self.fxJSON = #"{"CNY":{"rateToCNY":"1"}}"#
        self.lastFXRefresh = nil
        self.fxSource = ""
        self.lastMarketDiag = ""
        #if targetEnvironment(simulator)
        self.useMockMarketData = true
        #else
        self.useMockMarketData = false
        #endif
    }

    /// currency -> rateToCNY（1 单位外币 = 多少 CNY）
    var rateToCNYMap: [String: Decimal] {
        get {
            guard let data = fxJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ["CNY": 1]
            }
            var out: [String: Decimal] = ["CNY": 1]
            for (code, value) in obj {
                if let dict = value as? [String: Any], let s = dict["rateToCNY"] as? String, let d = Decimal(string: s) {
                    out[code.uppercased()] = d
                } else if let n = value as? Double { // 兼容旧格式
                    out[code.uppercased()] = Decimal(n)
                } else if let s = value as? String, let d = Decimal(string: s) {
                    out[code.uppercased()] = d
                }
            }
            out["CNY"] = 1
            return out
        }
        set {
            var payload: [String: [String: String]] = [:]
            for (code, rate) in newValue {
                payload[code.uppercased()] = ["rateToCNY": "\(rate)"]
            }
            payload["CNY"] = ["rateToCNY": "1"]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let str = String(data: data, encoding: .utf8) {
                fxJSON = str
            }
        }
    }

    func rateToCNY(for currency: String) -> Decimal {
        let code = currency.uppercased()
        if code == "CNY" { return 1 }
        return rateToCNYMap[code] ?? 1
    }

    /// 是否已有该币种对人民币汇率（缺省时 `rateToCNY` 仍回落为 1，但应提示用户）
    func hasKnownRate(for currency: String) -> Bool {
        let code = currency.uppercased()
        if code == "CNY" { return true }
        return rateToCNYMap[code] != nil
    }

    /// 兼容旧调用名
    var fxRates: [String: Double] {
        get {
            Dictionary(uniqueKeysWithValues: rateToCNYMap.map { ($0.key, DecimalMath.double($0.value)) })
        }
        set {
            var map: [String: Decimal] = ["CNY": 1]
            for (k, v) in newValue {
                map[k.uppercased()] = Decimal(v)
            }
            rateToCNYMap = map
        }
    }
}
