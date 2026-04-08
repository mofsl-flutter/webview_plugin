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
    var webView: WKWebView!
    weak var delegate: WebViewControllerDelegate?
    private var configuredJavaScriptChannels: Set<String> = []
    private var isChart = true
    private var progressObserver: NSKeyValueObservation?
    private var fileUploadCompletionHandler: (([URL]?) -> Void)?

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
        print("Started Loading: \(String(describing: webView.url))")
        if let url = webView.url?.absoluteString {
            delegate?.onPageStarted(url: url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("Finished Loading: \(String(describing: webView.url))")
        if let url = webView.url?.absoluteString {
            delegate?.onPageFinished(url: url)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("Error loading page: \(error.localizedDescription)")
        delegate?.onReceivedError(message: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didReceive serverRedirectForProvisionalNavigation: WKNavigation!) {
        print("Redirect detected.")
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        print("JavaScript Alert: \(message)")
        let url = webView.url?.absoluteString ?? ""
        delegate?.onJsAlert(url: url, message: message)
        completionHandler()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("Message received: \(message.name)")
        
        var messageString = ""
        if let body = message.body as? String {
            messageString = body
        } else if let bodyData = try? JSONSerialization.data(withJSONObject: message.body, options: []),
                  let bodyString = String(data: bodyData, encoding: .utf8) {
            messageString = bodyString
        }

        if configuredJavaScriptChannels.contains(message.name) {
            delegate?.onJavascriptChannelMessageReceived(channelName: message.name, message: messageString)
        }
        
        delegate?.sendMessageBody(body: messageString)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            
            // Allow blocking from Dart
            delegate?.onNavigationRequest(url: url.absoluteString) { allow in
                if !allow {
                    decisionHandler(.cancel)
                    return
                }
                
                // Check if the URL is a file link or special scheme
                if url.absoluteString.contains(".pdf") || url.absoluteString.contains("SH=") || url.isFileURL {
                    // Open the URL in an external browser
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    decisionHandler(.cancel) // Cancel the navigation in WebView
                    return
                } else if (url.absoluteString.contains("tel:")) || (url.absoluteString.contains("mailto:")) {
                    if UIApplication.shared.canOpenURL(url) {
                      UIApplication.shared.open(url, options: [:], completionHandler: nil)
                      decisionHandler(.cancel)
                      return
                    }
                }
                
                decisionHandler(.allow) // Allow navigation for other URLs
            }
            return
        }
        decisionHandler(.allow)
    }


    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.uiDelegate = self
        newWebView.navigationDelegate = self

        newWebView.load(URLRequest(url: url))

        return newWebView
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Trust the certificate — supports self-signed / internal CA certificates.
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
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
