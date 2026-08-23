import SwiftUI

enum LegalDocumentKind: String, Identifiable, CaseIterable {
    case privacy
    case terms
    case risk
    case dataSources
    case accountSecurity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: return "隐私政策"
        case .terms: return "用户协议"
        case .risk: return "金融风险提示"
        case .dataSources: return "数据来源说明"
        case .accountSecurity: return "账户安全说明"
        }
    }

    var bodyText: String {
        switch self {
        case .privacy: return Self.privacyText
        case .terms: return Self.termsText
        case .risk: return Self.riskText
        case .dataSources: return Self.dataSourcesText
        case .accountSecurity: return Self.accountSecurityText
        }
    }

    private static let privacyText = """
    更新日期：2026-08-23

    WealthKeeper（下称「本应用」）是运行在您设备上的个人财富记账与估值工具。开发者不运营云端账户系统，也不要求您注册登录。

    一、我们如何处理数据
    1. 您录入的资产、交易、分红、银行存款、债券、外币、现金、负债与生活记账等，仅保存在本机 SwiftData 数据库中（Application Support 目录下的本地文件）。
    2. 开发者不提供云同步，也不会把上述金额、持仓数量或交易明细上传到开发者自有服务器。
    3. 本应用不集成第三方统计分析 SDK、广告 SDK 或崩溃收集 SDK。

    二、会离开本机的请求
    当您主动刷新行情、搜索标的或拉取分红方案时，本应用可能通过 HTTPS 向第三方公开行情接口发送证券代码或搜索关键词，用于获取价格、净值、分红或汇率。请求中不包含持仓数量、成本、银行余额或生活记账金额。
    第三方可能包括：东方财富相关公开接口、Yahoo Finance、新浪外汇接口（汇率失败时的备用来源）。上述接口并非交易所/管理人官方授权数据源，仅作尽力估值参考，可能失败、延迟或不准确；失败时可手填价格或代码。

    公网隐私政策副本（若已托管）：请与 App Store 产品页「隐私政策」链接保持一致。

    三、日志
    正式版（Release）不对持仓代码、金额与交易明细做调试打印；设置中的行情诊断仅保留脱敏后的摘要。

    四、您的权利
    您可在设置中导出本地数据、导入备份、清除行情缓存，或删除全部本地数据。删除后相关业务数据将从本机移除；若系统备份中仍有历史副本，需由您在系统层面管理。

    五、联系
    请发送邮件至 \(AppSupportConfig.supportEmail)，或通过 App Store 产品页的开发者支持渠道反馈隐私问题。
    """

    private static let termsText = """
    更新日期：2026-08-23

    一、服务性质
    本应用仅为个人本地记账与资产估值辅助工具，不是银行、券商、基金销售机构、支付机构或投资顾问。

    二、使用要求
    1. 您应保证录入信息的真实性与合法性，并自行保管设备解锁方式。
    2. 禁止将本应用用于违法用途。
    3. 行情、净值、分红与汇率信息可能延迟或不准确，仅供个人参考；第三方公开接口非官方授权，失败时请以手动录入或官方渠道为准。

    三、无投资建议
    本应用不提供荐股、买卖建议、价格预测、收益保证或任何形式的投资咨询。任何投资决策应由您独立作出，并应以银行、券商、基金管理人等官方信息为准。

    四、数据与责任
    本地数据可能因卸载、系统清理、数据库升级失败重置或设备损坏而丢失。请定期使用「导出数据」自行备份，并在需要时使用「导入备份」恢复。因第三方行情接口不可用、设备故障或操作失误导致的损失，开发者在法律允许范围内不承担责任。

    五、协议变更
    我们可能更新本协议；更新后继续使用即视为知悉相关变更。

    六、联系
    \(AppSupportConfig.supportEmail)
    """

    private static let riskText = """
    重要提示（请仔细阅读）

    1. 本应用不是银行、证券公司、基金销售平台或持牌投资顾问，不提供开户、交易下单或资金托管。
    2. 本应用不提供荐股、买卖建议、价格预测或收益保证。
    3. 股票价格、基金净值、分红方案与汇率可能延迟、缺失或与交易所/管理人公布值存在误差。
    4. 分红与持仓收益按您录入的流水及本地规则估算，可能与券商交割单不一致。
    5. 您应以银行、券商、基金管理人、交易所等官方渠道信息作为最终依据。
    6. 投资有风险，入市需谨慎。历史收益不代表未来表现。
    """

    private static let dataSourcesText = """
    一、本地数据（仅本机）
    • 保存位置：应用沙盒 Application Support 目录中的 SwiftData 文件（当前库名形如 WealthKeeper_v11.store）。
    • 内容：标的、交易流水、持仓汇总、手动资产、生活记账、行情缓存、汇率快照与应用设置。
    • 保存期限：直至您删除、卸载或数据库升级失败被重置。
    • 备份行为：可能随 iCloud/电脑备份一并备份（取决于系统设置）。本应用未额外开启云同步。
    • 文件保护：创建库目录时会请求「首次解锁前完整保护」（completeUntilFirstUserAuthentication），设备锁定且未解锁前限制读取。本应用不自行实现复杂加密或账号登录。
    • 本应用不要求也不保存银行/券商密码、验证码或 API Key（详见「账户安全说明」）。

    二、第三方行情请求（HTTPS，非官方授权、尽力获取）
    • 东方财富公开接口：A 股报价、场外基金净值、分红方案、部分外汇、标的搜索；用途为估值与分红估算。
    • Yahoo Finance 公开接口：港股与美股报价、分红/拆股事件。
    • 新浪外汇公开接口：在东财外汇失败时作为汇率备用来源。
    • 本应用以可识别的 App User-Agent 访问上述 HTTPS 接口；不保证可用性。失败或缺失时请手填价格/代码，或以银行、券商、基金管理人、交易所官方信息为准。
    • 请求内容仅为证券代码或搜索关键词，不含持仓数量、成本或账户余额。
    • 更新时间：以您在应用内手动刷新为准；设置页可查看上次刷新时间与汇率来源。
    • 发送内容：证券代码或搜索关键词；不发送持仓数量与金额。

    三、日志与分析
    • 不使用第三方分析、广告或崩溃 SDK。
    • Release 模式关闭调试日志，错误日志脱敏。

    四、删除与导出
    • 导出数据：设置 → 导出数据（JSON，经系统分享面板保存）。
    • 清除行情缓存：删除 CachedQuote 与市场诊断，不影响交易与持仓。
    • 删除全部本地数据：清除全部业务实体、重置设置与汇率快照，并清除相关 UserDefaults 标记（需二次确认）。
    """

    private static let accountSecurityText = """
    本 App 只用于记录资产、查看行情和估算收益。当前版本不连接银行或券商账户，也不会代用户登录、交易或转账。

    使用本 App 不需要填写银行密码、券商密码、短信验证码、支付密码或 API Key。请不要在任何输入框中填写这些信息。

    你在 App 中录入的持仓、交易记录和资产信息保存在本机。查询行情时，App 只会发送获取行情所需的证券代码或搜索词，不会发送持仓数量、买入成本、资产金额或银行余额。

    行情数据可能存在延迟或误差，具体以相关银行、券商、基金公司或交易所公布的信息为准。
    """
}

struct LegalDocumentView: View {
    let kind: LegalDocumentKind

    var body: some View {
        ScrollView {
            Text(kind.bodyText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 录入表单顶部的短安全提示卡
struct SecurityTipCard: View {
    @Environment(\.wkTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("安全提示")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            Text("本 App 只用于记录资产、查看行情和估算收益，不提供银行或券商账户登录、交易或转账。无需输入银行/券商密码、短信验证码或支付密码。")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.secondaryCardBackground)
        )
    }
}

enum SecurityTipStorage {
    static let manualAssetsFirstTipKey = "wk_manual_assets_security_tip_seen_v1"

    static var hasSeenManualAssetsTip: Bool {
        UserDefaults.standard.bool(forKey: manualAssetsFirstTipKey)
    }

    static func markManualAssetsTipSeen() {
        UserDefaults.standard.set(true, forKey: manualAssetsFirstTipKey)
    }
}
