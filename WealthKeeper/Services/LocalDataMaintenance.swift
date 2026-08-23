import Foundation
import SwiftData

enum LocalDataImportError: LocalizedError {
    case invalidJSON
    case invalidStructure
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "无法解析备份文件，请选择由本应用导出的 JSON。"
        case .invalidStructure:
            return "备份文件格式不正确或缺少必要字段。"
        case .persistence(let message):
            return "导入失败：\(message)"
        }
    }
}

/// 本地数据维护：清空 / 清缓存 / 导出 / 导入。不含云同步与账号。
enum LocalDataMaintenance {
    static let userDefaultsKeys = [
        "wk_manual_assets_seeded_v1",
        "wk_mock_default_applied_v1",
        SecurityTipStorage.manualAssetsFirstTipKey,
    ]

    /// 用户主动清空后禁止再次自动植入演示资产
    static let skipDemoSeedKey = "wk_user_cleared_data_v1"

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterFallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 删除全部 SwiftData 业务实体，重置 AppSettings，清除 UserDefaults 标记。
    @MainActor
    static func deleteAllLocalData(context: ModelContext) throws {
        try wipeBusinessData(context: context, includingSettings: true)

        let fresh = AppSettings()
        context.insert(fresh)
        try context.save()

        clearUserDefaultsFlags()
        UserDefaults.standard.set(true, forKey: skipDemoSeedKey)
        AppLog.debug("local data wipe completed")
    }

    /// 仅清除行情缓存与市场诊断；不动持仓与交易。
    @MainActor
    static func clearQuoteCache(context: ModelContext) throws {
        try deleteAll(of: CachedQuote.self, context: context)
        if let settings = try context.fetch(FetchDescriptor<AppSettings>()).first {
            settings.lastMarketDiag = ""
            settings.lastMarketRefresh = nil
        }
        try context.save()
        AppLog.debug("quote cache cleared")
    }

    static func clearUserDefaultsFlags() {
        let defaults = UserDefaults.standard
        for key in userDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
    }

    /// 从 `exportJSON` 同结构的备份恢复；会替换全部本地业务数据。
    @MainActor
    static func importJSON(_ data: Data, context: ModelContext) throws {
        let rootObject: Any
        do {
            rootObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LocalDataImportError.invalidJSON
        }
        guard let root = rootObject as? [String: Any] else {
            throw LocalDataImportError.invalidStructure
        }

        let instruments = root["instruments"] as? [[String: Any]] ?? []
        let transactions = root["transactions"] as? [[String: Any]] ?? []
        let positions = root["positions"] as? [[String: Any]] ?? []
        let deposits = root["bankDeposits"] as? [[String: Any]] ?? []
        let fx = root["fxSavings"] as? [[String: Any]] ?? []
        let bonds = root["bonds"] as? [[String: Any]] ?? []
        let cash = root["cashOther"] as? [[String: Any]] ?? []
        let liabilities = root["liabilities"] as? [[String: Any]] ?? []
        let events = root["manualCapitalEvents"] as? [[String: Any]] ?? []
        let lifestyle = root["lifestyle"] as? [[String: Any]] ?? []
        let settingsDict = root["settings"] as? [String: Any]

        do {
            try wipeBusinessData(context: context, includingSettings: true)

            for dict in instruments {
                let market = Market(rawValue: dict["market"] as? String ?? "") ?? .cnA
                let type = InstrumentType(rawValue: dict["type"] as? String ?? "") ?? .stock
                let item = Instrument(
                    symbol: dict["symbol"] as? String ?? "",
                    name: dict["name"] as? String ?? "",
                    market: market,
                    type: type,
                    currency: dict["currency"] as? String
                )
                if let id = dict["id"] as? String, !id.isEmpty {
                    item.id = id
                }
                context.insert(item)
            }

            var importedTransactions: [TransactionRecord] = []
            for dict in transactions {
                let kind = TransactionKind(rawValue: dict["kind"] as? String ?? "") ?? .buy
                let tradeDate = parseDate(dict["tradeDate"]) ?? .now
                let tx = TransactionRecord(
                    instrumentID: dict["instrumentID"] as? String ?? "",
                    kind: kind,
                    tradeDate: tradeDate,
                    quantity: decimal(dict["quantity"]),
                    price: decimal(dict["price"]),
                    fee: decimal(dict["fee"]),
                    cashAmount: decimal(dict["cashAmount"]),
                    splitRatio: decimal(dict["splitRatio"], default: 1),
                    note: dict["note"] as? String ?? "",
                    recordDate: parseDate(dict["recordDate"]),
                    sharesOnRecord: decimal(dict["sharesOnRecord"]),
                    currency: dict["currency"] as? String ?? ""
                )
                if let idString = dict["id"] as? String, let id = UUID(uuidString: idString) {
                    tx.id = id
                }
                context.insert(tx)
                importedTransactions.append(tx)
            }

            for dict in deposits {
                let kind = BankDepositKind(rawValue: dict["depositKind"] as? String ?? "") ?? .demand
                let wealthStyle = BankWealthStyle(rawValue: dict["wealthStyle"] as? String ?? "") ?? .netValue
                let risk = BankWealthRiskLevel(rawValue: dict["riskLevel"] as? String ?? "") ?? .r2
                let item = BankDepositAccount(
                    name: dict["name"] as? String ?? "",
                    balance: decimal(dict["balance"]),
                    currency: dict["currency"] as? String ?? "CNY",
                    annualRate: decimal(dict["annualRate"]),
                    valueDate: parseDate(dict["valueDate"]),
                    maturityDate: parseDate(dict["maturityDate"]),
                    expectedRedemptionDate: parseDate(dict["expectedRedemptionDate"]),
                    accruedInterest: decimal(dict["accruedInterest"]),
                    receivedInterest: decimal(dict["receivedInterest"]),
                    depositKind: kind,
                    productName: dict["productName"] as? String ?? "",
                    wealthStyle: wealthStyle,
                    riskLevel: risk,
                    unitNav: decimal(dict["unitNav"], default: 1),
                    note: dict["note"] as? String ?? ""
                )
                if let idString = dict["id"] as? String, let id = UUID(uuidString: idString) {
                    item.id = id
                }
                context.insert(item)
            }

            for dict in fx {
                let item = FXSavingsAccount(
                    name: dict["name"] as? String ?? "",
                    balance: decimal(dict["balance"]),
                    currency: dict["currency"] as? String ?? "USD",
                    annualRate: decimal(dict["annualRate"]),
                    valueDate: parseDate(dict["valueDate"]),
                    maturityDate: parseDate(dict["maturityDate"]),
                    accruedInterest: decimal(dict["accruedInterest"]),
                    receivedInterest: decimal(dict["receivedInterest"]),
                    note: dict["note"] as? String ?? ""
                )
                if let idString = dict["id"] as? String, let id = UUID(uuidString: idString) {
                    item.id = id
                }
                context.insert(item)
            }

            for dict in bonds {
                let freq = BondCouponPaymentFrequency(rawValue: dict["couponFrequency"] as? String ?? "") ?? .unset
                let marketValue: Decimal? = {
                    guard dict["marketValue"] != nil, !(dict["marketValue"] is NSNull) else { return nil }
                    return decimal(dict["marketValue"])
                }()
                let item = BondHolding(
                    name: dict["name"] as? String ?? "",
                    currency: dict["currency"] as? String ?? "CNY",
                    faceValue: decimal(dict["faceValue"]),
                    cost: decimal(dict["cost"]),
                    couponRate: decimal(dict["couponRate"]),
                    purchaseDate: parseDate(dict["purchaseDate"]) ?? .now,
                    valueDate: parseDate(dict["valueDate"]),
                    maturityDate: parseDate(dict["maturityDate"]),
                    expectedRedemptionDate: parseDate(dict["expectedRedemptionDate"]),
                    couponFrequency: freq,
                    marketValue: marketValue,
                    accruedInterest: decimal(dict["accruedInterest"]),
                    receivedInterest: decimal(dict["receivedInterest"]),
                    note: dict["note"] as? String ?? ""
                )
                if let idString = dict["id"] as? String, let id = UUID(uuidString: idString) {
                    item.id = id
                }
                context.insert(item)
            }

            for dict in cash {
                let kindRaw = dict["kindRaw"] as? String ?? ""
                let kind = CashOtherKind(rawValue: kindRaw) ?? .other
                let item = CashOtherAsset(
                    name: dict["name"] as? String ?? "",
                    balance: decimal(dict["balance"]),
                    currency: dict["currency"] as? String ?? "CNY",
                    note: dict["note"] as? String ?? "",
                    kind: kind
                )
                if kindRaw.isEmpty {
                    item.kindRaw = ""
                } else {
                    item.kindRaw = kindRaw
                }
                if let idString = dict["id"] as? String, let id = UUID(uuidString: idString) {
                    item.id = id
                }
                context.insert(item)
            }

            for dict in liabilities {
                let item = LiabilityRecord(
                    name: dict["name"] as? String ?? "",
                    balance: decimal(dict["balance"]),
                    currency: dict["currency"] as? String ?? "CNY",
                    note: dict["note"] as? String ?? ""
                )
                if let idString = dict["id"] as? String, let id = UUID(uuidString: idString) {
                    item.id = id
                }
                context.insert(item)
            }

            for dict in events {
                let assetIDString = dict["assetID"] as? String ?? ""
                let assetClass = AssetClass(rawValue: dict["assetClass"] as? String ?? "") ?? .cashOther
                let kind = ManualCapitalEventKind(rawValue: dict["kind"] as? String ?? "") ?? .deposit
                let item = ManualCapitalEvent(
                    assetID: UUID(uuidString: assetIDString) ?? UUID(),
                    assetClass: assetClass,
                    kind: kind,
                    amount: decimal(dict["amount"]),
                    currency: dict["currency"] as? String ?? "CNY",
                    eventDate: parseDate(dict["eventDate"]) ?? .now,
                    note: dict["note"] as? String ?? ""
                )
                item.assetID = assetIDString
                if let idString = dict["id"] as? String, let id = UUID(uuidString: idString) {
                    item.id = id
                }
                context.insert(item)
            }

            for dict in lifestyle {
                let flow = LifestyleFlowKind(rawValue: dict["flowKind"] as? String ?? "") ?? .expense
                let category = LifestyleCategory(rawValue: dict["category"] as? String ?? "")
                    ?? (flow == .income ? .otherIncome : .otherExpense)
                let item = LifestyleEntry(
                    flowKind: flow,
                    category: category,
                    amount: decimal(dict["amount"]),
                    currency: dict["currency"] as? String ?? "CNY",
                    entryDate: parseDate(dict["entryDate"]) ?? .now,
                    note: dict["note"] as? String ?? ""
                )
                if let idString = dict["id"] as? String, let id = UUID(uuidString: idString) {
                    item.id = id
                }
                context.insert(item)
            }

            let fresh = AppSettings()
            if let settingsDict {
                fresh.baseCurrency = settingsDict["baseCurrency"] as? String ?? "CNY"
                fresh.autoImportCorporateActions = settingsDict["autoImportCorporateActions"] as? Bool ?? true
                fresh.useMockMarketData = settingsDict["useMockMarketData"] as? Bool ?? false
            }
            context.insert(fresh)

            try context.save()

            if !importedTransactions.isEmpty {
                PortfolioEngine.rebuildPositions(transactions: importedTransactions, context: context)
            } else {
                for dict in positions {
                    let instrumentID = dict["instrumentID"] as? String ?? ""
                    guard !instrumentID.isEmpty else { continue }
                    let position = Position(instrumentID: instrumentID)
                    position.quantity = decimal(dict["quantity"])
                    position.averageCost = decimal(dict["averageCost"])
                    position.totalCost = decimal(dict["totalCost"])
                    position.realizedPnL = decimal(dict["realizedPnL"])
                    position.totalDividends = decimal(dict["totalDividends"])
                    position.totalFees = decimal(dict["totalFees"])
                    context.insert(position)
                }
                try context.save()
            }

            clearUserDefaultsFlags()
            UserDefaults.standard.set(true, forKey: skipDemoSeedKey)
            AppLog.debug("local data import completed")
        } catch let error as LocalDataImportError {
            throw error
        } catch {
            throw LocalDataImportError.persistence(error.localizedDescription)
        }
    }

    /// 导出本地数据为 JSON（供系统分享面板）。不含密码与 API Key（本 App 亦不存储这些）。
    @MainActor
    static func exportJSON(context: ModelContext) throws -> Data {
        let instruments = try context.fetch(FetchDescriptor<Instrument>())
        let transactions = try context.fetch(FetchDescriptor<TransactionRecord>(
            sortBy: [SortDescriptor(\.tradeDate, order: .forward)]
        ))
        let positions = try context.fetch(FetchDescriptor<Position>())
        let deposits = try context.fetch(FetchDescriptor<BankDepositAccount>())
        let fx = try context.fetch(FetchDescriptor<FXSavingsAccount>())
        let bonds = try context.fetch(FetchDescriptor<BondHolding>())
        let cash = try context.fetch(FetchDescriptor<CashOtherAsset>())
        let liabilities = try context.fetch(FetchDescriptor<LiabilityRecord>())
        let events = try context.fetch(FetchDescriptor<ManualCapitalEvent>())
        let lifestyle = try context.fetch(FetchDescriptor<LifestyleEntry>())
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first

        let payload: [String: Any] = [
            "exportedAt": isoString(from: Date()),
            "app": "WealthKeeper",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "note": "本地导出备份。不含银行卡/券商密码、验证码或 API Key。",
            "instruments": instruments.map { [
                "id": $0.id,
                "symbol": $0.symbol,
                "name": $0.name,
                "market": $0.market.rawValue,
                "type": $0.type.rawValue,
                "currency": $0.currency,
            ] as [String: Any] },
            "transactions": transactions.map { tx -> [String: Any] in
                [
                    "id": tx.id.uuidString,
                    "instrumentID": tx.instrumentID,
                    "kind": tx.kind.rawValue,
                    "tradeDate": isoString(from: tx.tradeDate),
                    "recordDate": tx.recordDate.map { isoString(from: $0) } as Any,
                    "quantity": "\(tx.quantity)",
                    "sharesOnRecord": "\(tx.sharesOnRecord)",
                    "price": "\(tx.price)",
                    "fee": "\(tx.fee)",
                    "cashAmount": "\(tx.cashAmount)",
                    "splitRatio": "\(tx.splitRatio)",
                    "currency": tx.currency,
                    "note": tx.note,
                ]
            },
            "positions": positions.map { [
                "instrumentID": $0.instrumentID,
                "quantity": "\($0.quantity)",
                "averageCost": "\($0.averageCost)",
                "totalCost": "\($0.totalCost)",
                "realizedPnL": "\($0.realizedPnL)",
                "totalDividends": "\($0.totalDividends)",
                "totalFees": "\($0.totalFees)",
            ] as [String: Any] },
            "bankDeposits": deposits.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "productName": $0.productName,
                "balance": "\($0.balance)",
                "currency": $0.currency,
                "annualRate": "\($0.annualRate)",
                "valueDate": $0.valueDate.map { isoString(from: $0) } as Any,
                "maturityDate": $0.maturityDate.map { isoString(from: $0) } as Any,
                "accruedInterest": "\($0.accruedInterest)",
                "receivedInterest": "\($0.receivedInterest)",
                "depositKind": $0.depositKind.rawValue,
                "wealthStyle": $0.wealthStyle.rawValue,
                "riskLevel": $0.riskLevel.rawValue,
                "unitNav": "\($0.unitNav)",
                "expectedRedemptionDate": $0.expectedRedemptionDate.map { isoString(from: $0) } as Any,
                "note": $0.note,
            ] as [String: Any] },
            "fxSavings": fx.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "balance": "\($0.balance)",
                "currency": $0.currency,
                "annualRate": "\($0.annualRate)",
                "valueDate": $0.valueDate.map { isoString(from: $0) } as Any,
                "maturityDate": $0.maturityDate.map { isoString(from: $0) } as Any,
                "accruedInterest": "\($0.accruedInterest)",
                "receivedInterest": "\($0.receivedInterest)",
                "note": $0.note,
            ] as [String: Any] },
            "bonds": bonds.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "faceValue": "\($0.faceValue)",
                "cost": "\($0.cost)",
                "currency": $0.currency,
                "couponRate": "\($0.couponRate)",
                "purchaseDate": isoString(from: $0.purchaseDate),
                "valueDate": $0.valueDate.map { isoString(from: $0) } as Any,
                "maturityDate": $0.maturityDate.map { isoString(from: $0) } as Any,
                "expectedRedemptionDate": $0.expectedRedemptionDate.map { isoString(from: $0) } as Any,
                "couponFrequency": $0.couponFrequency.rawValue,
                "marketValue": $0.marketValue.map { "\($0)" } as Any,
                "accruedInterest": "\($0.accruedInterest)",
                "receivedInterest": "\($0.receivedInterest)",
                "note": $0.note,
            ] as [String: Any] },
            "cashOther": cash.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "balance": "\($0.balance)",
                "currency": $0.currency,
                "kindRaw": $0.kindRaw,
                "note": $0.note,
            ] as [String: Any] },
            "liabilities": liabilities.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "balance": "\($0.balance)",
                "currency": $0.currency,
                "note": $0.note,
            ] as [String: Any] },
            "manualCapitalEvents": events.map { [
                "id": $0.id.uuidString,
                "assetID": $0.assetID,
                "assetClass": $0.assetClass.rawValue,
                "kind": $0.kind.rawValue,
                "amount": "\($0.amount)",
                "currency": $0.currency,
                "eventDate": isoString(from: $0.eventDate),
                "note": $0.note,
            ] as [String: Any] },
            "lifestyle": lifestyle.map { [
                "id": $0.id.uuidString,
                "flowKind": $0.flowKind.rawValue,
                "amount": "\($0.amount)",
                "category": $0.category.rawValue,
                "currency": $0.currency,
                "entryDate": isoString(from: $0.entryDate),
                "note": $0.note,
            ] as [String: Any] },
            "settings": [
                "baseCurrency": settings?.baseCurrency ?? "CNY",
                "autoImportCorporateActions": settings?.autoImportCorporateActions ?? true,
                "useMockMarketData": settings?.useMockMarketData ?? false,
                // 导出不含 lastMarketDiag（可能含诊断信息）
            ] as [String: Any],
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    /// 供测试：统计各实体数量与敏感设置是否清空。
    @MainActor
    static func residualSnapshot(context: ModelContext) throws -> [String: Int] {
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        let diagEmpty = settings.allSatisfy { $0.lastMarketDiag.isEmpty }
        let fxReset = settings.allSatisfy {
            $0.fxJSON.contains(#""CNY""#) && !$0.fxJSON.contains("7.")
        }
        return [
            "instruments": try context.fetch(FetchDescriptor<Instrument>()).count,
            "transactions": try context.fetch(FetchDescriptor<TransactionRecord>()).count,
            "positions": try context.fetch(FetchDescriptor<Position>()).count,
            "quotes": try context.fetch(FetchDescriptor<CachedQuote>()).count,
            "corporateActions": try context.fetch(FetchDescriptor<CorporateActionRecord>()).count,
            "deposits": try context.fetch(FetchDescriptor<BankDepositAccount>()).count,
            "fx": try context.fetch(FetchDescriptor<FXSavingsAccount>()).count,
            "bonds": try context.fetch(FetchDescriptor<BondHolding>()).count,
            "cash": try context.fetch(FetchDescriptor<CashOtherAsset>()).count,
            "liabilities": try context.fetch(FetchDescriptor<LiabilityRecord>()).count,
            "events": try context.fetch(FetchDescriptor<ManualCapitalEvent>()).count,
            "lifestyle": try context.fetch(FetchDescriptor<LifestyleEntry>()).count,
            "settingsRows": settings.count,
            "diagCleared": diagEmpty ? 1 : 0,
            "fxSnapshotReset": fxReset ? 1 : 0,
            "udFlagsCleared": userDefaultsKeys.allSatisfy { UserDefaults.standard.object(forKey: $0) == nil } ? 1 : 0,
        ]
    }

    // MARK: - Private

    @MainActor
    private static func wipeBusinessData(context: ModelContext, includingSettings: Bool) throws {
        try deleteAll(of: Instrument.self, context: context)
        try deleteAll(of: TransactionRecord.self, context: context)
        try deleteAll(of: Position.self, context: context)
        try deleteAll(of: CachedQuote.self, context: context)
        try deleteAll(of: CorporateActionRecord.self, context: context)
        try deleteAll(of: BankDepositAccount.self, context: context)
        try deleteAll(of: FXSavingsAccount.self, context: context)
        try deleteAll(of: BondHolding.self, context: context)
        try deleteAll(of: CashOtherAsset.self, context: context)
        try deleteAll(of: LiabilityRecord.self, context: context)
        try deleteAll(of: ManualCapitalEvent.self, context: context)
        try deleteAll(of: LifestyleEntry.self, context: context)

        if includingSettings {
            let settings = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
            for item in settings {
                context.delete(item)
            }
        }
    }

    private static func deleteAll<T: PersistentModel>(of type: T.Type, context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        for item in items {
            context.delete(item)
        }
    }

    private static func decimal(_ any: Any?, default defaultValue: Decimal = 0) -> Decimal {
        if let s = any as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let d = Decimal(string: trimmed) { return d }
            return defaultValue
        }
        if let n = any as? NSNumber {
            return Decimal(string: n.stringValue) ?? defaultValue
        }
        return defaultValue
    }

    private static func parseDate(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isoFormatter.date(from: trimmed) ?? isoFormatterFallback.date(from: trimmed)
    }

    private static func isoString(from date: Date) -> String {
        isoFormatterFallback.string(from: date)
    }
}
