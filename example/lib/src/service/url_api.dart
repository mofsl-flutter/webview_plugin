import "dart:convert";
import "dart:io";

import "../config/endpoints.dart";
import "../config/web_flows.dart";

/// Result of asking an `api/Url/*` endpoint for a page URL.
class UrlFetch {
  /// Creates a result.
  const UrlFetch({
    required this.ok,
    required this.statusCode,
    required this.totalMicros,
    this.url,
    this.connectMicros,
    this.ttfbMicros,
    this.bytes = 0,
    this.rawBody = "",
    this.error,
  });

  /// Whether a usable URL came back.
  final bool ok;

  /// HTTP status, or 0 when the request never completed.
  final int statusCode;

  /// Total request duration.
  final int totalMicros;

  /// The page URL, when [ok].
  final String? url;

  /// Time until the request headers were sent.
  final int? connectMicros;

  /// Time until the response headers arrived.
  final int? ttfbMicros;

  /// Response body size.
  final int bytes;

  /// Body exactly as received.
  ///
  /// Always retained. These endpoints answer 404 for a client without the entitlement, and the
  /// body is the only thing that distinguishes that from a genuinely missing route.
  final String rawBody;

  /// Failure description, when not [ok].
  final String? error;

  /// Total in milliseconds.
  double get totalMs => totalMicros / 1000.0;
}

/// Calls the `api/Url/*` endpoints that hand back web page URLs.
///
/// Uses `dart:io` directly rather than a package so connect time is separable from the response
/// wait — the same reason the token client does. The app itself sends protobuf here; this asks
/// for JSON, which the backend also serves.
class UrlApi {
  /// Creates a client bound to [token].
  UrlApi({
    required this.token,
    this.appId = kDefaultAppId,
    this.base = kTraderBase,
    this.superAppBase = kSuperAppBase,
    this.apiKey = "",
  });

  /// Bearer token.
  final String token;

  /// Application id, used in the User-Agent.
  final String appId;

  /// Trader API base.
  final String base;

  /// SuperApp services base.
  final String superAppBase;

  /// Product key sent as `XApiKey`, for the flows that require one.
  ///
  /// Taken at runtime rather than read from the app's committed `.env`, so no product secret
  /// lives in this repo.
  final String apiKey;

  /// Requests the URL for [flow].
  Future<UrlFetch> fetch(WebFlow flow, {String apiVersion = "1.0"}) async {
    if (flow.needsApiKey && apiKey.isEmpty) {
      return const UrlFetch(
        ok: false,
        statusCode: 0,
        totalMicros: 0,
        error: "Needs an XApiKey — paste the product key in the Analysis tab",
      );
    }
    final String root = flow.host == FlowHost.superApp ? superAppBase : base;
    final Stopwatch sw = Stopwatch()..start();
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final Uri uri = Uri.parse("$root${flow.path}");
      final HttpClientRequest req = flow.method == FlowMethod.post
          ? await client.postUrl(uri)
          : await client.getUrl(uri);
      req.headers
        ..set("Authorization", "Bearer $token")
        ..set("Accept", "application/json")
        ..set("X-Api-Version", apiVersion)
        ..set("User-Agent", userAgentFor(appId));
      if (apiKey.isNotEmpty) req.headers.set("XApiKey", apiKey);
      if (flow.method == FlowMethod.post) {
        // The app posts an empty object for these; without a body the server answers 411.
        req.headers.contentType = ContentType.json;
        req.write("{}");
      }
      final int connectMicros = sw.elapsedMicroseconds;

      final HttpClientResponse res = await req.close();
      final int ttfbMicros = sw.elapsedMicroseconds;
      final String body = await res.transform(utf8.decoder).join();
      final int totalMicros = sw.elapsedMicroseconds;

      if (res.statusCode != 200) {
        return UrlFetch(
          ok: false,
          statusCode: res.statusCode,
          totalMicros: totalMicros,
          connectMicros: connectMicros,
          ttfbMicros: ttfbMicros,
          bytes: body.length,
          rawBody: body,
          error: "HTTP ${res.statusCode}",
        );
      }

      final String? url = _extractUrl(body);
      return UrlFetch(
        ok: url != null && url.isNotEmpty,
        statusCode: res.statusCode,
        totalMicros: totalMicros,
        connectMicros: connectMicros,
        ttfbMicros: ttfbMicros,
        bytes: body.length,
        rawBody: body,
        url: url,
        error: url == null ? "No url field in response" : null,
      );
    } on Object catch (e) {
      return UrlFetch(
        ok: false,
        statusCode: 0,
        totalMicros: sw.elapsedMicroseconds,
        error: e.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Pulls the page URL out of a response body.
  ///
  /// Tolerant on purpose: most flows return `{"url": "..."}`, but IPO and e-modification use
  /// their own shapes, and a bare JSON string is possible. Rather than model each one, take the
  /// first string field that looks like a URL.
  static String? _extractUrl(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is String) return decoded.startsWith("http") ? decoded : null;
      if (decoded is Map) {
        for (final String key in <String>["url", "Url", "URL", "webUrl", "link"]) {
          final Object? v = decoded[key];
          if (v is String && v.startsWith("http")) return v;
        }
        for (final Object? v in decoded.values) {
          if (v is String && v.startsWith("http")) return v;
        }
      }
      return null;
    } on FormatException {
      return null;
    }
  }
}
