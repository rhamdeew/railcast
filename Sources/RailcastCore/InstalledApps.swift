import Foundation

public struct InstalledApp: Sendable, Identifiable, Hashable {
    public let name: String
    public let path: String
    let searchNames: [String]

    public var id: String { path }

    init(name: String, path: String) {
        self.name = name
        self.path = path
        let bundleName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        searchNames = Array(Set([name.lowercased(), bundleName.lowercased()]))
    }
}

/// Finds app bundles in the standard application folders. Nothing else on disk is looked at.
public enum AppScanner {
    /// Enough for folders like /Applications/Vendor/Suite/App.app.
    private static let maxFolderDepth = 2

    public static var defaultRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    public static var defaultExtraApps: [URL] {
        [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
    }

    public static func scan(
        roots: [URL] = defaultRoots,
        extraApps: [URL] = defaultExtraApps
    ) -> [InstalledApp] {
        var found = extraApps
        for root in roots {
            collectApps(in: root, depth: maxFolderDepth, into: &found)
        }

        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for url in found {
            // Some system apps, like Safari, are symlinks into another volume.
            let path = url.resolvingSymlinksInPath().path
            guard isLaunchable(path), seen.insert(path).inserted else { continue }
            apps.append(InstalledApp(name: displayName(of: url), path: path))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func collectApps(in directory: URL, depth: Int, into found: inout [URL]) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            if url.pathExtension.lowercased() == "app" {
                // Never descend into a bundle: helper apps inside it are not launchable by users.
                found.append(url)
                continue
            }
            guard depth > 0, let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true
            else { continue }
            collectApps(in: url, depth: depth - 1, into: &found)
        }
    }

    /// iPhone and iPad apps on Apple Silicon have a WrappedBundle instead of Contents.
    private static func isLaunchable(_ path: String) -> Bool {
        let files = FileManager.default
        return files.fileExists(atPath: path + "/Contents/Info.plist")
            || files.fileExists(atPath: path + "/WrappedBundle")
    }

    private static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

public enum AppSearch {
    /// Every word of the query must match. An empty query returns nothing, so apps appear only when searched for.
    public static func search(_ apps: [InstalledApp], query: String) -> [InstalledApp] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }

        var matches: [(score: Int, app: InstalledApp)] = []
        for app in apps {
            let scores = tokens.map { score($0, app) }
            if !scores.contains(0) {
                matches.append((scores.reduce(0, +), app))
            }
        }
        return matches.sorted {
            ($0.score, $1.app.name.count, $1.app.name) > ($1.score, $0.app.name.count, $0.app.name)
        }.map(\.app)
    }

    private static func score(_ token: String, _ app: InstalledApp) -> Int {
        app.searchNames.map { name in
            if name.hasPrefix(token) { return 3 }
            let words = name.split { !$0.isLetter && !$0.isNumber }
            if words.contains(where: { $0.hasPrefix(token) }) { return 2 }
            return name.contains(token) ? 1 : 0
        }.max() ?? 0
    }
}
