import SwiftUI
import UIKit

// MARK: - Mode

/// 用户可选主题。新用户默认「跟随系统」；无法解析时回落「阳光清爽」。
enum AppThemeMode: String, CaseIterable, Identifiable {
    case night
    case sunny
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .night: return "夜间黑"
        case .sunny: return "阳光清爽"
        case .system: return "跟随系统"
        }
    }

    /// `nil` 表示跟随系统外观。
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .night: return .dark
        case .sunny: return .light
        }
    }

    /// 写入 UIWindow，确保窗口层风格跟随主题。
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .night: return .dark
        case .sunny: return .light
        case .system: return .unspecified
        }
    }

    static let storageKey = "wk_theme_mode"

    static func stored(raw: String?) -> AppThemeMode {
        guard let raw, let mode = AppThemeMode(rawValue: raw) else { return .sunny }
        return mode
    }
}

// MARK: - Tokens

/// 语义化主题色，页面应通过 `@Environment(\.wkTheme)` 使用，避免散落写死色值。
struct ThemeTokens: Equatable {
    /// 夜间主题标记（勿用 Color 相等性推断）
    var isNight: Bool

    var pageBackground: Color
    var cardBackground: Color
    var secondaryCardBackground: Color
    var primaryText: Color
    var secondaryText: Color
    var separator: Color
    var accent: Color
    /// 生活记账：收入
    var income: Color
    /// 生活记账：支出
    var expense: Color
    /// 生活记账：结余
    var net: Color
    /// 行情涨/正收益（A 股习惯：红）
    var gain: Color
    /// 行情跌/负收益（A 股习惯：绿）
    var loss: Color
    var warning: Color
    var destructive: Color
    var onAccent: Color

    /// 生活小账本总览卡渐变
    var lifestyleOverviewTop: Color
    var lifestyleOverviewBottom: Color
    var lifestyleOverviewTitle: Color
    var lifestyleOverviewSubtitle: Color
    var lifestyleChipBackground: Color
    var lifestyleIncomeSoft: Color
    var lifestyleExpenseSoft: Color

    // MARK: Floating capsule tab bar
    var tabBarBackground: Color
    var tabBarBorder: Color
    var tabBarShadow: Color
    var tabBarSelectedBackground: Color
    var tabBarSelectedForeground: Color
    var tabBarUnselectedForeground: Color
    /// 胶囊整体圆角
    var tabBarCornerRadius: CGFloat
    /// 胶囊高度（含内边距）
    var tabBarHeight: CGFloat
    /// 相对屏幕左右边距
    var tabBarHorizontalInset: CGFloat
    /// 胶囊上方与列表末行的空隙
    var tabBarTopInset: CGFloat
    /// 相对 Home Indicator 上方的额外 padding（下沉后通常为 0）
    var tabBarBottomInset: CGFloat
    /// 再向下偏移，沉入 Home Indicator，减少视觉留白
    var tabBarDownOffset: CGFloat
    /// 列表底部可滚避让：只计「仍压在内容区上」的高度
    var tabBarChromeHeight: CGFloat {
        max(tabBarHeight - tabBarDownOffset + tabBarTopInset + tabBarBottomInset, 44)
    }

    var lifestyleOverviewGradient: LinearGradient {
        LinearGradient(
            colors: [lifestyleOverviewTop, lifestyleOverviewBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// UIKit 底板色（避免 Color→UIColor 动态解析在切主题时闪白/闪黑）
    var uiPageBackground: UIColor {
        isNight
            ? UIColor(red: 0, green: 0, blue: 0, alpha: 1)
            : UIColor(red: 245 / 255, green: 246 / 255, blue: 242 / 255, alpha: 1)
    }

    var uiPrimaryText: UIColor {
        isNight
            ? .white
            : UIColor(red: 32 / 255, green: 37 / 255, blue: 34 / 255, alpha: 1)
    }

    var uiAccent: UIColor {
        isNight
            ? UIColor(red: 10 / 255, green: 132 / 255, blue: 255 / 255, alpha: 1)
            : UIColor(red: 52 / 255, green: 135 / 255, blue: 216 / 255, alpha: 1)
    }

    var uiSeparator: UIColor {
        isNight
            ? UIColor(red: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1)
            : UIColor(red: 225 / 255, green: 229 / 255, blue: 223 / 255, alpha: 1)
    }

    func marketPnL(_ value: Decimal) -> Color {
        value >= 0 ? gain : loss
    }

    func lifestyleAmount(isIncome: Bool) -> Color {
        isIncome ? income : expense
    }

    static func resolve(colorScheme: ColorScheme) -> ThemeTokens {
        colorScheme == .dark ? .night : .sunny
    }

    /// 阳光清爽
    static let sunny = ThemeTokens(
        isNight: false,
        pageBackground: Color(hex: 0xF5F6F2),
        cardBackground: Color(hex: 0xFFFFFF),
        secondaryCardBackground: Color(hex: 0xF0F2ED),
        primaryText: Color(hex: 0x202522),
        secondaryText: Color(hex: 0x68716B),
        separator: Color(hex: 0xE1E5DF),
        accent: Color(hex: 0x3487D8),
        income: Color(hex: 0x23805C),
        expense: Color(hex: 0xC35D4D),
        net: Color(hex: 0x405D78),
        gain: Color(hex: 0xD1433B),
        loss: Color(hex: 0x2F9B6A),
        warning: Color(hex: 0xC47A2C),
        destructive: Color(hex: 0xC35D4D),
        onAccent: Color.white,
        lifestyleOverviewTop: Color(hex: 0xD7EDE3),
        lifestyleOverviewBottom: Color(hex: 0xF6E9DC),
        lifestyleOverviewTitle: Color(hex: 0x202522),
        lifestyleOverviewSubtitle: Color(hex: 0x68716B),
        lifestyleChipBackground: Color.white.opacity(0.72),
        lifestyleIncomeSoft: Color(hex: 0xD8EFE4),
        lifestyleExpenseSoft: Color(hex: 0xF8E4DF),
        tabBarBackground: Color.white.opacity(0.92),
        tabBarBorder: Color(hex: 0xE8EAE5),
        tabBarShadow: Color.black.opacity(0.10),
        tabBarSelectedBackground: Color(hex: 0xE8EDF5),
        tabBarSelectedForeground: Color(hex: 0x3487D8),
        tabBarUnselectedForeground: Color(hex: 0x202522),
        tabBarCornerRadius: 28,
        tabBarHeight: 58,
        tabBarHorizontalInset: 18,
        tabBarTopInset: 4,
        tabBarBottomInset: 0,
        tabBarDownOffset: 14
    )

    /// 夜间黑（贴近系统深色，保留现有红涨绿跌风格）
    static let night = ThemeTokens(
        isNight: true,
        pageBackground: Color(hex: 0x000000),
        cardBackground: Color(hex: 0x1C1C1E),
        secondaryCardBackground: Color(hex: 0x2C2C2E),
        primaryText: Color.white,
        secondaryText: Color(hex: 0xA1A1A6),
        separator: Color(hex: 0x3A3A3C),
        accent: Color(hex: 0x0A84FF),
        income: Color(hex: 0x34C759),
        expense: Color(hex: 0xFF6B5A),
        net: Color(hex: 0x7AA2C9),
        gain: Color.red,
        loss: Color.green,
        warning: Color.orange,
        destructive: Color.red,
        onAccent: Color.white,
        lifestyleOverviewTop: Color(hex: 0x1A2420),
        lifestyleOverviewBottom: Color(hex: 0x24201C),
        lifestyleOverviewTitle: Color.white,
        lifestyleOverviewSubtitle: Color(hex: 0xA1A1A6),
        lifestyleChipBackground: Color.white.opacity(0.10),
        lifestyleIncomeSoft: Color(hex: 0x1E3A2F),
        lifestyleExpenseSoft: Color(hex: 0x3A2420),
        tabBarBackground: Color(hex: 0x1C1C1E),
        tabBarBorder: Color(hex: 0x303236),
        tabBarShadow: Color.black.opacity(0.45),
        tabBarSelectedBackground: Color(hex: 0x343438),
        tabBarSelectedForeground: Color(hex: 0x4C9CFF),
        tabBarUnselectedForeground: Color(hex: 0xF2F2F7),
        tabBarCornerRadius: 28,
        tabBarHeight: 58,
        tabBarHorizontalInset: 18,
        tabBarTopInset: 4,
        tabBarBottomInset: 0,
        tabBarDownOffset: 14
    )
}

// MARK: - Environment

private struct ThemeTokensKey: EnvironmentKey {
    static let defaultValue: ThemeTokens = .sunny
}

extension EnvironmentValues {
    var wkTheme: ThemeTokens {
        get { self[ThemeTokensKey.self] }
        set { self[ThemeTokensKey.self] = newValue }
    }

    /// 根 Tab 胶囊占用高度；由 `wkPageChrome` 写入 List/Form 底部可滚边距。
    var wkTabBarClearance: CGFloat {
        get { self[WKTabBarClearanceKey.self] }
        set { self[WKTabBarClearanceKey.self] = newValue }
    }
}

private struct WKTabBarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

// MARK: - Root host

/// 根层主题宿主：持久化选择、立即切换 `preferredColorScheme` 与语义色。
struct RootThemeHost<Content: View>: View {
    @AppStorage(AppThemeMode.storageKey) private var themeModeRaw: String = AppThemeMode.system.rawValue
    @Environment(\.colorScheme) private var systemColorScheme
    @ViewBuilder var content: () -> Content

    private var mode: AppThemeMode {
        AppThemeMode.stored(raw: themeModeRaw)
    }

    /// 按用户选择解析 Token，避免依赖尚未传播的 colorScheme。
    private var theme: ThemeTokens {
        tokens(for: mode)
    }

    var body: some View {
        content()
            .environment(\.wkTheme, theme)
            .preferredColorScheme(mode.preferredColorScheme)
            .tint(theme.accent)
            .background(theme.pageBackground.ignoresSafeArea())
            // 注意：不要用 .id(themeModeRaw) 整树重建，否则切主题会白屏/黑屏闪一下并加重卡顿。
            .onAppear {
                // 仅启动时刷一次 UIAppearance；之后切主题只改窗口，避免 List 白板/卡死。
                ThemeChrome.applyAppearanceProxies(theme)
                ThemeChrome.applyWindowChrome(theme, interfaceStyle: mode.userInterfaceStyle)
            }
            .onChange(of: themeModeRaw) { _, newRaw in
                let next = AppThemeMode.stored(raw: newRaw)
                ThemeChrome.applyWindowChrome(tokens(for: next), interfaceStyle: next.userInterfaceStyle)
            }
            .onChange(of: systemColorScheme) { _, _ in
                guard mode == .system else { return }
                ThemeChrome.applyWindowChrome(theme, interfaceStyle: .unspecified)
            }
    }

    private func tokens(for mode: AppThemeMode) -> ThemeTokens {
        switch mode {
        case .night:
            return .night
        case .sunny:
            return .sunny
        case .system:
            return systemColorScheme == .dark ? .night : .sunny
        }
    }
}

/// 主题 UIKit 侧轻量同步：禁止在切主题时深刷 VC 树 / 反复改 appearance。
enum ThemeChrome {
    private static var lastStyle: UIUserInterfaceStyle?
    private static var lastPageHash: Int?

    /// 启动时配置一次导航栏外观；运行时不再反复调用。
    static func applyAppearanceProxies(_ theme: ThemeTokens) {
        let page = theme.uiPageBackground
        let title = theme.uiPrimaryText
        let accent = theme.uiAccent
        let separator = theme.uiSeparator

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = page
        nav.shadowColor = separator.withAlphaComponent(0.35)
        nav.titleTextAttributes = [.foregroundColor: title]
        nav.largeTitleTextAttributes = [.foregroundColor: title]

        let navbar = UINavigationBar.appearance()
        navbar.standardAppearance = nav
        navbar.scrollEdgeAppearance = nav
        navbar.compactAppearance = nav
        navbar.tintColor = accent
        navbar.isTranslucent = false

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tab
        tabBar.scrollEdgeAppearance = tab
        tabBar.isTranslucent = true
    }

    /// 只改窗口风格与底色；不遍历子 VC、不改 UITableView.appearance（那是白板/卡死主因）。
    static func applyWindowChrome(_ theme: ThemeTokens, interfaceStyle: UIUserInterfaceStyle) {
        let page = theme.uiPageBackground
        let pageHash = theme.isNight ? 1 : 0
        if lastStyle == interfaceStyle, lastPageHash == pageHash {
            return
        }
        lastStyle = interfaceStyle
        lastPageHash = pageHash

        let apply = {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    // 分享面板等临时窗口不要强行改风格，避免导出白板。
                    if window.rootViewController is UIActivityViewController { continue }
                    if String(describing: type(of: window)).contains("UIRemote") { continue }
                    window.overrideUserInterfaceStyle = interfaceStyle
                    window.backgroundColor = page
                    if let root = window.rootViewController, root.presentedViewController == nil {
                        root.view.backgroundColor = page
                    }
                }
            }
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

// MARK: - View helpers

extension View {
    /// 列表/表单页隐藏系统滚动底并铺主题页背景。
    func wkPageChrome() -> some View {
        modifier(WKPageChromeModifier())
    }
}

private struct WKPageChromeModifier: ViewModifier {
    @Environment(\.wkTheme) private var theme
    @Environment(\.wkTabBarClearance) private var tabBarClearance

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            // 写在 List/Form 自身上，保证滚到底时末行高出胶囊。
            .contentMargins(.bottom, tabBarClearance, for: .scrollContent)
            .background {
                theme.pageBackground.ignoresSafeArea(edges: .all)
            }
            .toolbarBackground(theme.pageBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.isNight ? .dark : .light, for: .navigationBar)
    }
}

// MARK: - Hex

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
