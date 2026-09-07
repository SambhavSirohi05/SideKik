import AppKit

// Entry point for SideKik native menu-bar desktop companion
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
