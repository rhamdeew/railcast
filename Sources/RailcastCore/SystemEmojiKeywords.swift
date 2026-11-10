import Foundation

/// Reads the emoji search words built into macOS, which cover slang that Unicode data lacks ("хз" → 🤷).
///
/// The index is a private part of macOS, so it is read on the user's Mac and never bundled.
/// When the file or a function is missing, the result is empty and search uses the bundled data alone.
public enum SystemEmojiKeywords {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/CoreEmoji.framework/CoreEmoji"
    private static let resourcesPath = "/System/Library/PrivateFrameworks/CoreEmoji.framework/Versions/A/Resources"

    private typealias CreateLocaleData = @convention(c) (CFString) -> UnsafeMutableRawPointer?
    private typealias CreateToken = @convention(c) (Int, UnsafeMutableRawPointer) -> UnsafeRawPointer?
    private typealias TokenString = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>?

    /// Returns search words keyed by emoji. macOS ships this index only for some languages.
    /// Tokens stay unreleased: their ownership is undocumented, and there are about 2,000 of them, once.
    public static func load(language: String) -> [String: [String]] {
        let indexURL = URL(fileURLWithPath: "\(resourcesPath)/\(language).lproj/term_index.plist")
        guard let library = dlopen(frameworkPath, RTLD_NOW),
              let createLocaleSymbol = dlsym(library, "CEMCreateEmojiLocaleData"),
              let createTokenSymbol = dlsym(library, "CEMEmojiTokenCreateWithIndex"),
              let tokenStringSymbol = dlsym(library, "CEMEmojiTokenGetString"),
              let data = try? Data(contentsOf: indexURL),
              let index = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [Int]]
        else { return [:] }

        let createLocaleData = unsafeBitCast(createLocaleSymbol, to: CreateLocaleData.self)
        let createToken = unsafeBitCast(createTokenSymbol, to: CreateToken.self)
        let tokenString = unsafeBitCast(tokenStringSymbol, to: TokenString.self)
        guard let localeData = createLocaleData(language as CFString) else { return [:] }

        var characters: [Int: String] = [:]
        var keywords: [String: [String]] = [:]
        for (term, ids) in index {
            for id in ids {
                if characters[id] == nil,
                   let token = createToken(id, localeData),
                   let string = tokenString(token) {
                    characters[id] = string.takeUnretainedValue() as String
                }
                if let character = characters[id] {
                    keywords[character, default: []].append(term)
                }
            }
        }
        return keywords
    }
}
