import AppKit
import SwiftUI

@MainActor final class WorkspaceCalculation: ObservableObject {
  static let shared = WorkspaceCalculation()
  @Published var expression = "" {
    didSet { error = false }
  }
  @Published private(set) var history: [Entry] = []
  @Published private(set) var error = false

  struct Entry: Equatable {
    let expression: String
    let result: String
  }

  var result: String? {
    if expression.isEmpty { return "0" }
    var parser = NotchCalculator(expression)
    return parser.evaluate().map { String(format: "%.12g", $0) }
  }

  func evaluate() {
    guard !expression.isEmpty else { return }
    guard let result else { error = true; return }
    let entry = Entry(expression: expression, result: result)
    if entry != history.first {
      history.insert(entry, at: 0)
      if history.count > 20 { history.removeLast() }
    }
    expression = result
  }

  func press(_ key: String) {
    switch key {
    case "AC": expression = ""
    case "=": evaluate()
    case "⌫": if !expression.isEmpty { expression.removeLast() }
    case "±": apply("-(\(expression))")
    case "x²": apply("(\(expression))^2")
    case "1/x": apply("1/(\(expression))")
    case "x!": apply("fact(\(expression))")
    case "xʸ": expression += "^"
    case "EE": expression += "e"
    case "√": expression += "sqrt("
    case "sin", "cos", "tan", "log", "ln": expression += key + "("
    default: expression += key
    }
  }

  private func apply(_ formula: String) {
    guard result != nil, !expression.isEmpty else { return }
    expression = formula
    evaluate()
  }

  func copy() {
    guard let result else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(result, forType: .string)
  }
}

struct WorkspaceCalculatorView: View {
  @ObservedObject var shelf: DropPopupController
  @ObservedObject private var model = WorkspaceCalculation.shared
  @Environment(\.colorScheme) private var appearance

  private let keys = ["AC", "±", "%", "÷", "7", "8", "9", "×", "4", "5", "6", "−",
                      "1", "2", "3", "+", "0", ".", "⌫", "="]
  private let functions = ["sin", "cos", "tan", "log", "ln", "√", "x²", "xʸ", "1/x",
                           "π", "(", ")", "e", "EE", "x!"]
  private var teal: Color { Color(red: 0.58, green: 0.89, blue: 0.87) }

  var body: some View {
    VStack(spacing: 8) {
      if shelf.isArrowPreview {
        HStack(spacing: 7) {
          Image(systemName: NotchModule.calculator.symbol).foregroundStyle(teal)
          Text("Calculator").font(.system(size: 13, weight: .semibold))
          Spacer()
          Button { shelf.openArrow(.calculator, at: nil) } label: { Image(systemName: "return") }
            .buttonStyle(.plain).help("Open Calculator").accessibilityLabel("Open Calculator")
        }
        Spacer(minLength: 0)
        display(historyOnly: true)
          .contentShape(Rectangle())
          .onTapGesture { shelf.openArrow(.calculator, at: nil) }
      } else {
        header
        display(historyOnly: false)
        Spacer(minLength: 0)
        HStack(spacing: 9) {
          if shelf.calculatorScientific && !shelf.calculatorExpandsRight { grid(functions, columns: 3, compact: true) }
          grid(keys, columns: 4, compact: false)
          if shelf.calculatorScientific && shelf.calculatorExpandsRight { grid(functions, columns: 3, compact: true) }
        }
      }
    }
    .padding(.horizontal, 1)
    .padding(.vertical, shelf.isArrowPreview ? 2 : 4)

  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: NotchModule.calculator.symbol).foregroundStyle(teal).accessibilityHidden(true)
      Button { shelf.toggleCalculatorMode() } label: {
        Text(shelf.calculatorScientific ? "Scientific" : "Basic")
          .font(.system(size: 12, weight: .semibold))
          .padding(.horizontal, 11).padding(.vertical, 5)
          .background(teal.opacity(0.18), in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(shelf.calculatorScientific ? "Basic mode" : "Scientific mode")
      .help(shelf.calculatorScientific ? "Switch to Basic" : "Switch to Scientific")
      Spacer(minLength: 4)
      Menu {
        ForEach(Array(model.history.enumerated()), id: \.offset) { _, entry in
          Button("\(entry.expression) = \(entry.result)") { model.expression = entry.result }
        }
        if model.history.isEmpty { Text("No calculations yet") }
      } label: { Image(systemName: "clock").font(.system(size: 13)).frame(width: 19, height: 23) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("History").help("Calculation history")
      Button(action: model.copy) { Image(systemName: "doc.on.doc").frame(width: 19, height: 23) }
        .buttonStyle(.plain).accessibilityLabel("Copy").help("Copy result").disabled(model.result == nil)
      Menu {
        Button(shelf.keepArrowOpen ? "Unpin panel" : "Keep panel open", action: shelf.toggleArrowRetention)
        Button("Close Calculator", action: shelf.dismiss)
      } label: { Image(systemName: "ellipsis").frame(width: 16, height: 23) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Calculator options")
    }
    .font(.system(size: 13, weight: .medium))
  }

  private func display(historyOnly: Bool) -> some View {
    let history = model.history.first
    let expression = history.map { "\($0.expression) =" } ?? " "
    let shown = historyOnly ? (history?.result ?? model.result ?? "0") : (model.error ? "Error" : model.result ?? "—")
    return VStack(alignment: .trailing, spacing: 1) {
      if historyOnly {
        Text(expression).lineLimit(1).foregroundStyle(.secondary)
      } else {
        let committed = history?.result == model.expression
        CalculatorInput(expression: $model.expression, focusRequest: shelf.calculatorFocusRequest,
          showsHistory: committed, mayFocus: {
            shelf.activeModule == .calculator && shelf.toolsVisible && !shelf.choosingArrow && !shelf.isArrowPreview
          }, evaluate: model.evaluate)
          .frame(height: 20)
          .overlay(alignment: .trailing) {
            if committed {
              Text(expression).lineLimit(1).foregroundStyle(.secondary)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
          }
      }
      Text(shown)
        .font(.system(size: historyOnly ? 35 : 43, weight: .light).monospacedDigit())
        .lineLimit(1).minimumScaleFactor(0.45)
        .accessibilityLabel("Result " + shown)
    }.font(.system(size: 13).monospacedDigit())
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.horizontal, 4)
  }

  private func grid(_ labels: [String], columns: Int, compact: Bool) -> some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns), spacing: 5) {
      ForEach(labels, id: \.self) { key in
        let isOperator = ["÷", "×", "−", "+", "="].contains(key)
        let fill = key == "=" ? teal : isOperator ? Color(red: 0.21, green: 0.47, blue: 0.49)
          : (appearance == .dark ? Color(red: 0.16, green: 0.23, blue: 0.29) : Color.primary.opacity(0.085))
        Button {
          model.press(key)
          shelf.focusForKeyboard()
        } label: {
          Text(key).font(.system(size: compact ? 12 : 17, weight: key == "=" ? .semibold : .regular))
            .foregroundStyle(key == "=" ? Color.black : isOperator ? .white : .primary)
            .frame(maxWidth: .infinity).frame(height: 35)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }.buttonStyle(WorkspaceKeyStyle())
          .accessibilityLabel(key == "⌫" ? "Delete" : key)
      }
    }.frame(width: compact ? 132 : nil)
  }
}

private struct CalculatorInput: NSViewRepresentable {
  @Binding var expression: String
  let focusRequest: Int
  let showsHistory: Bool
  let mayFocus: () -> Bool
  let evaluate: () -> Void

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: CalculatorInput
    var lastFocusRequest: Int?
    init(_ parent: CalculatorInput) { self.parent = parent }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.expression = field.stringValue
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
      guard command == #selector(NSResponder.insertNewline(_:)) else { return false }
      parent.evaluate()
      return true
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField(string: expression)
    field.isEditable = true
    field.isSelectable = true
    field.isBezeled = false
    field.isBordered = false
    field.drawsBackground = false
    field.alignment = .right
    field.usesSingleLineMode = true
    field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    field.setAccessibilityLabel("Expression")
    field.delegate = context.coordinator
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    if field.stringValue != expression {
      field.stringValue = expression
      if let editor = field.currentEditor() as? NSTextView {
        editor.string = expression
        editor.setSelectedRange(NSRange(location: expression.utf16.count, length: 0))
      }
    }
    field.textColor = showsHistory ? .clear : .secondaryLabelColor
    (field.currentEditor() as? NSTextView)?.textColor = field.textColor
    guard coordinator.lastFocusRequest != focusRequest else { return }
    coordinator.lastFocusRequest = focusRequest
    DispatchQueue.main.async { [weak field] in
      guard mayFocus(), let field, let window = field.window, window.isKeyWindow else { return }
      if field.currentEditor() == nil { window.makeFirstResponder(field) }
    }
  }
}

struct WorkspaceKeyStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.68 : 1)
  }
}
