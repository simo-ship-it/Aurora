import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.regular)

let documentController = AuroraDocumentController()
let delegate = AppDelegate()
application.delegate = delegate
application.run()
