# Settings sidebar implementation plan

**Goal:** Give settings a native macOS sidebar and detail layout that accommodates additional categories.

**Architecture:** NavigationSplitView hosts a selectable category list and independent detail views. General contains the existing language form. SettingsCategory owns stable identifiers, titles, and icons; an exhaustive detail switch routes each category to its page.

**Constraints:** Keep the existing settings menu, Command-comma shortcut, first-run language selection, and saved preferences. Show only the implemented General category. Use native controls and translated titles. Default window size is 760 × 480 points, with a 680 × 420 minimum.

- [x] Split settings into sidebar navigation and GeneralSettingsView.
- [x] Configure window sizing and translate General in English and Simplified Chinese.
- [x] Build, run language regression tests, check resources, and inspect the installed settings layout where UI access is available.

Validation: Release build and seven language regression tests passed. Native UI and screenshots confirmed the selected General category, separate language detail pane, no collapse button, and immediate Chinese/English title and content updates. Both resource catalogs contain 1,030 matching keys.
