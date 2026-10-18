import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
AppDelegate.shared = delegate
app.delegate = delegate

// Before anything is opened: ZIP names stored in a Windows code page are read as Windows reads them in the user's region
SevenZipBridge.windowsCodePages = WindowsCodePages(.current)

let launch = LaunchArguments(Array(CommandLine.arguments.dropFirst()))
delegate.pendingCommand = launch.command
delegate.pendingFiles = launch.files

app.run()
