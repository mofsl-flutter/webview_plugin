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
                print("Received isChart: \(isChart)")
                WebViewManager.shared.loadURL(urlString, isChart, withJavaScriptChannel: javaScriptChannelName, plugin: self)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "URL is required", details: nil))
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
        case "setUserInteractionEnabled":
            if let args = call.arguments as? [String: Any],
               let enabled = args["enabled"] as? Bool {
                WebViewManager.shared.setUserInteractionEnabled(enabled)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "enabled parameter is required", details: nil))
            }
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

class WebViewManager: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = WebViewManager()
    var webView: WKWebView!
    weak var delegate: WebViewControllerDelegate?
    private var configuredJavaScriptChannels: Set<String> = []
    private let defaultURLString = "https://tradingview.com/"
    private var isChart = true

    override init() {
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        addJavascriptChannel(name: "ChartAppDelegate")
    }

    func loadURL(_ urlString: String, _ isFromChart: Bool, withJavaScriptChannel javaScriptChannelName: String?, plugin: WKScriptMessageHandler) {
        isChart = isFromChart
        print("Received loadURL isChart: \(isChart)")
        guard let url = URL(string: urlString), isValidURL(url) else {
            delegate?.onPageLoadError()
            print("Invalid URL provided, loading default URL.")
            loadDefaultURL()
            return
        }

        if javaScriptChannelName != nil {
            addJavascriptChannel(name: javaScriptChannelName ?? "ChartAppDelegate")
        }

        print("Loading URL: \(urlString)")
        webView.load(URLRequest(url: url))
        
    }

    func getWebView(frame: CGRect) -> WKWebView {
        webView?.frame = frame
        return webView!
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
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(wrapperScript)
        webView.configuration.userContentController.add(self, name: name)
        configuredJavaScriptChannels.insert(name)
        return true
    }

    func setUserInteractionEnabled(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.webView.isUserInteractionEnabled = enabled
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadingError()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadingError()
    }

    private func handleLoadingError() {
        delegate?.onPageLoadError()
        print("Failed to load URL, navigating to default URL.")
        loadDefaultURL()
    }

    private func loadDefaultURL() {
        if let defaultURL = URL(string: defaultURLString) {
            webView.load(URLRequest(url: defaultURL))
        }
    }

    private func isValidURL(_ url: URL) -> Bool {
        return UIApplication.shared.canOpenURL(url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("Received pageDidLoad isChart: \(isChart)")
        if isChart {
            delegate?.pageDidLoad(url: webView.url?.absoluteString ?? "")
        } else {
            delegate?.onPageFinished(url: webView.url?.absoluteString ?? "")
        }
    }

    @objc public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("Received message: \(message.name) with body: \(message.body)")
        if let messageBody = message.body as? String {
            print("Received message from JavaScript: \(messageBody)")
            let channelName = message.name
            delegate?.onJavascriptChannelMessageReceived(channelName: channelName, message: messageBody)
        }
    }
}
