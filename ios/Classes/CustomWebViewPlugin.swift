import Flutter
import UIKit
import WebKit
import UniformTypeIdentifiers

public class CustomWebViewPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "custom_webview_flutter", binaryMessenger: registrar.messenger())
        let instance = CustomWebViewPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Initialize the view factory
        let factory = CustomWebViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "custom_webview_flutter")
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "resetCache":
            let websiteDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            let date = Date(timeIntervalSince1970: 0)
            WKWebsiteDataStore.default().removeData(ofTypes: websiteDataTypes, modifiedSince: date, completionHandler: {
                result(nil)
            })
        case "clearCookies":
            let cookieStore = WKWebsiteDataStore.default().httpCookieStore
            cookieStore.getAllCookies { cookies in
                for cookie in cookies {
                    cookieStore.delete(cookie)
                }
                result(nil)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

public protocol WebViewControllerDelegate: AnyObject {
    func pageDidLoad(url: String)
    func sendMessageBody(body: String)
    func onPageLoadError()
    func onJavascriptChannelMessageReceived(channelName: String, message: String)
    func onNavigationRequest(url: String, completion: @escaping (Bool) -> Void)
    func onPageStarted(url: String)
    func onPageFinished(url: String)
    func onProgress(progress: Int)
    func onReceivedError(message: String)
    func onJsAlert(url: String, message: String)
}

class WebViewManager: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    // Dedicated bridge for blob downloads — kept out of configuredJavaScriptChannels
    // so its payloads are never forwarded to Dart.
    private static let blobDownloaderChannelName = "CustomBlobDownloader"
    // Standard download bridge that web apps probe for via
    // window.webkit.messageHandlers.downloadHandler (e.g. MF Central CAS QR flow).
    private static let downloadHandlerChannelName = "downloadHandler"

    var webView: WKWebView!
    weak var delegate: WebViewControllerDelegate?
    private var configuredJavaScriptChannels: Set<String> = []
    private var isChart = true
    private var progressObserver: NSKeyValueObservation?
    private var fileUploadCompletionHandler: (([URL]?) -> Void)?
    // Retains the window.open()/target="_blank" popup webview and the modal that
    // presents it. Without this, the popup WKWebView is never shown and — since
    // nothing else keeps it alive — gets torn down almost immediately, which is
    // what left window.open() callers on the JS side holding a dead reference.
    private var popupWebView: WKWebView?
    private weak var popupNavigationController: UINavigationController?

    override init() {
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        _ = addJavascriptChannel(name: "ChartAppDelegate")
        webView.configuration.userContentController.add(self, name: Self.blobDownloaderChannelName)
        webView.configuration.userContentController.add(self, name: Self.downloadHandlerChannelName)

        setupProgressObserver()
    }

    private func setupProgressObserver() {
        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            let progress = Int(webView.estimatedProgress * 100)
            self?.delegate?.onProgress(progress: progress)
        }
    }

    deinit {
        progressObserver?.invalidate()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.blobDownloaderChannelName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.downloadHandlerChannelName)
    }

    func loadURL(_ urlString: String, _ isFromChart: Bool, withJavaScriptChannels channelNames: [String], zoomEnabled: Bool, headers: [String: String]? = nil) {
        isChart = isFromChart
        configureZoom(enabled: zoomEnabled)
        print("Received loadURL isChart: \(isChart), zoomEnabled: \(zoomEnabled)")
        guard let url = URL(string: urlString), isValidURL(url) else {
            delegate?.onPageLoadError()
            print("Invalid URL provided, loading default URL.")
            return
        }

        channelNames.forEach { _ = addJavascriptChannel(name: $0) }

        print("Loading URL: \(urlString)")
        var request = URLRequest(url: url)
        if let headers = headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }
        webView.load(request)
        
    }

    func loadHtmlData(htmlString: String, baseURL: URL?, javaScriptChannelNames: [String]) {
        print("Loading HTML data...")

        javaScriptChannelNames.forEach { _ = addJavascriptChannel(name: $0) }

        // Load the HTML string
        webView.loadHTMLString(htmlString, baseURL: baseURL)
    }

    func getWebView(frame: CGRect) -> WKWebView {
        webView?.frame = frame
        return webView!
    }

    private func configureZoom(enabled: Bool) {
        webView?.scrollView.isScrollEnabled = true
        webView?.scrollView.pinchGestureRecognizer?.isEnabled = enabled

        if !enabled {
            let zoomDisableScript = getZoomDisableScript()
            webView?.configuration.userContentController.addUserScript(zoomDisableScript)
        }
    }

    private func getZoomDisableScript() -> WKUserScript {
        let source: String = "var meta = document.createElement('meta');" +
            "meta.name = 'viewport';" +
            "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';" +
            "var head = document.getElementsByTagName('head')[0];" + "head.appendChild(meta);"
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    func evaluateJavaScript(_ script: String, completionHandler: @escaping (Any?, Error?) -> Void) {
        webView.evaluateJavaScript(script, completionHandler: completionHandler)
    }

    func resetWebViewCache() {
        let websiteDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let date = Date(timeIntervalSince1970: 0)
        WKWebsiteDataStore.default().removeData(ofTypes: websiteDataTypes, modifiedSince: date, completionHandler: {})
    }

    func addJavascriptChannel(name: String) -> Bool {
        if configuredJavaScriptChannels.contains(name) {
            return false
        }
        let wrapperSource = "window.\(name) = webkit.messageHandlers.\(name);"
        let wrapperScript = WKUserScript(
            source: wrapperSource,
            injectionTime: WKUserScriptInjectionTime.atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(wrapperScript)
        webView.configuration.userContentController.add(self, name: name)
        configuredJavaScriptChannels.insert(name)
        return true
    }

    func removeJavascriptChannel(name: String) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        configuredJavaScriptChannels.remove(name)
    }

     func setUserInteractionEnabled(_ enabled: Bool) {
            DispatchQueue.main.async {
                self.webView.isUserInteractionEnabled = enabled
            }
     }

    func isValidURL(_ url: URL) -> Bool {
        return UIApplication.shared.canOpenURL(url)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let source = webView === popupWebView ? "POPUP" : (webView === self.webView ? "MAIN" : "OTHER")
        NSLog("%@", "[\(source)] Started Loading: \(String(describing: webView.url))")
        if let url = webView.url?.absoluteString {
            delegate?.onPageStarted(url: url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let source = webView === popupWebView ? "POPUP" : (webView === self.webView ? "MAIN" : "OTHER")
        NSLog("%@", "[\(source)] Finished Loading: \(String(describing: webView.url))")
        if let url = webView.url?.absoluteString {
            delegate?.onPageFinished(url: url)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let source = webView === popupWebView ? "POPUP" : (webView === self.webView ? "MAIN" : "OTHER")
        NSLog("%@", "[\(source)] Error loading page (provisional): \(error.localizedDescription)")
        delegate?.onReceivedError(message: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let source = webView === popupWebView ? "POPUP" : (webView === self.webView ? "MAIN" : "OTHER")
        NSLog("%@", "[\(source)] Error loading page (committed): \(error.localizedDescription)")
        delegate?.onReceivedError(message: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didReceive serverRedirectForProvisionalNavigation: WKNavigation!) {
        let source = webView === popupWebView ? "POPUP" : (webView === self.webView ? "MAIN" : "OTHER")
        NSLog("%@", "[\(source)] Redirect detected.")
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        print("JavaScript Alert: \(message)")
        let url = webView.url?.absoluteString ?? ""
        delegate?.onJsAlert(url: url, message: message)
        completionHandler()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("Message received: \(message.name)")

        if message.name == Self.blobDownloaderChannelName {
            handleBlobDownloadMessage(message.body)
            return
        }

        if message.name == Self.downloadHandlerChannelName {
            handleDownloadHandlerMessage(message.body)
            return
        }

        var messageString = ""
        if let body = message.body as? String {
            messageString = body
        } else if let bodyData = try? JSONSerialization.data(withJSONObject: message.body, options: []),
                  let bodyString = String(data: bodyData, encoding: .utf8) {
            messageString = bodyString
        }

        NSLog("%@", "[JSChannel] \(message.name): \(messageString.prefix(500))")

        if configuredJavaScriptChannels.contains(message.name) {
            delegate?.onJavascriptChannelMessageReceived(channelName: message.name, message: messageString)
        }

        delegate?.sendMessageBody(body: messageString)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let source = webView === popupWebView ? "POPUP" : (webView === self.webView ? "MAIN" : "OTHER")
        if let url = navigationAction.request.url {
            // blob:/data: URLs are downloads, not navigations — WKWebView cannot load
            // them as pages (navigation would fail and surface "download failed").
            let scheme = url.scheme?.lowercased()
            let targetFrameDesc: String
            if let targetFrame = navigationAction.targetFrame {
                targetFrameDesc = targetFrame.isMainFrame ? "mainFrame" : "subFrame"
            } else {
                targetFrameDesc = "nil(new-window-request)"
            }
            NSLog("%@", "[CustomWebView][\(source)] navigation request (\(scheme ?? "nil")) type=\(navigationAction.navigationType.rawValue) targetFrame=\(targetFrameDesc): \(url.absoluteString.prefix(200))")
            if scheme == "blob" {
                NSLog("%@", "[BlobDownload] intercepted blob URL, injecting fetch script")
                decisionHandler(.cancel)
                downloadBlobUrl(url.absoluteString)
                return
            }
            if scheme == "data" {
                NSLog("%@", "[BlobDownload] intercepted data URL, decoding natively")
                decisionHandler(.cancel)
                saveDataUrl(url)
                return
            }

            // Allow blocking from Dart
            delegate?.onNavigationRequest(url: url.absoluteString) { allow in
                if !allow {
                    NSLog("%@", "[CustomWebView][\(source)] decision: CANCEL (onNavigationRequest denied)")
                    decisionHandler(.cancel)
                    return
                }

                // Check if the URL is a file link or special scheme
                if url.absoluteString.contains(".pdf") || url.absoluteString.contains("SH=") || url.isFileURL {
                    // Open the URL in an external browser
                    NSLog("%@", "[CustomWebView][\(source)] decision: CANCEL (pdf/SH/file -> external)")
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    decisionHandler(.cancel) // Cancel the navigation in WebView
                    return
                }
                // Any non-web scheme (whatsapp://, tel:, mailto:, sms://, upi://, etc.)
                // must be handed off to the system — WKWebView cannot load them and
                // attempting to do so causes a silent navigation failure.
                let webSchemes: Set<String> = ["http", "https", "file", "data", "blob", "javascript", "about"]
                let requestedScheme = url.scheme?.lowercased() ?? ""
                if !requestedScheme.isEmpty && !webSchemes.contains(requestedScheme) {
                    NSLog("%@", "[CustomWebView][\(source)] decision: CANCEL (non-web scheme -> external)")
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    decisionHandler(.cancel)
                    return
                }

                NSLog("%@", "[CustomWebView][\(source)] decision: ALLOW")
                decisionHandler(.allow) // Allow navigation for other URLs
            }
            return
        }
        decisionHandler(.allow)
    }


    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        NSLog("%@", "[Popup] createWebViewWith invoked, url=\(navigationAction.request.url?.absoluteString ?? "nil")")
        guard let url = navigationAction.request.url else { return nil }

        // window.open on a blob/data URL is a download, not a popup — a popup
        // webview cannot load a blob URL (silent no-op), so download instead.
        let scheme = url.scheme?.lowercased()
        if scheme == "blob" {
            NSLog("%@", "[BlobDownload] intercepted blob URL from window.open")
            downloadBlobUrl(url.absoluteString)
            return nil
        }
        if scheme == "data" {
            NSLog("%@", "[BlobDownload] intercepted data URL from window.open")
            saveDataUrl(url)
            return nil
        }

        // Non-web schemes triggered via window.open() (e.g. whatsapp://) cannot be
        // loaded by a WKWebView — open them externally instead of creating a popup.
        // window.open('', '_blank') (no URL yet — callers commonly grab a handle
        // synchronously, then navigate it later, e.g. via windowInstance.location=)
        // has an empty/nil scheme; it must fall through to popup creation below,
        // not be treated as a foreign scheme (UIApplication.shared.open on an empty
        // URL fails outright, which previously made window.open() return null).
        let webSchemes: Set<String> = ["http", "https", "file", "data", "blob", "javascript", "about"]
        let requestedScheme = url.scheme?.lowercased() ?? ""
        if !requestedScheme.isEmpty && !webSchemes.contains(requestedScheme) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return nil
        }

        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.uiDelegate = self
        newWebView.navigationDelegate = self

        // window.open('', '_blank') gives JS a handle with nothing to show yet —
        // callers (e.g. this SDK) immediately follow up with
        // windowInstance.location = realURL. If we kick off our own load of this
        // empty URL first, that load is still in-flight/settling on the same
        // WKWebView when the real navigation's decidePolicyFor fires a few ms
        // later, and WebKit silently drops the real navigation (allowed, but no
        // didStartProvisionalNavigation ever follows — confirmed via timestamped
        // logging). Skipping the pointless empty load removes that race.
        if !url.absoluteString.isEmpty {
            newWebView.load(URLRequest(url: url))
        }
        presentPopupWebView(newWebView)

        return newWebView
    }

    // Presents the popup webview modally so it is actually visible to the user
    // and, just as importantly, retained (self.popupWebView) for as long as it's
    // on screen — mirroring the Android implementation, which shows the popup
    // WebView inside an AlertDialog that the dialog itself keeps alive.
    private func presentPopupWebView(_ popup: WKWebView) {
        guard let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            NSLog("%@", "[Popup] no key window / root view controller found to present popup")
            return
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }

        let contentVC = UIViewController()
        contentVC.view = popup
        contentVC.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Close", style: .done, target: self, action: #selector(closePopupWebView)
        )

        let navController = UINavigationController(rootViewController: contentVC)
        navController.modalPresentationStyle = .pageSheet
        navController.presentationController?.delegate = self

        popupWebView = popup
        popupNavigationController = navController

        topVC.present(navController, animated: true)
    }

    @objc private func closePopupWebView() {
        popupNavigationController?.dismiss(animated: true)
        popupWebView = nil
        popupNavigationController = nil
    }

    // Called when the popup's JS runs window.close().
    func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        closePopupWebView()
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Let the system perform standard certificate-chain validation. We must
        // never blindly trust the server certificate — building a URLCredential
        // from an unevaluated serverTrust bypasses TLS validation and exposes the
        // WebView to man-in-the-middle attacks.
        completionHandler(.performDefaultHandling, nil)
    }

    @available(iOS 18.4, *)
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        fileUploadCompletionHandler = completionHandler

        // Find the topmost view controller to present from
        guard let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            completionHandler(nil)
            return
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }

        if #available(iOS 14.0, *) {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            picker.allowsMultipleSelection = parameters.allowsMultipleSelection
            picker.delegate = self
            topVC.present(picker, animated: true)
        } else {
            // Fallback for older iOS if needed, but for now we target modern
            completionHandler(nil)
        }
    }

    // MARK: - Blob / data URL downloads

    private func downloadBlobUrl(_ blobUrl: String) {
        // Embed the URL as a JSON string literal so a hostile blob URL cannot
        // break out of the injected script.
        guard let urlData = try? JSONSerialization.data(withJSONObject: [blobUrl]),
              let jsonArray = String(data: urlData, encoding: .utf8) else {
            delegate?.onReceivedError(message: "Blob download failed: could not encode URL")
            return
        }
        let script = """
        (function() {
            var blobUrl = \(jsonArray)[0];
            function report(payload) {
                window.webkit.messageHandlers.\(Self.blobDownloaderChannelName).postMessage(payload);
            }
            fetch(blobUrl)
                .then(function(response) {
                    if (!response.ok) { throw new Error('HTTP ' + response.status); }
                    return response.blob();
                })
                .then(function(blob) {
                    var reader = new FileReader();
                    reader.onloadend = function() {
                        var base64 = (reader.result || '').split(',')[1] || '';
                        report({ base64: base64, mimeType: blob.type || '' });
                    };
                    reader.onerror = function() {
                        report({ error: 'Blob download failed: FileReader could not read blob' });
                    };
                    reader.readAsDataURL(blob);
                })
                .catch(function(e) { report({ error: 'Blob fetch failed: ' + e.message }); });
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error = error {
                NSLog("%@", "[BlobDownload] fetch script injection FAILED: \(error)")
                self?.delegate?.onReceivedError(message: "Blob download failed: \(error.localizedDescription)")
            } else {
                NSLog("%@", "[BlobDownload] fetch script injected, waiting for blob data")
            }
        }
    }

    private func handleBlobDownloadMessage(_ body: Any) {
        guard let dict = body as? [String: Any] else {
            NSLog("%@", "[BlobDownload] unexpected message body: \(type(of: body))")
            delegate?.onReceivedError(message: "Blob download failed: unexpected message format")
            return
        }
        if let jsError = dict["error"] as? String {
            NSLog("%@", "[BlobDownload] JS reported error: \(jsError)")
            delegate?.onReceivedError(message: jsError)
            return
        }
        guard let base64 = dict["base64"] as? String, !base64.isEmpty else {
            NSLog("%@", "[BlobDownload] empty base64 payload")
            delegate?.onReceivedError(message: "Blob download failed: empty payload")
            return
        }
        NSLog("%@", "[BlobDownload] received blob data: \(base64.count) base64 chars, mime=\(dict["mimeType"] ?? "?")")
        let mimeType = (dict["mimeType"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "application/octet-stream"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
                DispatchQueue.main.async {
                    self?.delegate?.onReceivedError(message: "Blob download failed: invalid base64 data")
                }
                return
            }
            self?.saveAndPresentDownload(data: data, mimeType: mimeType)
        }
    }

    // Handles download requests posted by web pages that detect the native
    // bridge (window.webkit.messageHandlers.downloadHandler). Expected shape:
    // { type: "mfc-cas-download", data: { base64: "...", filename: "x.png" } }
    // but a flat { base64, filename } payload is accepted too.
    private func handleDownloadHandlerMessage(_ body: Any) {
        guard let dict = body as? [String: Any] else {
            NSLog("%@", "[BlobDownload] downloadHandler: unexpected payload type \(type(of: body))")
            delegate?.onReceivedError(message: "Download failed: unexpected downloadHandler payload")
            return
        }
        let payload = dict["data"] as? [String: Any] ?? dict
        guard let base64 = payload["base64"] as? String, !base64.isEmpty else {
            NSLog("%@", "[BlobDownload] downloadHandler: no base64 in payload, keys=\(Array(dict.keys))")
            delegate?.onReceivedError(message: "Download failed: downloadHandler payload has no base64 data")
            return
        }
        let fileName = (payload["filename"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        NSLog("%@", "[BlobDownload] downloadHandler: received \(base64.count) base64 chars, filename=\(fileName ?? "nil")")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Accept both a plain base64 string and a full data URI.
            var raw = base64
            if let commaIndex = raw.firstIndex(of: ","), raw.lowercased().hasPrefix("data:") {
                raw = String(raw[raw.index(after: commaIndex)...])
            }
            guard let bytes = Data(base64Encoded: raw, options: .ignoreUnknownCharacters) else {
                DispatchQueue.main.async {
                    self?.delegate?.onReceivedError(message: "Download failed: invalid base64 in downloadHandler payload")
                }
                return
            }
            self?.saveAndPresentDownload(data: bytes, mimeType: "application/octet-stream", suggestedName: fileName)
        }
    }

    private func saveDataUrl(_ url: URL) {
        let urlString = url.absoluteString
        guard let commaIndex = urlString.firstIndex(of: ",") else {
            delegate?.onReceivedError(message: "Download failed: malformed data URL")
            return
        }
        let header = String(urlString[..<commaIndex])  // data:[<mediatype>][;base64]
        let payload = String(urlString[urlString.index(after: commaIndex)...])
        let mimeType = header.dropFirst("data:".count)
            .split(separator: ";").first.map(String.init)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "application/octet-stream"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data: Data?
            if header.lowercased().contains(";base64") {
                let raw = payload.removingPercentEncoding ?? payload
                data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters)
            } else {
                data = (payload.removingPercentEncoding ?? payload).data(using: .utf8)
            }
            guard let bytes = data else {
                DispatchQueue.main.async {
                    self?.delegate?.onReceivedError(message: "Download failed: could not decode data URL")
                }
                return
            }
            self?.saveAndPresentDownload(data: bytes, mimeType: mimeType)
        }
    }

    private func suggestedFileName(forMimeType mimeType: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        var ext = "bin"
        if #available(iOS 14.0, *),
           let utType = UTType(mimeType: mimeType),
           let preferred = utType.preferredFilenameExtension {
            ext = preferred
        } else {
            let fallback: [String: String] = [
                "application/pdf": "pdf", "image/png": "png", "image/jpeg": "jpg",
                "text/csv": "csv", "text/plain": "txt", "application/zip": "zip",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
            ]
            ext = fallback[mimeType.lowercased()] ?? "bin"
        }
        return "download_\(timestamp).\(ext)"
    }

    private func saveAndPresentDownload(data: Data, mimeType: String, suggestedName: String? = nil) {
        let fileName = suggestedName ?? suggestedFileName(forMimeType: mimeType)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL, options: .atomic)
            NSLog("%@", "[BlobDownload] wrote \(data.count) bytes to \(tempURL.path)")
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.onReceivedError(message: "Download failed: could not write file (\(error.localizedDescription))")
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.presentDownloadedFile(at: tempURL)
        }
    }

    private func presentDownloadedFile(at fileURL: URL) {
        NSLog("%@", "[BlobDownload] presenting save dialog for \(fileURL.lastPathComponent)")
        guard let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            NSLog("%@", "[BlobDownload] no key window / root view controller found")
            delegate?.onReceivedError(message: "Download failed: no view controller to present from")
            return
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }

        if #available(iOS 14.0, *) {
            // asCopy keeps the temp file valid; user cancel is a valid outcome.
            let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
            topVC.present(picker, animated: true)
        } else {
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            // iPad requires a popover anchor.
            activityVC.popoverPresentationController?.sourceView = webView
            activityVC.popoverPresentationController?.sourceRect = CGRect(
                x: webView.bounds.midX, y: webView.bounds.midY, width: 1, height: 1)
            topVC.present(activityVC, animated: true)
        }
    }
}

extension WebViewManager: UIAdaptivePresentationControllerDelegate {
    // User swiped the popup sheet away without tapping "Close" — release our
    // strong reference so the popup webview can be deallocated.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        popupWebView = nil
        popupNavigationController = nil
    }
}

@available(iOS 18.4, *)
extension WebViewManager: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        fileUploadCompletionHandler?(urls)
        fileUploadCompletionHandler = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        fileUploadCompletionHandler?(nil)
        fileUploadCompletionHandler = nil
    }
}
