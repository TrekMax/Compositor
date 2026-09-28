import AppKit

/// SwiftUI's built-in menu headings and AppKit commands do not inherit the editor's locale.
/// Limit changes to known system items; recent file names and document titles remain verbatim.
final class NativeMenuLocalization: NSObject {
    private var refreshScheduled = false
    func install() {
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAfterUpdate),
                                               name: .applicationLanguageDidChange, object: nil)
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(refreshAfterUpdate), name: name, object: nil)
        }
        refresh()
    }

    @objc private func refreshAfterUpdate() {
        // Let SwiftUI finish rebuilding its command menus first.
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    @objc private func refresh() {
        guard let menu = NSApp.mainMenu else { return }
        let headings = ["File", "Edit", "View", "Window", "Help"]
        for item in menu.items {
            if let key = headings.first(where: { key in
                item.title == key || item.title == L10n.text(key, language: .simplifiedChinese)
            }) {
                let title = L10n.text(key)
                if item.title != title { item.title = title }
                if item.submenu?.title != title { item.submenu?.title = title }
            }
            if let submenu = item.submenu { refreshSystemCommands(submenu) }
        }
    }

    private func refreshSystemCommands(_ menu: NSMenu) {
        let titles = ["orderFrontStandardAboutPanel:": "About Compositor", "terminate:": "Quit Compositor",
                      "performMiniaturize:": "Minimize", "performZoom:": "Zoom",
                      "arrangeInFront:": "Bring All to Front"]
        for item in menu.items {
            if let action = item.action, let key = titles[NSStringFromSelector(action)] {
                let title = L10n.text(key)
                if item.title != title { item.title = title }
            }
        }
    }
}
