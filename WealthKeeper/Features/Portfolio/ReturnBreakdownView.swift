import SwiftUI
import SwiftData

/// 收益构成：利息 / 股票 / 分红
struct ReturnBreakdownView: View {
    @Environment(\.wkTheme) private var theme
    let pnl: PnLBreakdown
    let todayReturnCNY: Decimal

    var body: some View {
        List {
            Section {
                HStack {
                    Text("今日收益")
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    Text(MoneyFormat.compact(todayReturnCNY, sign: true))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(theme.marketPnL(todayReturnCNY))
                }
                .listRowBackground(theme.cardBackground)
            }

            Section("收益构成") {
                row("利息", pnl.interestCNY)
                row("股票", pnl.stockReturnCNY)
                row("分红", pnl.dividendCNY)
            }
        }
        .wkPageChrome()
        .navigationTitle("收益构成")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: Decimal) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(theme.primaryText)
            Spacer()
            Text(MoneyFormat.compact(value, sign: true))
                .monospacedDigit()
                .foregroundStyle(theme.marketPnL(value))
        }
        .font(.body)
        .listRowBackground(theme.cardBackground)
    }
}
