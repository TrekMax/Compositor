# Tool name hover hints

Approved in conversation: show a tool's localized name and shortcut to the right after 0.5 seconds of hovering. Hide on exit or click. General settings contain an enabled toggle (default on) and delay from 0 to 3 seconds. Changes apply immediately and persist across launches.

Use an AppKit tracking view behind each tool button and a nonactivating, mouse-transparent tooltip panel to escape the tool rail's scroll clipping. Preserve the SwiftUI button's click target and accessibility label; replace only its system help tooltip. Cancel pending work on exit, click, scrolling, window deactivation, and view removal. Changing preferences cancels/restarts the current wait. Use the existing language bundle for presentation text.

Preferences belong in UserDefaults, not project documents. Validate delay values on load and save. Test persistence and bounds, delayed appearance and cancellation, settings changes while hovering, and pass-through hit testing. Build and inspect the settings panel and tooltip integration.
