import SwiftUI
import UIKit

/// 中文/英文/数字名称输入。
/// 关键：组字期间不同步 Binding、编辑中不回写 UITextField，否则拼音会被打断。
struct CJKTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = PaddingTextField()
        field.placeholder = placeholder
        field.delegate = context.coordinator
        field.text = text
        field.borderStyle = .roundedRect
        field.backgroundColor = .secondarySystemBackground
        // 必须用 default：asciiCapable 会禁掉中文键盘
        field.keyboardType = .default
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        // 不要强制 .no：部分系统上会干扰中文输入法
        field.autocorrectionType = .default
        field.autocapitalizationType = .none
        field.spellCheckingType = .default
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.textContentType = nil
        field.tintColor = .label
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.field = uiView
        // 编辑过程中（含拼音组字）禁止从 SwiftUI 回写，否则候选/组字会被清掉
        guard !uiView.isFirstResponder else { return }
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        weak var field: UITextField?

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func editingChanged(_ sender: UITextField) {
            // 拼音未上屏时 markedTextRange != nil：此时不要改 Binding，避免整页刷新打断输入法
            guard sender.markedTextRange == nil else { return }
            let value = sender.text ?? ""
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            let value = textField.text ?? ""
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // 始终允许（含中文上屏、删除、选词）
            return true
        }
    }
}

/// 给 Form 里一点内边距，避免圆角框贴边
private final class PaddingTextField: UITextField {
    override func textRect(forBounds bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: 8, dy: 6)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: 8, dy: 6)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: 8, dy: 6)
    }
}

/// 小数金额输入：String 态保存，允许 `.` / `。` / `,`；键盘上方仅保留「完成」收起。
struct DecimalTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = PaddingTextField()
        field.placeholder = placeholder
        field.delegate = context.coordinator
        field.text = text
        field.borderStyle = .roundedRect
        field.backgroundColor = .secondarySystemBackground
        field.keyboardType = .decimalPad
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.clearButtonMode = .whileEditing
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "完成", style: .done, target: context.coordinator, action: #selector(Coordinator.done))
        toolbar.items = [flex, done]
        field.inputAccessoryView = toolbar
        context.coordinator.field = field

        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.field = uiView
        if !uiView.isFirstResponder, uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        weak var field: UITextField?

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func editingChanged(_ sender: UITextField) {
            let normalized = Self.normalizeDecimalTyping(sender.text ?? "")
            if sender.text != normalized {
                sender.text = normalized
            }
            text.wrappedValue = normalized
        }

        @objc func done() {
            field?.resignFirstResponder()
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty { return true }
            let normalizedReplacement = string
                .replacingOccurrences(of: "。", with: ".")
                .replacingOccurrences(of: "．", with: ".")
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: "，", with: ".")

            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: swiftRange, with: normalizedReplacement)
            return Self.isValidDecimalTyping(proposed)
        }

        static func normalizeDecimalTyping(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: "。", with: ".")
                .replacingOccurrences(of: "．", with: ".")
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: "，", with: ".")
        }

        static func isValidDecimalTyping(_ value: String) -> Bool {
            if value.isEmpty { return true }
            let pattern = #"^\d*\.?\d*$"#
            return value.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

/// 代码输入。不用 asciiCapable，避免同一页切到名称时中文键盘被系统粘住/切不回来。
struct SymbolTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = PaddingTextField()
        field.placeholder = placeholder
        field.delegate = context.coordinator
        field.text = text
        field.borderStyle = .roundedRect
        field.backgroundColor = .secondarySystemBackground
        field.keyboardType = .default
        field.autocorrectionType = .no
        field.autocapitalizationType = .allCharacters
        field.spellCheckingType = .no
        field.returnKeyType = .next
        field.clearButtonMode = .whileEditing
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        guard !uiView.isFirstResponder else { return }
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func editingChanged(_ sender: UITextField) {
            guard sender.markedTextRange == nil else { return }
            let value = sender.text ?? ""
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            let value = textField.text ?? ""
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
