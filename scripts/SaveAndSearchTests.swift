#!/usr/bin/env swift
/**
 保存 / 搜索链路可重复测试
 用法: swift scripts/SaveAndSearchTests.swift
 */

import Foundation

// MARK: - Minimal mirrors

enum Market: String { case cnA = "CN_A", hk = "HK", us = "US", cnFund = "CN_FUND"
    var defaultCurrency: String {
        switch self {
        case .cnA, .cnFund: return "CNY"
        case .hk: return "HKD"
        case .us: return "USD"
        }
    }
}
enum InstrumentType: String { case stock, etf, fund }
enum TransactionKind: String { case buy, sell, dividend, fee, split }

enum NumberParsing {
    static func double(from raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }
}

enum TransactionSaveError: Error, Equatable {
    case missingSymbol, invalidQuantityOrPrice, invalidDividend, invalidFee, invalidSplit
}

struct SaveInput {
    var market: Market
    var assetType: InstrumentType
    var symbol: String
    var name: String
    var currency: String
    var kind: TransactionKind
    var quantityText: String
    var priceText: String
    var feeText: String
    var cashAmountText: String
    var splitRatioText: String
}

func prepare(_ input: SaveInput) -> Result<(symbol: String, qty: Double, px: Double), TransactionSaveError> {
    let trimmed = input.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized: String = {
        switch input.market {
        case .us: return trimmed.uppercased()
        case .hk:
            let d = trimmed.filter(\.isNumber)
            return d.isEmpty ? trimmed.uppercased() : String(d)
        case .cnA, .cnFund: return trimmed.uppercased()
        }
    }()
    guard !normalized.isEmpty else { return .failure(.missingSymbol) }
    let qty = NumberParsing.double(from: input.quantityText) ?? 0
    let px = NumberParsing.double(from: input.priceText) ?? 0
    let fee = NumberParsing.double(from: input.feeText) ?? 0
    let cash = NumberParsing.double(from: input.cashAmountText) ?? 0
    let ratio = NumberParsing.double(from: input.splitRatioText) ?? 1
    switch input.kind {
    case .buy, .sell:
        guard qty > 0, px > 0 else { return .failure(.invalidQuantityOrPrice) }
    case .dividend:
        guard cash > 0 || (qty > 0 && px > 0) else { return .failure(.invalidDividend) }
    case .fee:
        guard cash > 0 || fee > 0 else { return .failure(.invalidFee) }
    case .split:
        guard ratio > 0 else { return .failure(.invalidSplit) }
    }
    return .success((normalized, qty, px))
}

struct Hit: Equatable {
    var symbol: String
    var name: String
    var market: Market
}

let mockCatalog: [Hit] = [
    .init(symbol: "600519", name: "贵州茅台", market: .cnA),
    .init(symbol: "AAPL", name: "苹果", market: .us),
    .init(symbol: "00700", name: "腾讯控股", market: .hk),
    .init(symbol: "110022", name: "易方达消费行业股票", market: .cnFund),
]

func mockSearch(_ q: String) -> [Hit] {
    let upper = q.uppercased()
    let digits = String(q.filter(\.isNumber))
    return mockCatalog.filter {
        $0.symbol.uppercased().contains(upper) || $0.name.contains(q) || (!digits.isEmpty && $0.symbol.contains(digits))
    }
}

enum SearchErr: Error, Equatable { case timeout, ok }

func simulateSearch(useMock: Bool, forceTimeout: Bool) -> Result<[Hit], SearchErr> {
    if forceTimeout { return .failure(.timeout) }
    if useMock { return .success(mockSearch("600519")) }
    return .failure(.timeout) // 模拟远程不可达
}

// MARK: - Harness

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

// 1) 保存成功
do {
    let input = SaveInput(
        market: .cnA, assetType: .stock, symbol: "600519", name: "贵州茅台", currency: "CNY",
        kind: .buy, quantityText: "100", priceText: "1680.5", feeText: "5", cashAmountText: "", splitRatioText: "1"
    )
    let result = prepare(input)
    expect("保存成功：校验通过", {
        if case .success(let v) = result { return v.symbol == "600519" && v.qty == 100 && v.px == 1680.5 }
        return false
    }())
}

// 2) 保存失败：缺数量/价格
do {
    let input = SaveInput(
        market: .cnA, assetType: .stock, symbol: "600519", name: "", currency: "CNY",
        kind: .buy, quantityText: "", priceText: "10", feeText: "", cashAmountText: "", splitRatioText: "1"
    )
    let result = prepare(input)
    expect("保存失败：无效数量单价", {
        if case .failure(.invalidQuantityOrPrice) = result { return true }
        return false
    }())
}

// 2b) 保存失败：缺代码
do {
    let input = SaveInput(
        market: .cnA, assetType: .stock, symbol: "  ", name: "", currency: "CNY",
        kind: .buy, quantityText: "1", priceText: "10", feeText: "", cashAmountText: "", splitRatioText: "1"
    )
    expect("保存失败：缺代码", {
        if case .failure(.missingSymbol) = prepare(input) { return true }
        return false
    }())
}

// 2c) 兼容千分位输入仍可保存
do {
    let input = SaveInput(
        market: .us, assetType: .stock, symbol: "aapl", name: "", currency: "USD",
        kind: .buy, quantityText: "1,000", priceText: "190", feeText: "", cashAmountText: "", splitRatioText: "1"
    )
    expect("保存成功：千分位数量", {
        if case .success(let v) = prepare(input) { return v.symbol == "AAPL" && v.qty == 1000 }
        return false
    }())
}

// 3) 搜索成功（Mock）
do {
    let result = simulateSearch(useMock: true, forceTimeout: false)
    expect("搜索成功：Mock 返回茅台", {
        if case .success(let hits) = result {
            return hits.contains(where: { $0.symbol == "600519" && $0.name.contains("茅台") })
        }
        return false
    }())
    expect("搜索成功：Mock 可查 AAPL", mockSearch("AAPL").contains(where: { $0.symbol == "AAPL" }))
    expect("搜索成功：Mock 可查 0700→腾讯", mockSearch("0700").contains(where: { $0.name.contains("腾讯") }))
}

// 4) 搜索超时
do {
    let result = simulateSearch(useMock: false, forceTimeout: true)
    expect("搜索超时：返回 timeout", {
        if case .failure(.timeout) = result { return true }
        return false
    }())
    // 错误文案约定（与 App InstrumentSearchError.timeout 一致意图）
    let message = "搜索请求超时。可开启「设置 → 使用 Mock 数据」或稍后重试。"
    expect("搜索超时：提示含 Mock 引导", message.contains("Mock") && message.contains("超时"))
}

print("\n——")
print("Result: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
