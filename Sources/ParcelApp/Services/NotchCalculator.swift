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
    if consume("(") {
      guard let value = sum(), consume(")") else { return nil }
      return value
    }
    let start = index
    while index < input.count, input[index].isNumber || input[index] == "." { index += 1 }
    guard index > start, let value = Double(String(input[start..<index])) else { return nil }
    return consume("%") ? value / 100 : value
  }
}
