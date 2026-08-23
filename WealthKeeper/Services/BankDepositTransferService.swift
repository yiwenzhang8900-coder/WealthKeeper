import Foundation
import SwiftData

/// 同银行（同名同币种）定期 ↔ 活期账本互转，不接真实银行接口。
enum BankDepositTransferService {
    /// 定期本金转入活期（不含预计利息；全部转出请用 `transferFixedToDemandFull`）。
    @MainActor
    static func transferFixedToDemand(
        _ fixed: BankDepositAccount,
        amount: Decimal,
        note: String,
        context: ModelContext
    ) -> BankDepositAccount? {
        guard fixed.depositKind == .fixed else { return nil }
        guard amount > 0, amount <= fixed.balance else { return nil }

        fixed.balance -= amount
        fixed.updatedAt = .now
        context.insert(
            ManualCapitalEvent(
                assetID: fixed.id,
                assetClass: .bankDeposit,
                kind: .withdraw,
                amount: amount,
                currency: fixed.currency,
                note: note
            )
        )

        let demand = findOrCreate(
            bankName: fixed.name,
            currency: fixed.currency,
            kind: .demand,
            context: context
        )
        demand.balance += amount
        demand.updatedAt = .now
        context.insert(
            ManualCapitalEvent(
                assetID: demand.id,
                assetClass: .bankDeposit,
                kind: .deposit,
                amount: amount,
                currency: fixed.currency,
                note: note
            )
        )

        return save(context, returning: demand)
    }

    /// 定期本息全部转入活期（到期 / 提前支取清仓）。
    @MainActor
    static func transferFixedToDemandFull(
        _ fixed: BankDepositAccount,
        note: String,
        context: ModelContext
    ) -> BankDepositAccount? {
        guard fixed.depositKind == .fixed else { return nil }
        let principal = fixed.balance
        let interest = fixed.displayAccruedInterest
        let total = principal + interest
        guard total > 0 else { return nil }

        if principal > 0 {
            context.insert(
                ManualCapitalEvent(
                    assetID: fixed.id,
                    assetClass: .bankDeposit,
                    kind: .withdraw,
                    amount: principal,
                    currency: fixed.currency,
                    note: note
                )
            )
        }
        if interest > 0 {
            context.insert(
                ManualCapitalEvent(
                    assetID: fixed.id,
                    assetClass: .bankDeposit,
                    kind: .interestReceived,
                    amount: interest,
                    currency: fixed.currency,
                    note: "\(note)·利息"
                )
            )
            fixed.receivedInterest += interest
        }

        fixed.balance = 0
        fixed.accruedInterest = 0
        fixed.updatedAt = .now

        let demand = findOrCreate(
            bankName: fixed.name,
            currency: fixed.currency,
            kind: .demand,
            context: context
        )
        demand.balance += total
        demand.updatedAt = .now
        context.insert(
            ManualCapitalEvent(
                assetID: demand.id,
                assetClass: .bankDeposit,
                kind: .deposit,
                amount: total,
                currency: fixed.currency,
                note: note
            )
        )

        return save(context, returning: demand)
    }

    /// 活期本金转入同名定期：指定已有定期，或按利率/起息/到期新建一笔。
    @MainActor
    static func transferDemandToFixed(
        _ demand: BankDepositAccount,
        amount: Decimal,
        targetFixed: BankDepositAccount?,
        createAnnualRate: Decimal = 0,
        createValueDate: Date? = nil,
        createMaturityDate: Date? = nil,
        note: String,
        context: ModelContext
    ) -> BankDepositAccount? {
        guard demand.depositKind == .demand else { return nil }
        guard amount > 0, amount <= demand.balance else { return nil }

        demand.balance -= amount
        demand.updatedAt = .now
        context.insert(
            ManualCapitalEvent(
                assetID: demand.id,
                assetClass: .bankDeposit,
                kind: .withdraw,
                amount: amount,
                currency: demand.currency,
                note: note
            )
        )

        let fixed: BankDepositAccount
        if let targetFixed, targetFixed.depositKind == .fixed,
           targetFixed.name == demand.name,
           targetFixed.currency == demand.currency {
            fixed = targetFixed
            fixed.balance += amount
            fixed.updatedAt = .now
        } else {
            fixed = BankDepositAccount(
                name: demand.name,
                balance: amount,
                currency: demand.currency,
                annualRate: createAnnualRate,
                valueDate: createValueDate,
                maturityDate: createMaturityDate,
                accruedInterest: 0,
                receivedInterest: 0,
                depositKind: .fixed,
                note: "由活期转入"
            )
            context.insert(fixed)
        }

        context.insert(
            ManualCapitalEvent(
                assetID: fixed.id,
                assetClass: .bankDeposit,
                kind: .deposit,
                amount: amount,
                currency: demand.currency,
                note: note
            )
        )

        return save(context, returning: fixed)
    }

    @MainActor
    static func peerAccounts(
        of item: BankDepositAccount,
        kind: BankDepositKind,
        context: ModelContext
    ) -> [BankDepositAccount] {
        let all = (try? context.fetch(FetchDescriptor<BankDepositAccount>())) ?? []
        return all.filter {
            $0.id != item.id
                && $0.name == item.name
                && $0.currency == item.currency
                && $0.depositKind == kind
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    @MainActor
    static func ensureDemandAccount(
        bankName: String,
        currency: String = "CNY",
        context: ModelContext
    ) -> BankDepositAccount {
        findOrCreate(
            bankName: bankName,
            currency: currency,
            kind: .demand,
            context: context
        )
    }

    @MainActor
    private static func findOrCreate(
        bankName: String,
        currency: String,
        kind: BankDepositKind,
        context: ModelContext
    ) -> BankDepositAccount {
        let all = (try? context.fetch(FetchDescriptor<BankDepositAccount>())) ?? []
        if let existing = all.first(where: {
            $0.name == bankName
                && $0.currency == currency.uppercased()
                && $0.depositKind == kind
        }) {
            return existing
        }
        let created = BankDepositAccount(
            name: bankName,
            balance: 0,
            currency: currency,
            annualRate: 0,
            depositKind: kind,
            note: ""
        )
        context.insert(created)
        try? context.save()
        return created
    }

    @MainActor
    private static func save(_ context: ModelContext, returning item: BankDepositAccount) -> BankDepositAccount? {
        do {
            try context.save()
            return item
        } catch {
            AppLog.error("bank deposit transfer failed: \(error.localizedDescription)")
            return nil
        }
    }
}

enum BankDepositMaturityPromptStore {
    private static func key(_ id: UUID) -> String { "wk_maturity_prompted_\(id.uuidString)" }

    static func hasPrompted(_ id: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(id))
    }

    static func markPrompted(_ id: UUID) {
        UserDefaults.standard.set(true, forKey: key(id))
    }
}

/// 银行理财：预计赎回到账日到期后的确认提醒（避免重复弹窗）
enum BankWealthRedemptionPromptStore {
    private static func key(_ id: UUID) -> String { "wk_wealth_redeem_prompted_\(id.uuidString)" }

    static func hasPrompted(_ id: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(id))
    }

    static func markPrompted(_ id: UUID) {
        UserDefaults.standard.set(true, forKey: key(id))
    }

    static func clearPrompted(_ id: UUID) {
        UserDefaults.standard.removeObject(forKey: key(id))
    }
}

enum BankWealthSettlementService {
    /// 确认到账：记收益到账和/或赎回本金，并清除预计到账日提醒状态。
    @discardableResult
    static func confirmArrival(
        _ item: BankDepositAccount,
        actualDate: Date,
        income: Decimal,
        redeemPrincipal: Decimal,
        context: ModelContext
    ) -> Bool {
        guard item.depositKind == .wealth else { return false }
        guard income >= 0, redeemPrincipal >= 0 else { return false }
        guard redeemPrincipal <= item.balance else { return false }
        guard income > 0 || redeemPrincipal > 0 else { return false }

        if income > 0 {
            item.receivedInterest += income
            context.insert(ManualCapitalEvent(
                assetID: item.id,
                assetClass: .bankDeposit,
                kind: .interestReceived,
                amount: income,
                currency: item.currency,
                eventDate: actualDate,
                note: "收益到账"
            ))
        }
        if redeemPrincipal > 0 {
            item.balance -= redeemPrincipal
            context.insert(ManualCapitalEvent(
                assetID: item.id,
                assetClass: .bankDeposit,
                kind: .withdraw,
                amount: redeemPrincipal,
                currency: item.currency,
                eventDate: actualDate,
                note: "赎回到账"
            ))
        }
        item.expectedRedemptionDate = nil
        item.updatedAt = .now
        BankWealthRedemptionPromptStore.markPrompted(item.id)
        do {
            try context.save()
            return true
        } catch {
            AppLog.error("wealth settlement failed: \(error.localizedDescription)")
            return false
        }
    }
}

/// 债券到期 / 预计到账日确认提醒
enum BondSettlementPromptStore {
    private static func key(_ id: UUID) -> String { "wk_bond_settle_prompted_\(id.uuidString)" }

    static func hasPrompted(_ id: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(id))
    }

    static func markPrompted(_ id: UUID) {
        UserDefaults.standard.set(true, forKey: key(id))
    }

    static func clearPrompted(_ id: UUID) {
        UserDefaults.standard.removeObject(forKey: key(id))
    }
}

enum BondSettlementService {
    /// 确认到期到账：记兑付收益，并可按面值/成本做到期赎回。
    @discardableResult
    static func confirmArrival(
        _ item: BondHolding,
        actualDate: Date,
        income: Decimal,
        redeemFace: Decimal,
        redeemCost: Decimal,
        context: ModelContext
    ) -> Bool {
        guard income >= 0, redeemFace >= 0, redeemCost >= 0 else { return false }
        guard redeemFace <= item.faceValue, redeemCost <= item.cost else { return false }
        guard income > 0 || redeemFace > 0 || redeemCost > 0 else { return false }

        if income > 0 {
            item.receivedInterest += income
            context.insert(ManualCapitalEvent(
                assetID: item.id,
                assetClass: .bond,
                kind: .interestReceived,
                amount: income,
                currency: item.currency,
                eventDate: actualDate,
                note: "兑付收益到账"
            ))
        }
        if redeemFace > 0 || redeemCost > 0 {
            let redeemAmount = redeemCost > 0 ? redeemCost : redeemFace
            item.faceValue = max(0, item.faceValue - redeemFace)
            item.cost = max(0, item.cost - redeemCost)
            if item.faceValue == 0 {
                item.marketValue = nil
                item.accruedInterest = 0
            }
            context.insert(ManualCapitalEvent(
                assetID: item.id,
                assetClass: .bond,
                kind: .maturityRedeem,
                amount: redeemAmount,
                currency: item.currency,
                eventDate: actualDate,
                note: "到期赎回"
            ))
        }
        item.expectedRedemptionDate = nil
        item.updatedAt = .now
        BondSettlementPromptStore.markPrompted(item.id)
        do {
            try context.save()
            return true
        } catch {
            AppLog.error("bond settlement failed: \(error.localizedDescription)")
            return false
        }
    }
}

/// 仅登记银行名称与可选英文字母简称（可无账户），与存款记录合并展示。
enum BankNameStore {
    private static let namesKey = "wk_bank_names"
    private static let abbrKey = "wk_bank_abbreviations"

    static func all() -> [String] {
        (UserDefaults.standard.stringArray(forKey: namesKey) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 用户保存的简称；未设置时返回 nil（由官方目录自动识别）。
    static func abbreviation(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let map = abbreviationMap()
        if let exact = map[trimmed], !exact.isEmpty { return exact }
        if let pair = map.first(where: { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame }),
           !pair.value.isEmpty {
            return pair.value
        }
        return nil
    }

    static func add(_ name: String, abbreviation: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var names = all()
        if !names.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            names.append(trimmed)
            names.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            UserDefaults.standard.set(names, forKey: namesKey)
        }
        let abbr = abbreviation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !abbr.isEmpty {
            setAbbreviation(abbr, for: trimmed)
        }
    }

    static func setAbbreviation(_ abbreviation: String, for name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbbr = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        var map = abbreviationMap()
        let key = all().first(where: { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }) ?? trimmedName
        if trimmedAbbr.isEmpty {
            map.removeValue(forKey: key)
        } else {
            map[key] = trimmedAbbr
        }
        UserDefaults.standard.set(map, forKey: abbrKey)
    }

    static func remove(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = all().filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        UserDefaults.standard.set(next, forKey: namesKey)
        var map = abbreviationMap()
        map = map.filter { $0.key.caseInsensitiveCompare(trimmed) != .orderedSame }
        UserDefaults.standard.set(map, forKey: abbrKey)
    }

    private static func abbreviationMap() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: abbrKey) as? [String: String]) ?? [:]
    }
}

/// 常见银行官方 / 通行英文字母简称（按关键词长度优先匹配）。
enum BankAbbreviationCatalog {
    struct Match: Equatable {
        let code: String
        /// 是否命中已知银行目录（可自动填充）
        let isOfficial: Bool
    }

    /// 返回推荐简称；命中目录时 `isOfficial == true`。
    static func match(for bankName: String) -> Match? {
        let name = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let rules: [(keywords: [String], code: String)] = [
            // 国有大行
            (["工商银行", "中国工商银行", "工行"], "ICBC"),
            (["建设银行", "中国建设银行", "建行"], "CCB"),
            (["农业银行", "中国农业银行", "农行"], "ABC"),
            (["中国银行", "中行"], "BOC"),
            (["交通银行", "交行"], "BOCOM"),
            (["邮储银行", "邮政储蓄银行", "邮政储蓄", "邮储"], "PSBC"),
            // 股份行
            (["招商银行", "招行"], "CMB"),
            (["浦发银行", "浦东发展银行", "浦发"], "SPDB"),
            (["兴业银行", "兴业"], "CIB"),
            (["民生银行", "民生"], "CMBC"),
            (["光大银行", "中国光大银行", "光大"], "CEB"),
            (["平安银行"], "PAB"),
            (["广发银行", "广发"], "CGB"),
            (["中信银行", "中国中信银行"], "CITIC"),
            (["华夏银行", "华夏"], "HXB"),
            (["浙商银行", "浙商"], "CZB"),
            (["渤海银行", "渤海"], "CBHB"),
            (["恒丰银行", "恒丰"], "HFBank"),
            // 城商 / 农商（常见）
            (["北京银行"], "BOB"),
            (["上海银行"], "BOS"),
            (["宁波银行"], "NBCB"),
            (["江苏银行"], "JSB"),
            (["南京银行"], "NJCB"),
            (["杭州银行"], "HZBANK"),
            (["上海农商", "沪农商"], "SRCB"),
            (["重庆银行"], "CQBANK"),
            (["成都银行"], "BOCD"),
            (["天津银行"], "TCCB"),
            // 外资
            (["汇丰银行", "汇丰"], "HSBC"),
            (["渣打银行", "渣打"], "SCB"),
            (["花旗银行", "花旗"], "Citi"),
            (["恒生银行", "恒生"], "HangSeng"),
            (["东亚银行", "东亚"], "BEA"),
            (["星展银行", "星展"], "DBS"),
            (["德意志银行", "德银"], "DB"),
            (["摩根大通", "JP摩根", "摩根大通银行"], "JPM"),
            // 互联网银行
            (["众安银行", "众安"], "ZA"),
            (["微众银行", "微众"], "WeBank"),
            (["网商银行", "网商"], "MYbank"),
            (["新网银行", "新网"], "XWBANK"),
            (["百信银行", "百信"], "AiBank"),
            (["苏宁银行", "苏宁"], "SNB"),
        ]

        let sorted = rules.sorted {
            let l = $0.keywords.map(\.count).max() ?? 0
            let r = $1.keywords.map(\.count).max() ?? 0
            return l > r
        }
        for rule in sorted {
            if rule.keywords.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
                return Match(code: rule.code, isOfficial: true)
            }
        }

        let latin = name.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
            .map { Character(UnicodeScalar($0.value)!).uppercased() }
            .joined()
        if latin.count >= 2 {
            return Match(code: String(latin.prefix(6)), isOfficial: false)
        }
        return nil
    }

    static func suggestedCode(for bankName: String) -> String? {
        match(for: bankName)?.code
    }

    /// 展示用：用户自定义 > 官方/候选识别 > 占位
    static func displayCode(for bankName: String) -> String {
        if let custom = BankNameStore.abbreviation(for: bankName), !custom.isEmpty {
            return custom
        }
        if let suggested = suggestedCode(for: bankName) {
            return suggested
        }
        return "BK"
    }
}
