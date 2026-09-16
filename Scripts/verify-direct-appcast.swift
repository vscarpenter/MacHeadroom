#!/usr/bin/env swift
// Verify generated update metadata against the actual DMG and its exported app.
// Sparkle 2 writes version fields as item children, and edSignature on enclosure.
// This command only reads files and verifies with the app's public key. It never
// accesses Keychain, retrieves a signing key, or uses the network.
import CryptoKit
import Foundation

private let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
private let feedURL = "https://www.macheadroom.com/direct/appcast.xml"
private let bundleID = "com.vinnycarpenter.SystemHeadroom.Direct"

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw VerificationFailure(message) }
}

private func plistString(_ plist: [String: Any], _ key: String) throws -> String {
    guard let value = plist[key] as? String, !value.isEmpty,
          value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
        throw VerificationFailure("App Info.plist must contain a nonempty \(key) string")
    }
    return value
}

private func child(_ parent: XMLElement, _ name: String, namespace: String = "") throws -> XMLElement {
    let matches = (parent.children ?? []).compactMap { $0 as? XMLElement }.filter {
        $0.localName == name && ($0.uri ?? "") == namespace
    }
    try require(matches.count == 1, "Appcast must contain exactly one \(name) under \(parent.name ?? "parent")")
    return matches[0]
}

private func sparkleText(_ item: XMLElement, _ name: String) throws -> String {
    let element = try child(item, name, namespace: sparkleNamespace)
    try require(!(element.children ?? []).contains { $0 is XMLElement }, "Appcast \(name) must contain text only")
    guard let value = element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        throw VerificationFailure("Appcast \(name) must not be empty")
    }
    return value
}

private func attribute(_ element: XMLElement, _ name: String, namespace: String = "") -> String? {
    (element.attributes ?? []).first {
        $0.localName == name && ($0.uri ?? "") == namespace
    }?.stringValue
}

private func canonicalBase64(_ value: String, bytes: Int, name: String) throws -> Data {
    guard let decoded = Data(base64Encoded: value), decoded.count == bytes,
          decoded.base64EncodedString() == value else {
        throw VerificationFailure("\(name) must be canonical Base64 encoding exactly \(bytes) bytes")
    }
    return decoded
}

private func validatePublicKey(_ data: Data) throws {
    // Ed25519 stores y little-endian with x's sign in the top bit. CryptoKit's
    // raw-key initializer accepts low-order points, including the identity,
    // which can verify signatures without a secret key. Reject those points
    // and noncanonical y encodings before using CryptoKit's signature check.
    var y = Array(data)
    y[31] &= 0x7f
    let prime: [UInt8] = [0xed] + Array(repeating: 0xff, count: 30) + [0x7f]
    try require(y.reversed().lexicographicallyPrecedes(prime.reversed()),
                "SUPublicEDKey must use a canonical Ed25519 point")
    let lowOrderY: Set<String> = [
        String(repeating: "00", count: 32),
        "01" + String(repeating: "00", count: 31),
        "ec" + String(repeating: "ff", count: 30) + "7f",
        "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
        "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
    ]
    let encodedY = y.map { String(format: "%02x", $0) }.joined()
    try require(!lowOrderY.contains(encodedY), "SUPublicEDKey must not be a low-order Ed25519 point")
}

private func verify(appcastURL: URL, dmgURL: URL, infoURL: URL) throws {
    guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any] else {
        throw VerificationFailure("App Info.plist must be a dictionary")
    }
    let marketingVersion = try plistString(info, "CFBundleShortVersionString")
    let build = try plistString(info, "CFBundleVersion")
    let minimumOS = try plistString(info, "LSMinimumSystemVersion")
    try require(marketingVersion.range(of: #"^[0-9]+(?:\.[0-9]+){0,2}$"#, options: .regularExpression) != nil,
                "CFBundleShortVersionString must have one to three numeric components")
    try require(build.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
                "CFBundleVersion must be an integer")
    try require(try plistString(info, "CFBundleIdentifier") == bundleID, "App must use the Direct bundle identifier")
    try require(try plistString(info, "SUFeedURL") == feedURL, "App SUFeedURL must be \(feedURL)")
    let publicKeyData = try canonicalBase64(plistString(info, "SUPublicEDKey"), bytes: 32, name: "SUPublicEDKey")
    try validatePublicKey(publicKeyData)
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)

    let xmlData = try Data(contentsOf: appcastURL)
    // No external entity loads, even for an untrusted local appcast.
    let document = try XMLDocument(data: xmlData, options: .nodeLoadExternalEntitiesNever)
    try require(document.dtd == nil, "Appcast must not contain a DTD")
    guard let rss = document.rootElement(), rss.localName == "rss", (rss.uri ?? "").isEmpty else {
        throw VerificationFailure("Appcast root must be rss")
    }
    let channel = try child(rss, "channel")
    let item = try child(channel, "item")
    let enclosure = try child(item, "enclosure")
    // A fresh release stages one complete archive. Reject delta/extra enclosures
    // so an unrelated update cannot pass validation beside the expected one.
    let enclosures = try document.nodes(forXPath: "//*[local-name()='enclosure']")
    try require(enclosures.count == 1, "Appcast must contain exactly one full enclosure")
    try require(attribute(enclosure, "deltaFrom", namespace: sparkleNamespace) == nil,
                "Appcast must contain a full enclosure, not a delta")

    for (field, expected) in [("version", build), ("shortVersionString", marketingVersion), ("minimumSystemVersion", minimumOS)] {
        try require(try sparkleText(item, field) == expected, "Appcast sparkle:\(field) must match app Info.plist (\(expected))")
        // Current generate_appcast uses item children. Refuse conflicting legacy
        // enclosure attributes if an appcast is edited or mixed with older XML.
        if let legacyValue = attribute(enclosure, field, namespace: sparkleNamespace) {
            try require(legacyValue == expected, "Appcast enclosure sparkle:\(field) conflicts with app Info.plist")
        }
    }

    let expectedURL = "https://www.macheadroom.com/direct/updates/System-Headroom-Direct-\(marketingVersion)-\(build).dmg"
    try require(attribute(enclosure, "url") == expectedURL, "Appcast enclosure URL must be exactly \(expectedURL)")
    let dmgData = try Data(contentsOf: dmgURL, options: .mappedIfSafe)
    guard let lengthText = attribute(enclosure, "length"), let length = UInt64(lengthText),
          lengthText == String(length), length == UInt64(dmgData.count) else {
        throw VerificationFailure("Appcast enclosure length must match actual DMG size (\(dmgData.count) bytes)")
    }
    guard let signatureText = attribute(enclosure, "edSignature", namespace: sparkleNamespace) else {
        throw VerificationFailure("Appcast enclosure is missing its Sparkle EdDSA signature")
    }
    let signature = try canonicalBase64(signatureText, bytes: 64, name: "Sparkle EdDSA signature")
    try require(publicKey.isValidSignature(signature, for: dmgData),
                "Appcast EdDSA signature does not verify against the DMG and the app's SUPublicEDKey")
    print("OK: verified Direct appcast for \(marketingVersion) (\(build)), \(dmgData.count) bytes, valid EdDSA signature")
}

do {
    guard CommandLine.arguments.count == 4 else {
        throw VerificationFailure("Usage: verify-direct-appcast.swift appcast.xml release.dmg exported-app-Info.plist")
    }
    try verify(appcastURL: URL(fileURLWithPath: CommandLine.arguments[1]),
               dmgURL: URL(fileURLWithPath: CommandLine.arguments[2]),
               infoURL: URL(fileURLWithPath: CommandLine.arguments[3]))
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}
