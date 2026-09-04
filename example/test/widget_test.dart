import "package:flutter_test/flutter_test.dart";
import "package:webview_harness/main.dart";

void main() {
  testWidgets("harness boots and shows its three tabs", (WidgetTester tester) async {
    await tester.pumpWidget(const HarnessApp());
    await tester.pump();

    expect(find.text("WebView Harness"), findsOneWidget);
    expect(find.text("Browser"), findsOneWidget);
    expect(find.text("Audit"), findsOneWidget);
    expect(find.text("Log"), findsOneWidget);
  });
}
