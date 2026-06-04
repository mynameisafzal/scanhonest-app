# ScanHonest Pro — Manual QA Checklist
**Version:** 1.0 | **Date:** 2026-05-20 | **Tier:** Pro Subscription

> Use this checklist for every release candidate that touches a Pro feature.  
> Each section maps to one Pro capability. Mark each row ✅ Pass / ❌ Fail / ⚠️ Partial.  
> Capture failure notes in the "Notes" column.

---

## Pre-flight Setup

| # | Step | Done |
|---|------|------|
| 1 | Device: physical iPhone (not simulator) for haptics + FaceID | ☐ |
| 2 | Signed in with a **Sandbox Apple ID** (Settings → App Store) | ☐ |
| 3 | Fresh install — or nuke container in Settings → General → Transfer or Reset | ☐ |
| 4 | Pro purchased via sandbox (or `--isPro` launch arg for unit-gate checks) | ☐ |
| 5 | Background App Refresh ON (Settings → General → Background App Refresh) | ☐ |
| 6 | iCloud Drive ON for cloud-sync tests | ☐ |

---

## 1 — Folder Organization

### 1a. Creating Folders

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| F1 | Tap "New Folder" (Pro gate)  | Folder creation sheet appears immediately | ☐ | |
| F2 | Type a name → Save | Folder appears in Library grid/list | ☐ | |
| F3 | Long name (>80 chars) | Name is truncated gracefully, no crash | ☐ | |
| F4 | Emoji in folder name | Folder created, emoji renders in grid | ☐ | |
| F5 | Duplicate folder name | Second folder created (UUID-keyed, no error) | ☐ | |

### 1b. Moving Documents

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| F6 | Drag-and-drop doc → folder | Doc moves; source folder count decrements | ☐ | **Watch:** "file vanishing" — doc absent from both |
| F7 | Move via context menu → Move to → [folder] | Doc moves immediately, list refreshes | ☐ | |
| F8 | Move doc A→B, then B→C | Doc appears only in C | ☐ | |
| F9 | Move last doc out of folder | Folder shows "Empty" state, not a crash | ☐ | |
| F10 | Background the app mid-drag, foreground | No orphaned state; doc remains in source | ☐ | |

### 1c. State Persistence

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| F11 | Move doc, force-quit, reopen | Doc still in destination folder | ☐ | |
| F12 | Move doc, kill app, restore from iCloud | Folder assignment preserved in cloud | ☐ | |
| F13 | Rename folder, background app, foreground | New name displayed correctly | ☐ | |

### 1d. Paywall Guard (Free User)

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| F14 | Log out Pro → tap "New Folder" | Paywall/Upsell sheet appears, no folder created | ☐ | |
| F15 | Paywall dismiss | Library unchanged | ☐ | |

---

## 2 — AI Smart File Naming

### 2a. Name Suggestion Quality

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| A1 | Scan a printed invoice | Suggested name includes "Invoice" or supplier name | ☐ | **Watch:** generic "Scan_MMM_YYYY" despite OCR success |
| A2 | Scan a business card | Suggested name includes person or company name | ☐ | |
| A3 | Scan a blank page | Falls back to "Scan_MMM_YYYY", no crash | ☐ | |
| A4 | Scan handwritten note | OCR may be partial; name must still be non-empty | ☐ | |

### 2b. Filename Sanitization

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| A5 | Document first line contains `:` or `/` | Suggested filename has `_` in place of illegal chars | ☐ | |
| A6 | Document first line is >30 chars | Name is truncated to 30 chars + `_MMM_YYYY` | ☐ | |
| A7 | Document first line is all punctuation | Falls back to `Scan_MMM_YYYY` | ☐ | |
| A8 | Accept suggested name → save → re-open | File saved under the suggested name in Library | ☐ | |
| A9 | Edit the suggested name before saving | Custom name persists; no crash | ☐ | |

### 2c. UI Responsiveness During "Thinking" State

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| A10 | OCR running on a dense page | Activity indicator visible within 0.5 s | ☐ | |
| A11 | During OCR: scroll Library, tap other buttons | App remains responsive (no UI freeze) | ☐ | |
| A12 | Kill OCR task (background app) | No crash; partial OCR result or "Scan_MMM_YYYY" on return | ☐ | |
| A13 | Run on iPhone with 2 GB RAM | No memory warning; OCR completes | ☐ | |

### 2d. Paywall Guard

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| A14 | Free user taps "Suggest Name" | Paywall appears | ☐ | |

---

## 3 — iOS Home Screen Widgets

### 3a. Timeline Refresh

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| W1 | Scan a new document | Widget updates within 15 min (WidgetKit budget) | ☐ | **Watch:** widget shows "No Data" after app closes |
| W2 | Force widget refresh (hold widget → Edit) | Widget shows current 3 most-recent scans | ☐ | |
| W3 | Delete the most recent document | Widget refreshes, shows next document | ☐ | |
| W4 | Rename a document in-app | Widget name updates on next refresh | ☐ | |

### 3b. Deep Link

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| W5 | Tap document thumbnail in widget | App opens and navigates to that document | ☐ | |
| W6 | Tap widget while app is suspended | Cold launch → correct document | ☐ | |
| W7 | Tap widget to a document that was deleted | App opens Library (graceful fallback, no crash) | ☐ | |

### 3c. Privacy (Sensitive Filenames)

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| W8 | Lock device → view widget from lock screen | Widget visible per user's privacy setting | ☐ | |
| W9 | Password-protected document appears in recent 3 | Widget shows title but no thumbnail (or blurred thumbnail) | ☐ | |

### 3d. Paywall Guard

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| W10 | Free user views widget settings | "Pro only" badge or upsell prompt | ☐ | |

---

## 4 — Password Protection

### 4a. Locking a Document

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| P1 | Tap "Lock" on a document | Password-set sheet appears | ☐ | |
| P2 | Set a 6-digit PIN | Document marked with lock icon in Library | ☐ | |
| P3 | Set a long passphrase (20 chars) | Accepted; lock icon visible | ☐ | |
| P4 | Leave password empty → confirm | Error: "Password cannot be empty" | ☐ | |
| P5 | Passwords don't match → confirm | Error: "Passwords do not match" | ☐ | |

### 4b. Immediate Lockout on App-Switch

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| P6 | Open locked doc → switch to another app | **Blur/placeholder appears immediately** on app switch | ☐ | **Critical: no "sneak peek"** |
| P7 | Return to app from App Switcher | Password prompt shown before content is visible | ☐ | |
| P8 | Return to app via icon (not Switcher) | Same: password prompt before content | ☐ | |
| P9 | Correct password entered | Document opens | ☐ | |
| P10 | Wrong password entered | Error message; document remains locked | ☐ | |
| P11 | Open a different (unlocked) doc, switch app, return | No password prompt for unlocked doc | ☐ | |

### 4c. App Switcher Blur

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| P12 | With locked doc open, double-press Home / swipe up | App Switcher shows blur/splash, NOT document content | ☐ | **Top security priority** |
| P13 | With Library open (no locked doc visible), double-press Home | Library thumbnail visible (not blurred — non-sensitive) | ☐ | |

### 4d. FaceID / TouchID Fallback

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| P14 | Enable FaceID for document unlock | Biometric prompt appears before PIN sheet | ☐ | |
| P15 | FaceID success | Document unlocks without PIN | ☐ | |
| P16 | FaceID failure (wrong face) | Falls back to PIN entry | ☐ | |
| P17 | FaceID not enrolled (simulator) | Falls back directly to PIN | ☐ | |
| P18 | Cancel FaceID prompt | Document stays locked | ☐ | |

### 4e. Paywall Guard

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| P19 | Free user taps "Lock" | Paywall appears | ☐ | |

---

## 5 — Cloud Export (Google Drive / Dropbox)

### 5a. OAuth2 Flow

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| C1 | Tap "Export to Drive" (first time) | OAuth2 sign-in sheet appears | ☐ | |
| C2 | Complete OAuth2 sign-in | Token stored; export begins | ☐ | |
| C3 | Revoke app access in Google settings, then export | App detects 401, prompts re-auth (not silent failure) | ☐ | **Watch: silent 401** |
| C4 | Token expired (simulate 24h later) | Refresh token used automatically; upload proceeds | ☐ | |
| C5 | Cancel OAuth2 mid-flow | Upload cancelled; no crash | ☐ | |

### 5b. Progress Bar Accuracy

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| C6 | Export a 1 MB PDF | Progress bar advances smoothly 0–100% | ☐ | **Watch: bar jumps to 100% instantly** |
| C7 | Export a 20 MB PDF | Progress bar accurately reflects upload progress | ☐ | |
| C8 | Throttle network to 3G (dev tools) | Progress bar slows proportionally | ☐ | |
| C9 | Kill network mid-upload | Error toast shown; no partial silent upload | ☐ | |

### 5c. File Integrity (Checksum Validation)

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| C10 | Export 1-page PDF → download from Drive → compare | SHA-256 of uploaded file = SHA-256 of local file | ☐ | |
| C11 | Export 5-page PDF → download → compare | SHA-256 matches; page count intact | ☐ | |
| C12 | Export with special chars in name (`:`, `/`) | Filename sanitized on Drive (no upload error) | ☐ | |
| C13 | Export same file twice | Drive creates two distinct files (UUID-named or version-suffixed) | ☐ | |

### 5d. Paywall Guard

| # | Test | Expected | Result | Notes |
|---|------|----------|--------|-------|
| C14 | Free user taps "Drive" or "Dropbox" | Paywall appears | ☐ | |

---

## 6 — Haptics & Loading States

| # | Feature | Expected Haptic / State | Result | Notes |
|---|---------|------------------------|--------|-------|
| H1 | Scan limit approaching (4/5 used) | Medium impact haptic on the 4th scan | ☐ | |
| H2 | Scan limit hit (5/5) | Strong impact or notification haptic | ☐ | |
| H3 | Purchase completes | Success haptic + confetti/animation | ☐ | |
| H4 | FaceID unlock success | Light haptic | ☐ | |
| H5 | FaceID unlock failure | Error haptic (double-tap feel) | ☐ | |
| H6 | Drag-and-drop doc released into folder | Light selection haptic on drop | ☐ | |
| H7 | StoreKit products loading | Skeleton placeholders shown (not empty sheet) | ☐ | |
| H8 | iCloud sync in progress | Progress indicator visible | ☐ | |
| H9 | OCR "Thinking" state | Spinner + "Analysing…" label shown | ☐ | |
| H10 | Export complete | Toast / banner "Uploaded to Drive" | ☐ | |

---

## Sign-off

| Role | Name | Date | Signed |
|------|------|------|--------|
| QA Engineer | | | |
| iOS Developer | | | |
| Product Manager | | | |
