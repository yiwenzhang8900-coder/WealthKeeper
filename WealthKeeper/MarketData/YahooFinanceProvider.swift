import Foundation

/// Yahoo：港股 / 美股日线（未复权 close）。不作为 A 股/基金/全市场统一源。
actor YahooFinanceProvider: QuoteProviding {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 15
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    func fetchDailyQuote(for instrument: InstrumentDTO) async throws -> DailyQuote {
        let yahooSymbol = Self.yahooSymbol(for: instrument)
        let encoded = yahooSymbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? yahooSymbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=10d") else {
            throw MarketDataError.invalidResponse(yahooSymbol)
        }

        let source = instrument.market == .hk ? "hk-yahoo" : "us-yahoo"
        let (data, probe) = await NetworkProbe.get(url: url, source: source, session: session)
        guard let data else {
            throw MarketDataError.network("\(instrument.market.displayName) \(probe.errorKind ?? "") \(probe.detail ?? "") status=\(probe.statusCode.map(String.init) ?? "-") ms=\(probe.elapsedMs)")
        }

        do {
            let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = decoded.chart.result?.first,
                  let closes = result.indicators.quote.first?.close,
                  let timestamps = result.timestamp else {
                throw MarketDataError.emptyData(yahooSymbol)
            }
            let pairs: [(Date, Decimal)] = zip(timestamps, closes).compactMap { ts, close in
                guard let close else { return nil }
                return (Date(timeIntervalSince1970: TimeInterval(ts)), Decimal(close))
            }
            guard let last = pairs.last else { throw MarketDataError.emptyData(yahooSymbol) }
            let previous = pairs.dropLast().last?.1 ?? last.1
            return QuoteMetadataBuilder.make(
                instrumentID: instrument.id,
                symbol: instrument.symbol,
                market: instrument.market,
                closeOrNAV: last.1,
                previousClose: previous,
                currency: result.meta.currency ?? instrument.currency,
                quoteTimestamp: last.0,
                now: .now
            )
        } catch let e as MarketDataError {
            throw e
        } catch {
            throw MarketDataError.invalidResponse("\(instrument.market.displayName) JSON解析失败: \(error.localizedDescription)")
        }
    }

    func fetchCorporateActions(for instrument: InstrumentDTO) async throws -> [RemoteCorporateAction] {
        let yahooSymbol = Self.yahooSymbol(for: instrument)
        let encoded = yahooSymbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? yahooSymbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=2y&events=div%7Csplit") else {
            return []
        }
        let (data, _) = await NetworkProbe.get(url: url, source: "yahoo-events", session: session)
        guard let data else { return [] }
        guard let decoded = try? JSONDecoder().decode(YahooChartResponse.self, from: data),
              let events = decoded.chart.result?.first?.events else { return [] }

        var actions: [RemoteCorporateAction] = []
        if let dividends = events.dividends {
            for (_, div) in dividends {
                let ex = Date(timeIntervalSince1970: TimeInterval(div.date))
                actions.append(
                    RemoteCorporateAction(
                        instrumentID: instrument.id,
                        kind: .dividend,
                        exDate: ex,
                        value: Decimal(div.amount),
                        currency: instrument.currency,
                        source: "yahoo",
                        recordDate: ex,
                        settlement: .cash
                    )
                )
            }
        }
        if let splits = events.splits {
            for (_, split) in splits {
                let ratio = Decimal(split.numerator) / max(Decimal(split.denominator), Decimal(string: "0.0001")!)
                actions.append(
                    RemoteCorporateAction(
                        instrumentID: instrument.id,
                        kind: .split,
                        exDate: Date(timeIntervalSince1970: TimeInterval(split.date)),
                        value: ratio,
                        currency: instrument.currency,
                        source: "yahoo"
                    )
                )
            }
        }
        return actions.sorted { $0.exDate < $1.exDate }
    }

    static func yahooSymbol(for instrument: InstrumentDTO) -> String {
        switch instrument.market {
        case .us: return instrument.symbol
        case .hk:
            let digits = instrument.symbol.filter(\.isNumber)
            let padded = String(repeating: "0", count: max(0, 4 - digits.count)) + digits
            return "\(padded).HK"
        case .cnA:
            return instrument.symbol.hasPrefix("6") ? "\(instrument.symbol).SS" : "\(instrument.symbol).SZ"
        case .cnFund:
            return instrument.symbol
        }
    }
}

private struct YahooChartResponse: Decodable {
    let chart: YahooChart
}

private struct YahooChart: Decodable {
    let result: [YahooResult]?
}

private struct YahooResult: Decodable {
    let meta: YahooMeta
    let timestamp: [Int]?
    let events: YahooEvents?
    let indicators: YahooIndicators
}

private struct YahooMeta: Decodable {
    let currency: String?
}

private struct YahooIndicators: Decodable {
    let quote: [YahooQuote]
}

private struct YahooQuote: Decodable {
    let close: [Double?]?
}

private struct YahooEvents: Decodable {
    let dividends: [String: YahooDividend]?
    let splits: [String: YahooSplit]?
}

private struct YahooDividend: Decodable {
    let amount: Double
    let date: Int
}

private struct YahooSplit: Decodable {
    let date: Int
    let numerator: Double
    let denominator: Double
}
