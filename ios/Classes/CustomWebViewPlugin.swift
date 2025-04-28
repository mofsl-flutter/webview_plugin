import Flutter
import UIKit
import WebKit

public class CustomWebViewPlugin: NSObject, FlutterPlugin, WKScriptMessageHandler, WebViewControllerDelegate {
    private var webView: WKWebView?
    private var channel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "custom_webview_flutter", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "custom_webview_plugin_events", binaryMessenger: registrar.messenger())
        let instance = CustomWebViewPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)

        // Initialize the view factory
        let factory = CustomWebViewFactory(messenger: registrar.messenger(), delegate: instance)
        registrar.register(factory, withId: "custom_webview_flutter")
    }
    
    private var eventSink: FlutterEventSink?
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadUrl":
            if let args = call.arguments as? [String: Any],
               let urlString = args["initialUrl"] as? String {
                let javaScriptChannelName = args["javaScriptChannelName"] as? String
                let isChart = args["isChart"] as? Bool ?? true
                let zoomEnabled = args["zoomEnabled"] as? Bool ?? true
                print("Received isChart: \(isChart), zoomEnabled: \(zoomEnabled)")
                WebViewManager.shared.loadURL(urlString, isChart, withJavaScriptChannel: javaScriptChannelName, zoomEnabled: zoomEnabled, plugin: self)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "URL is required", details: nil))
            }
        case "loadHtmlData":
    if let args = call.arguments as? [String: Any],
       let htmlString = args["htmlString"] as? String {
        let baseURLString = args["baseURL"] as? String
        let baseURL = baseURLString != nil ? URL(string: baseURLString!) : nil
        let javaScriptChannelName = args["javaScriptChannelName"] as? String // New parameter
        WebViewManager.shared.loadHtmlData(
            htmlString: htmlString,
            baseURL: baseURL,
            javaScriptChannelName: javaScriptChannelName
        )
        result(nil)
    } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "HTML string is required", details: nil))
    }
        case "runJavaScript":
            if let script = (call.arguments as? [String: Any])?["script"] as? String {
                WebViewManager.shared.evaluateJavaScript(script, completionHandler: { (response, error) in
                    if let error = error {
                        result(FlutterError(code: "JAVASCRIPT_ERROR", message: error.localizedDescription, details: nil))
                    } else {
                        result(response)
                    }
                })
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "JavaScript code is required", details: nil))
            }
        case "reloadUrl":
            WebViewManager.shared.webView?.reload()
            result(nil)
        case "resetCache":
            WebViewManager.shared.resetWebViewCache()
            result(nil)
        case "addJavascriptChannel":
            if let args = call.arguments as? [String: Any], let channelName = args["channelName"] as? String {
                WebViewManager.shared.addJavascriptChannel(name: channelName)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Channel name is required", details: nil))
            }
        case "getCurrentUrl":
            result(WebViewManager.shared.webView?.url?.absoluteString)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    @objc public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("Received message: \(message.name) with body: \(message.body)")
        if let messageBody = message.body as? String {
            print("Received message from JavaScript: \(messageBody)")
            eventSink?(messageBody)
        }
    }
    
    func sendMessageBody(body: String) {
        eventSink?(body)
    }
    
    func pageDidLoad(url: String) {
        eventSink?(["event": "pageFinished", "url": url])
    }

    func onPageLoadError() {
        eventSink?(["event": "error", "message": "error"])
    }

    func onJavascriptChannelMessageReceived(channelName: String, message: String) {
        eventSink?(["event": "javascriptChannelMessageReceived",  "channelName" : channelName, "message": message])
    }

    func onNavigationRequest(url: String) {

    }

    func onPageFinished(url: String) {
        eventSink?(["event": "pageFinished", "url": url])
    }

    func onReceivedError(message: String) {

    }

    func onJsAlert(url: String, message: String) {

    }

}



extension CustomWebViewPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        WebViewManager.shared.delegate = self
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        WebViewManager.shared.delegate = nil
        return nil
    }

}

protocol WebViewControllerDelegate: AnyObject {
    func pageDidLoad(url: String)
    func sendMessageBody(body: String)
    func onPageLoadError()
    func onJavascriptChannelMessageReceived(channelName: String, message: String)
    func onNavigationRequest(url: String)
    func onPageFinished(url: String)
    func onReceivedError(message: String)
    func onJsAlert(url: String, message: String)
}

class WebViewManager: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = WebViewManager()
    var webView: WKWebView!
    weak var delegate: WebViewControllerDelegate?
    private var configuredJavaScriptChannels: Set<String> = []
    private var isChart = true

    override init() {
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        addJavascriptChannel(name: "ChartAppDelegate")
    }

    func loadURL(_ urlString: String, _ isFromChart: Bool, withJavaScriptChannel javaScriptChannelName: String?, zoomEnabled: Bool, plugin: WKScriptMessageHandler) {
        isChart = isFromChart
        configureZoom(enabled: zoomEnabled)
        print("Received loadURL isChart: \(isChart), zoomEnabled: \(zoomEnabled)")
        guard let url = URL(string: urlString), isValidURL(url) else {
            delegate?.onPageLoadError()
            print("Invalid URL provided, loading default URL.")
            return
        }

        if javaScriptChannelName != nil {
            addJavascriptChannel(name: javaScriptChannelName ?? "ChartAppDelegate")
        }

        print("Loading URL: \(urlString)")
        webView.load(URLRequest(url: url))
        
    }

    func loadHtmlData(htmlString: String, baseURL: URL?, javaScriptChannelName: String?) {
    print("Loading HTML data...")

    // Add JavaScript channel if provided
    if let channelName = javaScriptChannelName, !channelName.isEmpty {
        addJavascriptChannel(name: channelName)
    }

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

    func isValidURL(_ url: URL) -> Bool {
        return UIApplication.shared.canOpenURL(url)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("Started Loading: \(String(describing: webView.url))")
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
        completionHandler()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("Message received: \(message.name)")
        if configuredJavaScriptChannels.contains(message.name) {
            if let body = message.body as? String {
                // Call the method if the channel is in the configured list
                delegate?.onJavascriptChannelMessageReceived(channelName: message.name, message: body)
            }
        }   
        if let body = message.body as? String {
            delegate?.sendMessageBody(body: body)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            // Check if the URL is a file link
            if url.absoluteString.contains(".pdf") || url.absoluteString.contains("SH=") || url.isFileURL {
                // Open the URL in an external browser
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel) // Cancel the navigation in WebView
                return
            }
        }
        decisionHandler(.allow) // Allow navigation for other URLs
    }


    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            print("NEW WINDOW CREATED with URL: \(url)")

            // Create a new WKWebView with the provided configuration
            let newWebView = WKWebView(frame: .zero, configuration: configuration)
            newWebView.uiDelegate = self
            newWebView.navigationDelegate = self

            self.webView.load(URLRequest(url: url))

            return newWebView
        }
        
        return webView
    }
}
