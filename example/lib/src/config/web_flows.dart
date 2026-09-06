/// HTTP verb a flow uses.
enum FlowMethod {
  /// The `api/Url/*` family.
  get,

  /// The SuperApp services family, which posts an empty body.
  post,
}

/// Which host serves a flow.
enum FlowHost {
  /// Trader API — the `api/Url/*` family.
  trader,

  /// SuperApp services.
  superApp,
}

/// One web page flow: an endpoint whose response carries a page URL.
class WebFlow {
  /// Creates a flow.
  const WebFlow(
    this.id,
    this.label,
    this.path, {
    this.note,
    this.method = FlowMethod.get,
    this.host = FlowHost.trader,
    this.needsApiKey = false,
  });

  /// Short id used in results.
  final String id;

  /// Human-readable name.
  final String label;

  /// Path under the trader base, e.g. `api/Url/Stockal`.
  final String path;

  /// Anything unusual about this flow's response shape or params.
  final String? note;

  /// Verb.
  final FlowMethod method;

  /// Host that serves it.
  final FlowHost host;

  /// Whether the request needs an `XApiKey` product key in addition to the bearer token.
  final bool needsApiKey;
}

/// Every `api/Url/*` endpoint in the app, taken from `packages/trader_network/lib/URL.dart`.
///
/// All are GET and all return a payload whose single interesting field is a URL, which the app
/// then loads into a WebView. The three noted below do not return the plain `UrlResponse` shape.
/// The three-way difference these two carry against the other 42: POST not GET, the SuperApp host
/// not the trader host, and a URL that arrives as the **bare string value of `data`** rather than
/// `data.url`. The extractor handles the last of those by scanning values for anything that looks
/// like a URL, so only the request differs.
const List<WebFlow> kWebFlows = <WebFlow>[
  WebFlow("referEarn", "Refer & earn", "/services/api/refer_and_earn/Refer_And_Earn",
      method: FlowMethod.post,
      host: FlowHost.superApp,
      needsApiKey: true,
      note: "url is the bare string value of `data`"),
  // Verified broken server-side, 2026-09-04: returns HTTP 500
  // NullReferenceException from superAppServicesMiddleWare.apiKeyMiddleware.InvokeAsync, both
  // with and without an XApiKey. So it is NOT a missing-key problem, and the refer & earn key is
  // not valid here. Kept in the catalog so the failure stays visible; expect a red row until the
  // SuperApp services owners fix the middleware.
  WebFlow("superSavingPass", "Super saving pass", "/services/Ekyc/SubscriptionPlan",
      method: FlowMethod.post,
      host: FlowHost.superApp,
      note: "HTTP 500 server-side (apiKeyMiddleware NPE); url would be bare `data`"),
  // NOTE: "offernrewards" is Offers & Rewards, a different product from Refer & Earn.
  WebFlow("offersRewards", "Offers & rewards", "api/Url/Other/offernrewards"),
  WebFlow("smallcase", "Smallcase", "api/Url/Other/adviceallsmallcases"),
  WebFlow("ipoBonds", "IPO / bonds (OFS)", "api/Url/Other/ipobonds",
      note: "returns IpoUrlResponse, not UrlResponse"),
  WebFlow("ipoV2Other", "IPO v2 (other)", "api/Url/Other/ipov2"),
  WebFlow("ipoV2", "IPO v2", "api/Url/IpoV2", note: "returns IpoUrlResponse"),
  WebFlow("bonds", "Bonds", "api/Url/Bonds"),
  WebFlow("stockal", "US equity (Stockal)", "api/Url/Stockal"),
  WebFlow("tradetron", "Tradetron", "api/Url/Tradetron"),
  WebFlow("aceProduct", "Advisory portfolio", "api/Url/AceProduct"),
  WebFlow("aceImp", "Advisory portfolio (IMP)", "api/Url/AceProduct?mostType=IMP",
      note: "query param"),
  WebFlow("aceAuto", "Ace auto approval", "api/Url/AceAutoApproval"),
  WebFlow("nonPoa", "eDIS / margin transfer", "api/Url/NonPoaTransfer"),
  WebFlow("convertDelivery", "Convert to delivery", "api/Url/ConvertToDelivery"),
  WebFlow("allianceTransfer", "Alliance transfer stocks", "api/Url/Alliance/TransferStocks"),
  WebFlow("alliancePledge", "Alliance margin pledge", "api/Url/Alliance/MarginPledge"),
  WebFlow("moGenie", "Chat bot (MoGenie)", "api/Url/MoGenie"),
  WebFlow("marginCalc", "Margin calculator", "api/Url/MarginCalculator"),
  WebFlow("tejiMandi", "Teji Mandi", "api/Url/TejiMandi"),
  WebFlow("moApi", "MoApi", "api/Url/MoApi"),
  WebFlow("trendicator", "Trendicator", "api/Url/Trendicator"),
  WebFlow("mostGuide", "Most guide", "api/Url/MostGuide"),
  WebFlow("wallet", "Wallet", "api/Url/Wallet"),
  WebFlow("payIn", "Pay in", "api/Url/PayIn"),
  WebFlow("priceAlert", "Price alert", "api/Url/PriceAlert"),
  WebFlow("emodification", "E-modification", "api/Url/Emodification",
      note: "returns EModification shape"),
  WebFlow("evoting", "E-voting", "api/Url/EvotingLink"),
  WebFlow("investmentAdvisory", "Investment advisory", "api/Url/InvestmentAdvisory"),
  WebFlow("accountAggregator", "Account aggregator", "api/Url/AccountAggregator"),
  WebFlow("segmentActivation", "Segment activation", "api/Url/SegmentActivation"),
  WebFlow("addSegmentServices", "Additional segment services",
      "api/Url/Other/AdditionalSegmentServices"),
  WebFlow("reactivation", "Reactivation", "api/Url/Reactivation"),
  WebFlow("shortSelling", "Short selling / SLBS", "api/Url/Other/ShortSellingSlbs"),
  WebFlow("iapSipMandate", "IAP SIP mandate", "api/Url/Other/iapsipmandate"),
  WebFlow("marketMojo", "Market Mojo", "api/Url/MarketMojo?section=", note: "query param"),
  WebFlow("mofslCommunity", "MOFSL community", "api/Url/MofslCommunity"),
  WebFlow("obPerformance", "Option brain performance", "api/Url/ObPerformance"),
  WebFlow("manageOptionBrain", "Manage option brain", "api/Url/manageoptionbrain"),
  WebFlow("tgsHelp", "TGS help", "api/Url/TGS/HelpUrl"),
  WebFlow("tgsManage", "TGS manage", "api/Url/TGS/Manage"),
  WebFlow("tgsStock", "TGS stock selection", "api/Url/TGS/StockSelection"),
  WebFlow("investorGrievance", "Investor grievance", "api/Url/investorgrievance"),
  WebFlow("pr", "PR", "api/Url/PR"),
];
