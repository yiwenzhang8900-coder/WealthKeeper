import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Query private var settingsList: [AppSettings]
    @Query private var transactions: [TransactionRecord]

    @AppStorage(AppThemeMode.storageKey) private var themeModeRaw: String = AppThemeMode.system.rawValue

    @State private var confirmDeleteAll = false
    @State private var confirmClearQuotes = false
    @State private var confirmImport = false
    @State private var showImporter = false
    @State private var statusMessage: String?
    /// 最近一次导出文件，分享结束后可清理
    @State private var lastExportURL: URL?

    private var settings: AppSettings {
        if let first = settingsList.first { return first }
        let created = AppSettings()
        context.insert(created)
        return created
    }

    private var themeMode: Binding<AppThemeMode> {
        Binding(
            get: { AppThemeMode.stored(raw: themeModeRaw) },
            set: { themeModeRaw = $0.rawValue }
        )
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("主题模式", selection: themeMode) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } header: {
                    Text("外观")
                } footer: {
                    Text("新用户默认跟随系统。切换后立即生效，并在下次启动时保持。")
                }

                Section {
                    NavigationLink("计价") {
                        PricingSettingsView()
                    }
                    NavigationLink("汇率") {
                        FXSettingsView()
                    }
                    NavigationLink("数据") {
                        LocalDataStatsView()
                    }
                } header: {
                    Text("偏好与状态")
                }

                legalSection
                dataManagementSection
                aboutSection
            }
            .wkPageChrome()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "清除行情缓存？",
                isPresented: $confirmClearQuotes,
                titleVisibility: .visible
            ) {
                Button("清除缓存", role: .destructive, action: clearQuotes)
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除本地行情缓存与诊断摘要，不影响交易与持仓。")
            }
            .confirmationDialog(
                "删除全部本地数据？",
                isPresented: $confirmDeleteAll,
                titleVisibility: .visible
            ) {
                Button("永久删除", role: .destructive, action: deleteAll)
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作不可撤销。将清除全部资产、交易、缓存与相关本地标记。建议先导出备份。")
            }
            .confirmationDialog(
                "导入备份将替换全部本地数据？",
                isPresented: $confirmImport,
                titleVisibility: .visible
            ) {
                Button("继续导入", role: .destructive) { showImporter = true }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将用所选 JSON 备份覆盖当前全部资产、交易、持仓与设置。此操作不可撤销，建议先导出当前数据。")
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        statusMessage = "未选择备份文件。"
                        return
                    }
                    importBackup(from: url)
                case .failure:
                    statusMessage = "导入失败，请重试。"
                }
            }
            .alert("提示", isPresented: statusAlertBinding) {
                Button("好", role: .cancel) { statusMessage = nil }
            } message: {
                Text(statusMessage ?? "")
            }
        }
        .background {
            theme.pageBackground.ignoresSafeArea(edges: .all)
        }
    }

    private var statusAlertBinding: Binding<Bool> {
        Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )
    }

    private var legalSection: some View {
        Section("隐私与安全") {
            ForEach(LegalDocumentKind.allCases) { kind in
                NavigationLink(kind.title) {
                    LegalDocumentView(kind: kind)
                }
            }
            if let privacyURL = AppSupportConfig.privacyPolicyURL {
                Link("在线隐私政策", destination: privacyURL)
            }
            if let termsURL = AppSupportConfig.termsOfUseURL {
                Link("在线用户协议", destination: termsURL)
            }
        }
    }

    private var dataManagementSection: some View {
        Section {
            NavigationLink("流水记录") {
                CapitalFlowRecordsView()
            }
            Button("导出数据", action: exportData)
            Button("导入备份") { confirmImport = true }
            Button("清除行情缓存") { confirmClearQuotes = true }
            Button("重建持仓") {
                PortfolioEngine.rebuildPositions(transactions: transactions, context: context)
                statusMessage = "已按交易流水重建持仓。"
            }
            Button("删除全部本地数据", role: .destructive) {
                confirmDeleteAll = true
            }
        } header: {
            Text("数据管理")
        } footer: {
            Text("流水记录按资产类型分类展示。导入会替换全部本地数据。删除将清除持仓、交易、手动资产、行情缓存、汇率快照与设置中的诊断信息，且需确认。导出仅保存在您选择的位置。")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: appVersion)
            Link("联系支持（邮件）", destination: AppSupportConfig.supportURL)
            Text(AppSupportConfig.supportEmail)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .textSelection(.enabled)
            Text("本应用不是银行、券商、基金平台或投资顾问；不提供荐股、买卖建议、价格预测或收益保证。行情、净值、分红与汇率可能延迟或存在误差，请以官方信息为准。")
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func exportData() {
        do {
            let data = try LocalDataMaintenance.exportJSON(context: context)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("WealthKeeper-export-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url, options: .atomic)
            if let old = lastExportURL {
                try? FileManager.default.removeItem(at: old)
            }
            lastExportURL = url
            // 用 UIKit present，避免 SwiftUI .sheet 包 UIActivityViewController 导致底层变白板。
            SharePresenter.present(items: [url]) {
                // 分享面板关闭后不强制清文件，便于用户再次导出对比；下次导出会替换。
            }
            AppLog.debug("export ok")
        } catch {
            statusMessage = "导出失败，请重试。"
            AppLog.error("export failed")
        }
    }

    private func importBackup(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            try LocalDataMaintenance.importJSON(data, context: context)
            statusMessage = "备份已导入。"
            AppLog.debug("import ok")
        } catch {
            statusMessage = error.localizedDescription
            AppLog.error("import failed")
        }
    }

    private func clearQuotes() {
        do {
            try LocalDataMaintenance.clearQuoteCache(context: context)
            statusMessage = "行情缓存已清除。"
        } catch {
            statusMessage = "清除失败，请重试。"
            AppLog.error("clear quotes failed")
        }
    }

    private func deleteAll() {
        do {
            try LocalDataMaintenance.deleteAllLocalData(context: context)
            statusMessage = "全部本地数据已删除。"
        } catch {
            statusMessage = "删除失败，请重试。"
            AppLog.error("wipe failed")
        }
    }
}

// MARK: - 计价

private struct PricingSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    private var settings: AppSettings {
        if let first = settingsList.first { return first }
        let created = AppSettings()
        context.insert(created)
        return created
    }

    var body: some View {
        Form {
            Section {
                Picker("本位币", selection: Binding(
                    get: { settings.baseCurrency },
                    set: {
                        settings.baseCurrency = $0
                        try? context.save()
                    }
                )) {
                    Text("人民币 CNY").tag("CNY")
                    Text("美元 USD").tag("USD")
                    Text("港币 HKD").tag("HKD")
                }
                Toggle("自动导入分红/拆股", isOn: Binding(
                    get: { settings.autoImportCorporateActions },
                    set: {
                        settings.autoImportCorporateActions = $0
                        try? context.save()
                    }
                ))
                #if DEBUG || targetEnvironment(simulator)
                Toggle("使用 Mock 数据（搜索/行情）", isOn: Binding(
                    get: { settings.useMockMarketData },
                    set: {
                        settings.useMockMarketData = $0
                        try? context.save()
                        AppLog.debug("useMockMarketData toggled")
                    }
                ))
                #endif
            } footer: {
                #if DEBUG || targetEnvironment(simulator)
                Text("模拟器若无法访问东财接口，可开启 Mock 做本地验收。银行余额请手动录入。失败的真实行情不会自动用 Mock 冒充。")
                #else
                Text("银行余额请手动录入。行情来自公开接口，可能延迟或失败。")
                #endif
            }
        }
        .navigationTitle("计价")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 汇率

private struct FXSettingsView: View {
    @Query private var settingsList: [AppSettings]

    private var settings: AppSettings {
        settingsList.first ?? AppSettings()
    }

    var body: some View {
        Form {
            Section {
                ForEach(["USD", "HKD"], id: \.self) { code in
                    if let rate = settings.rateToCNYMap[code] {
                        Text(MoneyFormat.fxLine(code: code, rateToCNY: rate))
                            .font(.body.monospacedDigit())
                    } else {
                        Text("1 \(code) = — CNY（尚未刷新）")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("CNY", value: "1 CNY = 1 CNY")
                if let last = settings.lastFXRefresh {
                    LabeledContent("更新时间", value: MoneyFormat.dateTime(last))
                } else {
                    LabeledContent("更新时间", value: "尚未刷新")
                }
                LabeledContent("来源", value: settings.fxSource.isEmpty ? "—" : settings.fxSource)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("公式：amountInCNY = amount × rateToCNY。大陆优先东财外汇，失败回落新浪；公开接口非官方授权，可能失败。")
                    if !settings.hasKnownRate(for: "USD") || !settings.hasKnownRate(for: "HKD") {
                        Text("部分汇率尚未获取：缺失币种将暂时按 1:1 折算，总资产可能不准。请回首页下拉/点刷新获取汇率。")
                            .foregroundStyle(Color.orange)
                    }
                }
            }
        }
        .navigationTitle("汇率")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 数据统计

private struct LocalDataStatsView: View {
    @Query private var settingsList: [AppSettings]
    @Query private var instruments: [Instrument]
    @Query private var transactions: [TransactionRecord]
    @Query private var positions: [Position]
    @Query private var quotes: [CachedQuote]

    private var settings: AppSettings {
        settingsList.first ?? AppSettings()
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("标的", value: "\(instruments.count)")
                LabeledContent("交易", value: "\(transactions.count)")
                LabeledContent("持仓", value: "\(positions.count)")
                LabeledContent("行情缓存", value: "\(quotes.count)")
                if let last = settings.lastMarketRefresh {
                    LabeledContent("上次刷新", value: MoneyFormat.shortDate(last))
                }
                if !settings.lastMarketDiag.isEmpty {
                    LabeledContent("诊断摘要", value: "已保存（代码已脱敏）")
                }
            }
        }
        .navigationTitle("数据")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 流水记录

private enum CapitalFlowSectionKind: String, CaseIterable, Identifiable {
    case bankDemand
    case bankFixed
    case bankWealth
    case bond
    case fxSavings
    case cashOther
    case liability
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bankDemand: return "银行活期"
        case .bankFixed: return "银行定期存款"
        case .bankWealth: return "银行理财"
        case .bond: return "债券"
        case .fxSavings: return "外币"
        case .cashOther: return "现金/其他"
        case .liability: return "负债"
        case .other: return "其他"
        }
    }
}

struct CapitalFlowRecordsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme

    @Query(sort: \ManualCapitalEvent.eventDate, order: .reverse) private var events: [ManualCapitalEvent]
    @Query private var deposits: [BankDepositAccount]
    @Query private var bonds: [BondHolding]
    @Query private var fxAccounts: [FXSavingsAccount]
    @Query private var cashItems: [CashOtherAsset]

    @State private var searchText = ""
    @State private var pendingDeleteID: UUID?
    @State private var confirmDelete = false

    private var filteredEvents: [ManualCapitalEvent] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(events) }
        return events.filter { matchesSearch($0, query: q) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.secondaryText)
                    TextField("搜索银行、操作、金额或备注", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if events.isEmpty {
                ContentUnavailableView("暂无流水", systemImage: "list.bullet.rectangle", description: Text("存入、取出、改余额等操作会出现在这里。"))
            } else if filteredEvents.isEmpty {
                ContentUnavailableView("无匹配结果", systemImage: "magnifyingglass", description: Text("试试其他关键词，如银行名、操作或备注。"))
            } else {
                ForEach(CapitalFlowSectionKind.allCases) { section in
                    let rows = filteredEvents.filter { sectionKind(for: $0) == section }
                    if !rows.isEmpty {
                        Section(section.title) {
                            ForEach(rows, id: \.id) { event in
                                CapitalFlowRow(
                                    date: event.eventDate,
                                    amount: event.amount,
                                    currency: event.currency,
                                    operation: operationTitle(for: event),
                                    subtitle: assetSubtitle(for: event),
                                    note: event.note
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteID = event.id
                                        confirmDelete = true
                                    } label: {
                                        Label("删除", systemImage: "trash.fill")
                                    }
                                    .tint(.red)
                                }
                            }
                        }
                    }
                }
            }
        }
        .wkPageChrome()
        .navigationTitle("流水记录")
        .navigationBarTitleDisplayMode(.inline)
        .alert("删除该笔流水？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                if let id = pendingDeleteID,
                   let event = events.first(where: { $0.id == id }) {
                    deleteEvent(event)
                }
                pendingDeleteID = nil
            }
            Button("取消", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("将撤销该流水对账户余额的影响，此操作不可撤销。")
        }
    }

    private func matchesSearch(_ event: ManualCapitalEvent, query: String) -> Bool {
        let haystacks: [String] = [
            operationTitle(for: event),
            assetSubtitle(for: event),
            event.note,
            event.currency,
            MoneyFormat.compact(event.amount),
            MoneyFormat.shortDate(event.eventDate),
            sectionKind(for: event).title,
            event.kind.displayName,
            event.assetClass.displayName
        ]
        return haystacks.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func sectionKind(for event: ManualCapitalEvent) -> CapitalFlowSectionKind {
        switch event.assetClass {
        case .bankDeposit:
            if let item = deposits.first(where: { $0.id.uuidString == event.assetID }) {
                switch item.depositKind {
                case .demand: return .bankDemand
                case .fixed: return .bankFixed
                case .wealth: return .bankWealth
                }
            }
            return .other
        case .bond: return .bond
        case .fxSavings: return .fxSavings
        case .cashOther: return .cashOther
        case .liability: return .liability
        default: return .other
        }
    }

    private func operationTitle(for event: ManualCapitalEvent) -> String {
        let note = event.note
        if note.contains("改余额") { return "改余额" }
        if note.contains("申购") || note == "买入" { return "买入" }
        if note.contains("赎回") { return "赎回" }
        if note.contains("存入") { return "存入" }
        if note.contains("取出") { return "取出" }
        switch event.kind {
        case .deposit: return "存入"
        case .withdraw: return "取出"
        case .adjustPrincipal: return "改余额"
        case .interestReceived: return "利息到账"
        case .maturityRedeem: return "到期赎回"
        }
    }

    private func assetSubtitle(for event: ManualCapitalEvent) -> String {
        switch event.assetClass {
        case .bankDeposit:
            if let item = deposits.first(where: { $0.id.uuidString == event.assetID }) {
                return item.displayTitle
            }
        case .bond:
            if let item = bonds.first(where: { $0.id.uuidString == event.assetID }) {
                return item.name
            }
        case .fxSavings:
            if let item = fxAccounts.first(where: { $0.id.uuidString == event.assetID }) {
                return item.name
            }
        case .cashOther:
            if let item = cashItems.first(where: { $0.id.uuidString == event.assetID }) {
                return item.name
            }
        default:
            break
        }
        return event.assetClass.displayName
    }

    private func deleteEvent(_ event: ManualCapitalEvent) {
        let impact = signedImpact(kind: event.kind, amount: event.amount)
        switch event.assetClass {
        case .bankDeposit:
            if let item = deposits.first(where: { $0.id.uuidString == event.assetID }) {
                item.balance = max(0, item.balance - impact.balance)
                item.receivedInterest = max(0, item.receivedInterest - impact.received)
                item.updatedAt = .now
            }
        case .fxSavings:
            if let item = fxAccounts.first(where: { $0.id.uuidString == event.assetID }) {
                item.balance = max(0, item.balance - impact.balance)
                item.receivedInterest = max(0, item.receivedInterest - impact.received)
                item.updatedAt = .now
            }
        case .cashOther:
            if let item = cashItems.first(where: { $0.id.uuidString == event.assetID }) {
                item.balance = max(0, item.balance - impact.balance)
                item.updatedAt = .now
            }
        case .bond:
            if let item = bonds.first(where: { $0.id.uuidString == event.assetID }) {
                item.cost = max(0, item.cost - impact.cost)
                item.receivedInterest = max(0, item.receivedInterest - impact.received)
                item.updatedAt = .now
            }
        default:
            break
        }
        context.delete(event)
        try? context.save()
    }

    private func signedImpact(kind: ManualCapitalEventKind, amount: Decimal) -> (balance: Decimal, received: Decimal, cost: Decimal) {
        switch kind {
        case .deposit, .adjustPrincipal:
            return (amount, 0, amount)
        case .withdraw, .maturityRedeem:
            return (-amount, 0, -amount)
        case .interestReceived:
            return (0, amount, 0)
        }
    }
}

private struct CapitalFlowRow: View {
    @Environment(\.wkTheme) private var theme

    let date: Date
    let amount: Decimal
    let currency: String
    let operation: String
    let subtitle: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(operation)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(MoneyFormat.compact(amount)) \(currency)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(MoneyFormat.shortDate(date))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }

            if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }
}

private enum SharePresenter {
    static func present(items: [Any], completion: (() -> Void)? = nil) {
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        guard let presenter = topViewController() else {
            AppLog.error("share present failed: no presenter")
            return
        }
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }

    private static func topViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
