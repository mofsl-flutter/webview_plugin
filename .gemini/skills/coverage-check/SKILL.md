---
name: coverage-check
description: Check and improve test coverage for custom_webview_plugin — writes missing tests, runs with --coverage, parses lcov, reports per-file results
---

# Skill: `coverage-check` for `custom_webview_plugin`

## Purpose
This skill:
1. Identifies gaps in the existing Dart unit tests for `custom_webview_plugin`
2. Writes new test cases to close those gaps
3. Runs all tests with `--coverage`
4. Parses the generated `coverage/lcov.info`
5. Reports per-file and overall coverage with a clear pass/fail threshold of > 90%

---

## Plugin Overview (context)

**Location**: `/Users/shikharjain/Development/Projects/webview_plugin`

### Dart library files (what needs coverage)

| File | Class | Public API |
|------|-------|------------|
| `lib/custom_webview_plugin.dart` | `CustomWebViewPlugin` | `resetCache()` (static) |
| `lib/custom_webview_plugin.dart` | `CustomWebViewWidget` | StatefulWidget — platform view (UiKitView/AndroidView) |
| `lib/custom_webview_controller.dart` | `CustomWebViewController` | `loadUrl`, `loadHtmlData`, `addJavascriptChannel`, `removeJavascriptChannel`, `reloadUrl`, `runJavaScript`, `getCurrentUrl`, `setUserInteractionEnabled`, `setCustomUserAgent`, `enableMultipleWindows`, `setBackgroundColor`, `canGoBack`, `goBack` + callbacks |
| `lib/custom_webview_cookie_manager.dart` | `CustomWebViewCookieManager` | `clearCookies()` (static) |

### Coverage gaps — new tests the skill must write
(If they are not already covered in tests)

#### Gap 1 — `canGoBack()`
File: `custom_webview_controller.dart`
- Test: mock returns `true` → `canGoBack()` returns `true`
- Test: mock returns `false` → `canGoBack()` returns `false`
- Test: `PlatformException` is caught and `false` is returned

#### Gap 2 — `goBack()`
File: `custom_webview_controller.dart`
- Test: invokes MethodChannel `"goBack"` with no arguments
- Test: `PlatformException` is rethrown

#### Gap 3 — `removeJavascriptChannel()`
File: `custom_webview_controller.dart`
- Test: invoking `removeJavascriptChannel('TestChannel')` calls MethodChannel `"removeJavascriptChannel"` with `{channelName: 'TestChannel'}`

#### Gap 4 — `onTitleChanged` callback
File: `custom_webview_controller.dart`
- Test: simulate `onTitleChanged` platform message

#### Gap 5 — `onNavigationRequest` default behavior (no callback set)
File: `custom_webview_controller.dart`
- Test: when `onNavigationRequest` is `null`, the handler returns `true` (allow all navigation)

#### Gap 6 — `pageLoaded` platform event
File: `custom_webview_controller.dart`
- Test: simulate `pageLoaded` platform message → `onPageFinished` callback is triggered

#### Gap 7 — `CustomWebViewWidget` renders a platform view
File: `custom_webview_plugin.dart`
- Test: `pumpWidget(CustomWebViewWidget(controller: controller))` does not throw
- Test: on Android, a `PlatformViewLink` is in the widget tree

---

## Step-by-Step Skill Execution Flow

When this skill is invoked:

### Step 1 — Verify working directory
Ensure existing test files exist in `/Users/shikharjain/Development/Projects/webview_plugin/test/`.

### Step 2 — Check for missing test cases
Use `grep` to check which of the above gaps are NOT tested yet.

### Step 3 — Write missing tests
Append new tests to the appropriate existing test file. 

#### Mock setup pattern (example):
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
        case 'canGoBack': return true;
        default: return null;
      }
    },
  );
});
```

### Step 4 — Run tests with coverage
```bash
cd /Users/shikharjain/Development/Projects/webview_plugin && flutter test --coverage
```

### Step 5 — Parse `coverage/lcov.info` and report
Run this Python snippet to parse lcov and enforce a 90% threshold:

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
    flag = "✅" if pct >= 90 else ("⚠️ " if pct >= 75 else "❌")
    print(f"{flag} {rel:<68} {lines:>6} {hit:>6} {pct:>9.1f}%")
    total_hit += hit
    total_lines += lines

overall = (total_hit / total_lines * 100) if total_lines > 0 else 0
print("-" * 96)
flag = "✅ PASS" if overall >= 90 else "❌ FAIL"
print(f"\n{flag}  Overall coverage: {overall:.1f}%  ({total_hit}/{total_lines} lines)")
print(f"Threshold: 90%")
EOF
```

### Step 6 — Report to user
Present the output table from Step 5.
- State which files are below threshold (< 90%)
- Identify remaining gaps (if any)
- State whether the coverage gate passed (> 90%)
