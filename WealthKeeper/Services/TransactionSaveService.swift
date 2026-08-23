import Foundation
import SwiftData

enum TransactionSaveError: LocalizedError, Equatable {
    case missingSymbol
    case invalidQuantityOrPrice
    case invalidDividend
    case invalidReinvest
    case invalidBonusShare
    case invalidFee
    case invalidSplit
    case invalidDecimal(field: String)
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .missingSymbol:
            return "请先搜索选择标的，或打开「手动输入代码」并填写代码"
        case .invalidQuantityOrPrice:
            return "请填写有效的数量与单价（须为大于 0 的数字，支持小数）"
        case .invalidDividend:
            return "请填写分红总额，或登记日持仓×每股/份分红"
        case .invalidReinvest:
            return "请填写再投资份额，或登记日持仓×每份分红（及净值）"
        case .invalidBonusShare:
            return "请填写送股数量"
        case .invalidFee:
            return "请填写手续费金额"
        case .invalidSplit:
            return "请填写有效的拆合股比例"
        case .invalidDecimal(let field):
            return "「\(field)」不是有效数字，请使用 0-9 和小数点"
        case .persistence(let msg):
            return "保存失败：\(msg)"
        }
    }
}

enum TransactionSaveService {
    struct Input: Equatable {
        var market: Market
        var assetType: InstrumentType
        var symbol: String
        var name: String
        var currency: String
        var kind: TransactionKind
        var tradeDate: Date
        var recordDate: Date?
        var quantityText: String
        var sharesOnRecordText: String
        var priceText: String
        var feeText: String
        var cashAmountText: String
        var splitRatioText: String
        var note: String
    }

    struct Prepared: Equatable {
        var instrumentID: String
        var symbol: String
        var name: String
        var market: Market
        var assetType: InstrumentType
        var currency: String
        var kind: TransactionKind
        var tradeDate: Date
        var recordDate: Date?
        var quantity: Decimal
        var sharesOnRecord: Decimal
        var price: Decimal
        var fee: Decimal
        var cashAmount: Decimal
        var splitRatio: Decimal
        var note: String
    }

    static func prepare(_ input: Input) -> Result<Prepared, TransactionSaveError> {
        let trimmed = input.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSymbol: String = {
            switch input.market {
            case .us: return trimmed.uppercased()
            case .hk:
                let digits = trimmed.filter(\.isNumber)
                return digits.isEmpty ? trimmed.uppercased() : String(digits)
            case .cnA, .cnFund: return trimmed.uppercased()
            }
        }()

        guard !normalizedSymbol.isEmpty else { return .failure(.missingSymbol) }

        func requiredDecimal(_ text: String, field: String, allowEmptyAsZero: Bool) -> Result<Decimal, TransactionSaveError> {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                return allowEmptyAsZero ? .success(0) : .failure(.invalidDecimal(field: field))
            }
            guard let v = DecimalMath.parse(t) else {
                return .failure(.invalidDecimal(field: field))
            }
            return .success(v)
        }

        let qtyR = requiredDecimal(input.quantityText, field: "数量", allowEmptyAsZero: true)
        let sharesR = requiredDecimal(input.sharesOnRecordText, field: "登记日持仓", allowEmptyAsZero: true)
        let pxR = requiredDecimal(input.priceText, field: "单价", allowEmptyAsZero: true)
        let feeR = requiredDecimal(input.feeText, field: "手续费", allowEmptyAsZero: true)
        let cashR = requiredDecimal(input.cashAmountText, field: "金额", allowEmptyAsZero: true)
        let ratioR = requiredDecimal(input.splitRatioText.isEmpty ? "1" : input.splitRatioText, field: "拆合股比例", allowEmptyAsZero: false)

        guard case .success(let qty) = qtyR else {
            if case .failure(let e) = qtyR { return .failure(e) }
            return .failure(.invalidDecimal(field: "数量"))
        }
        guard case .success(var sharesOnRecord) = sharesR else {
            if case .failure(let e) = sharesR { return .failure(e) }
            return .failure(.invalidDecimal(field: "登记日持仓"))
        }
        guard case .success(let px) = pxR else {
            if case .failure(let e) = pxR { return .failure(e) }
            return .failure(.invalidDecimal(field: "单价"))
        }
        guard case .success(let feeValue) = feeR else {
            if case .failure(let e) = feeR { return .failure(e) }
            return .failure(.invalidDecimal(field: "手续费"))
        }
        guard case .success(var cash) = cashR else {
            if case .failure(let e) = cashR { return .failure(e) }
            return .failure(.invalidDecimal(field: "金额"))
        }
        guard case .success(let ratio) = ratioR else {
            if case .failure(let e) = ratioR { return .failure(e) }
            return .failure(.invalidDecimal(field: "拆合股比例"))
        }

        switch input.kind {
        case .buy, .sell:
            guard qty > 0, px > 0 else { return .failure(.invalidQuantityOrPrice) }
        case .dividend:
            if sharesOnRecord <= 0 { sharesOnRecord = qty }
            if cash <= 0, sharesOnRecord > 0, px > 0 {
                cash = sharesOnRecord * px
            }
            guard cash > 0 || (sharesOnRecord > 0 && px > 0) else { return .failure(.invalidDividend) }
        case .dividendReinvest:
            if sharesOnRecord <= 0 { sharesOnRecord = qty }
            if cash <= 0, sharesOnRecord > 0, px > 0 {
                cash = sharesOnRecord * px
            }
            // quantity = 再投资得到的份额；若未填则用现金/净值估算（此时 price 作净值）
            guard qty > 0 || cash > 0 else { return .failure(.invalidReinvest) }
        case .bonusShare:
            guard qty > 0 else { return .failure(.invalidBonusShare) }
            if sharesOnRecord <= 0 { sharesOnRecord = 0 }
        case .fee:
            guard cash > 0 || feeValue > 0 else { return .failure(.invalidFee) }
        case .split:
            guard ratio > 0 else { return .failure(.invalidSplit) }
        }

        let resolvedType: InstrumentType = input.market == .cnFund ? .fund : input.assetType
        let resolvedCurrency = input.currency.isEmpty ? input.market.defaultCurrency : input.currency
        let resolvedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)

        let recordDate: Date? = {
            if input.kind.isDividendEvent || input.kind == .bonusShare {
                return input.recordDate ?? input.tradeDate
            }
            return input.recordDate
        }()

        let storedQty: Decimal = {
            switch input.kind {
            case .dividend:
                // 现金分红：quantity 存登记日持仓，便于旧逻辑兼容
                return sharesOnRecord > 0 ? sharesOnRecord : qty
            default:
                return qty
            }
        }()

        return .success(
            Prepared(
                instrumentID: "\(input.market.rawValue):\(normalizedSymbol)",
                symbol: normalizedSymbol,
                name: resolvedName.isEmpty ? normalizedSymbol : resolvedName,
                market: input.market,
                assetType: resolvedType,
                currency: resolvedCurrency,
                kind: input.kind,
                tradeDate: (input.kind.isDividendEvent || input.kind == .bonusShare)
                    ? (recordDate ?? input.tradeDate)
                    : input.tradeDate,
                recordDate: recordDate,
                quantity: storedQty,
                sharesOnRecord: sharesOnRecord,
                price: px,
                fee: input.kind == .fee ? max(cash, feeValue) : feeValue,
                cashAmount: input.kind == .fee ? max(cash, feeValue) : cash,
                splitRatio: ratio,
                note: input.note
            )
        )
    }

    @MainActor
    static func persist(_ prepared: Prepared, context: ModelContext) throws {
        let targetID = prepared.instrumentID
        let descriptor = FetchDescriptor<Instrument>(
            predicate: #Predicate<Instrument> { $0.id == targetID }
        )
        let existing = try context.fetch(descriptor).first

        let instrument: Instrument
        if let existing {
            existing.name = prepared.name
            existing.currency = prepared.currency
            existing.type = prepared.assetType
            existing.market = prepared.market
            existing.symbol = prepared.symbol
            instrument = existing
        } else {
            let created = Instrument(
                symbol: prepared.symbol,
                name: prepared.name,
                market: prepared.market,
                type: prepared.assetType,
                currency: prepared.currency
            )
            context.insert(created)
            instrument = created
        }

        context.insert(
            TransactionRecord(
                instrumentID: instrument.id,
                kind: prepared.kind,
                tradeDate: prepared.tradeDate,
                quantity: prepared.quantity,
                price: prepared.price,
                fee: prepared.fee,
                cashAmount: prepared.cashAmount,
                splitRatio: prepared.splitRatio,
                note: prepared.note,
                recordDate: prepared.recordDate,
                sharesOnRecord: prepared.sharesOnRecord,
                currency: prepared.currency
            )
        )

        try context.save()
        AppLog.debug("save ok market=\(prepared.market.rawValue) kind=\(prepared.kind.rawValue)")

        let all = try context.fetch(FetchDescriptor<TransactionRecord>())
        PortfolioEngine.rebuildPositions(transactions: all, context: context)
    }
}
