# ScanHonest — Branch Strategy

## Branch Map

| Branch | Contents | Purpose |
|--------|----------|---------|
| `main` | Swift source only | Architecture-level code for GitHub — what collaborators/reviewers see |
| `design` | `Design/` folder | HTML + JSX design files, Figma exports (1.4 MB+) |
| `testing` | `ScanHonestTests/` + `ScanHonestUITests/` | Unit tests + UI automation tests |

## Why separate branches?

- **`main` stays lean** — only production Swift architecture lives here. No 1.25 MB HTML files, no test noise.
- **`design` branch** — design files are large and change at a different cadence to code. Keeping them separate means `git clone` of `main` is fast and clean.
- **`testing` branch** — test targets can be reviewed/run independently of shipping code.

---

## What lives on `main`

```
ScanHonest/           ← all production Swift source
ScanHonestWidget/     ← home screen widget target
ScanHonest.xcodeproj/ ← Xcode project file
.gitignore
README.md
MANUAL_QA_CHECKLIST.md
SECURITY_AUDIT.md
```

## What lives on `design`

```
Design/
  ├── ScanHonest.html           (full design spec)
  ├── ScanHonest-Components.html
  ├── ScanHonest-Icon.html
  ├── screens.jsx
  ├── design-canvas.jsx
  └── ios-frame.jsx
```

## What lives on `testing`

```
ScanHonestTests/
  ├── ChecksumIntegrityTests.swift
  ├── FileNamingTests.swift
  ├── FolderOperationsTests.swift
  ├── PasswordProtectionTests.swift
  ├── ScanLimitManagerTests.swift
  ├── ScannedDocumentTests.swift
  ├── StorageManagerTests.swift
  ├── StoreKitManagerTests.swift
  └── SubscriptionAccessControlTests.swift

ScanHonestUITests/
  ├── DocumentDetailUITests.swift
  ├── LibraryUITests.swift
  ├── OnboardingUITests.swift
  ├── PaywallUITests.swift
  ├── ScanReviewUITests.swift
  ├── SettingsUITests.swift
  ├── ShareSheet10BUITests.swift
  └── UITestHelpers.swift
```

---

## Setup (run once)

```bash
bash setup-branches.sh
```

Then push all branches to GitHub:

```bash
git push origin main design testing
```

---

## Day-to-day workflow

```bash
# Working on app code → always on main
git checkout main

# Working on design files → switch to design
git checkout design

# Running / updating tests → switch to testing
git checkout testing
```
