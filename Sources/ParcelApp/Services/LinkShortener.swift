import Foundation

enum LinkShortener {
  enum Failure: LocalizedError {
    case invalidLink, rejected(String)
    var errorDescription: String? {
      switch self {
      case .invalidLink: "That link could not be shortened."
      case .rejected(let message): message
      }
    }
  }

  static func links(in text: String) -> [URL] {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
    var seen = Set<String>()
    return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
      guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
        seen.insert(url.absoluteString).inserted else { return nil }
      return url
    }
  }

  static func request(for url: URL) throws -> URLRequest {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw Failure.invalidLink }
    var endpoint = URLComponents(string: "https://da.gd/s")!
    endpoint.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
    guard let requestURL = endpoint.url else { throw Failure.invalidLink }
    var request = URLRequest(url: requestURL)
    request.timeoutInterval = 15
    return request
  }

  static func shorten(_ url: URL, session: URLSession = .shared) async throws -> URL {
    let (data, response) = try await session.data(for: request(for: url))
    let text = String(decoding: data.prefix(8_192), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      !text.hasPrefix("Error: ") else { throw Failure.rejected(text.isEmpty ? "The shortening service did not accept this link." : text) }
    guard let shortened = URL(string: text), shortened.scheme == "https", shortened.host == "da.gd" else {
      throw Failure.invalidLink
    }
    return shortened
  }
}
