#!/usr/bin/env swift
import Foundation

func rebase(_ cnyBased: [String: Double], to base: String) -> [String: Double] {
    let baseUpper = base.uppercased()
    guard let baseInCNY = cnyBased[baseUpper], baseInCNY > 0 else { return cnyBased }
    var out: [String: Double] = [:]
    for (cur, perCNY) in cnyBased {
        out[cur] = perCNY / baseInCNY
    }
    out[baseUpper] = 1
    return out
}

func parseSinaFX(text: String, symbol: String) -> Double? {
    guard let range = text.range(of: "hq_str_\(symbol)=\"") else { return nil }
    let rest = text[range.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    let body = String(rest[..<end])
    let parts = body.split(separator: ",").map(String.init)
    for part in parts.dropFirst().prefix(8) {
        if let v = Double(part), v > 0.5, v < 20 { return v }
    }
    return nil
}

var passed = 0, failed = 0
func expect(_ name: String, _ cond: Bool) {
    if cond { passed += 1; print("PASS  \(name)") }
    else { failed += 1; print("FAIL  \(name)") }
}

let cnyBased = ["CNY": 1.0, "USD": 7.2, "HKD": 0.92]
let toCNY = rebase(cnyBased, to: "CNY")
expect("本位 CNY：USD≈7.2", abs((toCNY["USD"] ?? 0) - 7.2) < 0.0001)
expect("本位 CNY：HKD≈0.92", abs((toCNY["HKD"] ?? 0) - 0.92) < 0.0001)

let toUSD = rebase(cnyBased, to: "USD")
expect("本位 USD：USD=1", abs((toUSD["USD"] ?? 0) - 1) < 0.0001)
expect("本位 USD：CNY≈1/7.2", abs((toUSD["CNY"] ?? 0) - (1 / 7.2)) < 0.0001)

let sample = #"var hq_str_fx_susdcny="美元,12:00:00,7.2450,7.2470,7.2400";"#
expect("新浪解析 USD/CNY", abs((parseSinaFX(text: sample, symbol: "fx_susdcny") ?? 0) - 7.245) < 0.0001)

print("\nResult: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
