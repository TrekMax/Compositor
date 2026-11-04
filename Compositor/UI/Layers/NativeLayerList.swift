import AppKit
import SwiftUI

/// Native mouse-down selection and drag tracking, without a double-click delay.
struct NativeLayerList: NSViewRepresentable {
    @Environment(\.locale) private var locale
    let session: EditorSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = LayerTableView()
        table.session = session
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .plain
        table.rowHeight = 52
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layer"))
        column.width = 252
        table.addTableColumn(column)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.renameClickedLayer(_:))
        table.action = #selector(Coordinator.clickedLayer(_:))
        table.registerForDraggedTypes([Coordinator.layerType, Coordinator.maskType, Coordinator.effectType])
        table.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        table.setAccessibilityIdentifier("layersList")
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        context.coordinator.update(table)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        _ = locale
        if let table = scroll.documentView as? NSTableView { context.coordinator.update(table) }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
        static let layerType = NSPasteboard.PasteboardType("com.compositor.layer-row")
        /// An Option-drag from a mask thumbnail: the id of the layer whose mask is being copied.
        static let effectType = NSPasteboard.PasteboardType("com.compositor.layer-effect")
        static let maskType = NSPasteboard.PasteboardType("com.compositor.layer-mask")
        let session: EditorSession
        var rows: [ImageLayer] = []
        private var rowDetails: [UUID: LayerHierarchy.Entry] = [:]
        private var oldCollapsed: Set<UUID> = []
        private var language: AppLanguage?
        private var editingEnabled = false
        private var synchronizing = false
        private var activeLayerID: UUID?
        init(session: EditorSession) { self.session = session }

        func update(_ table: NSTableView) {
            let selectionChanged = activeLayerID != session.activeLayerID
            activeLayerID = session.activeLayerID
            // The panel's search and type filter narrow what is listed; every row index below is one of these.
            let entries = session.filteredLayerRows
            let byID = Dictionary(uniqueKeysWithValues: (session.document?.layers ?? []).map { ($0.id, $0) })
            let next = entries.compactMap { byID[$0.layer.id] }
            let previousDetails = rowDetails
            rowDetails = Dictionary(uniqueKeysWithValues: entries.map { ($0.layer.id, $0) })
            let languageChanged = language != LanguageSettings.shared.selection
            language = LanguageSettings.shared.selection
            let expansionChanged = oldCollapsed != session.collapsedGroupIDs
            oldCollapsed = session.collapsedGroupIDs
            let enabled = session.layersLookEditable
            synchronizing = true
            defer { synchronizing = false }
            let old = rows
            rows = next
            let editableChanged = editingEnabled != enabled
            editingEnabled = enabled
            if old.map(\.id) != next.map(\.id) {
                table.reloadData()
            } else {
                // Selection never reloads cells or recreates thumbnails. A depth change can keep the very same picture
                // (Convert to 16-Bit on an 8-bit layer), so its tag is compared too.
                let changed = IndexSet(next.indices.filter {
                    languageChanged || editableChanged || expansionChanged || (old[$0].name != next[$0].name || old[$0].isVisible != next[$0].isVisible || old[$0].size != next[$0].size || old[$0].parentID != next[$0].parentID || old[$0].isGroup != next[$0].isGroup || old[$0].asset?.image !== next[$0].asset?.image || old[$0].depthLabel != next[$0].depthLabel || (old[$0].liveText != nil) != (next[$0].liveText != nil) || old[$0].effects != next[$0].effects || old[$0].mask != next[$0].mask || old[$0].maskSourceID != next[$0].maskSourceID) || previousDetails[next[$0].id]?.depth != rowDetails[next[$0].id]?.depth || previousDetails[next[$0].id]?.visible != rowDetails[next[$0].id]?.visible
                })
                let resized = IndexSet(next.indices.filter { (old[$0].effects?.kinds.count ?? 0) != (next[$0].effects?.kinds.count ?? 0) })
                // Adding or removing an effect only changes how tall a row is. Left to AppKit that is animated, and
                // the row appears to be taken away and put back; here it simply becomes its new height.
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0
                if !resized.isEmpty { table.noteHeightOfRows(withIndexesChanged: resized) }
                if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0)) }
                NSAnimationContext.endGrouping()
            }
            let indices = IndexSet(next.indices.filter { session.selectedEffect == nil && session.selectedLayerIDs.contains(next[$0].id) })
            if table.selectedRowIndexes != indices { table.selectRowIndexes(indices, byExtendingSelection: false) }
            // Reveal a newly selected layer, without undoing a manual scroll on later display updates.
            if selectionChanged, let id = activeLayerID, let row = next.firstIndex(where: { $0.id == id }) {
                table.scrollRowToVisible(row)
            }
            // Border-only updates: selecting a target never rebuilds thumbnails or canvas pixels.
            let visible = table.rows(in: table.visibleRect)
            if visible.location != NSNotFound {
                for row in visible.location..<min(next.count, NSMaxRange(visible)) {
                    (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? LayerCell)?.updateTarget()
                }
            }
            // A rename — double-click, the row's menu, or the Layer menu — is typed in the row itself.
            if let id = session.renamingLayerID, let row = next.firstIndex(where: { $0.id == id }) {
                table.scrollRowToVisible(row)
                DispatchQueue.main.async {
                    (table.view(atColumn: 0, row: row, makeIfNecessary: true) as? LayerCell)?.beginRenaming()
                }
            }
        }

        func layer(for row: Int) -> ImageLayer? {
            guard rows.indices.contains(row) else { return nil }
            return rows[row]
        }

        func contextMenu(for row: Int) -> NSMenu? {
            guard rows.indices.contains(row) else { return nil }
            if session.selectedLayerIDs.isEmpty {
                session.selectLayer(rows[row].id)
            }
            let menu = NSMenu()

            // 1. Duplicate Layer
            let duplicateItem = NSMenuItem(title: L10n.text("Duplicate Layer"), action: #selector(duplicateLayerAction), keyEquivalent: "")
            duplicateItem.target = self
            duplicateItem.isEnabled = validateMenuItem(duplicateItem)
            menu.addItem(duplicateItem)

            // 2. Rename…
            let renameItem = NSMenuItem(title: L10n.text("Rename…"), action: #selector(renameLayerAction), keyEquivalent: "")
            renameItem.target = self
            renameItem.isEnabled = validateMenuItem(renameItem)
            menu.addItem(renameItem)

            // 3. Delete Layer / Delete Selected Layers
            let deleteTitle: String
            if session.isMaskSelected, let layer = session.activeLayer, session.selectedMask(for: layer) != nil {
                deleteTitle = "Delete Mask"
            } else if session.selectedLayerIDs.count > 1 {
                deleteTitle = "Delete Selected Layers"
            } else {
                deleteTitle = "Delete Layer"
            }
            let deleteItem = NSMenuItem(title: L10n.text(deleteTitle), action: #selector(deleteLayerAction), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.isEnabled = validateMenuItem(deleteItem)
            menu.addItem(deleteItem)

            menu.addItem(NSMenuItem.separator())

            // 4. Create Clipping Mask / Release Clipping Mask
            let clippingItem = NSMenuItem(title: L10n.text(session.selectedClippingTitle), action: #selector(toggleClippingMaskAction), keyEquivalent: "")
            clippingItem.target = self
            clippingItem.isEnabled = validateMenuItem(clippingItem)
            menu.addItem(clippingItem)

            // 5. Group Selected Layers
            let groupItem = NSMenuItem(title: L10n.text("Group Selected Layers"), action: #selector(groupSelectedLayersAction), keyEquivalent: "")
            groupItem.target = self
            groupItem.isEnabled = validateMenuItem(groupItem)
            menu.addItem(groupItem)

            // A folder right-clicked can be ungrouped: its layers stay where they are, and the folder goes.
            if rows[row].isGroup {
                let ungroupItem = NSMenuItem(title: L10n.text("Ungroup Layers"), action: #selector(ungroupLayersAction), keyEquivalent: "")
                ungroupItem.target = self
                ungroupItem.isEnabled = validateMenuItem(ungroupItem)
                menu.addItem(ungroupItem)
            }

            // 6. Move Out of Folder
            let moveOutItem = NSMenuItem(title: L10n.text("Move Out of Folder"), action: #selector(moveOutOfFolderAction), keyEquivalent: "")
            moveOutItem.target = self
            moveOutItem.isEnabled = validateMenuItem(moveOutItem)
            menu.addItem(moveOutItem)

            // 7. Merge Down / Merge Layers / Merge Group
            let mergeItem = NSMenuItem(title: L10n.text(session.mergeTitle), action: #selector(mergeLayersAction), keyEquivalent: "")
            mergeItem.target = self
            mergeItem.isEnabled = validateMenuItem(mergeItem)
            menu.addItem(mergeItem)

            // 7b. Convert to 16-Bit / Convert to 8-Bit: whichever would change a selected layer, both for a mix (an HDR
            // layer can go to 16 bits as well as to 8). Shown, greyed, for layers neither applies to.
            let sixteen = session.canConvertToSixteenBit, eight = session.canConvertToEightBit
            if sixteen || !eight {
                let sixteenItem = NSMenuItem(title: L10n.text("Convert to 16-Bit"), action: #selector(convertToSixteenBitAction), keyEquivalent: "")
                sixteenItem.target = self
                sixteenItem.isEnabled = validateMenuItem(sixteenItem)
                menu.addItem(sixteenItem)
            }
            if eight {
                let eightItem = NSMenuItem(title: L10n.text("Convert to 8-Bit"), action: #selector(convertToEightBitAction), keyEquivalent: "")
                eightItem.target = self
                eightItem.isEnabled = validateMenuItem(eightItem)
                menu.addItem(eightItem)
            }

            menu.addItem(NSMenuItem.separator())

            // 8. Add Mask >
            let addMaskItem = NSMenuItem(title: L10n.text("Add Mask"), action: nil, keyEquivalent: "")
            addMaskItem.identifier = NSUserInterfaceItemIdentifier("addMask")
            let addMaskSubmenu = NSMenu(title: L10n.text("Add Mask"))
            let revealAllItem = NSMenuItem(title: L10n.text("Reveal All (White)"), action: #selector(addWhiteMaskAction), keyEquivalent: "")
            revealAllItem.target = self
            revealAllItem.isEnabled = validateMenuItem(revealAllItem)
            addMaskSubmenu.addItem(revealAllItem)
            let hideAllItem = NSMenuItem(title: L10n.text("Hide All (Black)"), action: #selector(addBlackMaskAction), keyEquivalent: "")
            hideAllItem.target = self
            hideAllItem.isEnabled = validateMenuItem(hideAllItem)
            addMaskSubmenu.addItem(hideAllItem)
            addMaskItem.submenu = addMaskSubmenu
            addMaskItem.isEnabled = session.canEditMask && session.activeLayer?.mask == nil
            menu.addItem(addMaskItem)

            // 9. Enable Mask / Disable Mask
            let toggleMaskTitle = session.activeLayer?.mask?.isEnabled == false ? "Enable Mask" : "Disable Mask"
            let toggleMaskItem = NSMenuItem(title: L10n.text(toggleMaskTitle), action: #selector(toggleMaskAction), keyEquivalent: "")
            toggleMaskItem.target = self
            toggleMaskItem.isEnabled = validateMenuItem(toggleMaskItem)
            menu.addItem(toggleMaskItem)

            // 10. Delete Mask
            let deleteMaskItem = NSMenuItem(title: L10n.text("Delete Mask"), action: #selector(deleteMaskAction), keyEquivalent: "")
            deleteMaskItem.target = self
            deleteMaskItem.isEnabled = validateMenuItem(deleteMaskItem)
            menu.addItem(deleteMaskItem)

            // 11. Link Mask / Unlink Mask
            let linkMaskTitle = session.activeLayer?.mask?.isLinked == false ? "Link Mask" : "Unlink Mask"
            let linkMaskItem = NSMenuItem(title: L10n.text(linkMaskTitle), action: #selector(toggleMaskLinkAction), keyEquivalent: "")
            linkMaskItem.target = self
            linkMaskItem.isEnabled = validateMenuItem(linkMaskItem)
            menu.addItem(linkMaskItem)

            menu.addItem(NSMenuItem.separator())

            // 12. Hide Layer / Show Layer, or Layers with several selected
            let visibilityItem = NSMenuItem(title: L10n.text(session.visibilityTitle), action: #selector(toggleVisibilityAction), keyEquivalent: "")
            visibilityItem.target = self
            visibilityItem.isEnabled = validateMenuItem(visibilityItem)
            menu.addItem(visibilityItem)

            menu.addItem(NSMenuItem.separator())

            // 13. Export Layer as PNG… / Export Layers as PNGs…
            let exportTitle = session.selectedLayerIDs.count > 1 ? "Export Layers as PNGs…" : "Export Layer as PNG…"
            let exportItem = NSMenuItem(title: L10n.text(exportTitle), action: #selector(exportLayersAction), keyEquivalent: "")
            exportItem.target = self
            exportItem.isEnabled = validateMenuItem(exportItem)
            menu.addItem(exportItem)

            return menu
        }

        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            switch menuItem.action {
            case #selector(duplicateLayerAction):
                return session.canEditLayers && session.activeLayer != nil
            case #selector(renameLayerAction):
                return session.canEditLayers && session.activeLayer != nil && session.selectedLayerIDs.count == 1
            case #selector(deleteLayerAction):
                return session.canEditLayers && session.activeLayer != nil
            case #selector(toggleClippingMaskAction):
                return session.canToggleSelectedClipping
            case #selector(groupSelectedLayersAction):
                return session.canEditLayers && session.document != nil && (session.document?.layers.count ?? 0) < 10_000 && !session.selectedLayerIDs.isEmpty
            case #selector(ungroupLayersAction):
                return session.canUngroupLayers
            case #selector(moveOutOfFolderAction):
                return session.canEditLayers && session.activeLayer?.parentID != nil
            case #selector(mergeLayersAction):
                return session.canMergeLayers
            case #selector(convertToSixteenBitAction):
                return session.canConvertToSixteenBit
            case #selector(convertToEightBitAction):
                return session.canConvertToEightBit
            case #selector(addWhiteMaskAction), #selector(addBlackMaskAction):
                return session.canEditMask && session.activeLayer?.mask == nil
            case #selector(toggleMaskAction):
                return session.canEditMask && session.activeLayer?.mask != nil
            case #selector(deleteMaskAction):
                return session.canEditMask && session.activeLayer?.mask != nil
            case #selector(toggleMaskLinkAction):
                return session.canEditLayers && session.activeLayer?.mask != nil && session.activeLayer?.isGroup == false && session.activeLayer?.adjustment == nil
            case #selector(toggleVisibilityAction):
                return session.canEditLayers && session.activeLayer != nil
            case #selector(exportLayersAction):
                return session.canStartProjectOperation && session.activeLayer != nil && session.exportsLayers != nil
            default:
                if menuItem.submenu != nil && menuItem.identifier?.rawValue == "addMask" {
                    return session.canEditMask && session.activeLayer?.mask == nil
                }
                return true
            }
        }

        @objc func exportLayersAction(_ sender: Any?) {
            guard let export = session.exportsLayers else { return }
            Task { await export() }
        }

        @objc func duplicateLayerAction(_ sender: Any?) {
            session.duplicateActiveLayer()
        }

        @objc func renameLayerAction(_ sender: Any?) {
            guard session.canEditLayers, let id = session.activeLayerID else { return }
            session.renamingLayerID = id
        }

        @objc func deleteLayerAction(_ sender: Any?) {
            session.deleteLayerOrMask()
        }

        @objc func toggleClippingMaskAction(_ sender: Any?) {
            session.toggleSelectedClipping()
        }

        @objc func groupSelectedLayersAction(_ sender: Any?) {
            session.groupSelectedLayers()
        }

        @objc func ungroupLayersAction(_ sender: Any?) {
            session.ungroupLayers()
        }

        @objc func moveOutOfFolderAction(_ sender: Any?) {
            session.moveActiveLayerOutOfGroup()
        }

        @objc func mergeLayersAction(_ sender: Any?) {
            session.mergeLayers()
        }

        @objc func convertToSixteenBitAction(_ sender: Any?) {
            session.convertLayers(toSixteenBit: true)
        }

        @objc func convertToEightBitAction(_ sender: Any?) {
            session.convertLayers(toSixteenBit: false)
        }

        @objc func addWhiteMaskAction(_ sender: Any?) {
            guard let id = session.activeLayerID else { return }
            session.selectLayerTarget(id, mask: false)
            session.addMask(revealing: true)
        }

        @objc func addBlackMaskAction(_ sender: Any?) {
            guard let id = session.activeLayerID else { return }
            session.selectLayerTarget(id, mask: false)
            session.addMask(revealing: false)
        }

        @objc func toggleMaskAction(_ sender: Any?) {
            guard let id = session.activeLayerID else { return }
            session.selectLayerTarget(id, mask: false)
            session.toggleLayerMask()
        }

        @objc func deleteMaskAction(_ sender: Any?) {
            guard let id = session.activeLayerID else { return }
            session.selectLayerTarget(id, mask: false)
            session.deleteLayerMask()
        }

        @objc func toggleMaskLinkAction(_ sender: Any?) {
            if let id = session.activeLayerID { session.toggleMaskLink(id) }
        }

        @objc func toggleVisibilityAction(_ sender: Any?) {
            session.toggleSelectedLayersVisibility()
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            52 + CGFloat(rows[row].effects?.kinds.count ?? 0) * 24
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("layerCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? LayerCell ?? LayerCell()
            cell.identifier = identifier
            cell.configure(rows[row], enabled: editingEnabled, session: session, depth: rowDetails[rows[row].id]?.depth ?? 0, visible: rowDetails[rows[row].id]?.visible ?? true)
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizing, let table = notification.object as? NSTableView else { return }
            let selected = table.selectedRowIndexes.filter { rows.indices.contains($0) }
            let ids = Set(selected.map { rows[$0].id })
            let primary = selected.contains(table.clickedRow) ? rows[table.clickedRow].id : selected.first.map { rows[$0].id }
            session.selectLayers(ids, primary: primary)
        }
        /// A click on a row's name (its thumbnails are buttons of their own) targets the layer itself, even when its
        /// mask was selected — so transforming then moves layer and mask together.
        @objc func clickedLayer(_ table: NSTableView) {
            guard rows.indices.contains(table.clickedRow), session.isMaskSelected,
                  session.selectedLayerIDs == [rows[table.clickedRow].id],
                  // Clicks on the row's buttons (the mask thumbnail among them) reach the table too.
                  let event = NSApp.currentEvent,
                  (table.view(atColumn: 0, row: table.clickedRow, makeIfNecessary: false) as? LayerCell)?.isOnControl(event.locationInWindow) != true
            else { return }
            session.commitTransform()
            session.selectLayerTarget(rows[table.clickedRow].id, mask: false)
        }
        @objc func renameClickedLayer(_ table: NSTableView) {
            guard session.canEditLayers, rows.indices.contains(table.clickedRow) else { return }
            let id = rows[table.clickedRow].id
            session.activeLayerID = id
            // On the thumbnail (or another of the row's controls) a double-click opens what the layer holds: its
            // text, or an adjustment's settings. On the name it renames the layer, as it does for every other layer.
            let point = NSApp.currentEvent?.locationInWindow ?? .zero
            let cell = table.view(atColumn: 0, row: table.clickedRow, makeIfNecessary: false) as? LayerCell
            if cell?.isOnControl(point) == true {
                if rows[table.clickedRow].liveText != nil { session.editActiveText(); return }
                if rows[table.clickedRow].adjustment?.kind.isEditable == true { session.adjustmentEditingID = id; return }
            }
            session.renamingLayerID = id
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard session.canEditLayers, rows.indices.contains(row) else { return nil }
            let item = NSPasteboardItem()
            item.setString(rows[row].id.uuidString, forType: Self.layerType)
            return item
        }
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                       proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
            if let source = info.draggingSource as? LayerEffectRow {
                let target = tableView.row(at: tableView.convert(info.draggingLocation, from: nil))
                guard source.session === session, rows.indices.contains(target),
                      session.canCopyEffect(source.kind, from: source.layerID, to: rows[target].id) else { return [] }
                tableView.setDropRow(target, dropOperation: .on)
                return .copy
            }
            if let source = draggedMask(info) {
                // A mask lands on whichever row is under the pointer.
                let target = tableView.row(at: tableView.convert(info.draggingLocation, from: nil))
                guard rows.indices.contains(target), session.canCopyMask(from: source, to: rows[target].id) else { return [] }
                tableView.setDropRow(target, dropOperation: .on)
                return .copy
            }
            guard session.canEditLayers, info.draggingSource as? NSTableView === tableView,
                  (0...rows.count).contains(row) else { return [] }
            let ids = draggedLayers(info)
            guard !ids.isEmpty else { return [] }
            // With Option held the drag offers only Copy, including complete folder trees.
            let copying = info.draggingSourceOperationMask == .copy
            let intoFolder = operation == .on && rows.indices.contains(row) && rows[row].isGroup
            let parent = intoFolder ? rows[row].id : (rows.indices.contains(row) ? rows[row].parentID : nil)
            guard ids.allSatisfy({ session.canPlaceLayer($0, in: parent) }) else { return [] }
            tableView.setDropRow(row, dropOperation: intoFolder ? .on : .above)
            return copying ? .copy : .move
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                       row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            if let source = info.draggingSource as? LayerEffectRow {
                guard source.session === session, rows.indices.contains(row),
                      session.canCopyEffect(source.kind, from: source.layerID, to: rows[row].id) else { return false }
                session.copyEffect(source.kind, from: source.layerID, to: rows[row].id)
                return true
            }
            if let source = draggedMask(info) {
                guard rows.indices.contains(row), session.canCopyMask(from: source, to: rows[row].id) else { return false }
                session.copyMask(from: source, to: rows[row].id)
                return true
            }
            guard info.draggingSource as? NSTableView === tableView else { return false }
            let ids = draggedLayers(info)
            guard !ids.isEmpty else { return false }
            let copying = info.draggingSourceOperationMask == .copy
            let intoFolder = dropOperation == .on && rows.indices.contains(row) && rows[row].isGroup
            return place(ids, at: row, intoFolder: intoFolder, copying: copying)
        }
        /// Reorders one layer to the row a drop above it would use: the list's own move, without the dragging
        /// plumbing, so anything that picks a row by itself — a test, a keyboard command — can reach it.
        @discardableResult func moveLayer(_ id: UUID, to row: Int) -> Bool {
            // `session.placeLayer` already refuses an unknown layer and a session that cannot edit layers, so the
            // only thing left to reject is a row that is not a drop target. `place` treats a row past the end as
            // the bottom, so what this actually catches is a negative one; the bound is written the way
            // `validateDrop` writes it, so the two accept the same rows.
            guard (0...rows.count).contains(row) else { return false }
            return place([id], at: row, intoFolder: false, copying: false)
        }
        private func place(_ ids: [UUID], at row: Int, intoFolder: Bool, copying: Bool) -> Bool {
            // Where the drop lands is worked out once: each layer placed shifts the rows beneath it.
            // The filtered rows, so a drop's indexes mean the rows the panel is showing.
            let current = session.filteredLayerRows
            let parent: UUID?, above: UUID?, atBottom: Bool
            if intoFolder {
                parent = rows[row].id; above = nil; atBottom = false
            } else if row >= current.count {
                parent = nil; above = nil; atBottom = true
            } else {
                let target = current[row].layer
                parent = target.parentID; above = target.id; atBottom = false
            }
            // Dropped above a layer (or at the very bottom) the last one placed ends up nearest it, so they go in
            // from the top down; dropped into a folder each lands on top, so they go in from the bottom up.
            let order = intoFolder ? Array(ids.reversed()) : ids
            session.beginEdit(copying ? (ids.count > 1 ? "Duplicate Layers" : "Duplicate Layer")
                                      : (ids.count > 1 ? "Move Layers" : "Move Layer"))
            var placed = false
            for id in order {
                let done = copying ? session.duplicateLayer(id, in: parent, above: above, atBottom: atBottom)
                                   : session.placeLayer(id, in: parent, above: above, atBottom: atBottom)
                placed = done || placed
            }
            // The layers that moved stay selected, so they can be dragged on as a group.
            if placed, !copying { session.selectLayers(Set(ids), primary: ids.first) }
            session.endEdit()
            return placed
        }
        private func draggedMask(_ info: NSDraggingInfo) -> UUID? {
            info.draggingPasteboard.string(forType: Self.maskType).flatMap(UUID.init(uuidString:))
        }
        /// Every layer being dragged, in the order the list shows them: a row's pasteboard item each, leaving out
        /// anything inside a dragged folder, which the folder brings along itself.
        private func draggedLayers(_ info: NSDraggingInfo) -> [UUID] {
            let dropped = (info.draggingPasteboard.pasteboardItems ?? []).compactMap {
                $0.string(forType: Self.layerType).flatMap(UUID.init(uuidString:))
            }
            let dragged = Set(dropped)
            let carried = dragged.reduce(into: Set<UUID>()) { $0.formUnion(session.descendantIDs(of: $1)) }
            return session.filteredLayerRows.map(\.layer.id).filter { dragged.contains($0) && !carried.contains($0) }
        }
    }
}
