import Foundation

/// 上架 / 支持相关链接与联系方式。
/// App Store Connect 的「隐私政策 URL」必须与 `privacyPolicyURL` 指向同一可公网访问的 HTTPS 页面。
enum AppSupportConfig {
    /// 开发者支持邮箱（设置页「联系我们」与隐私政策文案共用）
    static let supportEmail = "yiwenzhang8900@gmail.com"

    /// 支持页（可为邮箱 mailto，或后续换成官网）
    static let supportURL = URL(string: "mailto:\(supportEmail)")!

    /// 公网隐私政策（GitHub Pages：仓库 Settings → Pages → /docs）
    static let privacyPolicyURLString = "https://yiwenzhang8900-coder.github.io/WealthKeeper/privacy/"

    /// 公网用户协议
    static let termsOfUseURLString = "https://yiwenzhang8900-coder.github.io/WealthKeeper/terms/"

    static var privacyPolicyURL: URL? {
        resolvedPublicURL(privacyPolicyURLString)
    }

    static var termsOfUseURL: URL? {
        resolvedPublicURL(termsOfUseURLString)
    }

    private static func resolvedPublicURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host,
              !host.isEmpty,
              host != "example.com"
        else { return nil }
        return url
    }
}
