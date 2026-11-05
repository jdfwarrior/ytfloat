import AppKit
import WebKit
import OSLog
#if SWIFT_PACKAGE
import YTFloatCore
#endif

final class PlayerController: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onOpen: (() -> Void)?
    var onTitle: ((String) -> Void)?
    var onExternal: (() -> Void)?
    private(set) var currentVideo: VideoRequest?
    private(set) var pageURL: URL?
    private(set) var state = "waiting"
    private(set) var embedReferer = "not observed"
    private var pageReady = false
    private let preferences: Preferences
    private let logger = Logger(subsystem: "app.ytfloat.YTFloat", category: "player")

    init(preferences: Preferences) {
        self.preferences = preferences
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(self, name: "player")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = .black
        webView.setAccessibilityLabel("YouTube player")
        #if DEBUG
        webView.isInspectable = true
        #endif
    }

    func start(at url: URL) {
        pageURL = url
        pageReady = false
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // The enclosing document remains HTTP. WebKit propagates its real origin to the iframe.
        request.setValue("https://app.ytfloat.YTFloat".lowercased(), forHTTPHeaderField: "Referer")
        webView.load(request)
    }

    func open(_ video: VideoRequest) {
        currentVideo = video
        state = "loading"
        if pageReady { sendVideo(video) }
    }

    private var playerPreferences: [String: Any] {
        ["autoplay": preferences.autoplay, "showControls": preferences.showControls]
    }

    private func sendVideo(_ video: VideoRequest) {
        run("window.YTFloat.open(video, preferences)", arguments: [
            "video": ["id": video.id, "start": video.start], "preferences": playerPreferences])
    }

    func applyPreferences() {
        guard pageReady else { return }
        run("window.YTFloat.configure(preferences)", arguments: ["preferences": playerPreferences])
    }

    func togglePlayback() { run("window.YTFloat.toggle()") }
    func seek(_ delta: Int) { run("window.YTFloat.seek(delta)", arguments: ["delta": delta]) }
    func pause() { run("window.YTFloat.pause()") }

    private func run(_ script: String, arguments: [String: Any] = [:]) {
        guard pageReady else { return }
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result {
                let detail = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                self?.logger.error("Player command failed: \(detail, privacy: .public)")
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url == pageURL,
              let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
        switch event {
        case "pageReady":
            pageReady = true
            state = "idle"
            if let currentVideo { sendVideo(currentVideo) }
        case "ready": state = "ready"
        case "state":
            let values = [-1: "unstarted", 0: "ended", 1: "playing", 2: "paused", 3: "buffering", 5: "cued"]
            state = values[body["state"] as? Int ?? -1] ?? "unknown"
            if body["videoID"] as? String == currentVideo?.id, let title = body["title"] as? String, !title.isEmpty {
                onTitle?(String(title.prefix(200)))
            }
        case "error":
            state = "error \(body["code"] as? Int ?? 0)"
            logger.error("YouTube playback \(self.state, privacy: .public)")
        case "networkError": state = "network error"
        case "autoplayBlocked": state = "autoplay blocked"
        case "open": onOpen?()
        case "external": onExternal?()
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.host == "www.youtube.com", url.path.hasPrefix("/embed/") {
            embedReferer = action.request.value(forHTTPHeaderField: "Referer") ?? "missing"
            logger.debug("YouTube iframe Referer: \(self.embedReferer, privacy: .public)")
        }
        if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else if action.targetFrame?.isMainFrame == true {
            decisionHandler(url == pageURL ? .allow : .cancel)
        } else {
            decisionHandler(["https", "http", "about"].contains(url.scheme ?? "") ? .allow : .cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.navigationType == .linkActivated, let url = action.request.url, url.scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        state = "WebKit restarted"
        if let pageURL { start(at: pageURL) }
    }

    func stop() {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "player")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}
