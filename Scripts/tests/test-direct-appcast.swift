#!/usr/bin/env swift
// Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift Scripts/tests/test-direct-appcast.swift
// All signing keys are ephemeral CryptoKit keys. This test never opens Keychain or the network.
import CryptoKit
import Foundation

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): return message }
    }
}

func run(_ executable: URL, _ arguments: [String]) throws -> (Int32, String) {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

let fileManager = FileManager.default
let testURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let scripts = testURL.deletingLastPathComponent().deletingLastPathComponent()
let temporary = fileManager.temporaryDirectory.appendingPathComponent("direct-appcast-tests-\(UUID().uuidString)")

do {
    try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: temporary) }
    let verifier = temporary.appendingPathComponent("verify-direct-appcast")
    let compilation = try run(URL(fileURLWithPath: "/usr/bin/xcrun"), [
        "swiftc", scripts.appendingPathComponent("verify-direct-appcast.swift").path,
        "-module-cache-path", temporary.appendingPathComponent("modules").path,
        "-o", verifier.path,
    ])
    guard compilation.0 == 0 else { throw TestFailure.failed("Verifier compilation failed:\n\(compilation.1)") }

    let key = Curve25519.Signing.PrivateKey()
    let otherKey = Curve25519.Signing.PrivateKey()
    let bytes = Data("fixture DMG bytes; no filesystem image is needed for signature verification".utf8)
    let signature = try key.signature(for: bytes).base64EncodedString()
    let dmg = temporary.appendingPathComponent("System-Headroom-Direct-1.2.3-45.dmg")
    let appcast = temporary.appendingPathComponent("appcast.xml")
    let plist = temporary.appendingPathComponent("Info.plist")
    let goodInfo: [String: Any] = [
        "CFBundleIdentifier": "com.vinnycarpenter.SystemHeadroom.Direct",
        "CFBundleShortVersionString": "1.2.3",
        "CFBundleVersion": "45",
        "LSMinimumSystemVersion": "14.0",
        "SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString(),
        "SUFeedURL": "https://www.macheadroom.com/direct/appcast.xml",
    ]
    let enclosure = """
    <enclosure url="https://www.macheadroom.com/direct/updates/System-Headroom-Direct-1.2.3-45.dmg" length="\(bytes.count)" type="application/octet-stream" sparkle:edSignature="\(signature)"/>
    """
    let item = """
    <item><title>Version 1.2.3</title>
      <sparkle:version>45</sparkle:version>
      <sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      \(enclosure)
    </item>
    """
    let goodXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel><title>System Headroom Direct</title>\(item)</channel>
    </rss>
    """
    var passed = 0

    func check(_ name: String, xml: String = goodXML, info: [String: Any] = goodInfo,
               data: Data = bytes, accepts: Bool = false, diagnostic: String? = nil) throws {
        try data.write(to: dmg)
        try Data(xml.utf8).write(to: appcast)
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: plist)
        let result = try run(verifier, [appcast.path, dmg.path, plist.path])
        guard (result.0 == 0) == accepts else {
            throw TestFailure.failed("\(name): expected \(accepts ? "acceptance" : "rejection"), got \(result.0): \(result.1)")
        }
        if let diagnostic, !result.1.contains(diagnostic) {
            throw TestFailure.failed("\(name): expected diagnostic '\(diagnostic)', got \(result.1)")
        }
        passed += 1
        print("PASS: \(name)")
    }

    try check("valid current Sparkle schema", accepts: true)
    try check("equivalent Sparkle namespace prefix", xml: goodXML.replacingOccurrences(of: "sparkle:", with: "update:").replacingOccurrences(of: "xmlns:sparkle", with: "xmlns:update"), accepts: true)
    var changedInfo = goodInfo
    changedInfo["SUPublicEDKey"] = otherKey.publicKey.rawRepresentation.base64EncodedString()
    try check("wrong app public key", info: changedInfo, diagnostic: "signature")
    var tampered = bytes
    tampered[0] ^= 1
    try check("tampered DMG with unchanged length", data: tampered, diagnostic: "signature")
    try check("wrong download host", xml: goodXML.replacingOccurrences(of: "https://www.macheadroom.com/", with: "https://example.com/"), diagnostic: "URL")
    try check("missing build in download URL", xml: goodXML.replacingOccurrences(of: "1.2.3-45.dmg", with: "1.2.3.dmg"), diagnostic: "URL")
    try check("wrong enclosure length", data: bytes + Data([0]), diagnostic: "length")
    try check("wrong build version", xml: goodXML.replacingOccurrences(of: "<sparkle:version>45", with: "<sparkle:version>46"), diagnostic: "version")
    try check("wrong marketing version", xml: goodXML.replacingOccurrences(of: "<sparkle:shortVersionString>1.2.3", with: "<sparkle:shortVersionString>1.2.4"), diagnostic: "shortVersionString")
    try check("conflicting legacy version", xml: goodXML.replacingOccurrences(of: "sparkle:edSignature=", with: "sparkle:version=\"46\" sparkle:edSignature="), diagnostic: "version")
    try check("wrong minimum OS", xml: goodXML.replacingOccurrences(of: "<sparkle:minimumSystemVersion>14.0", with: "<sparkle:minimumSystemVersion>13.0"), diagnostic: "minimumSystemVersion")
    try check("missing top-level version", xml: goodXML.replacingOccurrences(of: "<sparkle:version>45</sparkle:version>", with: ""), diagnostic: "version")
    try check("duplicate top-level version", xml: goodXML.replacingOccurrences(of: "<sparkle:version>45</sparkle:version>", with: "<sparkle:version>45</sparkle:version><sparkle:version>46</sparkle:version>"), diagnostic: "version")
    try check("wrong Sparkle namespace", xml: goodXML.replacingOccurrences(of: "http://www.andymatuschak.org/xml-namespaces/sparkle", with: "https://example.com/namespace"), diagnostic: "version")
    try check("extra full enclosure", xml: goodXML.replacingOccurrences(of: enclosure, with: enclosure + enclosure), diagnostic: "enclosure")
    try check("extra item", xml: goodXML.replacingOccurrences(of: item, with: item + item), diagnostic: "item")
    try check("delta enclosure only", xml: goodXML.replacingOccurrences(of: "sparkle:edSignature=", with: "sparkle:deltaFrom=\"44\" sparkle:edSignature="), diagnostic: "delta")
    try check("delta enclosure alongside full", xml: goodXML.replacingOccurrences(of: enclosure, with: enclosure + "<sparkle:deltas>" + enclosure + "</sparkle:deltas>"), diagnostic: "enclosure")
    try check("malformed signature", xml: goodXML.replacingOccurrences(of: signature, with: "not-base64"), diagnostic: "signature")
    changedInfo = goodInfo
    changedInfo["SUPublicEDKey"] = "$(DIRECT_SPARKLE_PUBLIC_ED_KEY)"
    try check("unexpanded public key", info: changedInfo, diagnostic: "SUPublicEDKey")
    changedInfo["SUPublicEDKey"] = Data(repeating: 0, count: 32).base64EncodedString()
    try check("zero public key", info: changedInfo, diagnostic: "SUPublicEDKey")
    changedInfo["SUPublicEDKey"] = Data(repeating: 1, count: 31).base64EncodedString()
    try check("short public key", info: changedInfo, diagnostic: "SUPublicEDKey")
    let identity = Data([1] + Array(repeating: 0, count: 31))
    changedInfo["SUPublicEDKey"] = identity.base64EncodedString()
    let forgedSignature = (identity + Data(repeating: 0, count: 32)).base64EncodedString()
    try check("identity-key forged signature", xml: goodXML.replacingOccurrences(of: signature, with: forgedSignature), info: changedInfo, diagnostic: "SUPublicEDKey")
    let lowOrderPoints = [
        "ec" + String(repeating: "ff", count: 30) + "7f",
        "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
        "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
    ]
    for (index, hex) in lowOrderPoints.enumerated() {
        var point = stride(from: 0, to: hex.count, by: 2).map { offset -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
        for sign in [UInt8(0), UInt8(0x80)] {
            point[31] = (point[31] & 0x7f) | sign
            changedInfo["SUPublicEDKey"] = Data(point).base64EncodedString()
            try check("low-order public key \(index), sign \(sign)", info: changedInfo, diagnostic: "SUPublicEDKey")
        }
    }
    changedInfo["SUPublicEDKey"] = Data([0xed] + Array(repeating: 0xff, count: 30) + [0x7f]).base64EncodedString()
    try check("noncanonical public key", info: changedInfo, diagnostic: "SUPublicEDKey")
    changedInfo = goodInfo
    changedInfo["CFBundleIdentifier"] = "com.vinnycarpenter.SystemHeadroom"
    try check("App Store bundle rejected", info: changedInfo, diagnostic: "Direct bundle")
    changedInfo = goodInfo
    changedInfo["SUFeedURL"] = "https://example.com/appcast.xml"
    try check("wrong app update feed", info: changedInfo, diagnostic: "SUFeedURL")
    changedInfo = goodInfo
    changedInfo["LSMinimumSystemVersion"] = nil
    try check("missing minimum OS in app", info: changedInfo, diagnostic: "LSMinimumSystemVersion")
    try check("DTD rejected", xml: goodXML.replacingOccurrences(of: "<rss ", with: "<!DOCTYPE rss [<!ENTITY local '45'>]><rss "), diagnostic: "DTD")
    print("OK: \(passed) direct appcast verification tests passed (no Keychain or network access)")
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}
