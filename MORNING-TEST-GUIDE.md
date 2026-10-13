# Parcel — Morning Test Guide (2026-10-14)

Branch: `feature/shelf-share-licensing` · 5 new commits on top of `a212670`

## Setup

```bash
cd ~/FirstVentures/parcel
git pull origin feature/shelf-share-licensing
bash Scripts/build-macos.sh
open build/Parcel.app
```

## What's new to test

### 1. Pinnable items + self-cleaning shelf
- Right-click any item → **Pin**. A pin badge appears in the row.
- `⌥⌘P` pins/unpins all selected items.
- Preferences → **"Self-cleaning shelf"** (on by default): unpinned items older than 24h clear on launch. Pinned items always survive.
- To verify: pin one item, leave one unpinned, quit, set the Mac clock forward a day (or wait), relaunch — only the pinned one remains.

### 2. Clipboard history
- Click **Clipboard** in the workbench header.
- Copy some text or an image anywhere — it appears in the panel.
- Search, pin, re-copy on tap. Password-manager apps are never watched.
- Toggle "Watch clipboard" off/on.

### 3. Quick-action bar
- Strip under the header: **Pack**, **AirDrop**, **Copy link**, **Contents**.
- One click each, no dialogs. Hover states + tooltips.

### 4. Pack profiles (recipes)
- Inspector → Pack section → bookmark icon: **save current settings as a recipe**.
- Switch recipes from the "Saved recipes" menu. Delete from the manage view.

### 5. UI polish
- Items animate in/out with a spring when added/removed.
- Empty state mentions pinning + self-cleaning.

## Regression checklist (core still intact)
- [ ] Drop popup appears on drag, no visual errors
- [ ] Gather → Prepare → Pack → Send flow works end to end
- [ ] OCR "Copy text from images" in Prepare sheet
- [ ] "Copy Contents" on text files
- [ ] ZIP / 7z / RAR packing
- [ ] Sidebar + in-parcel search
- [ ] Menu-bar and Dock menus
- [ ] Reduce Motion respected

## If something breaks
Each feature is its own commit — `git log --oneline` shows them. Revert one with:
```bash
git revert <commit-hash>
bash Scripts/build-macos.sh
```
