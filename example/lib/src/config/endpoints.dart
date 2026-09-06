/// Hosts and fixed inputs for the web-page load harness.
library;

/// Access-token API.
///
/// Note the lowercase `tradingapiV2` segment: routing is case-sensitive here, and the
/// `TradingApiV2` spelling used by the URL APIs returns 404 for this path.
const String kTokenBase =
    "https://tradingapi.motilaloswaluat.com/tradingapiV2/api/Authorize/AccessToken";

/// Base for the `api/Url/*` endpoints that hand back web page URLs.
///
/// Matches `TRADERAPPBASEURL` in the app's `.env_uat`.
const String kTraderBase = "https://tradingapi.motilaloswaluat.com/TradingApiV2/";

/// Default client code. Must be an account entitled to the web products under test.
const String kDefaultClientCode = "T06794";

/// Default user type.
const String kDefaultUserType = "T";

/// Default application id header value.
const String kDefaultAppId = "3f5b73f9-a07f-4ab9-9678-09133a99282a";

/// User-Agent the app sends, with the appId appended. Some gateways route on it.
String userAgentFor(String appId) =>
    "Android/14/SuperApp/6.0.21(UAT-24)_5195/$appId";
