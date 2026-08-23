#!/usr/bin/env swift
/**
 隐私相关：日志脱敏 + 清空标记逻辑（无 SwiftData）
 用法: swift scripts/PrivacySafetyTests.swift
 */

import Foundation

enum AppLogMirror {
    static func maskSymbol(_ symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3 else { return "***" }
        return "***\(trimmed.suffix(3))"
    }

    static func sanitize(_ raw: String) -> String {
        var text = raw
        let patterns = [
            #"(?i)(api[_-]?key|token|password|secret|authorization)\s*[=:]\s*\S+"#,
            #"(?i)Bearer\s+\S+"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: "[redacted]"
                )
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"\b([0-9]{5,6}|[A-Z]{1,5})\b"#) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            let keep: Set<String> = ["CNY", "USD", "HKD", "DEBUG", "ERROR", "HTTP", "FX", "OK"]
            for match in matches.reversed() {
                let token = ns.substring(with: match.range)
                if keep.contains(token.uppercased()) { continue }
                if token.count >= 4 || token.allSatisfy(\.isNumber) {
                    text = (text as NSString).replacingCharacters(in: match.range, with: maskSymbol(token))
                }
            }
        }
        return text
    }
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

expect("maskSymbol 600519", AppLogMirror.maskSymbol("600519") == "***519")
expect("maskSymbol AAPL", AppLogMirror.maskSymbol("AAPL") == "***APL")
expect("sanitize hides token", !AppLogMirror.sanitize("token=D43EE5B10BFB2E0B6E4F2B5E9B5E5E5E").contains("D43EE"))
expect("sanitize masks code", AppLogMirror.sanitize("ashare 600519 ok").contains("***519"))
expect("sanitize keeps FX label", AppLogMirror.sanitize("FX fail").contains("FX"))

// UserDefaults wipe keys
let keys = ["wk_manual_assets_seeded_v1", "wk_mock_default_applied_v1"]
let skipKey = "wk_user_cleared_data_v1"
let suite = UserDefaults(suiteName: "wk.privacy.test.\(UUID().uuidString)")!
for k in keys { suite.set(true, forKey: k) }
for k in keys { suite.removeObject(forKey: k) }
suite.set(true, forKey: skipKey)
expect("ud flags cleared", keys.allSatisfy { suite.object(forKey: $0) == nil })
expect("skip demo seed set", suite.bool(forKey: skipKey) == true)

print("\n——")
print("Result: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
