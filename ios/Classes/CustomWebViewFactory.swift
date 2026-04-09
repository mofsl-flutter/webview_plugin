import Flutter
import UIKit
import WebKit

class CustomWebViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return WebViewMoFlutter(frame: frame, viewIdentifier: viewId, args: args, messenger: messenger)
    }
}

class WebViewMoFlutter: NSObject, FlutterPlatformView, WebViewControllerDelegate {
    private var webViewManager: WebViewManager
    private var methodChannel: FlutterMethodChannel
    private var isChart: Bool = true

    init(frame: CGRect, viewIdentifier viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        self.webViewManager = WebViewManager()
        self.methodChannel = FlutterMethodChannel(name: "custom_webview_flutter_\(viewId)", binaryMessenger: messenger)
        super.init()
        
        self.webViewManager.delegate = self
        self.methodChannel.setMethodCallHandler(self.handle)

        // Process creation arguments
        if let argsDict = args as? [String: Any] {
            self.isChart = argsDict["isChart"] as? Bool ?? true
            let initialUrl = argsDict["initialUrl"] as? String
            let headers = argsDict["headers"] as? [String: String]
            let jsChannels = argsDict["javaScriptChannelNames"] as? [String] ?? []
            let zoomEnabled = argsDict["zoomEnabled"] as? Bool ?? true
            let enableMultipleWindows = argsDict["enableMultipleWindows"] as? Bool ?? true

            // Apply multiple windows setting
            webViewManager.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = enableMultipleWindows
            
            if let initialUrl = initialUrl {
                webViewManager.loadURL(initialUrl, isChart, withJavaScriptChannels: jsChannels, zoomEnabled: zoomEnabled, headers: headers)
            }
        }
        
       if #available(iOS 16.4,*) {
           self.webViewManager.webView.isInspectable = true
       }
    }

    func view() -> UIView {
        return webViewManager.webView
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadUrl":
            if let args = call.arguments as? [String: Any],
               let urlString = args["initialUrl"] as? String {
                let channelNames = args["javaScriptChannelNames"] as? [String] ?? []
                let isChart = args["isChart"] as? Bool ?? true
                let zoomEnabled = args["zoomEnabled"] as? Bool ?? true
                let headers = args["headers"] as? [String: String]
                webViewManager.loadURL(urlString, isChart, withJavaScriptChannels: channelNames, zoomEnabled: zoomEnabled, headers: headers)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "URL is required", details: nil))
            }
        case "loadHtmlData":
            if let args = call.arguments as? [String: Any],
               let htmlString = args["htmlString"] as? String {
                let baseURLString = args["baseURL"] as? String
                let baseURL = baseURLString != nil ? URL(string: baseURLString!) : nil
                let channelNames = args["javaScriptChannelNames"] as? [String] ?? []
                webViewManager.loadHtmlData(htmlString: htmlString, baseURL: baseURL, javaScriptChannelNames: channelNames)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "HTML string is required", details: nil))
            }
        case "runJavaScript":
            if let script = (call.arguments as? [String: Any])?["script"] as? String {
                webViewManager.evaluateJavaScript(script, completionHandler: { (response, error) in
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
            webViewManager.webView?.reload()
            result(nil)
        case "addJavascriptChannel":
            if let args = call.arguments as? [String: Any], let channelName = args["channelName"] as? String {
                _ = webViewManager.addJavascriptChannel(name: channelName)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Channel name is required", details: nil))
            }
        case "removeJavascriptChannel":
            if let args = call.arguments as? [String: Any], let channelName = args["channelName"] as? String {
                webViewManager.removeJavascriptChannel(name: channelName)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Channel name is required", details: nil))
            }
        case "getCurrentUrl":
            result(webViewManager.webView?.url?.absoluteString)
        case "canGoBack":
            result(webViewManager.webView?.canGoBack ?? false)
        case "goBack":
            webViewManager.webView?.goBack()
            result(nil)
        case "setUserInteractionEnabled":
            if let args = call.arguments as? [String: Any],
               let enabled = args["enabled"] as? Bool {
                webViewManager.setUserInteractionEnabled(enabled)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "enabled parameter is required", details: nil))
            }
        case "setCustomUserAgent":
            if let args = call.arguments as? [String: Any] {
                let userAgent = args["userAgent"] as? String
                webViewManager.webView.customUserAgent = userAgent
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Arguments required", details: nil))
            }
        case "enableMultipleWindows":
            if let args = call.arguments as? [String: Any],
               let enabled = args["enabled"] as? Bool {
                webViewManager.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = enabled
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "enabled parameter is required", details: nil))
            }
        case "setBackgroundColor":
            if let args = call.arguments as? [String: Any],
               let colorInt = args["color"] as? Int {
                let alpha = CGFloat((colorInt >> 24) & 0xFF) / 255.0
                let red   = CGFloat((colorInt >> 16) & 0xFF) / 255.0
                let green = CGFloat((colorInt >>  8) & 0xFF) / 255.0
                let blue  = CGFloat( colorInt        & 0xFF) / 255.0
                let color = UIColor(red: red, green: green, blue: blue, alpha: alpha)
                DispatchQueue.main.async {
                    self.webViewManager.webView.isOpaque = (alpha == 1.0)
                    self.webViewManager.webView.backgroundColor = color
                    self.webViewManager.webView.scrollView.backgroundColor = color
                }
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "color is required", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func pageDidLoad(url: String) {
        if isChart {
            methodChannel.invokeMethod("pageLoaded", arguments: nil)
        } else {
            methodChannel.invokeMethod("onPageFinished", arguments: ["url": url])
        }
    }

    func sendMessageBody(body: String) {
        methodChannel.invokeMethod("onMessageReceived", arguments: body)
    }

    func onPageLoadError() {
        methodChannel.invokeMethod("onReceivedError", arguments: ["message": "error"])
    }

    func onJavascriptChannelMessageReceived(channelName: String, message: String) {
        methodChannel.invokeMethod("onJavascriptChannelMessageReceived", arguments: ["channelName": channelName, "message": message])
    }

    func onNavigationRequest(url: String, completion: @escaping (Bool) -> Void) {
        methodChannel.invokeMethod("onNavigationRequest", arguments: ["url": url]) { result in
            if let allow = result as? Bool {
                completion(allow)
            } else {
                completion(true)
            }
        }
    }

    func onPageStarted(url: String) {
        methodChannel.invokeMethod("onPageStarted", arguments: ["url": url])
    }

    func onPageFinished(url: String) {
        methodChannel.invokeMethod("onPageFinished", arguments: ["url": url])
    }

    func onProgress(progress: Int) {
        methodChannel.invokeMethod("onProgress", arguments: ["progress": progress])
    }

    func onReceivedError(message: String) {
        methodChannel.invokeMethod("onReceivedError", arguments: ["message": message])
    }

    func onJsAlert(url: String, message: String) {
        methodChannel.invokeMethod("onJsAlert", arguments: ["url": url, "message": message])
    }
}