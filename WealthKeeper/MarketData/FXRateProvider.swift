import Foundation

/// 汇率统一以 CNY 为基准：rateToCNY 表示 1 外币 = 多少人民币。
/// 大陆主路径东财，回落新浪；不作为股票/基金行情源。
actor FXRateProvider {
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

    struct Snapshot: Sendable {
        /// currency -> rateToCNY
        let rateToCNY: [String: Decimal]
        let asOf: Date
        let source: String
        let diagnostics: [NetworkProbe.Result]
    }

    func fetchRateToCNY() async throws -> Snapshot {
        var diags: [NetworkProbe.Result] = []
        do {
            let (usd, hkd, asOf, probe) = try await fetchFromEastMoney()
            diags.append(probe)
            return Snapshot(
                rateToCNY: ["CNY": 1, "USD": usd, "HKD": hkd],
                asOf: asOf,
                source: "eastmoney",
                diagnostics: diags
            )
        } catch {
            AppLog.error("fx eastmoney failed: \(error.localizedDescription)")
        }

        do {
            let (usd, hkd, asOf, probe) = try await fetchFromSina()
            diags.append(probe)
            return Snapshot(
                rateToCNY: ["CNY": 1, "USD": usd, "HKD": hkd],
                asOf: asOf,
                source: "sina",
                diagnostics: diags
            )
        } catch {
            AppLog.error("fx sina failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func fetchFromEastMoney() async throws -> (Decimal, Decimal, Date, NetworkProbe.Result) {
        var components = URLComponents(string: "https://push2delay.eastmoney.com/api/qt/ulist.np/get")!
        components.queryItems = [
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fields", value: "f12,f14,f2,f4"),
            URLQueryItem(name: "secids", value: "133.USDCNH,133.HKDCNH"),
        ]
        guard let url = components.url else { throw MarketDataError.invalidResponse("fx-em-url") }

        let (data, probe) = await NetworkProbe.get(
            url: url,
            source: "fx-eastmoney",
            session: session,
            headers: ["Referer": "https://quote.eastmoney.com/"]
        )
        guard let data else {
            throw MarketDataError.network(probe.detail ?? probe.errorKind ?? "fx-em")
        }
        do {
            let decoded = try JSONDecoder().decode(EastMoneyFXListResponse.self, from: data)
            let rows = decoded.data?.diff ?? []
            var usd: Decimal?
            var hkd: Decimal?
            for row in rows {
                let code = (row.f12 ?? "").uppercased()
                guard let price = row.f2, price > 0 else { continue }
                let d = Decimal(price)
                if code.contains("USD") { usd = d }
                if code.contains("HKD") { hkd = d }
            }
            guard let usdCny = usd, let hkdCny = hkd else {
                throw MarketDataError.emptyData("fx-em-usd-or-hkd")
            }
            return (usdCny, hkdCny, .now, probe)
        } catch let e as MarketDataError {
            throw e
        } catch {
            AppLog.error("fx eastmoney json parse")
            throw MarketDataError.invalidResponse("fx-em-json: \(error.localizedDescription)")
        }
    }

    private func fetchFromSina() async throws -> (Decimal, Decimal, Date, NetworkProbe.Result) {
        guard let url = URL(string: "https://hq.sinajs.cn/list=fx_susdcny,fx_shkdcny") else {
            throw MarketDataError.invalidResponse("fx-sina-url")
        }
        let (data, probe) = await NetworkProbe.get(
            url: url,
            source: "fx-sina",
            session: session,
            headers: ["Referer": "https://finance.sina.com.cn"]
        )
        guard let data else {
            throw MarketDataError.network(probe.detail ?? "fx-sina")
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        guard let usd = Self.parseSinaFX(text: text, symbol: "fx_susdcny"),
              let hkd = Self.parseSinaFX(text: text, symbol: "fx_shkdcny") else {
            throw MarketDataError.emptyData("fx-sina-parse")
        }
        return (usd, hkd, .now, probe)
    }

    static func parseSinaFX(text: String, symbol: String) -> Decimal? {
        guard let range = text.range(of: "hq_str_\(symbol)=\"") else { return nil }
        let rest = text[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let body = String(rest[..<end])
        let parts = body.split(separator: ",").map(String.init)
        for part in parts.dropFirst().prefix(8) {
            if let v = DecimalMath.parse(part), v > Decimal(string: "0.5")!, v < Decimal(20) {
                return v
            }
        }
        return nil
    }
}

private struct EastMoneyFXListResponse: Decodable {
    let data: EastMoneyFXListData?
}

private struct EastMoneyFXListData: Decodable {
    let diff: [EastMoneyFXRow]?
}

private struct EastMoneyFXRow: Decodable {
    let f12: String?
    let f14: String?
    let f2: Double?
}
