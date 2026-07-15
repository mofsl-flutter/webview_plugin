## 1.0.5

* **Security:** Fixed unsafe WebView SSL error handling that triggered the Google Play
  "Unsafe Implementation of WebView SSL Error Handler" (Device and Network Abuse) policy
  violation.
  * Android: `onReceivedSslError` no longer calls `handler.proceed()` unconditionally; it
    now cancels the load on any certificate error and reports it to Dart.
  * iOS: the authentication-challenge handler no longer trusts the server certificate
    blindly; it defers to the system's standard certificate-chain validation.

## 0.0.1

* TODO: Describe initial release.
