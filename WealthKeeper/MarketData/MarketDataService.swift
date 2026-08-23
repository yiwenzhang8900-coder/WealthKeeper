import Foundation
import SwiftData

/// 统一行情门面：按市场区分数据源（Mock / 东财A股 / 东财基金 / Yahoo港美）
@MainActor
final class MarketDataService {
    private let eastMoney = EastMoneyProvider()
    private let yahoo = YahooFinanceProvider()
    private let fxProvider = FXRateProvider()

    struct RefreshResult {
        var success: Int
        var failures: [(String, String)]
        var diagnostics: [String]
    }

    func refresh(
        instruments: [Instrument],
        settings: AppSettings,
        context: ModelContext
    ) async -> RefreshResult {
        var success = 0
        var failures: [(String, String)] = []
        var diagnostics: [String] = []
        var actionsBuffer: [RemoteCorporateAction] = []
        let useMock = settings.useMockMarketData
        AppLog.debug("refresh start count=\(instruments.count) mock=\(useMock)")

        // 汇率：始终存 rateToCNY
        do {
            if useMock {
                settings.rateToCNYMap = [
                    "CNY": 1,
                    "USD": Decimal(string: "7.2000")!,
                    "HKD": Decimal(string: "0.9200")!,
                ]
                settings.lastFXRefresh = .now
                settings.fxSource = "mock"
                diagnostics.append("FX mock ok")
            } else {
                let snapshot = try await fxProvider.fetchRateToCNY()
                settings.rateToCNYMap = snapshot.rateToCNY
                settings.lastFXRefresh = snapshot.asOf
                settings.fxSource = snapshot.source
                for p in snapshot.diagnostics {
                    diagnostics.append("FX \(p.source) status=\(p.statusCode.map(String.init) ?? "-") ms=\(p.elapsedMs) err=\(p.errorKind ?? "-")")
                }
            }
        } catch {
            failures.append(("汇率", "fetch_failed"))
            diagnostics.append("FX fail")
        }

        for instrument in instruments {
            let dto = InstrumentDTO(instrument)
            let sourceLabel: String = {
                if useMock { return "mock" }
                switch instrument.market {
                case .cnA: return "ashare-eastmoney"
                case .cnFund: return "fund-eastmoney"
                case .hk: return "hk-yahoo"
                case .us: return "us-yahoo"
                }
            }()
            do {
                let quote: DailyQuote
                if useMock {
                    quote = MockMarketData.quote(for: dto)
                } else {
                    quote = try await fetchQuote(dto)
                }
                upsertQuote(quote, context: context)
                success += 1
                diagnostics.append("\(sourceLabel) \(AppLog.maskSymbol(instrument.symbol)) ok")

                if !useMock, settings.autoImportCorporateActions {
                    let actions: [RemoteCorporateAction]
                    switch instrument.market {
                    case .us, .hk:
                        actions = try await yahoo.fetchCorporateActions(for: dto)
                    case .cnA, .cnFund:
                        actions = try await eastMoney.fetchCorporateActions(for: dto)
                    }
                    actionsBuffer.append(contentsOf: actions)
                    if !actions.isEmpty {
                        diagnostics.append("\(sourceLabel) \(AppLog.maskSymbol(instrument.symbol)) div=\(actions.count)")
                    }
                }
            } catch {
                let msg = AppLog.sanitize(error.localizedDescription)
                markStale(instrumentID: instrument.id, context: context)
                failures.append(("\(instrument.market.displayName) \(AppLog.maskSymbol(instrument.symbol))", msg))
                diagnostics.append("\(sourceLabel) \(AppLog.maskSymbol(instrument.symbol)) fail")
            }
        }

        for action in actionsBuffer {
            upsertCorporateAction(action, context: context, settings: settings)
        }

        settings.lastMarketRefresh = .now
        settings.lastMarketDiag = diagnostics.suffix(20).joined(separator: "\n")
        try? context.save()
        return RefreshResult(success: success, failures: failures, diagnostics: diagnostics)
    }

    private func fetchQuote(_ dto: InstrumentDTO) async throws -> DailyQuote {
        switch dto.market {
        case .cnA, .cnFund:
            return try await eastMoney.fetchDailyQuote(for: dto)
        case .hk, .us:
            return try await yahoo.fetchDailyQuote(for: dto)
        }
    }

    private func upsertQuote(_ quote: DailyQuote, context: ModelContext) {
        let id = quote.instrumentID
        let descriptor = FetchDescriptor<CachedQuote>(predicate: #Predicate { $0.instrumentID == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.closeOrNAV = quote.closeOrNAV
            existing.previousClose = quote.previousClose
            existing.currency = quote.currency
            existing.asOf = quote.quoteTimestamp
            existing.marketDate = quote.marketDate
            existing.exchangeTimeZone = quote.exchangeTimeZone
            existing.quoteTimestamp = quote.quoteTimestamp
            existing.isOfficialClose = quote.isOfficialClose
            existing.marketRaw = quote.market.rawValue
            existing.isStale = false
            existing.updatedAt = .now
        } else {
            context.insert(
                CachedQuote(
                    instrumentID: quote.instrumentID,
                    symbol: quote.symbol,
                    market: quote.market,
                    closeOrNAV: quote.closeOrNAV,
                    currency: quote.currency,
                    asOf: quote.quoteTimestamp,
                    previousClose: quote.previousClose,
                    marketDate: quote.marketDate,
                    exchangeTimeZone: quote.exchangeTimeZone,
                    quoteTimestamp: quote.quoteTimestamp,
                    isOfficialClose: quote.isOfficialClose
                )
            )
        }
    }

    private func markStale(instrumentID: String, context: ModelContext) {
        let descriptor = FetchDescriptor<CachedQuote>(predicate: #Predicate { $0.instrumentID == instrumentID })
        if let existing = try? context.fetch(descriptor).first {
            existing.isStale = true
            existing.updatedAt = .now
        }
    }

    private func upsertCorporateAction(
        _ action: RemoteCorporateAction,
        context: ModelContext,
        settings: AppSettings
    ) {
        let day = Calendar.current.startOfDay(for: action.exDate)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dayKey = formatter.string(from: day)
        let id = "\(action.instrumentID):\(action.kind.rawValue):\(dayKey)"
        let descriptor = FetchDescriptor<CorporateActionRecord>(predicate: #Predicate { $0.id == id })
        if (try? context.fetch(descriptor).first) != nil { return }

        let recordDate = action.effectiveRecordDate
        let record = CorporateActionRecord(
            instrumentID: action.instrumentID,
            kind: action.kind,
            exDate: action.exDate,
            value: DecimalMath.double(action.value),
            currency: action.currency,
            source: action.source,
            recordDate: recordDate,
            settlement: action.settlement
        )
        context.insert(record)
        guard settings.autoImportCorporateActions else { return }

        if action.kind == .dividend {
            // 按权益登记日回放持仓，禁止用当前 Position.quantity
            let allTx = (try? context.fetch(FetchDescriptor<TransactionRecord>())) ?? []
            let qty = PortfolioEngine.quantityAsOf(
                transactions: allTx,
                instrumentID: action.instrumentID,
                asOf: recordDate
            )
            guard qty > 0 else { return }

            let cash = qty * action.value
            let txKind: TransactionKind = action.settlement == .reinvest ? .dividendReinvest : .dividend
            let note: String = {
                let ex = formatter.string(from: Calendar.current.startOfDay(for: action.exDate))
                let rec = formatter.string(from: Calendar.current.startOfDay(for: recordDate))
                let settle = action.settlement == .reinvest ? "再投资" : "现金"
                return "自动导入分红 · \(settle) · 登记日 \(rec) · 除息 \(ex)"
            }()

            context.insert(
                TransactionRecord(
                    instrumentID: action.instrumentID,
                    kind: txKind,
                    tradeDate: recordDate,
                    quantity: qty,
                    price: action.value,
                    cashAmount: cash,
                    note: note,
                    recordDate: recordDate,
                    sharesOnRecord: qty,
                    currency: action.currency
                )
            )
            record.sharesOnRecord = DecimalMath.double(qty)
            record.cashAmount = DecimalMath.double(cash)
            record.importedAsTransaction = true
        } else if action.kind == .split {
            context.insert(
                TransactionRecord(
                    instrumentID: action.instrumentID,
                    kind: .split,
                    tradeDate: action.exDate,
                    splitRatio: action.value,
                    note: "自动导入拆合股",
                    currency: action.currency
                )
            )
            record.importedAsTransaction = true
        } else if action.kind == .bonusShare {
            let allTx = (try? context.fetch(FetchDescriptor<TransactionRecord>())) ?? []
            let qty = PortfolioEngine.quantityAsOf(
                transactions: allTx,
                instrumentID: action.instrumentID,
                asOf: recordDate
            )
            guard qty > 0, action.value > 0 else { return }
            // value = 每持有 1 股送出的股数，或拆送比例增量
            let bonus = qty * action.value
            context.insert(
                TransactionRecord(
                    instrumentID: action.instrumentID,
                    kind: .bonusShare,
                    tradeDate: recordDate,
                    quantity: bonus,
                    note: "自动导入送股",
                    recordDate: recordDate,
                    sharesOnRecord: qty,
                    currency: action.currency
                )
            )
            record.sharesOnRecord = DecimalMath.double(qty)
            record.importedAsTransaction = true
        }
    }
}
