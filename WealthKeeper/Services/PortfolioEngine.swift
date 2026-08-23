import Foundation
import SwiftData

struct PositionValuation: Identifiable {
    var id: String { instrumentID }
    let instrumentID: String
    let symbol: String
    let name: String
    let market: Market
    let instrumentType: InstrumentType
    let quantity: Decimal
    let averageCost: Decimal
    let totalCost: Decimal
    let marketPrice: Decimal
    let marketValueNative: Decimal
    /// 统一折算人民币：amount × rateToCNY
    let marketValueCNY: Decimal
    let unrealizedPnLCNY: Decimal
    let dayPnLCNY: Decimal
    let dayPnLIsFinal: Bool
    let quoteStatus: QuoteDataStatus
    let marketDate: String?
    let exchangeTimeZone: String?
    let quoteTimestamp: Date?
    let isOfficialClose: Bool
    let realizedPnLCNY: Decimal
    let dividendsCNY: Decimal
    let feesCNY: Decimal
    let currency: String
    let priceAsOf: Date?
    let isStale: Bool
    let rateToCNY: Decimal

    /// 列表展示用价格标签：收盘 / 净值 / 现价
    var priceLabel: String {
        switch quoteStatus {
        case .officialClose, .previousSessionClose:
            return "收盘"
        case .fundNAV:
            return "净值"
        default:
            if market == .cnFund || instrumentType == .fund || instrumentType == .etf {
                return "净值"
            }
            return "现价"
        }
    }

    var formattedPrice: String {
        MoneyFormat.quotePrice(marketPrice, instrumentType: instrumentType, market: market)
    }

    // UI 兼容别名（数值为 CNY）
    var marketValueBase: Double { DecimalMath.double(marketValueCNY) }
    var unrealizedPnLBase: Double { DecimalMath.double(unrealizedPnLCNY) }
    var dayPnLBase: Double { DecimalMath.double(dayPnLCNY) }
    var realizedPnLBase: Double { DecimalMath.double(realizedPnLCNY) }
    var dividendsBase: Double { DecimalMath.double(dividendsCNY) }
    var feesBase: Double { DecimalMath.double(feesCNY) }
}

struct MarketQuoteStatusSummary: Identifiable {
    var id: String { market.rawValue }
    let market: Market
    let status: QuoteDataStatus
    let marketDate: String?
    let quoteTimestamp: Date?
    let exchangeTimeZone: String?
    let positionCount: Int
}

struct PortfolioSummary {
    let totalAssetsCNY: Decimal
    let totalCostCNY: Decimal
    let unrealizedPnLCNY: Decimal
    let finalDayPnLCNY: Decimal
    let intradayEstimatePnLCNY: Decimal
    let realizedPnLCNY: Decimal
    let dividendsCNY: Decimal
    let feesCNY: Decimal
    let positions: [PositionValuation]
    let marketStatuses: [MarketQuoteStatusSummary]

    var totalAssetsBase: Double { DecimalMath.double(totalAssetsCNY) }
    var totalCostBase: Double { DecimalMath.double(totalCostCNY) }
    var unrealizedPnLBase: Double { DecimalMath.double(unrealizedPnLCNY) }
    var finalDayPnLBase: Double { DecimalMath.double(finalDayPnLCNY) }
    var intradayEstimatePnLBase: Double { DecimalMath.double(intradayEstimatePnLCNY) }
    var realizedPnLBase: Double { DecimalMath.double(realizedPnLCNY) }
    var dividendsBase: Double { DecimalMath.double(dividendsCNY) }
    var feesBase: Double { DecimalMath.double(feesCNY) }
    var dayPnLBase: Double { finalDayPnLBase }
}

/// 可单测的持仓状态（不依赖 SwiftData）
struct PositionLedgerState: Equatable {
    var quantity: Decimal = 0
    var averageCost: Decimal = 0
    var totalCost: Decimal = 0
    var realizedPnL: Decimal = 0
    var totalDividends: Decimal = 0
    var totalFees: Decimal = 0
}

/// 可单测的流水快照
struct LedgerTransaction: Equatable {
    var kind: TransactionKind
    var tradeDate: Date
    var quantity: Decimal = 0
    var price: Decimal = 0
    var fee: Decimal = 0
    var cashAmount: Decimal = 0
    var splitRatio: Decimal = 1
    var recordDate: Date? = nil
    var sharesOnRecord: Decimal = 0
    var createdAt: Date = .distantPast

    init(
        kind: TransactionKind,
        tradeDate: Date,
        quantity: Decimal = 0,
        price: Decimal = 0,
        fee: Decimal = 0,
        cashAmount: Decimal = 0,
        splitRatio: Decimal = 1,
        recordDate: Date? = nil,
        sharesOnRecord: Decimal = 0,
        createdAt: Date = .distantPast
    ) {
        self.kind = kind
        self.tradeDate = tradeDate
        self.quantity = quantity
        self.price = price
        self.fee = fee
        self.cashAmount = cashAmount
        self.splitRatio = splitRatio
        self.recordDate = recordDate
        self.sharesOnRecord = sharesOnRecord
        self.createdAt = createdAt
    }

    init(_ tx: TransactionRecord) {
        self.kind = tx.kind
        self.tradeDate = tx.tradeDate
        self.quantity = tx.quantity
        self.price = tx.price
        self.fee = tx.fee
        self.cashAmount = tx.cashAmount
        self.splitRatio = tx.splitRatio
        self.recordDate = tx.recordDate
        self.sharesOnRecord = tx.sharesOnRecord
        self.createdAt = tx.createdAt
    }
}

enum PortfolioEngine {
    private static let eps = Decimal(string: "0.0000001")!

    static func rebuildPositions(
        transactions: [TransactionRecord],
        context: ModelContext
    ) {
        let existing = (try? context.fetch(FetchDescriptor<Position>())) ?? []
        for item in existing { context.delete(item) }

        let grouped = Dictionary(grouping: transactions, by: \.instrumentID)
        for (instrumentID, list) in grouped {
            let ledger = list.map(LedgerTransaction.init)
            var state = PositionLedgerState()
            for tx in Self.sorted(ledger) {
                apply(tx, to: &state)
            }
            // 只要还有交易流水就保留 Position（含已清仓 quantity=0），绝不因清仓丢掉历史关联。
            let position = Position(instrumentID: instrumentID)
            position.quantity = state.quantity <= eps ? 0 : state.quantity
            position.averageCost = state.quantity <= eps ? 0 : state.averageCost
            position.totalCost = state.quantity <= eps ? 0 : state.totalCost
            position.realizedPnL = state.realizedPnL
            position.totalDividends = state.totalDividends
            position.totalFees = state.totalFees
            position.updatedAt = .now
            context.insert(position)
        }
        try? context.save()
    }

    /// 按日历日截止（含当日）回放买卖/拆送/再投资，得到权益登记日有效持仓。
    /// 不使用当前持仓，也不把现金分红计入数量。
    static func quantityAsOf(
        _ transactions: [LedgerTransaction],
        asOf recordDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Decimal {
        let end = calendar.startOfDay(for: recordDate)
        let relevant = transactions.filter {
            calendar.startOfDay(for: $0.tradeDate) <= end
        }
        var state = PositionLedgerState()
        for tx in sorted(relevant) {
            // 现金分红不影响持仓数量；登记日持仓只看调仓与公司行为
            if tx.kind == .dividend || tx.kind == .fee { continue }
            apply(tx, to: &state)
        }
        return max(0, state.quantity)
    }

    static func quantityAsOf(
        transactions: [TransactionRecord],
        instrumentID: String,
        asOf recordDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Decimal {
        let ledger = transactions
            .filter { $0.instrumentID == instrumentID }
            .map(LedgerTransaction.init)
        return quantityAsOf(ledger, asOf: recordDate, calendar: calendar)
    }

    static func sorted(_ transactions: [LedgerTransaction]) -> [LedgerTransaction] {
        transactions.sorted { a, b in
            if a.tradeDate != b.tradeDate { return a.tradeDate < b.tradeDate }
            if a.kind.ledgerRank != b.kind.ledgerRank {
                return a.kind.ledgerRank < b.kind.ledgerRank
            }
            return a.createdAt < b.createdAt
        }
    }

    static func apply(_ tx: LedgerTransaction, to position: inout PositionLedgerState) {
        switch tx.kind {
        case .buy:
            let spend = tx.quantity * tx.price + tx.fee
            let newQty = position.quantity + tx.quantity
            if newQty > 0 {
                position.totalCost += spend
                position.averageCost = position.totalCost / newQty
                position.quantity = newQty
            }
            position.totalFees += tx.fee
        case .sell:
            let qty = min(tx.quantity, position.quantity)
            let costReleased = position.averageCost * qty
            let proceeds = qty * tx.price - tx.fee
            position.realizedPnL += proceeds - costReleased
            position.quantity -= qty
            position.totalCost = position.averageCost * position.quantity
            if position.quantity <= eps {
                position.quantity = 0
                position.totalCost = 0
                position.averageCost = 0
            }
            position.totalFees += tx.fee
        case .dividend:
            let cash = dividendCash(tx)
            position.totalDividends += cash
            position.realizedPnL += cash
            position.totalFees += tx.fee
        case .dividendReinvest:
            // 先按现金分红计入收益，再用该金额增加份额（等价于到账后再申购）
            let cash = dividendCash(tx)
            position.totalDividends += cash
            position.realizedPnL += cash
            position.totalFees += tx.fee
            let shares = tx.quantity > 0
                ? tx.quantity
                : (tx.price > 0 ? cash / tx.price : 0)
            guard shares > 0 else { return }
            let spend = cash > 0 ? cash : shares * tx.price
            let newQty = position.quantity + shares
            position.totalCost += spend
            position.quantity = newQty
            if newQty > 0 {
                position.averageCost = position.totalCost / newQty
            }
        case .bonusShare:
            let bonus = tx.quantity > 0 ? tx.quantity : position.quantity * max(tx.splitRatio - 1, 0)
            guard bonus > 0 else { return }
            position.quantity += bonus
            if position.quantity > 0 {
                position.averageCost = position.totalCost / position.quantity
            }
        case .fee:
            let amount = tx.cashAmount > 0 ? tx.cashAmount : tx.fee
            position.totalFees += amount
            position.realizedPnL -= amount
        case .split:
            let ratio = tx.splitRatio == 0 ? 1 : tx.splitRatio
            position.quantity *= ratio
            if position.quantity > 0 {
                position.averageCost /= ratio
                position.totalCost = position.averageCost * position.quantity
            }
        }
    }

    private static func dividendCash(_ tx: LedgerTransaction) -> Decimal {
        if tx.cashAmount > 0 { return tx.cashAmount }
        let shares = tx.sharesOnRecord > 0 ? tx.sharesOnRecord : tx.quantity
        return shares * tx.price
    }

    static func summarize(
        instruments: [Instrument],
        positions: [Position],
        quotes: [CachedQuote],
        settings: AppSettings,
        now: Date = .now
    ) -> PortfolioSummary {
        let instrumentMap = Dictionary(uniqueKeysWithValues: instruments.map { ($0.id, $0) })
        let quoteMap = Dictionary(uniqueKeysWithValues: quotes.map { ($0.instrumentID, $0) })

        var valuations: [PositionValuation] = []

        for position in positions where position.quantity > eps {
            guard let instrument = instrumentMap[position.instrumentID] else { continue }
            valuations.append(
                makeValuation(
                    position: position,
                    instrument: instrument,
                    quote: quoteMap[position.instrumentID],
                    settings: settings,
                    now: now
                )
            )
        }

        valuations.sort { $0.marketValueCNY > $1.marketValueCNY }

        let totalAssets = valuations.reduce(Decimal(0)) { $0 + $1.marketValueCNY }
        let totalCost = valuations.reduce(Decimal(0)) { $0 + $1.totalCost * $1.rateToCNY }
        let unrealized = valuations.reduce(Decimal(0)) { $0 + $1.unrealizedPnLCNY }
        let finalDay = valuations.reduce(Decimal(0)) { $0 + ($1.dayPnLIsFinal ? $1.dayPnLCNY : 0) }
        let intraday = valuations.reduce(Decimal(0)) { $0 + ($1.quoteStatus == .intradayEstimate ? $1.dayPnLCNY : 0) }

        // 含已清仓但仍保留分红/已实现的 Position，保证历史分红仍进累计
        let allRealized = positions.reduce(Decimal(0)) { sum, p in
            let currency = instrumentMap[p.instrumentID]?.currency ?? "CNY"
            return sum + p.realizedPnL * settings.rateToCNY(for: currency)
        }
        let allDiv = positions.reduce(Decimal(0)) { sum, p in
            let currency = instrumentMap[p.instrumentID]?.currency ?? "CNY"
            return sum + p.totalDividends * settings.rateToCNY(for: currency)
        }
        let allFees = positions.reduce(Decimal(0)) { sum, p in
            let currency = instrumentMap[p.instrumentID]?.currency ?? "CNY"
            return sum + p.totalFees * settings.rateToCNY(for: currency)
        }

        return PortfolioSummary(
            totalAssetsCNY: totalAssets,
            totalCostCNY: totalCost,
            unrealizedPnLCNY: unrealized,
            finalDayPnLCNY: finalDay,
            intradayEstimatePnLCNY: intraday,
            realizedPnLCNY: allRealized,
            dividendsCNY: allDiv,
            feesCNY: allFees,
            positions: valuations,
            marketStatuses: buildMarketStatuses(from: valuations)
        )
    }

    /// 含已清仓（quantity=0）持仓的估值，用于详情页展示历史交易。
    static func valuationIncludingClosed(
        instrumentID: String,
        instruments: [Instrument],
        positions: [Position],
        quotes: [CachedQuote],
        settings: AppSettings,
        now: Date = .now
    ) -> PositionValuation? {
        guard let instrument = instruments.first(where: { $0.id == instrumentID }) else { return nil }
        let position = positions.first(where: { $0.instrumentID == instrumentID })
            ?? Position(instrumentID: instrumentID)
        let quote = quotes.first(where: { $0.instrumentID == instrumentID })
        return makeValuation(
            position: position,
            instrument: instrument,
            quote: quote,
            settings: settings,
            now: now
        )
    }

    private static func makeValuation(
        position: Position,
        instrument: Instrument,
        quote: CachedQuote?,
        settings: AppSettings,
        now: Date
    ) -> PositionValuation {
        let price = quote?.closeOrNAV ?? position.averageCost
        let prev = quote?.previousClose ?? price
        let rate = settings.rateToCNY(for: instrument.currency)

        let marketValueNative = position.quantity * price
        let marketValueCNY = marketValueNative * rate
        let costCNY = position.totalCost * rate
        let unrealized = marketValueCNY - costCNY
        let dayCNY = position.quantity * (price - prev) * rate

        let status = QuoteStatusResolver.resolve(
            market: instrument.market,
            now: now,
            quoteMarketDate: quote?.marketDate,
            isOfficialClose: quote?.isOfficialClose ?? false,
            hasQuote: quote != nil,
            isStale: quote?.isStale ?? (quote == nil)
        )
        let isFinal = QuoteStatusResolver.countsTowardFinalDayPnL(
            status: status,
            market: instrument.market,
            now: now,
            quoteMarketDate: quote?.marketDate
        )

        return PositionValuation(
            instrumentID: instrument.id,
            symbol: instrument.symbol,
            name: instrument.name,
            market: instrument.market,
            instrumentType: instrument.type,
            quantity: position.quantity,
            averageCost: position.averageCost,
            totalCost: position.totalCost,
            marketPrice: price,
            marketValueNative: marketValueNative,
            marketValueCNY: marketValueCNY,
            unrealizedPnLCNY: unrealized,
            dayPnLCNY: dayCNY,
            dayPnLIsFinal: isFinal,
            quoteStatus: status,
            marketDate: quote?.marketDate,
            exchangeTimeZone: quote?.exchangeTimeZone,
            quoteTimestamp: quote?.quoteTimestamp,
            isOfficialClose: quote?.isOfficialClose ?? false,
            realizedPnLCNY: position.realizedPnL * rate,
            dividendsCNY: position.totalDividends * rate,
            feesCNY: position.totalFees * rate,
            currency: instrument.currency,
            priceAsOf: quote?.quoteTimestamp ?? quote?.asOf,
            isStale: quote?.isStale ?? true,
            rateToCNY: rate
        )
    }

    private static func buildMarketStatuses(from valuations: [PositionValuation]) -> [MarketQuoteStatusSummary] {
        let order: [Market] = [.cnA, .hk, .us, .cnFund]
        var result: [MarketQuoteStatusSummary] = []
        for market in order {
            let items = valuations.filter { $0.market == market }
            guard !items.isEmpty else { continue }
            let representative = items.max { priority($0.quoteStatus) < priority($1.quoteStatus) } ?? items[0]
            result.append(
                MarketQuoteStatusSummary(
                    market: market,
                    status: representative.quoteStatus,
                    marketDate: representative.marketDate,
                    quoteTimestamp: representative.quoteTimestamp,
                    exchangeTimeZone: representative.exchangeTimeZone,
                    positionCount: items.count
                )
            )
        }
        return result
    }

    private static func priority(_ status: QuoteDataStatus) -> Int {
        switch status {
        case .awaitingOfficialClose: return 50
        case .intradayEstimate: return 40
        case .stale: return 35
        case .preOpen: return 20
        case .previousSessionClose: return 15
        case .fundNAV: return 10
        case .officialClose: return 5
        }
    }
}
