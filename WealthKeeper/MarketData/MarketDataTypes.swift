import Foundation

struct DailyQuote: Sendable {
    let instrumentID: String
    let symbol: String
    let market: Market
    /// 未复权收盘价或基金单位净值（禁止用复权价，避免与现金分红双计）
    let closeOrNAV: Decimal
    let previousClose: Decimal
    let currency: String
    let asOf: Date
    let marketDate: String
    let exchangeTimeZone: String
    let quoteTimestamp: Date
    let isOfficialClose: Bool
}

struct RemoteCorporateAction: Sendable {
    let instrumentID: String
    let kind: CorporateActionKind
    let exDate: Date
    /// 权益登记日；缺省时调用方应回退为 exDate
    let recordDate: Date?
    let value: Decimal
    let currency: String
    let source: String
    let settlement: DividendSettlement

    init(
        instrumentID: String,
        kind: CorporateActionKind,
        exDate: Date,
        value: Decimal,
        currency: String,
        source: String,
        recordDate: Date? = nil,
        settlement: DividendSettlement = .cash
    ) {
        self.instrumentID = instrumentID
        self.kind = kind
        self.exDate = exDate
        self.recordDate = recordDate
        self.value = value
        self.currency = currency
        self.source = source
        self.settlement = settlement
    }

    var effectiveRecordDate: Date { recordDate ?? exDate }
}

protocol QuoteProviding: Sendable {
    func fetchDailyQuote(for instrument: InstrumentDTO) async throws -> DailyQuote
    func fetchCorporateActions(for instrument: InstrumentDTO) async throws -> [RemoteCorporateAction]
}

struct InstrumentDTO: Sendable {
    let id: String
    let symbol: String
    let name: String
    let market: Market
    let type: InstrumentType
    let currency: String

    init(_ instrument: Instrument) {
        self.id = instrument.id
        self.symbol = instrument.symbol
        self.name = instrument.name
        self.market = instrument.market
        self.type = instrument.type
        self.currency = instrument.currency
    }
}

enum MarketDataError: LocalizedError {
    case unsupported(String)
    case invalidResponse(String)
    case emptyData(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let s): return "不支持的标的: \(s)"
        case .invalidResponse(let s): return "行情响应异常: \(s)"
        case .emptyData(let s): return "无行情数据: \(s)"
        case .network(let s): return "网络错误: \(s)"
        }
    }
}

enum QuoteMetadataBuilder {
    static func make(
        instrumentID: String,
        symbol: String,
        market: Market,
        closeOrNAV: Decimal,
        previousClose: Decimal,
        currency: String,
        quoteTimestamp: Date,
        now: Date = .now,
        forceOfficialClose: Bool? = nil
    ) -> DailyQuote {
        let tz = TradingCalendar.timeZoneID(for: market)
        let marketDate = TradingCalendar.marketDateString(for: quoteTimestamp, market: market)
        let phase = TradingCalendar.phase(at: now, market: market)
        let today = TradingCalendar.currentMarketDateString(at: now, market: market)

        let official: Bool
        if let forceOfficialClose {
            official = forceOfficialClose
        } else if market == .cnFund {
            official = true
        } else if marketDate < today {
            official = true
        } else if marketDate == today {
            switch phase {
            case .afterClose: official = true
            default: official = false
            }
        } else {
            official = false
        }

        return DailyQuote(
            instrumentID: instrumentID,
            symbol: symbol,
            market: market,
            closeOrNAV: closeOrNAV,
            previousClose: previousClose,
            currency: currency,
            asOf: quoteTimestamp,
            marketDate: marketDate,
            exchangeTimeZone: tz,
            quoteTimestamp: quoteTimestamp,
            isOfficialClose: official
        )
    }
}
