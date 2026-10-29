import Foundation

/// Settings → About → Legal Notices. The wording is the project's existing text (README.md and
/// THIRD_PARTY_NOTICES.md, kept in sync by the tests); it is shown in full, never shortened.
public enum LegalNotices {
    public struct Section: Equatable, Sendable {
        public let title: String
        public let body: String
    }

    public static let independence =
        "ZAP is an independent third-party application and is not affiliated with, endorsed by, or sponsored by Amazon."
    public static let trademarks =
        "Amazon, Fire TV, Fire OS and Alexa are trademarks of Amazon.com, Inc. or its affiliates. Apple, AirPlay and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions."
    public static let nameNotice =
        "ZAP is unrelated to the ZAP web security scanner (ZAP by Checkmarx, formerly OWASP ZAP)."
    public static let airPlayReceivers =
        "AirPlay receiver apps for Fire TV are third-party apps, not made or certified by Apple."
    public static let noThirdPartyCode = "ZAP contains no third-party code and has no package dependencies."
    public static let noAmazonCode =
        "No Amazon software was decompiled and no Amazon code, keys, firmware, APKs or assets are included."
    public static let appIcons =
        "App icons shown on shortcut tiles are not part of ZAP: they are the icons your Fire TV lists for its installed apps, downloaded at run time from Amazon's image servers and cached only on your Mac. They belong to their respective owners, and screenshots that show them do not imply any affiliation."

    /// The copyright line exactly as written in the LICENSE file.
    public static func copyrightLine(inLicense text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("Copyright") }
    }

    public static func sections(license: String?) -> [Section] {
        let copyright = [license.flatMap(copyrightLine(inLicense:)),
                         "ZAP is released under the MIT License; the full text is under License in About."]
            .compactMap { $0 }
            .joined(separator: "\n")
        return [
            Section(title: "Independent App", body: independence),
            Section(title: "Trademarks", body: "\(trademarks) \(airPlayReceivers) \(nameNotice)"),
            Section(title: "Copyright and License", body: copyright),
            Section(title: "Third-Party Content", body: "\(noThirdPartyCode) \(noAmazonCode)\n\(appIcons)"),
        ]
    }
}
