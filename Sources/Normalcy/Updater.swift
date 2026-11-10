import AppKit

// Checks GitHub for a newer release and, only when asked, swaps it in for this app and relaunches.
final class Updater: ObservableObject {
    static let shared = Updater()
    static let latestURL = URL(string: "https://api.github.com/repos/POSTTTT/Normalcy/releases/latest")!

    enum Status: Equatable { case idle, checking, upToDate, available, installing, failed(String) }
    struct Release: Equatable {
        var version: String
        var zip: URL
        var page: URL
    }

    @Published var status = Status.idle
    @Published var latest: Release? // set only when it's newer than this app
    @Published var auto = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(auto, forKey: "autoUpdate"); schedule() }
    }
    private var timer: Timer?

    // This app's version, e.g. "0.2.0". nil when run with swift run: there's no .app to replace.
    static var current: String? {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    // Compares dotted versions number by number: "0.10.0" is newer than "0.9.1".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // GitHub's latest-release JSON: the tag as the version, and the app zip attached to it.
    static func parse(_ data: Data) -> Release? {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Body: Decodable { let tag_name: String; let html_url: URL; let assets: [Asset] }
        guard let r = try? JSONDecoder().decode(Body.self, from: data),
              let zip = r.assets.first(where: { $0.name.hasPrefix("Normalcy-") && $0.name.hasSuffix(".zip") }),
              zip.browser_download_url.scheme == "https", zip.browser_download_url.host == "github.com" else { return nil }
        let v = r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name
        return Release(version: v, zip: zip.browser_download_url, page: r.html_url)
    }

    // At launch, then once a day while automatic checks are on.
    func start() {
        schedule()
        if auto { check() }
    }

    private func schedule() {
        timer?.invalidate()
        timer = auto ? Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.check() } : nil
    }

    func check() {
        guard let current = Self.current, status != .checking, status != .installing else { return }
        status = .checking
        var req = URLRequest(url: Self.latestURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let release = data.flatMap(Self.parse)
            DispatchQueue.main.async {
                guard let release else { self.status = .failed("Couldn't check GitHub for updates."); return }
                self.latest = Self.isNewer(release.version, than: current) ? release : nil
                self.status = self.latest == nil ? .upToDate : .available
            }
        }.resume()
    }

    func install() {
        guard let release = latest, Self.current != nil, status != .installing else { return }
        status = .installing
        URLSession.shared.downloadTask(with: release.zip) { file, _, _ in
            // The downloaded file is deleted once this returns, so unzip it here.
            let result = Result { try Self.unpack(file, release) }
            DispatchQueue.main.async {
                switch result {
                case .success(let app): self.replaceAndRelaunch(with: app)
                case .failure(let e): self.status = .failed(e.localizedDescription)
                }
            }
        }.resume()
    }

    // Unzips into a fresh temporary folder and returns the new app, once it's checked to be
    // Normalcy at the version the release says.
    static func unpack(_ file: URL?, _ release: Release) throws -> URL {
        guard let file else { throw Failure("The download failed.") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NormalcyUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", file.path, dir.path])
        let app = dir.appendingPathComponent("Normalcy.app")
        guard let b = Bundle(url: app), b.bundleIdentifier == Bundle.main.bundleIdentifier,
              b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == release.version else {
            throw Failure("The download isn't Normalcy \(release.version).")
        }
        return app
    }

    // The running app's files can be replaced; it keeps running from memory until it quits.
    private func replaceAndRelaunch(with app: URL) {
        let here = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(here, withItemAt: app)
        } catch {
            status = .failed("Couldn't replace \(here.path): \(error.localizedDescription)")
            return
        }
        // A shell outlives this app: it waits for it to quit, then opens the new one.
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$0\""
        _ = try? Process.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script, here.path])
        NSApp.terminate(nil)
    }

    private static func run(_ path: String, _ args: [String]) throws {
        let p = try Process.run(URL(fileURLWithPath: path), arguments: args)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Failure("Couldn't unzip the update.") }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
