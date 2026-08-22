import Foundation
import StoreKit

/// A compact, server-verifiable proof that an App Store customer has
/// downloaded this app. The server must independently verify the ID with
/// Apple's Get App Transaction Info endpoint before issuing any license.
struct DirectEditionPurchaseEvidence: Codable, Equatable, Sendable {
  let appTransactionID: String
  let bundleID: String
  let originalPurchaseDate: Date
}

/// Keeps the App Store transfer surface fail-closed. The user-facing entry
/// points exist only in a sandboxed build with an explicitly configured claim
/// endpoint; Direct builds and unconfigured App Store builds remain unchanged.
enum DirectEditionAccessPresentation {
  static func isVisible(canTerminate: Bool, claimEndpoint: URL?) -> Bool {
    !canTerminate && claimEndpoint != nil
  }
}

enum DirectEditionClaimError: LocalizedError, Equatable {
  case configurationMissing
  case purchaseVerificationFailed
  case claimServiceRejected
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .configurationMissing:
      "Direct edition transfer is not available yet."
    case .purchaseVerificationFailed:
      "We could not verify this App Store purchase. Try again while signed in to the App Store."
    case .claimServiceRejected:
      "The transfer service could not verify this purchase."
    case .invalidResponse:
      "The transfer service returned an invalid response."
    }
  }
}

enum AppStorePurchaseEvidence {
  static func load() async throws -> DirectEditionPurchaseEvidence {
    let result = try await AppTransaction.shared
    guard case .verified(let transaction) = result else {
      throw DirectEditionClaimError.purchaseVerificationFailed
    }

    return DirectEditionPurchaseEvidence(
      appTransactionID: transaction.appTransactionID,
      bundleID: transaction.bundleID,
      originalPurchaseDate: transaction.originalPurchaseDate
    )
  }
}

/// A narrow seam around the claim API. It deliberately sends only the
/// App Store transaction evidence; it never sends sampled process data or
/// other app preferences. The response is a short-lived HTTPS URL where the
/// customer completes the Direct-edition download.
struct DirectEditionClaimClient {
  private struct ClaimResponse: Decodable {
    let claimURL: URL
  }

  typealias EvidenceLoader = () async throws -> DirectEditionPurchaseEvidence
  typealias RequestSender = (URLRequest) async throws -> (Data, URLResponse)

  let endpoint: URL
  let loadEvidence: EvidenceLoader
  let send: RequestSender

  init(
    endpoint: URL,
    loadEvidence: @escaping EvidenceLoader = AppStorePurchaseEvidence.load,
    send: @escaping RequestSender = { request in
      try await URLSession.shared.data(for: request)
    }
  ) {
    self.endpoint = endpoint
    self.loadEvidence = loadEvidence
    self.send = send
  }

  func claim() async throws -> URL {
    guard endpoint.scheme == "https", endpoint.host != nil else {
      throw DirectEditionClaimError.configurationMissing
    }

    let evidence = try await loadEvidence()
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONEncoder.directEdition.encode(evidence)

    let (data, response) = try await send(request)
    guard response.url == endpoint else {
      throw DirectEditionClaimError.invalidResponse
    }
    guard let http = response as? HTTPURLResponse,
      (200...299).contains(http.statusCode)
    else {
      throw DirectEditionClaimError.claimServiceRejected
    }

    let claim = try JSONDecoder.directEdition.decode(ClaimResponse.self, from: data)
    guard claim.claimURL.scheme == "https", claim.claimURL.host != nil else {
      throw DirectEditionClaimError.invalidResponse
    }
    return claim.claimURL
  }
}

extension JSONEncoder {
  static let directEdition: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}

extension JSONDecoder {
  static let directEdition: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
