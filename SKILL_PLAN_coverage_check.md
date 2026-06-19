# Skill Plan: `coverage-check` for `custom_webview_plugin`

## Purpose

Create a Claude/Gemini Code skill named **`coverage-check`** that:
1. Identifies gaps in the existing Dart unit tests for `custom_webview_plugin`
2. Writes new test cases to close those gaps
3. Runs all tests with `--coverage`
4. Parses the generated `coverage/lcov.info`
5. Reports per-file and overall coverage with a clear pass/fail threshold

---

## Plugin Overview (context for skill author)

**Location**: `/Users/shikharjain/Development/Projects/webview_plugin`

### Dart library files (what needs coverage)

| File | Class | Public API |
|------|-------|------------|
| `lib/custom_webview_plugin.dart` | `CustomWebViewPlugin` | `resetCache()` (static) |
| `lib/custom_webview_plugin.dart` | `CustomWebViewWidget` | StatefulWidget — platform view (UiKitView/AndroidView) |
| `lib/custom_webview_controller.dart` | `CustomWebViewController` | `loadUrl`, `loadHtmlData`, `addJavascriptChannel`, `removeJavascriptChannel`, `reloadUrl`, `runJavaScript`, `getCurrentUrl`, `setUserInteractionEnabled`, `setCustomUserAgent`, `enableMultipleWindows`, `setBackgroundColor`, `canGoBack`, `goBack` + 7 callbacks |
| `lib/custom_webview_cookie_manager.dart` | `CustomWebViewCookieManager` | `clearCookies()` (static) |

### Existing test files (what is already covered)

| Test file | What it covers |
|-----------|----------------|
| `test/custom_webview_controller_test.dart` | `loadUrl`, `loadHtmlData`, `reloadUrl`, `runJavaScript`, `addJavascriptChannel`, `getCurrentUrl`, `setUserInteractionEnabled`, `setCustomUserAgent`, `enableMultipleWindows`, `setBackgroundColor`, `onPageStarted/Finished/Progress/Error/JsAlert/JsChannelMessage` callbacks, `onNavigationRequest` allow/block |
| `test/custom_webview_plugin_test.dart` | `CustomWebViewPlugin.resetCache()` |
| `test/custom_webview_cookie_manager_test.dart` | `CustomWebViewCookieManager.clearCookies()` |
| `test/custom_webview_js_handler_test.dart` | Multi-channel JS routing, per-channel callbacks, null JS result |

### Coverage gaps — new tests the skill must write

The following are **not tested** and must be added by the skill:

#### Gap 1 — `canGoBack()` (newly added method)
File: `custom_webview_controller.dart`
- Test: mock returns `true` → `canGoBack()` returns `true`
- Test: mock returns `false` → `canGoBack()` returns `false`
- Test: `PlatformException` is caught and `false` is returned (not rethrown)
- MethodChannel method name: `"canGoBack"`

#### Gap 2 — `goBack()` (newly added method)
File: `custom_webview_controller.dart`
- Test: invokes MethodChannel `"goBack"` with no arguments
- Test: `PlatformException` is rethrown
- MethodChannel method name: `"goBack"`

#### Gap 3 — `removeJavascriptChannel()`
File: `custom_webview_controller.dart`
- Test: invoking `removeJavascriptChannel('TestChannel')` calls MethodChannel `"removeJavascriptChannel"` with `{channelName: 'TestChannel'}`
- Test: after removal, a message to that channel no longer triggers the per-channel callback

#### Gap 4 — `onTitleChanged` callback
File: `custom_webview_controller.dart`
- Test: simulate `onTitleChanged` platform message → callback receives correct title string

#### Gap 5 — `onNavigationRequest` default behavior (no callback set)
File: `custom_webview_controller.dart`
- Test: when `onNavigationRequest` is `null`, the handler returns `true` (allow all navigation)

#### Gap 6 — `pageLoaded` platform event (chart mode alias)
File: `custom_webview_controller.dart`
- Test: simulate `pageLoaded` platform message → `onPageFinished` callback is triggered (same as `onPageFinished` case)

#### Gap 7 — `CustomWebViewWidget` renders a platform view
File: `custom_webview_plugin.dart`
- Test: `pumpWidget(CustomWebViewWidget(controller: controller))` does not throw
- Test: on Android, a `PlatformViewLink` is in the widget tree
- Test: creation params contain `initialUrl`, `isChart`, `zoomEnabled`, `enableMultipleWindows`
- Note: use `debugDefaultTargetPlatformOverride` to test both platforms

---

## Step-by-Step Skill Execution Flow

When the skill is invoked (`/coverage-check`):

### Step 1 — Verify working directory

```bash
ls /Users/shikharjain/Development/Projects/webview_plugin/test/
```

Expected files:
- `custom_webview_controller_test.dart`
- `custom_webview_plugin_test.dart`
- `custom_webview_cookie_manager_test.dart`
- `custom_webview_js_handler_test.dart`

### Step 2 — Check for missing test cases

For each gap listed above, grep the existing test files:

```bash
grep -r "canGoBack\|goBack" /Users/shikharjain/Development/Projects/webview_plugin/test/
grep -r "removeJavascriptChannel" /Users/shikharjain/Development/Projects/webview_plugin/test/
grep -r "onTitleChanged" /Users/shikharjain/Development/Projects/webview_plugin/test/
grep -r "pageLoaded" /Users/shikharjain/Development/Projects/webview_plugin/test/
grep -r "CustomWebViewWidget" /Users/shikharjain/Development/Projects/webview_plugin/test/
```

For each gap NOT already covered, write the tests (see Gap 1–7 above).

### Step 3 — Write missing tests

Append new tests to the **appropriate existing file** (do not create new files unless no appropriate file exists):

| Gap | Target file |
|-----|-------------|
| Gap 1 (`canGoBack`) | `custom_webview_controller_test.dart` — add to the existing `group('CustomWebViewController')` |
| Gap 2 (`goBack`) | `custom_webview_controller_test.dart` — same group |
| Gap 3 (`removeJavascriptChannel`) | `custom_webview_js_handler_test.dart` |
| Gap 4 (`onTitleChanged`) | `custom_webview_controller_test.dart` — extend the `'Native callbacks are routed correctly'` test |
| Gap 5 (default navigation) | `custom_webview_controller_test.dart` — new test in existing group |
| Gap 6 (`pageLoaded`) | `custom_webview_controller_test.dart` — new test in existing group |
| Gap 7 (`CustomWebViewWidget`) | New group in `custom_webview_plugin_test.dart` |

#### Mock setup pattern (all controller tests use this):

```dart
setUp(() {
  controller = CustomWebViewController();
  controller.setViewId(0);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('custom_webview_flutter_0'),
    (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'canGoBack': return true;   // or false for negative test
        case 'getCurrentUrl': return 'https://flutter.dev';
        case 'runJavaScript': return 'result';
        default: return null;
      }
    },
  );
});
```

#### Example: Gap 1 test body

```dart
test('canGoBack returns true when native returns true', () async {
  // mock already returns true for canGoBack
  final result = await controller.canGoBack();
  expect(log.last.method, 'canGoBack');
  expect(result, true);
});

test('canGoBack returns false on PlatformException', () async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('custom_webview_flutter_0'),
    (MethodCall methodCall) async {
      throw PlatformException(code: 'error', message: 'failed');
    },
  );
  final result = await controller.canGoBack();
  expect(result, false); // exception is caught, returns false
});

test('goBack invokes correctly', () async {
  await controller.goBack();
  expect(log.last.method, 'goBack');
});
```

#### Example: Gap 7 widget test

```dart
group('CustomWebViewWidget', () {
  testWidgets('renders without error on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = CustomWebViewController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: CustomWebViewWidget(
            controller: controller,
            initialUrl: 'https://example.com',
            isChart: false,
            zoomEnabled: true,
            enableMultipleWindows: false,
          ),
        ),
      ),
    );
    expect(find.byType(CustomWebViewWidget), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
});
```

### Step 4 — Run tests with coverage

```bash
cd /Users/shikharjain/Development/Projects/webview_plugin && flutter test --coverage
```

Expected outputs:
- `coverage/lcov.info` generated
- All tests pass (exit code 0)

If any test fails: read the failure message, read the relevant source file, diagnose, fix.

### Step 5 — Parse `coverage/lcov.info` and report

Run this Python snippet to parse lcov:

```bash
cd /Users/shikharjain/Development/Projects/webview_plugin && python3 << 'EOF'
import re, os

lcov_path = "coverage/lcov.info"
if not os.path.exists(lcov_path):
    print("ERROR: coverage/lcov.info not found. Run flutter test --coverage first.")
    exit(1)

files = {}
current_file = None
with open(lcov_path) as f:
    for line in f:
        line = line.strip()
        if line.startswith("SF:"):
            current_file = line[3:]
            files[current_file] = {"hit": 0, "total": 0}
        elif line.startswith("DA:") and current_file:
            _, hits = line[3:].split(",", 1)
            files[current_file]["total"] += 1
            if int(hits) > 0:
                files[current_file]["hit"] += 1

print(f"\n{'File':<70} {'Lines':>6} {'Hit':>6} {'Coverage':>10}")
print("-" * 96)

total_hit = 0
total_lines = 0
for filepath, data in sorted(files.items()):
    rel = filepath.replace("/Users/shikharjain/Development/Projects/webview_plugin/", "")
    if not rel.startswith("lib/"):
        continue
    lines = data["total"]
    hit = data["hit"]
    pct = (hit / lines * 100) if lines > 0 else 0
    flag = "✅" if pct >= 80 else ("⚠️ " if pct >= 60 else "❌")
    print(f"{flag} {rel:<68} {lines:>6} {hit:>6} {pct:>9.1f}%")
    total_hit += hit
    total_lines += lines

overall = (total_hit / total_lines * 100) if total_lines > 0 else 0
print("-" * 96)
flag = "✅ PASS" if overall >= 80 else "❌ FAIL"
print(f"\n{flag}  Overall coverage: {overall:.1f}%  ({total_hit}/{total_lines} lines)")
print(f"Threshold: 80%")
EOF
```

### Step 6 — Report to user

Present the output table from Step 5. Then state:
- Which files are below threshold (< 80%)
- Which gaps remain (if any)
- Whether the coverage gate passed

---

## Skill Metadata (for SKILL.md frontmatter)

```yaml
name: coverage-check
description: Check and improve test coverage for custom_webview_plugin — writes missing tests, runs with --coverage, parses lcov, reports per-file results
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, Grep
```

## Trigger Phrases

- `/coverage-check`
- "Check test coverage for the webview plugin"
- "Run coverage on custom_webview_plugin"
- "What's the test coverage of the plugin?"

---

## Coverage Threshold

| Level | Threshold |
|-------|-----------|
| Pass | ≥ 80% overall |
| Warning | 60–79% |
| Fail | < 60% |

Per-file threshold: same (80% pass, 60–79% warning, < 60% fail)

---

## File Structure to Create

```
/Users/shikharjain/Development/Projects/webview_plugin/
  .claude/
    skills/
      coverage-check/
        SKILL.md     ← the skill file Gemini creates
```

Or if Gemini uses a different skills directory, adapt accordingly.

---

## Notes for Gemini

1. **Do not regenerate tests that already exist** — grep first (Step 2), write only what is missing.
2. **Append to existing test files** — do not create redundant new files.
3. **The `canGoBack` `PlatformException` test** — the Dart implementation catches the exception and returns `false` (not rethrow). Verify this before writing the test.
4. **Widget tests for platform views** — `CustomWebViewWidget` uses `UiKitView` on iOS and `PlatformViewLink` on Android. These don't render actual native views in Flutter test environment; they just need to pump without throwing. Use `debugDefaultTargetPlatformOverride`.
5. **`coverage/lcov.info` includes test files** — the Python parser filters to `lib/` only (line: `if not rel.startswith("lib/"): continue`).
6. **`lcov` CLI tool** — if available on the system (`which lcov`), `genhtml coverage/lcov.info -o coverage/html` generates a browsable HTML report as a bonus step.
