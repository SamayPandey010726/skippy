# Skippy for Mac — acceptance results

GitHub’s macOS runner built and launched commit `4e520100d700`. All 188 native tests passed. The running application passed 89 UI checks across the global shortcut, keyboard finder, 18 arrows, floating strip and system menu bar. The device job booted an iPhone and iPad simulator. [Mac and simulator run](https://github.com/SamayPandey010726/parcel/actions/runs/44523641724)

## Motion and packaging

ScreenCaptureKit recorded the Mac display with normal motion enabled. During the first reveal, the recording contained 10 distinct measured backplate widths between 37 and 151 pixels. The outer edge varied by 0 pixels across those measurements. TextEdit retained foreground focus during the preview. [Mac recording](recordings/Skippy.mp4)

The developer bundle passed strict code-signature verification on macOS. A separate archive check validated both Mach-O slices (Apple silicon and Intel), the macOS 14 minimum and ZIP integrity. The website passed eight browser tests and the licensing tool passed five tests.

## Running-app checks

- Hovering preserved foreground application
- Accessibility can exercise UI controls
- Global shortcut opens dashboard
- Finder opens over dashboard
- Down and Return select the second matching tool
- Finder reopens over calculator
- Finder explains an empty result
- Escape cancels search and preserves the current tool
- Finder accepts keyboard focus
- Open File Shelf
- Files opened into shelf
- Finder accepts keyboard focus
- Open Clipboard
- Capture clipboard change
- Recall a filtered clipboard entry
- Clipboard restores the selected contents
- Finder accepts keyboard focus
- Open Extract text
- Run Vision from clipboard
- OCR writes expected words
- Finder accepts keyboard focus
- Open Pick colour
- Open system pixel sampler
- Sample actual screen pixel into pasteboard
- Finder accepts keyboard focus
- Open Timer
- Start timer
- Stop active countdown
- Timer returns to start
- Finder accepts keyboard focus
- Open Notes
- Copy edited note
- Note contains literal slash
- Finder accepts keyboard focus
- Open QR tools
- Copy generated QR
- Pasteboard contains generated image
- Finder accepts keyboard focus
- Open Search
- Edit web query
- Finder accepts keyboard focus
- Open Apps
- List running Finder
- Finder accepts keyboard focus
- Open Music
- Local playback picker available
- Finder accepts keyboard focus
- Open Downloads
- Recent download fixture
- Finder accepts keyboard focus
- Open Stay awake
- Acquire sleep assertion
- Release sleep assertion
- Finder accepts keyboard focus
- Open Recent actions
- Recent activity or empty state
- Finder accepts keyboard focus
- Open Mac
- Read real operating system version
- Finder accepts keyboard focus
- Open Calendar
- Fresh calendar account has a connect action
- Finder accepts keyboard focus
- Open Calculator
- Copy calculated result
- Calculator produced 16
- Finder accepts keyboard focus
- Open Screenshots
- Empty capture sequence
- Start screen region capture
- Region appears in sequence
- Copy joined regions
- Joined region on pasteboard
- Clear capture sequence
- Finder accepts keyboard focus
- Open Draw on screen
- Open drawing overlay
- Drawing toolbar
- Stroke enables undo
- Undo stroke
- Undo clears last stroke
- Close drawing overlay
- Summon again after leaving drawing
- Escape dismisses the final tool
- Real menu-bar item is exposed
- Status item expands on hover
- Hovering menu-bar shelf opens it
- Menu-bar preview survives pointer handoff
- Leaving both surfaces dismisses preview and releases menu space

## Coverage limits

This run checked Calendar on a fresh account and the local Music controls. Populated personal calendars, signed-in third-party players, audible playback, physical camera notches, Dock magnification and real external displays require separate hands-on acceptance. Simulator screenshots show device startup. The source currently has a macOS application target.

The 18 images in the gallery came from the packaged Mac app. [Arrow gallery](Skippy-arrows.jpg) · [Per-tool checks and competitor observations](SKIPPY-INTERACTION-QA.md)
