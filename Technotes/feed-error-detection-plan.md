# Feed Error Detection and Removal - Implementation Plan

## Overview

This document contains the analysis and implementation plan for adding problematic RSS feed detection to NetNewsWire. The approach is **simple and user-driven** - track errors, show visual indicators, let users decide what to remove.

**Philosophy:** No automatic removal, no complex scoring, no notification spam. Just make problems visible and give users control.

---

## Current State Analysis

### What Works Today

NetNewsWire has **functional error handling** but **minimal error tracking**:

✅ **HTTP Status Code Handling** (`RSWeb/DownloadSession.swift:169-190`)
- 4xx responses cached for ~53 hours
- 429 (Rate Limit) with Retry-After parsing
- Response caching (13 minutes for successful responses)

✅ **Feed Refresh Logic** (`Account/LocalAccount/LocalAccountRefresher.swift:103-167`)
- Updates `lastCheckDate` on every attempt
- Handles conditional GET (304 responses)
- Content hash verification (MD5)

✅ **Error Types Defined**
- `FeedParserError`: 6 parsing error types
- `AccountError`: Credential errors, 404 handling
- `TransportError`: HTTP status descriptions

### Critical Gaps

❌ **No Persistent Error Tracking**
- Errors logged but immediately forgotten
- Only `lastCheckDate` stored (attempt time, not success time)
- Feed doesn't know it has 10 consecutive 404 errors

❌ **Silent Failures**
- `LocalAccountRefresher.swift:110-112` - silently returns on error
- No user notification or UI indication
- Feed appears "normal" even when broken

❌ **No Feed Health Status**
- All feeds treated equally during refresh
- No `.healthy` / `.broken` status
- Can't distinguish working vs. failing feeds

---

## Key Source Files

| File | Purpose | Error Handling |
|------|---------|----------------|
| `Modules/RSWeb/Sources/RSWeb/DownloadSession.swift` (508 lines) | HTTP download orchestration | 4xx cache, 429 throttle, response caching |
| `Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift` (271 lines) | Feed refresh coordination | **Silent error drops (lines 110-112)** |
| `Modules/Account/Sources/Account/WebFeedMetadata.swift` (175 lines) | Feed metadata storage | **No error tracking fields** |
| `Modules/Account/Sources/Account/WebFeed.swift` (341 lines) | Feed model | lastCheckDate, conditionalGetInfo, contentHash |
| `Modules/RSParser/Sources/Swift/Feeds/FeedParserError.swift` | Parsing errors | 6 error types (minimal) |
| `Modules/RSWeb/Sources/RSWeb/HTTPResponseCode.swift` | HTTP status constants | Complete 1xx-5xx definitions |

---

## Implementation Plan

### Phase 1: Minimal Data Model Changes

**File:** `Modules/Account/Sources/Account/WebFeedMetadata.swift`

Add **3 new properties**:

```swift
// Add to WebFeedMetadata class
public var lastSuccessfulCheckDate: Date?  // When did this feed last work?
public var consecutiveErrorCount: Int = 0  // How many failures in a row?
public var lastErrorMessage: String?       // What went wrong? (simple string)
```

Add to `CodingKeys` enum:

```swift
enum CodingKeys: String, CodingKey {
    // ... existing keys ...
    case lastSuccessfulCheckDate
    case consecutiveErrorCount
    case lastErrorMessage
}
```

**Backwards compatible:** All properties are optional or have default values. Existing metadata files will load correctly.

---

### Phase 2: Error Tracking Logic

**File:** `Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift`

**Current implementation (lines 103-167):**
```swift
func downloadSession(_ downloadSession: DownloadSession,
                     downloadDidComplete url: URL,
                     response: URLResponse?,
                     data: Data,
                     error: NSError?) {

    guard let feed = urlToFeedDictionary[url.absoluteString] else { return }
    feed.lastCheckDate = Date()

    guard error == nil else {
        return  // ❌ Silent failure - NO ERROR TRACKING
    }

    guard let httpResponse = response as? HTTPURLResponse else { return }
    guard httpResponse.statusCode == 200 || httpResponse.statusCode == 304 else {
        return  // ❌ Silent failure - NO ERROR TRACKING
    }

    // ... parsing and update logic ...
}
```

**Proposed changes:**

```swift
func downloadSession(_ downloadSession: DownloadSession,
                     downloadDidComplete url: URL,
                     response: URLResponse?,
                     data: Data,
                     error: NSError?) {

    guard let feed = urlToFeedDictionary[url.absoluteString] else { return }
    feed.lastCheckDate = Date()

    // NEW: Track network errors
    guard error == nil else {
        feed.metadata.consecutiveErrorCount += 1
        feed.metadata.lastErrorMessage = error.localizedDescription
        return
    }

    guard let httpResponse = response as? HTTPURLResponse else { return }

    // NEW: Track HTTP error responses
    guard httpResponse.statusCode == 200 || httpResponse.statusCode == 304 else {
        feed.metadata.consecutiveErrorCount += 1
        feed.metadata.lastErrorMessage = "HTTP \(httpResponse.statusCode)"
        return
    }

    // Handle 304 (Not Modified) - still a success
    if httpResponse.statusCode == 304 {
        feed.metadata.lastSuccessfulCheckDate = Date()
        feed.metadata.consecutiveErrorCount = 0
        feed.metadata.lastErrorMessage = nil
        // ... update conditional GET info ...
        return
    }

    // ... parsing logic ...

    guard let parsedFeed = try? await FeedParser.parse(parserData) else {
        // NEW: Track parsing errors
        feed.metadata.consecutiveErrorCount += 1
        feed.metadata.lastErrorMessage = "Failed to parse feed"
        return
    }

    guard let articleChanges = try? await account.update(feed, with: parsedFeed) else {
        // NEW: Track database update errors
        feed.metadata.consecutiveErrorCount += 1
        feed.metadata.lastErrorMessage = "Failed to update articles"
        return
    }

    // NEW: Success! Reset error tracking
    feed.metadata.lastSuccessfulCheckDate = Date()
    feed.metadata.consecutiveErrorCount = 0
    feed.metadata.lastErrorMessage = nil
}
```

**Key improvements:**
1. Track errors instead of silently dropping
2. Store simple error message (user-friendly string)
3. Increment consecutive error counter
4. Reset counter to 0 on success
5. Track successful update time separately from attempt time

---

### Phase 3: UI Indicators (macOS)

#### 3.1 Sidebar Feed List

**Visual indicators based on error count:**

```
📰 TechCrunch                    (0 errors - no icon)
📰 Ars Technica                  (0 errors - no icon)
⚠️ Broken Blog                   (3-9 errors - yellow warning)
📰 Daring Fireball               (0 errors - no icon)
❌ Dead Feed                     (10+ errors - red X)
```

**Implementation locations:**
- `Mac/Sidebar/SidebarViewController.swift` - feed list controller
- `Mac/Sidebar/SidebarCell.swift` (if exists) - cell rendering
- Or relevant outline view data source methods

**Logic:**
```swift
func iconForFeed(_ feed: WebFeed) -> NSImage? {
    let errorCount = feed.metadata.consecutiveErrorCount

    if errorCount >= 10 {
        return NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Broken feed")
            ?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
    } else if errorCount >= 3 {
        return NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Feed has errors")
            ?.withSymbolConfiguration(.init(paletteColors: [.systemYellow]))
    }

    return nil  // No error icon
}
```

#### 3.2 Feed Inspector Panel

**Location:** `Mac/Inspector/WebFeedInspectorViewController.swift`

**Add "Feed Health" section (only visible if errors exist):**

```
┌─────────────────────────────────────────────┐
│ Feed Health                                 │
├─────────────────────────────────────────────┤
│ Status: ⚠️ Not updating                     │
│ Last successful update: 2 weeks ago         │
│ Consecutive errors: 5                       │
│ Last error: HTTP 404                        │
│                                             │
│ This feed hasn't updated successfully      │
│ in a while. You may want to check if       │
│ the feed URL has changed or remove it.     │
│                                             │
│ [Check Now]  [Remove Feed]                 │
└─────────────────────────────────────────────┘
```

**Implementation:**
```swift
// Only show section if errors exist
var shouldShowHealthSection: Bool {
    feed.metadata.consecutiveErrorCount > 0
}

func updateHealthSection() {
    guard shouldShowHealthSection else {
        healthSection.isHidden = true
        return
    }

    healthSection.isHidden = false

    let errorCount = feed.metadata.consecutiveErrorCount
    statusLabel.stringValue = errorCount >= 10 ? "❌ Broken" : "⚠️ Not updating"

    if let lastSuccess = feed.metadata.lastSuccessfulCheckDate {
        let formatter = RelativeDateTimeFormatter()
        lastSuccessLabel.stringValue = "Last successful update: \(formatter.localizedString(for: lastSuccess, relativeTo: Date()))"
    } else {
        lastSuccessLabel.stringValue = "Last successful update: Never"
    }

    errorCountLabel.stringValue = "Consecutive errors: \(errorCount)"

    if let errorMessage = feed.metadata.lastErrorMessage {
        lastErrorLabel.stringValue = "Last error: \(errorMessage)"
    }
}
```

**Buttons:**
- **Check Now**: Trigger immediate feed refresh
- **Remove Feed**: Delete the feed with confirmation dialog

#### 3.3 Optional: App Badge

Show count of broken feeds (10+ errors) as app icon badge:

```swift
func updateBrokenFeedBadge() {
    let brokenFeeds = AccountManager.shared.activeAccounts
        .flatMap { $0.flattenedWebFeeds() }
        .filter { $0.metadata.consecutiveErrorCount >= 10 }

    NSApp.dockTile.badgeLabel = brokenFeeds.count > 0 ? "\(brokenFeeds.count)" : nil
}
```

Call after each feed refresh cycle completes.

---

### Phase 4: UI Indicators (iOS)

Mirror the macOS implementation using UIKit:

#### 4.1 Feed List Cells
- `iOS/MasterFeed/MasterFeedViewController.swift` - feed list
- Add SF Symbol icons (same as macOS): `xmark.circle.fill` (red), `exclamationmark.triangle.fill` (yellow)

#### 4.2 Feed Detail View
- `iOS/Inspector/` or detail view controller
- Show same "Feed Health" section
- Use UIKit labels and buttons

#### 4.3 Optional: Tab Badge
- Show count of broken feeds on Feeds tab badge

---

### Phase 5: Optional Notifications

**Recommendation: Start without notifications.** Visual indicators are enough.

If users request it, add **Option B: One-Time Alert**:

```swift
// Add to WebFeedMetadata
var userNotifiedOfErrors: Bool = false

// In error tracking logic
if feed.metadata.consecutiveErrorCount == 10 && !feed.metadata.userNotifiedOfErrors {
    showBrokenFeedAlert(for: feed)
    feed.metadata.userNotifiedOfErrors = true
}

// Reset flag on successful update
if successfulUpdate {
    feed.metadata.userNotifiedOfErrors = false
}
```

**Alert:**
```
┌────────────────────────────────────────┐
│  Feed Not Updating                    │
├────────────────────────────────────────┤
│  "Broken Blog" hasn't updated         │
│  successfully in 2 weeks.             │
│                                        │
│  Last error: 404 Not Found            │
│                                        │
│  [Keep Feed]  [Remove Feed]           │
└────────────────────────────────────────┘
```

---

## Error Detection Thresholds

**Visual Indicators:**
- **0 errors**: No icon (feed is healthy)
- **1-2 errors**: No icon (transient failures are normal)
- **3-9 errors**: ⚠️ Yellow warning icon
- **10+ errors**: ❌ Red error icon

**Rationale:**
- Occasional failures are normal (server restarts, network issues)
- 3+ consecutive failures indicate a real problem
- 10+ consecutive failures = feed is almost certainly broken

**Time-based consideration:**
Feeds are refreshed every 30 minutes (configurable). So:
- 3 errors = ~1.5 hours of failures
- 10 errors = ~5 hours of failures
- This balances sensitivity with avoiding false positives

---

## User Actions

### 1. **Check Now** (Force Refresh)
Immediately attempt to download and parse the feed, bypassing normal refresh schedule.

**Implementation:**
```swift
@IBAction func checkNowButtonClicked(_ sender: Any) {
    guard let feed = inspectedFeed else { return }

    // Trigger immediate refresh for this specific feed
    feed.account?.refresh(feed) { result in
        switch result {
        case .success:
            // Show success message or just update UI
            self.updateHealthSection()
        case .failure(let error):
            // Error will be tracked automatically
            self.showAlert(title: "Refresh Failed", message: error.localizedDescription)
        }
    }
}
```

### 2. **Remove Feed** (Delete)
Delete the feed with confirmation dialog.

**Implementation:**
```swift
@IBAction func removeFeedButtonClicked(_ sender: Any) {
    guard let feed = inspectedFeed else { return }

    let alert = NSAlert()
    alert.messageText = "Remove Feed?"
    alert.informativeText = "Are you sure you want to remove \"\(feed.nameForDisplay)\"? This cannot be undone."
    alert.addButton(withTitle: "Remove")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning

    if alert.runModal() == .alertFirstButtonReturn {
        feed.account?.removeFeed(feed) { result in
            // Feed removed, close inspector or update UI
        }
    }
}
```

### 3. **Ignore** (Do Nothing)
User can choose to keep the feed even if it's broken. No action needed.

---

## Migration and Backwards Compatibility

### Existing Metadata Files

All new fields have safe defaults:
- `lastSuccessfulCheckDate: Date?` - Optional, starts as `nil`
- `consecutiveErrorCount: Int = 0` - Defaults to 0
- `lastErrorMessage: String?` - Optional, starts as `nil`

**First run after update:**
- Existing feeds will show 0 errors (default)
- `lastSuccessfulCheckDate` will be `nil`
- After next refresh, fields will populate correctly

### Feed Migration Strategy

**Option A: Gradual** (Recommended)
- New fields start empty/default
- Fill in as feeds are refreshed naturally
- No migration code needed

**Option B: One-time initialization**
```swift
// On app launch, set lastSuccessfulCheckDate to existing lastCheckDate
// for all feeds that don't have errors
for feed in allFeeds where feed.metadata.lastSuccessfulCheckDate == nil {
    // Assume last check was successful if we have articles
    if feed.metadata.consecutiveErrorCount == 0 {
        feed.metadata.lastSuccessfulCheckDate = feed.metadata.lastCheckDate
    }
}
```

**Recommendation:** Use Option A (gradual). Simpler and self-correcting.

---

## Testing Checklist

### Data Layer
- [ ] Add new fields to WebFeedMetadata
- [ ] Verify CodingKeys includes new fields
- [ ] Test loading existing metadata files (backwards compat)
- [ ] Test saving metadata with new fields

### Error Tracking
- [ ] Test network error tracking (disconnect network)
- [ ] Test HTTP 4xx error tracking (point feed to 404 URL)
- [ ] Test HTTP 5xx error tracking (point feed to 500 URL)
- [ ] Test parsing error tracking (point feed to invalid XML)
- [ ] Test success resets error count
- [ ] Test 304 (Not Modified) counts as success

### UI (macOS)
- [ ] Verify no icon for 0-2 errors
- [ ] Verify ⚠️ yellow icon for 3-9 errors
- [ ] Verify ❌ red icon for 10+ errors
- [ ] Test Feed Inspector health section appears/hides correctly
- [ ] Test "Check Now" button triggers refresh
- [ ] Test "Remove Feed" button deletes feed
- [ ] Test health section shows correct error counts and messages

### UI (iOS)
- [ ] Same as macOS but with UIKit components

### Edge Cases
- [ ] Feed transitions from broken to working
- [ ] Feed with no articles but successful updates
- [ ] Feed that never successfully updated (lastSuccessfulCheckDate = nil)
- [ ] Multiple accounts with broken feeds
- [ ] Smart feeds (should not show error indicators)

---

## Future Enhancements (Out of Scope for v1)

### 1. Error Categorization
Instead of simple string, categorize errors:
```swift
enum FeedErrorCategory: String, Codable {
    case network          // Network timeout, no connection
    case http4xx          // Client errors (404, 403, etc)
    case http5xx          // Server errors (500, 503, etc)
    case parse            // Feed parsing failed
    case auth             // 401, 403 credential errors
    case rateLimited      // 429 rate limit
}

var lastErrorCategory: FeedErrorCategory?
```

Benefits: Could adjust thresholds per category (be more patient with 5xx, less patient with 404).

### 2. Error History
Track last N errors instead of just last error:
```swift
struct FeedError: Codable {
    let date: Date
    let message: String
    let category: FeedErrorCategory
}

var errorHistory: [FeedError] = []  // Last 5-10 errors
```

Benefits: Could show trend in inspector ("Has been failing for 2 weeks").

### 3. Health Score
Calculate success rate over time:
```swift
var successRate: Double {
    // successfulChecks / totalChecks over last 30 days
    // 1.0 = perfect, 0.0 = never works
}
```

Benefits: More nuanced than consecutive errors (feed that fails 50% of time vs 100%).

### 4. Automatic Feed URL Updates
Detect 301 (Moved Permanently) and offer to update feed URL:
```swift
if httpResponse.statusCode == 301, let newURL = httpResponse.url {
    showAlert("Feed Moved", "Update URL to \(newURL)?")
}
```

Benefits: Fixes broken feeds automatically.

### 5. Bulk Actions
"Remove all broken feeds" button:
```swift
let brokenFeeds = account.feeds.filter { $0.metadata.consecutiveErrorCount >= 10 }
// Show list, let user confirm bulk deletion
```

Benefits: Easy cleanup of multiple dead feeds.

---

## Summary

### What We're Building

**Simple error tracking system:**
- 3 new metadata fields
- Error tracking in refresh logic
- Visual indicators in UI
- User-driven removal (no auto-delete)

### Why This Works

✅ **Minimal complexity**: Just 3 fields, simple logic
✅ **User control**: No automatic removal, users decide
✅ **Visible**: Clear indicators of broken feeds
✅ **Informative**: Shows what's wrong and when
✅ **Safe**: Backwards compatible, no data loss
✅ **Actionable**: "Check Now" and "Remove Feed" buttons

### Files to Modify

1. `Modules/Account/Sources/Account/WebFeedMetadata.swift` - Add 3 fields
2. `Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift` - Track errors
3. `Mac/Sidebar/` - Add visual indicators
4. `Mac/Inspector/WebFeedInspectorViewController.swift` - Add health section
5. `iOS/` - Mirror macOS changes (UIKit)

### Implementation Order

1. ✅ **Phase 1**: Data model (WebFeedMetadata) - COMPLETE
2. ✅ **Phase 2**: Error tracking logic (LocalAccountRefresher) - COMPLETE
3. ✅ **Phase 3**: macOS UI (Sidebar + Inspector) - COMPLETE
4. ✅ **Phase 4**: iOS UI (mirror macOS) - COMPLETE
   - ✅ Phase 4.1: iOS Feed List Cells with error indicators
   - ✅ Phase 4.2: iOS Feed Detail/Inspector View with health section
   - ⏭️ Phase 4.3: iOS Tab Badge (optional - skipped for v1)
5. ⚠️ **Phase 5**: Optional notifications (deferred - not implemented)

---

## Appendix: Current Error Flow

### Download Flow with Error Points

```
Feed URL
    ↓
DownloadSession.download(urls)
    ├─ Check cached response (200-399) → Return cached ✓
    ├─ Check cached 4xx response → Skip request
    ├─ Check 429 rate limit → Skip request
    ├─ URLSession.dataTask()
    │   ├─ Network Error → ❌ ERROR POINT 1: Network/timeout
    │   ├─ Status >= 400 → ❌ ERROR POINT 2: HTTP 4xx/5xx
    │   │   ├─ 429 → Store retry-after, throttle host
    │   │   └─ 400-499 → Cache 53 hours
    │   └─ Status 200-399 → Continue
    │
    ├─ Delegate: downloadSession(didComplete:)
    │   ├─ Set feed.lastCheckDate = now (always)
    │   ├─ Guard error == nil else return ← SILENT DROP
    │   ├─ Guard status 200 or 304 else return ← SILENT DROP
    │   ├─ Update conditionalGetInfo (304 handling)
    │   └─ Parse feed data
    │
    ├─ FeedParser.parse()
    │   ├─ Detect feed type (RSS/Atom/JSON)
    │   ├─ Parse items
    │   └─ Throw FeedParserError → ❌ ERROR POINT 3: Parse failure
    │
    └─ Account.update(feed, parsedFeed)
        ├─ Store feed metadata
        ├─ Insert/update articles
        └─ ❌ ERROR POINT 4: Database update failure

Result: Only "lastCheckDate" updated. All errors are lost.
```

### Error Points We'll Track

1. **Network errors** (timeout, no connection, DNS failure)
2. **HTTP 4xx errors** (404, 403, 410 Gone, etc)
3. **HTTP 5xx errors** (500, 503, etc)
4. **Parse errors** (invalid XML/JSON, missing required fields)
5. **Database errors** (article update failed)

All stored in simple `lastErrorMessage` string for v1.

---

---

## Implementation Summary

**Status:** ✅ COMPLETE (Phases 1-4)

### What Was Implemented

#### Phase 1: Data Model (WebFeedMetadata)
- Added 3 new fields to `WebFeedMetadata`:
  - `lastSuccessfulCheckDate: Date?` - Tracks when feed last updated successfully
  - `consecutiveErrorCount: Int` - Counts consecutive failures
  - `lastErrorMessage: String?` - Stores user-friendly error description
- Added public accessors on `WebFeed` for easy access
- Fully backwards compatible with existing metadata files

#### Phase 2: Error Tracking Logic (LocalAccountRefresher)
- Modified `downloadSession(_:downloadDidComplete:)` to track all error types:
  - Network errors (timeout, connectivity issues)
  - HTTP 4xx/5xx errors
  - Parse errors
  - Database update errors
- Errors increment `consecutiveErrorCount` and set `lastErrorMessage`
- Successful updates reset counter to 0 and update `lastSuccessfulCheckDate`
- HTTP 304 (Not Modified) correctly counts as success

#### Phase 3: macOS UI
**Sidebar Feed List** (`Mac/MainWindow/Sidebar/Cell/SidebarCell.swift`):
- Added `errorCount` property and `errorIndicatorView`
- Displays SF Symbol icons based on error count:
  - 0-2 errors: No icon
  - 3-9 errors: ⚠️ Yellow warning (`exclamationmark.triangle.fill`)
  - 10+ errors: ❌ Red X (`xmark.circle.fill`)
- Updated `SidebarCellLayout` to position error indicator
- Updated `SidebarViewController` to set error counts from feeds

**Feed Inspector** (`Mac/Inspector/WebFeedInspectorViewController.swift`):
- Added "Feed Health" section (programmatically created)
- Shows: status, last successful update, error count, last error message
- Section only visible when `consecutiveErrorCount > 0`
- Uses `RelativeDateTimeFormatter` for user-friendly time display

#### Phase 4: iOS UI
**Feed List Cells** (`iOS/MainFeed/Cell/MainFeedTableViewCell.swift`):
- Mirrored macOS implementation with UIKit
- Added `errorCount` property and `errorIndicatorView`
- Same visual indicators (yellow warning, red X)
- Updated `MainFeedTableViewCellLayout` to position indicator
- Updated `MainFeedViewController` to configure error counts

**Feed Inspector** (`iOS/Inspector/WebFeedInspectorViewController.swift`):
- Mirrored macOS health section with UIKit
- Programmatically created UIStackView with labels
- Shows as additional table section when errors exist
- Same information display as macOS version

**Skipped:** iOS Tab Badge (Phase 4.3) - marked optional in plan

### Files Modified

#### Data Model
- `Modules/Account/Sources/Account/WebFeedMetadata.swift`
- `Modules/Account/Sources/Account/WebFeed.swift`

#### Business Logic
- `Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift`

#### macOS UI
- `Mac/MainWindow/Sidebar/Cell/SidebarCell.swift`
- `Mac/MainWindow/Sidebar/Cell/SidebarCellLayout.swift`
- `Mac/MainWindow/Sidebar/SidebarViewController.swift`
- `Mac/Inspector/WebFeedInspectorViewController.swift`

#### iOS UI
- `iOS/MainFeed/Cell/MainFeedTableViewCell.swift`
- `iOS/MainFeed/Cell/MainFeedTableViewCellLayout.swift`
- `iOS/MainFeed/MainFeedViewController.swift`
- `iOS/Inspector/WebFeedInspectorViewController.swift`

### Git Commits (on feature/feed-error-detection branch)

1. `d4a11cd09` - Add error tracking fields to WebFeedMetadata
2. `dc7e0ca45` - Track feed errors in LocalAccountRefresher
3. `4ea1c3b61` - Add error indicators to sidebar feed list
4. `f84212d8a` - Add Feed Health section to WebFeed Inspector
5. `ae1e3e2c0` - Add public accessors and fix compilation errors
6. `d1192907e` - Add iOS feed error indicators and health section

### Testing Status

- ✅ iOS build succeeds
- ✅ macOS build succeeds
- ⚠️ Manual testing required (no automated UI tests added)

### Next Steps

1. **Testing**: Manually test on both platforms with feeds that have errors
2. **Code Review**: Have team review implementation
3. **Merge**: Merge feature branch to main after approval
4. **Future Enhancements** (if needed):
   - Phase 5: Optional notifications for broken feeds
   - Phase 4.3: iOS tab badge
   - Advanced features from plan (error history, health score, etc.)

---

**Document Version:** 1.1
**Created:** 2025-10-18
**Updated:** 2025-10-18
**Purpose:** Implementation plan and summary for feed error detection feature
**Status:** Implementation complete (Phases 1-4)
