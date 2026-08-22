import Foundation
import Testing

@testable import SystemHeadroom

@Suite("Direct edition presentation")
struct DirectEditionPresentationTests {
  @Test("Transfer UI is visible only for a configured App Store build")
  func visibilityGate() throws {
    let endpoint = try #require(URL(string: "https://claim.example.com/v1/claims"))

    #expect(DirectEditionAccessPresentation.isVisible(
      canTerminate: false, claimEndpoint: endpoint))
    #expect(!DirectEditionAccessPresentation.isVisible(
      canTerminate: false, claimEndpoint: nil))
    #expect(!DirectEditionAccessPresentation.isVisible(
      canTerminate: true, claimEndpoint: endpoint))
  }
}

@Suite("Direct edition claim")
struct DirectEditionClaimTests {
  @Test("Claim sends only the App Store purchase evidence")
  func claimSendsPurchaseEvidence() async throws {
    let endpoint = try #require(URL(string: "https://claim.example.com/v1/claims"))
    let expectedEvidence = DirectEditionPurchaseEvidence(
      appTransactionID: "app-transaction-123",
      bundleID: "com.vinnycarpenter.MacHeadroom",
      originalPurchaseDate: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let client = DirectEditionClaimClient(
      endpoint: endpoint,
      loadEvidence: { expectedEvidence },
      send: { request in
        #expect(request.url == endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        #expect(try JSONDecoder.directEdition.decode(
          DirectEditionPurchaseEvidence.self, from: body) == expectedEvidence)

        let response = HTTPURLResponse(
          url: endpoint, statusCode: 201, httpVersion: nil, headerFields: nil)!
        let data = Data("{\"claimURL\":\"https://www.macheadroom.com/direct/claim/token\"}".utf8)
        return (data, response)
      }
    )

    let claimURL = try await client.claim()
    #expect(claimURL.absoluteString == "https://www.macheadroom.com/direct/claim/token")
  }

  @Test("Claim rejects a non-HTTPS handoff URL")
  func claimRejectsNonHTTPSURL() async throws {
    let endpoint = try #require(URL(string: "https://claim.example.com/v1/claims"))
    let client = DirectEditionClaimClient(
      endpoint: endpoint,
      loadEvidence: {
        DirectEditionPurchaseEvidence(
          appTransactionID: "app-transaction-123",
          bundleID: "com.vinnycarpenter.MacHeadroom",
          originalPurchaseDate: .now)
      },
      send: { _ in
        let response = HTTPURLResponse(
          url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data("{\"claimURL\":\"http://example.com/claim\"}".utf8), response)
      }
    )

    await #expect(throws: DirectEditionClaimError.invalidResponse) {
      _ = try await client.claim()
    }
  }

  @Test("Claim refuses an endpoint that is not HTTPS")
  func claimRefusesNonHTTPSEndpoint() async throws {
    let endpoint = try #require(URL(string: "http://claim.example.com/v1/claims"))
    let client = DirectEditionClaimClient(
      endpoint: endpoint,
      loadEvidence: {
        Issue.record("Evidence loading should not be attempted for an invalid endpoint")
        return DirectEditionPurchaseEvidence(
          appTransactionID: "unused", bundleID: "unused", originalPurchaseDate: .now)
      },
      send: { _ in
        Issue.record("Request sending should not be attempted for an invalid endpoint")
        return (
          Data(),
          URLResponse(
            url: endpoint, mimeType: nil, expectedContentLength: 0,
            textEncodingName: nil)
        )
      }
    )

    await #expect(throws: DirectEditionClaimError.configurationMissing) {
      _ = try await client.claim()
    }
  }
}
