import Foundation

/// 东财：A 股 / 场外基金（大陆主源）。不做港美统一源。
actor EastMoneyProvider: QuoteProviding {
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
        switch instrument.market {
        case .cnA: return try await fetchAShare(instrument)
        case .cnFund: return try await fetchFundNAV(instrument)
        default: throw MarketDataError.unsupported(instrument.id)
        }
    }

    func fetchCorporateActions(for instrument: InstrumentDTO) async throws -> [RemoteCorporateAction] {
        switch instrument.market {
        case .cnA:
            return try await fetchAShareDividends(instrument)
        case .cnFund:
            return try await fetchFundDividends(instrument)
        default:
            return []
        }
    }

    /// A 股分红送配：PRETAX_BONUS_RMB = 每 10 股派息（含税）→ 每股 = /10
    private func fetchAShareDividends(_ instrument: InstrumentDTO) async throws -> [RemoteCorporateAction] {
        var components = URLComponents(string: "https://datacenter-web.eastmoney.com/api/data/v1/get")!
        components.queryItems = [
            URLQueryItem(name: "sortColumns", value: "EX_DIVIDEND_DATE,PLAN_NOTICE_DATE"),
            URLQueryItem(name: "sortTypes", value: "-1,-1"),
            URLQueryItem(name: "pageSize", value: "50"),
            URLQueryItem(name: "pageNumber", value: "1"),
            URLQueryItem(name: "reportName", value: "RPT_SHAREBONUS_DET"),
            URLQueryItem(name: "columns", value: "ALL"),
            URLQueryItem(name: "source", value: "WEB"),
            URLQueryItem(name: "client", value: "WEB"),
            URLQueryItem(name: "filter", value: "(SECURITY_CODE=\"\(instrument.symbol)\")"),
        ]
        guard let url = components.url else { return [] }

        let (data, probe) = await NetworkProbe.get(
            url: url,
            source: "ashare-dividend-eastmoney",
            session: session,
            headers: ["Referer": "https://data.eastmoney.com/yjfp/"]
        )
        guard let data else {
            AppLog.debug("ashare dividend fail \(probe.errorKind ?? "-")")
            return []
        }

        guard let decoded = try? JSONDecoder().decode(EastMoneyDividendListResponse.self, from: data),
              let rows = decoded.result?.data else {
            return []
        }

        var actions: [RemoteCorporateAction] = []
        for row in rows {
            // 只要已有明确派息额的方案；预披露且无金额的跳过
            guard let pretax10 = row.PRETAX_BONUS_RMB, pretax10 > 0 else { continue }
            let progress = row.ASSIGN_PROGRESS ?? ""
            // 优先实施分配；预案若已有金额也可作为估算
            if progress.contains("预披露"), row.EX_DIVIDEND_DATE == nil { continue }

            let perShare = Decimal(pretax10) / Decimal(10)
            let recordDate = Self.parseFlexibleDate(row.EQUITY_RECORD_DATE)
            let exDate = Self.parseFlexibleDate(row.EX_DIVIDEND_DATE)
                ?? recordDate
                ?? Self.parseFlexibleDate(row.PLAN_NOTICE_DATE)
            guard let exDate else { continue }

            actions.append(
                RemoteCorporateAction(
                    instrumentID: instrument.id,
                    kind: .dividend,
                    exDate: exDate,
                    value: perShare,
                    currency: "CNY",
                    source: "eastmoney-ashare-div",
                    recordDate: recordDate ?? exDate,
                    settlement: .cash
                )
            )
        }
        return actions.sorted { $0.exDate > $1.exDate }
    }

    /// 基金分红送配列表（元/份）：按代码在年度榜中定位
    private func fetchFundDividends(_ instrument: InstrumentDTO) async throws -> [RemoteCorporateAction] {
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: .now)
        var collected: [RemoteCorporateAction] = []
        for y in [year, year - 1] {
            let rows = await fetchFundDividendRows(symbol: instrument.symbol, year: y)
            for row in rows {
                guard let amount = DecimalMath.parse(row.amount), amount > 0 else { continue }
                let recordDate = Self.parseFlexibleDate(row.recordDate)
                guard let exDate = Self.parseFlexibleDate(row.exDate) ?? recordDate else { continue }
                collected.append(
                    RemoteCorporateAction(
                        instrumentID: instrument.id,
                        kind: .dividend,
                        exDate: exDate,
                        value: amount,
                        currency: "CNY",
                        source: "eastmoney-fund-div",
                        recordDate: recordDate ?? exDate,
                        settlement: .cash
                    )
                )
            }
            if !collected.isEmpty { break }
        }
        return collected.sorted { $0.exDate > $1.exDate }
    }

    private struct FundDivRow: Sendable {
        let code: String
        let amount: String
        let exDate: String
        let recordDate: String
    }

    private func fetchFundDividendRows(symbol: String, year: Int) async -> [FundDivRow] {
        // 先取首页拿总页数，再按基金代码二分定位（BZDM 升序）
        guard let first = await fetchFundDividendPage(year: year, page: 1) else { return [] }
        let totalPages = max(first.totalPages, 1)
        let target = symbol

        var foundPage: Int?
        var low = 1
        var high = totalPages
        while low <= high {
            let mid = (low + high) / 2
            guard let pack = await fetchFundDividendPage(year: year, page: mid) else { break }
            guard let firstCode = pack.rows.first?.code, let lastCode = pack.rows.last?.code else { break }
            if target < firstCode {
                high = mid - 1
            } else if target > lastCode {
                low = mid + 1
            } else {
                foundPage = mid
                break
            }
        }

        guard let startPage = foundPage else {
            // 兜底：扫前 3 页（按除息日倒序，覆盖近期分红）
            var fallback: [FundDivRow] = []
            for p in 1...min(3, totalPages) {
                if let pack = await fetchFundDividendPage(year: year, page: p, rankByExDate: true) {
                    fallback.append(contentsOf: pack.rows.filter { $0.code == target })
                }
            }
            return fallback
        }

        var matched: [FundDivRow] = []
        for p in max(1, startPage - 2)...min(totalPages, startPage + 2) {
            if let pack = await fetchFundDividendPage(year: year, page: p) {
                matched.append(contentsOf: pack.rows.filter { $0.code == target })
            }
        }
        return matched
    }

    private func fetchFundDividendPage(
        year: Int,
        page: Int,
        rankByExDate: Bool = false
    ) async -> (totalPages: Int, rows: [FundDivRow])? {
        var components = URLComponents(string: "https://fund.eastmoney.com/Data/funddataIndex_Interface.aspx")!
        components.queryItems = [
            URLQueryItem(name: "dt", value: "8"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "rank", value: rankByExDate ? "FSRQ" : "BZDM"),
            URLQueryItem(name: "sort", value: rankByExDate ? "desc" : "asc"),
            URLQueryItem(name: "gs", value: ""),
            URLQueryItem(name: "ftype", value: ""),
            URLQueryItem(name: "year", value: "\(year)"),
        ]
        guard let url = components.url else { return nil }
        let (data, _) = await NetworkProbe.get(
            url: url,
            source: "fund-dividend-eastmoney",
            session: session,
            headers: ["Referer": "https://fund.eastmoney.com/data/fundfenhong.html"]
        )
        guard let data, let text = String(data: data, encoding: .utf8) else { return nil }
        return Self.parseFundDividendJS(text)
    }

    private static func parseFundDividendJS(_ text: String) -> (totalPages: Int, rows: [FundDivRow]) {
        var totalPages = 1
        if let regex = try? NSRegularExpression(pattern: #"var pageinfo\s*=\s*\[(\d+)"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges >= 2,
           let range = Range(match.range(at: 1), in: text),
           let n = Int(text[range]) {
            totalPages = max(n, 1)
        }

        // ["代码","简称","权益登记日","除息日期","分红(元/份)","发放日",...]
        let pattern = #"\["(\d{6})","[^"]*","(\d{4}-\d{2}-\d{2})","(\d{4}-\d{2}-\d{2})","([0-9.]+)","(\d{4}-\d{2}-\d{2})""#
        var rows: [FundDivRow] = []
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (totalPages, []) }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard m.numberOfRanges >= 5 else { continue }
            let code = ns.substring(with: m.range(at: 1))
            let record = ns.substring(with: m.range(at: 2))
            let ex = ns.substring(with: m.range(at: 3))
            let amount = ns.substring(with: m.range(at: 4))
            rows.append(FundDivRow(code: code, amount: amount, exDate: ex, recordDate: record))
        }
        return (totalPages, rows)
    }

    private static func parseFlexibleDate(_ raw: String?) -> Date? {
        guard var raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let space = raw.firstIndex(of: " ") {
            raw = String(raw[..<space])
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for format in ["yyyy-MM-dd", "yyyy/MM/dd"] {
            formatter.dateFormat = format
            if let d = formatter.date(from: raw) { return d }
        }
        return nil
    }

    private func fetchAShare(_ instrument: InstrumentDTO) async throws -> DailyQuote {
        let secid = Self.secid(for: instrument.symbol)
        var components = URLComponents(string: "https://push2delay.eastmoney.com/api/qt/stock/get")!
        components.queryItems = [
            URLQueryItem(name: "secid", value: secid),
            URLQueryItem(name: "fields", value: "f43,f57,f58,f60,f86"),
            URLQueryItem(name: "invt", value: "2"),
        ]
        guard let url = components.url else { throw MarketDataError.invalidResponse(instrument.symbol) }

        let (data, probe) = await NetworkProbe.get(
            url: url,
            source: "ashare-eastmoney",
            session: session,
            headers: ["Referer": "https://quote.eastmoney.com/"]
        )
        guard let data else {
            throw MarketDataError.network("A股 \(probe.errorKind ?? "") \(probe.detail ?? "") status=\(probe.statusCode.map(String.init) ?? "-") ms=\(probe.elapsedMs)")
        }

        do {
            let decoded = try JSONDecoder().decode(EastMoneyStockResponse.self, from: data)
            guard let d = decoded.data else { throw MarketDataError.emptyData(instrument.symbol) }
            let price = Decimal((d.f43 ?? 0) / 100.0)
            let prev = Decimal((d.f60 ?? 0) / 100.0)
            guard price > 0 else { throw MarketDataError.emptyData(instrument.symbol) }
            let now = Date()
            let quoteTimestamp: Date = {
                if let ts = d.f86, ts > 0 { return Date(timeIntervalSince1970: ts) }
                return now
            }()
            return QuoteMetadataBuilder.make(
                instrumentID: instrument.id,
                symbol: instrument.symbol,
                market: .cnA,
                closeOrNAV: price,
                previousClose: prev > 0 ? prev : price,
                currency: "CNY",
                quoteTimestamp: quoteTimestamp,
                now: now
            )
        } catch let e as MarketDataError {
            throw e
        } catch {
            throw MarketDataError.invalidResponse("A股 JSON解析失败: \(error.localizedDescription)")
        }
    }

    private func fetchFundNAV(_ instrument: InstrumentDTO) async throws -> DailyQuote {
        var components = URLComponents(string: "https://api.fund.eastmoney.com/f10/lsjz")!
        components.queryItems = [
            URLQueryItem(name: "fundCode", value: instrument.symbol),
            URLQueryItem(name: "pageIndex", value: "1"),
            URLQueryItem(name: "pageSize", value: "2"),
        ]
        guard let url = components.url else { throw MarketDataError.invalidResponse(instrument.symbol) }

        let (data, probe) = await NetworkProbe.get(
            url: url,
            source: "fund-eastmoney",
            session: session,
            headers: ["Referer": "https://fundf10.eastmoney.com/"]
        )
        guard let data else {
            throw MarketDataError.network("基金 \(probe.errorKind ?? "") \(probe.detail ?? "") status=\(probe.statusCode.map(String.init) ?? "-") ms=\(probe.elapsedMs)")
        }

        do {
            let decoded = try JSONDecoder().decode(EastMoneyFundResponse.self, from: data)
            guard let rows = decoded.Data?.LSJZList, let first = rows.first,
                  let nav = DecimalMath.parse(first.DWJZ ?? "") else {
                throw MarketDataError.emptyData(instrument.symbol)
            }
            let prev = rows.count > 1 ? (DecimalMath.parse(rows[1].DWJZ ?? "") ?? nav) : nav
            guard let navDay = Self.parseFundDate(first.FSRQ) else {
                throw MarketDataError.emptyData(instrument.symbol)
            }
            let marketDate = TradingCalendar.marketDateString(for: navDay, market: .cnFund)
            let cal = TradingCalendar.calendar(for: .cnFund)
            var comps = cal.dateComponents([.year, .month, .day], from: navDay)
            comps.hour = 12
            comps.minute = 0
            let timestamp = cal.date(from: comps) ?? navDay
            return DailyQuote(
                instrumentID: instrument.id,
                symbol: instrument.symbol,
                market: .cnFund,
                closeOrNAV: nav,
                previousClose: prev,
                currency: "CNY",
                asOf: timestamp,
                marketDate: marketDate,
                exchangeTimeZone: TradingCalendar.timeZoneID(for: .cnFund),
                quoteTimestamp: timestamp,
                isOfficialClose: true
            )
        } catch let e as MarketDataError {
            throw e
        } catch {
            throw MarketDataError.invalidResponse("基金 JSON解析失败: \(error.localizedDescription)")
        }
    }

    static func secid(for symbol: String) -> String {
        if symbol.hasPrefix("6") || symbol.hasPrefix("5") || symbol.hasPrefix("9") {
            return "1.\(symbol)"
        }
        return "0.\(symbol)"
    }

    private static func parseFundDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TradingCalendar.timeZone(for: .cnFund)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}

private struct EastMoneyStockResponse: Decodable {
    let data: EastMoneyStockData?
}

private struct EastMoneyStockData: Decodable {
    let f43: Double?
    let f60: Double?
    let f86: Double?
}

private struct EastMoneyFundResponse: Decodable {
    let Data: EastMoneyFundData?
}

private struct EastMoneyFundData: Decodable {
    let LSJZList: [EastMoneyFundRow]?
}

private struct EastMoneyFundRow: Decodable {
    let FSRQ: String?
    let DWJZ: String?
}

private struct EastMoneyDividendListResponse: Decodable {
    let result: EastMoneyDividendListResult?
}

private struct EastMoneyDividendListResult: Decodable {
    let data: [EastMoneyDividendRow]?
}

private struct EastMoneyDividendRow: Decodable {
    let PRETAX_BONUS_RMB: Double?
    let ASSIGN_PROGRESS: String?
    let EX_DIVIDEND_DATE: String?
    let EQUITY_RECORD_DATE: String?
    let PLAN_NOTICE_DATE: String?
    let IMPL_PLAN_PROFILE: String?
}
