# NixClaw Development Guide

## Build Pipeline

NixClaw uses a self-hosted GitHub Actions runner on Mac Mini for wireless deployment to iPhone.

### How It Works

```
Commit → GitHub Actions → Mac Mini Runner → xcodebuild → devicectl → iPhone
                                    (~30 seconds total)
```

### Key Components

| Component | Location |
|-----------|----------|
| Workflow | `.github/workflows/build.yml` |
| Runner | Mac Mini (`arnabs-mac-mini.local`) |
| Project | `~/actions-runner/_work/NixClaw/NixClaw/` |
| Secrets | GitHub repo settings → Secrets |

### GitHub Secrets Required

| Secret | Purpose |
|--------|---------|
| `KEYCHAIN_PASSWORD` | Mac Mini login password (unlocks keychain for code signing) |
| `GEMINI_API_KEY` | Gemini API key for the build |
| `OPENCLAW_TOKEN` | Gateway auth token |

### Triggering Builds

Builds trigger automatically on push to `main`. Manual trigger:

```bash
gh workflow run build.yml --ref main
gh run watch --exit-status
```

---

## Adding New Swift Files

⚠️ **CRITICAL**: Just creating a `.swift` file is NOT enough. You MUST update `project.pbxproj`.

### The Problem

Xcode projects don't auto-discover files. Each file needs:
1. **PBXFileReference** — declares the file exists
2. **PBXBuildFile** — includes it in compilation  
3. **PBXGroup** — adds it to a folder in Project Navigator
4. **PBXSourcesBuildPhase** — adds it to the target's Sources

### Option 1: Use Xcode (Recommended)

1. Open `NixClaw.xcodeproj` in Xcode
2. Right-click the target folder → "Add Files to NixClaw..."
3. Select your new `.swift` file
4. Ensure "Add to targets: NixClaw" is checked
5. Commit both the `.swift` file AND `project.pbxproj`

### Option 2: Script (Remote/Headless)

Use the Python script at `/home/Arnab/clawd/scripts/add-swift-file.py`:

```bash
python3 ~/clawd/scripts/add-swift-file.py \
  NixClaw.xcodeproj/project.pbxproj \
  --file CaptureFlashView.swift \
  --group Components \
  --target NixClaw
```

### Option 3: Manual Edit (Last Resort)

Generate unique 24-char UUIDs (e.g., `CAPT01E2F0B0001000000001`).

Add 4 entries to `project.pbxproj`:

```
/* 1. PBXBuildFile section */
UUID2 /* File.swift in Sources */ = {isa = PBXBuildFile; fileRef = UUID1 /* File.swift */; };

/* 2. PBXFileReference section */
UUID1 /* File.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = File.swift; sourceTree = "<group>"; };

/* 3. In the target PBXGroup's children array */
UUID1 /* File.swift */,

/* 4. In PBXSourcesBuildPhase files array */
UUID2 /* File.swift in Sources */,
```

**⚠️ UUID MUST BE UNIQUE** — reusing existing UUIDs corrupts the project.

---

## Common Issues

### "Project is damaged and cannot be opened"

**Cause**: Duplicate UUIDs in `project.pbxproj`

**Fix**: 
```bash
git checkout HEAD~1 -- NixClaw.xcodeproj/project.pbxproj
```

### "cannot find 'X' in scope"

**Cause**: Swift file exists but isn't in `project.pbxproj`

**Fix**: Add the file properly (see above)

### Build passes but install fails

**Cause**: The workflow has `|| tail -50` which masks build failures

**Check**: Look for `** BUILD FAILED **` in the logs:
```bash
gh run view <run-id> --log | grep "BUILD FAILED"
```

### Code signing fails (errSecInternalComponent)

**Cause**: Keychain is locked

**Fix**: Ensure `KEYCHAIN_PASSWORD` secret is set and the "Unlock Keychain" step runs first

### Swift packages fail to resolve

**Cause**: Network issue or corrupted package cache

**Fix**: 
```bash
ssh arnabmac@arnabs-mac-mini.local "cd ~/projects/NixClaw && rm -rf ~/Library/Developer/Xcode/DerivedData/NixClaw-*"
```

---

## Project Structure

```
NixClaw/
├── Config/              # App configuration
│   ├── AppConfig.swift
│   ├── SetupWizardView.swift
│   └── SettingsView.swift
├── Gemini/              # Gemini Live integration
│   ├── GeminiConfig.swift
│   ├── GeminiLiveService.swift
│   ├── AudioManager.swift
│   └── GeminiSessionViewModel.swift
├── OpenClaw/            # OpenClaw bridge
│   ├── OpenClawBridge.swift
│   ├── ToolCallModels.swift
│   └── ToolCallRouter.swift
├── Views/               # UI
│   ├── StreamView.swift
│   ├── NonStreamView.swift
│   └── Components/
│       ├── CircleButton.swift
│       ├── CustomButton.swift
│       ├── CaptureFlashView.swift  ← NEW
│       └── ...
├── Background/          # Background mode
│   ├── BackgroundModeManager.swift
│   └── GeminiLiveActivity.swift
└── iPhone/              # iPhone camera
    └── IPhoneCameraManager.swift
```

---

## Testing Locally

### On Mac Mini

```bash
ssh arnabmac@arnabs-mac-mini.local
cd ~/projects/NixClaw
git pull
xcodebuild build -project NixClaw.xcodeproj -scheme NixClaw -destination 'generic/platform=iOS'
```

### Deploy to iPhone

```bash
xcrun devicectl device install app --device <DEVICE_ID> build/Debug-iphoneos/NixClaw.app
```

Find device ID:
```bash
xcrun devicectl list devices
```

---

## Useful Commands

```bash
# Watch latest workflow run
cd ~/clawd/projects/nix-claw && gh run watch --exit-status

# Check runner status
ssh arnabmac@arnabs-mac-mini.local "cd ~/actions-runner && ./svc.sh status"

# View build logs
gh run view <run-id> --log | less

# List recent runs
gh run list --workflow=build.yml --limit 5
```

---

## Lessons Learned

1. **Always update `project.pbxproj`** when adding Swift files
2. **UUIDs must be unique** — check with `grep` before using
3. **The workflow masks failures** — always check for `BUILD FAILED` in logs
4. **Keychain must be unlocked** before code signing
5. **Branch protection allows admin bypass** — direct pushes work but show warnings
