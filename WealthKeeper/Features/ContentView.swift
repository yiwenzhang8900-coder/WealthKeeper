import SwiftUI
import SwiftData
import UIKit

/// 根级主入口（自定义悬浮胶囊导航）
enum AppRootTab: Int, CaseIterable, Hashable, Identifiable {
    case assets
    case lifestyle
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .assets: return "资产"
        case .lifestyle: return "生活"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .assets: return "chart.pie.fill"
        case .lifestyle: return "leaf.fill"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wkTheme) private var theme
    @Query private var settingsList: [AppSettings]
    @State private var selectedTab: AppRootTab = .assets
    /// 按需加载已访问 Tab，减轻启动与切主题时四页 Query 同时挂载的卡顿。
    @State private var loadedTabs: Set<AppRootTab> = [.assets]
    /// 键盘弹出时隐藏底部胶囊，避免被顶到键盘上方并遮挡输入区。
    @State private var isKeyboardVisible = false

    var body: some View {
        ZStack {
            theme.pageBackground
                .ignoresSafeArea(edges: .all)

            rootTabs
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 胶囊只负责绘制；列表避让靠 wkTabBarClearance + contentMargins。
        .overlay(alignment: .bottom) {
            if !isKeyboardVisible {
                FloatingCapsuleTabBar(selection: $selectedTab)
                    .padding(.horizontal, theme.tabBarHorizontalInset)
                    .padding(.top, theme.tabBarTopInset)
                    .padding(.bottom, theme.tabBarBottomInset)
                    .offset(y: theme.tabBarDownOffset)
                    .ignoresSafeArea(edges: .bottom)
                    .ignoresSafeArea(.keyboard)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .injectWealthSummary()
        .onChange(of: selectedTab) { _, tab in
            loadedTabs.insert(tab)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardVisibility(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            animateKeyboardVisibility(false, from: notification)
        }
        .task {
            ensureSettings()
            #if targetEnvironment(simulator)
            // 仅模拟器植入演示数据；真机/上架包保持空账本，避免用户误以为是正式资产。
            MockMarketData.seedManualAssetsIfNeeded(context: context)
            #endif
        }
    }

    /// 已访问页保留，避免重复销毁 NavigationStack；未访问页不预创建。
    private var rootTabs: some View {
        ZStack {
            if loadedTabs.contains(.assets) {
                tabPane(.assets) { PortfolioView() }
            }
            if loadedTabs.contains(.lifestyle) {
                tabPane(.lifestyle) {
                    NavigationStack {
                        LifestyleLedgerView()
                    }
                    .background {
                        theme.pageBackground.ignoresSafeArea(edges: .all)
                    }
                }
            }
            if loadedTabs.contains(.settings) {
                tabPane(.settings) { SettingsView() }
            }
        }
    }

    @ViewBuilder
    private func tabPane<Content: View>(_ tab: AppRootTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .environment(
                \.wkTabBarClearance,
                isKeyboardVisible ? 0 : theme.tabBarChromeHeight
            )
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }

    private func updateKeyboardVisibility(from notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let screen = UIScreen.main.bounds
        let visible = frame.intersects(screen) && frame.minY < screen.maxY - 1
        animateKeyboardVisibility(visible, from: notification)
    }

    private func animateKeyboardVisibility(_ visible: Bool, from notification: Notification) {
        guard isKeyboardVisible != visible else { return }
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeInOut(duration: duration)) {
            isKeyboardVisible = visible
        }
    }

    private func ensureSettings() {
        if settingsList.isEmpty {
            context.insert(AppSettings())
            try? context.save()
            AppLog.debug("settings created")
        }
        #if targetEnvironment(simulator)
        if UserDefaults.standard.object(forKey: "wk_mock_default_applied_v1") == nil {
            if let settings = settingsList.first {
                settings.useMockMarketData = true
                try? context.save()
            }
            UserDefaults.standard.set(true, forKey: "wk_mock_default_applied_v1")
            AppLog.debug("simulator mock default enabled")
        }
        #endif
    }
}

// MARK: - Floating capsule tab bar

struct FloatingCapsuleTabBar: View {
    @Binding var selection: AppRootTab
    @Environment(\.wkTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppRootTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(height: theme.tabBarHeight)
        .background {
            RoundedRectangle(cornerRadius: theme.tabBarCornerRadius, style: .continuous)
                .fill(theme.tabBarBackground)
                .shadow(color: theme.tabBarShadow, radius: 14, x: 0, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.tabBarCornerRadius, style: .continuous)
                .stroke(theme.tabBarBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主导航")
    }

    private func tabButton(_ tab: AppRootTab) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? theme.tabBarSelectedForeground : theme.tabBarUnselectedForeground)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? theme.tabBarSelectedBackground : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Instrument.self,
            TransactionRecord.self,
            Position.self,
            CorporateActionRecord.self,
            CachedQuote.self,
            AppSettings.self,
            BankDepositAccount.self,
            FXSavingsAccount.self,
            BondHolding.self,
            CashOtherAsset.self,
            LiabilityRecord.self,
            ManualCapitalEvent.self,
            LifestyleEntry.self,
        ], inMemory: true)
}
