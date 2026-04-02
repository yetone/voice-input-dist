import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Edit menu enables Cmd+A/C/V/X/Z in text fields for LSUIElement apps
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
editMenu.addItem(.separator())
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

let editMenuItem = NSMenuItem()
editMenuItem.submenu = editMenu
let mainMenu = NSMenu()
mainMenu.addItem(editMenuItem)
app.mainMenu = mainMenu

let delegate = AppDelegate()
app.delegate = delegate
app.run()
