import Foundation

struct InstrumentSearchHit: Identifiable, Hashable, Sendable {
    let id: String
    let symbol: String
    let name: String
    let market: Market
    let currency: String
    let assetType: InstrumentType
    let securityTypeName: String

    var marketLabel: String { market.displayName }
    var assetTypeLabel: String { assetType.displayName }
}

enum InstrumentSearchError: LocalizedError {
    case timeout
    case network(String)
    case invalidResponse(Int)
    case decodeFailed
    case emptyQuery

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "搜索请求超时。可手填代码，或稍后重试。"
        case .network(let msg):
            return "网络错误：\(msg)。行情为尽力获取，失败时可手填。"
        case .invalidResponse(let code):
            return "搜索接口返回异常（HTTP \(code)）。该接口非官方授权，请稍后重试或手填代码。"
        case .decodeFailed:
            return "搜索结果解析失败。可手填代码继续录入。"
        case .emptyQuery:
            return "请输入代码或名称"
        }
    }
}

actor InstrumentSearchService {
    private let session: URLSession
    /// 东财公开 Suggest 接口的客户端参数（网页同款公开 query，非用户密钥）。
    private let eastMoneySuggestClientParam = "D43EE5B10BFB2E0B6E4F2B5E9B5E5E5E"
    private let useMock: Bool

    init(session: URLSession? = nil, useMock: Bool = false) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 15
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
        self.useMock = useMock
    }

    func search(query: String) async throws -> [InstrumentSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { throw InstrumentSearchError.emptyQuery }

        if useMock {
            AppLog.debug("search mock query_len=\(trimmed.count)")
            return MockMarketData.search(query: trimmed)
        }

        AppLog.debug("search remote query_len=\(trimmed.count)")

        var queries = [trimmed]
        if let paddedHK = Self.optionalHKPaddedQuery(trimmed) {
            queries.append(paddedHK)
        }

        var merged: [InstrumentSearchHit] = []
        var seen = Set<String>()

        do {
            for q in queries {
                let rows = try await fetchSuggest(input: q)
                for row in rows {
                    guard let hit = Self.mapRow(row) else { continue }
                    if seen.insert(hit.id).inserted {
                        merged.append(hit)
                    }
                }
            }
        } catch let urlError as URLError {
            AppLog.error("search URLError code=\(urlError.code.rawValue)")
            if urlError.code == .timedOut || urlError.code == .cannotFindHost
                || urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost {
                throw InstrumentSearchError.timeout
            }
            throw InstrumentSearchError.network(urlError.localizedDescription)
        }

        AppLog.debug("search remote hits=\(merged.count)")
        return Self.rank(merged, query: trimmed)
    }

    private func fetchSuggest(input: String) async throws -> [EastMoneySuggestRow] {
        var components = URLComponents(string: "https://searchapi.eastmoney.com/api/suggest/get")!
        components.queryItems = [
            URLQueryItem(name: "input", value: input),
            URLQueryItem(name: "type", value: "14"),
            URLQueryItem(name: "token", value: eastMoneySuggestClientParam),
            URLQueryItem(name: "count", value: "30"),
        ]
        guard let url = components.url else {
            throw InstrumentSearchError.invalidResponse(-1)
        }

        var request = URLRequest(url: url)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        request.setValue(
            "WealthKeeper/\(version) (iOS; personal portfolio; local-only)",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InstrumentSearchError.invalidResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            AppLog.error("search http=\(http.statusCode)")
            throw InstrumentSearchError.invalidResponse(http.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(EastMoneySuggestResponse.self, from: data)
            return decoded.QuotationCodeTable?.Data ?? []
        } catch {
            AppLog.error("search decode failed")
            throw InstrumentSearchError.decodeFailed
        }
    }

    /// 仅当用户输入 1–4 位纯数字时，追加五位港股常见写法以提升召回；不据此判定市场。
    static func optionalHKPaddedQuery(_ query: String) -> String? {
        let digits = query.filter(\.isNumber)
        guard digits.count == query.count, (1...4).contains(digits.count) else { return nil }
        let padded = String(repeating: "0", count: 5 - digits.count) + digits
        return padded == query ? nil : padded
    }

    static func mapRow(_ row: EastMoneySuggestRow) -> InstrumentSearchHit? {
        guard let code = row.Code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty,
              let name = row.Name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }

        let classify = (row.Classify ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let securityTypeName = row.SecurityTypeName ?? classify
        let quoteID = row.QuoteID ?? ""
        let mktNum = row.mktNumString

        guard let mapped = mapMarketAndType(
            classify: classify,
            securityTypeName: securityTypeName,
            quoteID: quoteID,
            mktNum: mktNum
        ) else {
            return nil
        }

        let symbol = normalizeSymbol(code, market: mapped.market)
        let id = "\(mapped.market.rawValue):\(symbol)"

        return InstrumentSearchHit(
            id: id,
            symbol: symbol,
            name: name,
            market: mapped.market,
            currency: mapped.market.defaultCurrency,
            assetType: mapped.assetType,
            securityTypeName: securityTypeName
        )
    }

    /// 市场与类型完全来自接口字段（Classify / SecurityTypeName / QuoteID / MktNum），不用代码猜市场。
    static func mapMarketAndType(
        classify: String,
        securityTypeName: String,
        quoteID: String,
        mktNum: String
    ) -> (market: Market, assetType: InstrumentType)? {
        let c = classify.uppercased()
        let sec = securityTypeName

        if c == "ASTOCK" || sec == "沪A" || sec == "深A" || sec == "京A" {
            return (.cnA, .stock)
        }
        if c == "HK" || sec == "港股" || mktNum == "116" || quoteID.hasPrefix("116.") {
            return (.hk, .stock)
        }
        if c == "USSTOCK" || sec == "美股" || quoteID.hasPrefix("105.") || quoteID.hasPrefix("106.") || quoteID.hasPrefix("107.") {
            return (.us, .stock)
        }
        if c == "OTCFUND" || mktNum == "150" || quoteID.hasPrefix("150.") {
            return (.cnFund, .fund)
        }
        if c == "FUND", quoteID.hasPrefix("0.") || quoteID.hasPrefix("1.") || mktNum == "0" || mktNum == "1" {
            return (.cnA, .etf)
        }

        return nil
    }

    static func normalizeSymbol(_ code: String, market: Market) -> String {
        switch market {
        case .us:
            return code.uppercased()
        case .hk:
            let digits = code.filter(\.isNumber)
            return digits.isEmpty ? code.uppercased() : digits
        case .cnA, .cnFund:
            return code.uppercased()
        }
    }

    static func rank(_ hits: [InstrumentSearchHit], query: String) -> [InstrumentSearchHit] {
        let q = query.uppercased()
        let qDigits = query.filter(\.isNumber)

        func score(_ hit: InstrumentSearchHit) -> (Int, String) {
            let symbol = hit.symbol.uppercased()
            var s = 0
            if symbol == q || symbol == qDigits { s += 100 }
            if symbol.hasPrefix(q) || (!qDigits.isEmpty && symbol.hasPrefix(qDigits)) { s += 40 }
            if hit.name.contains(query) { s += 20 }
            switch hit.market {
            case .cnA: s += 3
            case .hk: s += 2
            case .us: s += 2
            case .cnFund: s += 1
            }
            return (-s, hit.id)
        }

        return hits.sorted { score($0) < score($1) }
    }
}

struct EastMoneySuggestResponse: Decodable, Sendable {
    let QuotationCodeTable: EastMoneySuggestTable?
}

struct EastMoneySuggestTable: Decodable, Sendable {
    let Data: [EastMoneySuggestRow]?
}

struct EastMoneySuggestRow: Decodable, Sendable {
    let Code: String?
    let Name: String?
    let Classify: String?
    let SecurityTypeName: String?
    let QuoteID: String?
    let UnifiedCode: String?
    /// 东财偶发返回数字或字符串
    let MktNum: FlexibleString?

    var mktNumString: String { MktNum?.value ?? "" }
}

enum FlexibleString: Decodable, Sendable {
    case string(String)
    case int(Int)

    var value: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .int(Int(d))
        } else {
            self = .string("")
        }
    }
}
