import Foundation
import SwiftData

@Model
final class Instrument {
    @Attribute(.unique) var id: String
    var symbol: String
    var name: String
    var marketRaw: String
    var typeRaw: String
    var currency: String
    var createdAt: Date

    init(
        symbol: String,
        name: String,
        market: Market,
        type: InstrumentType,
        currency: String? = nil
    ) {
        self.id = "\(market.rawValue):\(symbol.uppercased())"
        self.symbol = symbol.uppercased()
        self.name = name
        self.marketRaw = market.rawValue
        self.typeRaw = type.rawValue
        self.currency = currency ?? market.defaultCurrency
        self.createdAt = .now
    }

    var market: Market {
        get { Market(rawValue: marketRaw) ?? .cnA }
        set { marketRaw = newValue.rawValue }
    }

    var type: InstrumentType {
        get { InstrumentType(rawValue: typeRaw) ?? .stock }
        set { typeRaw = newValue.rawValue }
    }
}
