# Parcel — Test Guide (Shreyash direction, 2026-10-14)

Branch: `feature/shelf-share-licensing` · Head: `2318ffc`

**New product identity:** Parcel is a living file shelf. Put files down → navigate → pick up. NOT gather → prepare → pack → share.

## Setup

```bash
cd ~/FirstVentures/parcel
git pull origin feature/shelf-share-licensing
bash Scripts/build-macos.sh
open build/Parcel.app
```

## What's new to test

### 1. Cuts (verify they're gone)
- No pack profiles / recipes anywhere (inspector has no recipe picker)
- No Clipboard button, panel, or menu
- No "Copy link" in the quick-action bar
- Manifest defaults OFF (Preferences → "Include a readable contents list" unchecked)

### 2. Skin system
- Preferences → **Shelf skin**: Kraft Courier / Night Messenger / Moss Courier
- Switch skins — the drop popup changes palette, layout stays identical
- Quit + relaunch — skin persists

### 3. Drop popup (the shelf)
- Drag a file → popup springs in (scale + fade)
- Drop lands → illustration bounces
- Copy reads "Give your files somewhere delightful to wait"
- Skin palette applies to the popup

### 4. Inspector
- "Pack with care" is now "Pack as ZIP" with a shelf-first note

## Regression checklist (core shelf still works)
- [ ] Drop popup appears on drag, no visual errors
- [ ] Drag files in/out of the shelf
- [ ] Pin items (⌥⌘P), self-cleaning clears unpinned after 24h
- [ ] Quick Look, reorder, remove
- [ ] Basic ZIP pack still works
- [ ] Sidebar, search, menu-bar + Dock menus
- [ ] Reduce Motion respected

## If something breaks
Each feature is its own commit — `git log --oneline` shows them. Revert one with:
```bash
git revert <commit-hash>
bash Scripts/build-macos.sh
```
