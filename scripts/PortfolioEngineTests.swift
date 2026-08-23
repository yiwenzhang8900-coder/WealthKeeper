#!/usr/bin/env swift
/**
 持仓引擎：买入 / 卖出 / 现金分红 / 红利再投资 / 送股 / 拆股
 用法: swift scripts/PortfolioEngineTests.swift
 */

import Foundation

// MARK: - Mirror enums & ledger (keep in sync with PortfolioEngine)

enum TransactionKind: String {
    case buy, sell, dividend, dividendReinvest, bonusShare, fee, split

    var ledgerRank: Int {
        switch self {
        case .buy: return 0
        case .sell: return 1
        case .split: return 2
        case .bonusShare: return 3
        case .dividendReinvest: return 4
        case .dividend: return 5
        case .fee: return 6
        }
    }
}

struct PositionLedgerState: Equatable {
    var quantity: Decimal = 0
    var averageCost: Decimal = 0
    var totalCost: Decimal = 0
    var realizedPnL: Decimal = 0
    var totalDividends: Decimal = 0
    var totalFees: Decimal = 0
}

struct LedgerTransaction {
    var kind: TransactionKind
    var tradeDate: Date
    var quantity: Decimal = 0
    var price: Decimal = 0
    var fee: Decimal = 0
    var cashAmount: Decimal = 0
    var splitRatio: Decimal = 1
    var sharesOnRecord: Decimal = 0
    var createdAt: Date = .distantPast
}

enum Engine {
    static let eps = Decimal(string: "0.0000001")!

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

    static func dividendCash(_ tx: LedgerTransaction) -> Decimal {
        if tx.cashAmount > 0 { return tx.cashAmount }
        let shares = tx.sharesOnRecord > 0 ? tx.sharesOnRecord : tx.quantity
        return shares * tx.price
    }

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
            if tx.kind == .dividend || tx.kind == .fee { continue }
            apply(tx, to: &state)
        }
        return max(0, state.quantity)
    }

    static func replay(_ transactions: [LedgerTransaction]) -> PositionLedgerState {
        var state = PositionLedgerState()
        for tx in sorted(transactions) {
            apply(tx, to: &state)
        }
        return state
    }
}

// MARK: - Helpers

func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d
    return Calendar(identifier: .gregorian).date(from: c)!
}

func approxEqual(_ a: Decimal, _ b: Decimal, eps: Decimal = Decimal(string: "0.0001")!) -> Bool {
    abs(a - b) <= eps
}

var passed = 0
var failed = 0
func expect(_ name: String, _ cond: @autoclosure () -> Bool, _ detail: @autoclosure () -> String = "") {
    if cond() {
        passed += 1
        print("PASS  \(name)")
    } else {
        failed += 1
        let d = detail()
        print("FAIL  \(name)\(d.isEmpty ? "" : " — \(d)")")
    }
}

// MARK: - Cases

let dBuy = day(2024, 1, 10)
let dRecord = day(2024, 6, 10)
let dSellAfter = day(2024, 6, 20)
let dSellBefore = day(2024, 5, 1)
let dEx = day(2024, 6, 11)

// 1) 买入
do {
    let txs = [
        LedgerTransaction(kind: .buy, tradeDate: dBuy, quantity: 100, price: 10, fee: 5)
    ]
    let s = Engine.replay(txs)
    expect("买入：数量", s.quantity == 100)
    expect("买入：成本含手续费", approxEqual(s.totalCost, 1005), "got \(s.totalCost)")
    expect("买入：均价", approxEqual(s.averageCost, Decimal(string: "10.05")!), "got \(s.averageCost)")
}

// 2) 卖出
do {
    let txs = [
        LedgerTransaction(kind: .buy, tradeDate: dBuy, quantity: 100, price: 10),
        LedgerTransaction(kind: .sell, tradeDate: dSellAfter, quantity: 40, price: 12, fee: 2)
    ]
    let s = Engine.replay(txs)
    expect("卖出：剩余数量", s.quantity == 60)
    // proceeds 40*12-2=478, costReleased 400, realized 78
    expect("卖出：已实现", approxEqual(s.realizedPnL, 78), "got \(s.realizedPnL)")
}

// 3) 现金分红：按登记日持仓；登记日后卖出不影响
do {
    let txs = [
        LedgerTransaction(kind: .buy, tradeDate: dBuy, quantity: 100, price: 10),
        LedgerTransaction(
            kind: .dividend, tradeDate: dRecord, quantity: 100, price: Decimal(string: "0.5")!,
            cashAmount: 50, sharesOnRecord: 100
        ),
        LedgerTransaction(kind: .sell, tradeDate: dSellAfter, quantity: 100, price: 11)
    ]
    let onRecord = Engine.quantityAsOf(txs, asOf: dRecord)
    expect("分红：登记日持仓（卖出前）", onRecord == 100)

    let s = Engine.replay(txs)
    expect("分红：清仓后数量为 0", s.quantity == 0)
    expect("分红：累计分红仍保留", approxEqual(s.totalDividends, 50), "got \(s.totalDividends)")
    expect("分红：已实现含分红", s.realizedPnL >= 50)
}

// 4) 登记日前卖出 → 登记日持仓 0，不应记分红（quantityAsOf）
do {
    let txs = [
        LedgerTransaction(kind: .buy, tradeDate: dBuy, quantity: 100, price: 10),
        LedgerTransaction(kind: .sell, tradeDate: dSellBefore, quantity: 100, price: 11)
    ]
    let onRecord = Engine.quantityAsOf(txs, asOf: dRecord)
    expect("登记日前卖出：登记日持仓为 0", onRecord == 0)

    // 若错误用「当前持仓」会在清仓后仍为 0，这里再买入验证：当前有仓但登记日无仓
    let txs2 = txs + [
        LedgerTransaction(kind: .buy, tradeDate: day(2024, 7, 1), quantity: 80, price: 9)
    ]
    let onRecord2 = Engine.quantityAsOf(txs2, asOf: dRecord)
    let current = Engine.replay(txs2).quantity
    expect("禁止倒推：登记日 0 且当前有仓", onRecord2 == 0 && current == 80)
}

// 5) 红利再投资
do {
    let txs = [
        LedgerTransaction(kind: .buy, tradeDate: dBuy, quantity: 1000, price: Decimal(string: "1.5")!),
        LedgerTransaction(
            kind: .dividendReinvest, tradeDate: dRecord,
            quantity: 20, // 再投资份额
            price: Decimal(string: "0.03")!, // 每份分红
            cashAmount: 30,
            sharesOnRecord: 1000
        )
    ]
    let s = Engine.replay(txs)
    expect("再投资：份额增加", s.quantity == 1020, "got \(s.quantity)")
    expect("再投资：累计分红", approxEqual(s.totalDividends, 30), "got \(s.totalDividends)")
    expect("再投资：成本增加分红额", approxEqual(s.totalCost, 1500 + 30), "got \(s.totalCost)")
}

// 6) 送股
do {
    let txs = [
        LedgerTransaction(kind: .buy, tradeDate: dBuy, quantity: 100, price: 10),
        LedgerTransaction(kind: .bonusShare, tradeDate: dRecord, quantity: 10, sharesOnRecord: 100)
    ]
    let s = Engine.replay(txs)
    expect("送股：数量 110", s.quantity == 110)
    expect("送股：总成本不变", approxEqual(s.totalCost, 1000), "got \(s.totalCost)")
    expect("送股：均价摊薄", approxEqual(s.averageCost, Decimal(string: "1000")! / 110), "got \(s.averageCost)")
    expect("送股：不分红现金", s.totalDividends == 0)
}

// 7) 拆股
do {
    let txs = [
        LedgerTransaction(kind: .buy, tradeDate: dBuy, quantity: 100, price: 20),
        LedgerTransaction(kind: .split, tradeDate: dEx, splitRatio: 2)
    ]
    let s = Engine.replay(txs)
    expect("拆股：数量翻倍", s.quantity == 200)
    expect("拆股：均价减半", approxEqual(s.averageCost, 10), "got \(s.averageCost)")
    expect("拆股：总成本不变", approxEqual(s.totalCost, 2000), "got \(s.totalCost)")
}

// 8) 登记日后卖出：quantityAsOf 仍用登记日数量算分红金额
do {
    let txs = [
        LedgerTransaction(kind: .buy, tradeDate: dBuy, quantity: 200, price: 10),
        LedgerTransaction(kind: .sell, tradeDate: dSellAfter, quantity: 150, price: 11)
    ]
    let onRecord = Engine.quantityAsOf(txs, asOf: dRecord)
    expect("登记日后卖出：登记日仍 200", onRecord == 200)
    let cash = onRecord * Decimal(string: "0.25")!
    expect("按登记日算分红金额", approxEqual(cash, 50), "got \(cash)")
}

print("\n——")
print("Result: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
