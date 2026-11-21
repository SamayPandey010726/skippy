import Foundation

/// A deliberately small arithmetic parser; input is never evaluated as code.
struct NotchCalculator {
  private var input: [Character]
  private var index = 0

  init(_ expression: String) {
    input = Array(expression.filter { !$0.isWhitespace })
  }

  mutating func evaluate() -> Double? {
    guard input.count <= 256, let value = sum(), index == input.count, value.isFinite else { return nil }
    return value
  }

  private mutating func consume(_ character: Character) -> Bool {
    guard index < input.count, input[index] == character else { return false }
    index += 1
    return true
  }

  private mutating func sum() -> Double? {
    guard var value = product() else { return nil }
    while index < input.count {
      if consume("+") { guard let rhs = product() else { return nil }; value += rhs }
      else if consume("-") || consume("−") { guard let rhs = product() else { return nil }; value -= rhs }
      else { break }
    }
    return value
  }

  private mutating func product() -> Double? {
    guard var value = factor() else { return nil }
    while index < input.count {
      if consume("*") || consume("×") { guard let rhs = factor() else { return nil }; value *= rhs }
      else if consume("/") || consume("÷") {
        guard let rhs = factor(), rhs != 0 else { return nil }; value /= rhs
      } else { break }
    }
    return value
  }

  private mutating func factor() -> Double? {
    if consume("-") || consume("−") { return factor().map { -$0 } }
    if consume("+") { return factor() }
    guard var value = atom() else { return nil }
    if consume("%") { value /= 100 }
    if consume("^") {
      guard let exponent = factor() else { return nil }
      value = pow(value, exponent)
    }
    return value
  }

  private mutating func atom() -> Double? {
    if consume("π") { return .pi }
    if consume("(") {
      guard let value = sum(), consume(")") else { return nil }
      return value
    }
    let start = index
    while index < input.count, input[index].isLetter { index += 1 }
    if index > start {
      let function = String(input[start..<index]).lowercased()
      guard consume("("), let value = sum(), consume(")") else { return nil }
      switch function {
      case "sin": return sin(value)
      case "cos": return cos(value)
      case "tan": return tan(value)
      case "sqrt": return sqrt(value)
      case "log": return log10(value)
      case "ln": return log(value)
      default: return nil
      }
    }
    while index < input.count, input[index].isNumber || input[index] == "." { index += 1 }
    guard index > start else { return nil }
    if consume("e") || consume("E") {
      if !consume("+") { _ = consume("-") }
      let exponentStart = index
      while index < input.count, input[index].isNumber { index += 1 }
      guard exponentStart < index else { return nil }
    }
    return Double(String(input[start..<index]))
  }
}
