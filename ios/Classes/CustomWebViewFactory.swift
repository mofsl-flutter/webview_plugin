import Flutter
import UIKit
import WebKit

class CustomWebViewFactory: NSObject, FlutterPlatformViewFactory {
   
    
    private var messenger: FlutterBinaryMessenger
    var delegate: WebViewControllerDelegate?

    init(messenger: FlutterBinaryMessenger, delegate: WebViewControllerDelegate?) {
        self.messenger = messenger
        self.delegate = delegate
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return WebViewMoFlutter(frame: frame, viewIdentifier: viewId, args: args, messenger: messenger, delegate: delegate)
    }
}

class WebViewMoFlutter: NSObject, FlutterPlatformView {
    private var webView: WKWebView
    private var url: URL?
    private var delegate: WebViewControllerDelegate?
    private var isChart: Bool = true

    init(frame: CGRect, viewIdentifier: Int64, args: Any?, messenger: FlutterBinaryMessenger, delegate: WebViewControllerDelegate?) {
        self.webView = WebViewManager.shared.getWebView(frame: frame)
        self.delegate = delegate
        super.init()

         // Initialize isChart from args
        if let argsDict = args as? [String: Any], let isChart = argsDict["isChart"] as? Bool {
            self.isChart = isChart
        } else {
            self.isChart = true
        }
        print("Received arg isChart: \(isChart)")

        if let argsDict = args as? [String: Any], let _ = argsDict["initialUrl"] as? String {

            // self.url = URL(string: urlString)
            // loadUrl()
        }
        self.webView.navigationDelegate = self
       if #available(iOS 16.4,*) {
           self.webView.isInspectable = true
       }
    }

    func view() -> UIView {
        return webView
    }

   
}

extension WebViewMoFlutter: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("Received pageDidLoad2 isChart: \(isChart)")
       if isChart {
            delegate?.pageDidLoad(url: webView.url?.absoluteString ?? "")
        } else {
            delegate?.onPageFinished(url: webView.url?.absoluteString ?? "")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // handleLoadingError()
        delegate?.onPageLoadError()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // handleLoadingError()
        delegate?.onPageLoadError()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
      // Check if the URL is a file link
      if url.absoluteString.contains(".pdf") || url.absoluteString.contains("SH=") || url.isFileURL {
        // Open the URL in an external browser
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        decisionHandler(.cancel) // Cancel the navigation in WebView
        return
      } else if (url.absoluteString.contains("tel:")) {
        print("called tel====== \(url.absoluteString)")
        if UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
          decisionHandler(.cancel)
          return
        }
      } else if (url.absoluteString.contains("mailto:")) {
        print("called mailto====== \(url.absoluteString)")
        if UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
          decisionHandler(.cancel)
          return
        }
      }
    }
      decisionHandler(.allow) // Allow navigation for other URLs
    }

     func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Bypass SSL certificate validation
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                let credential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    
}
