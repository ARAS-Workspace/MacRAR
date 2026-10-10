import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
AppDelegate.shared = delegate
app.delegate = delegate

let launch = LaunchArguments(Array(CommandLine.arguments.dropFirst()))
delegate.pendingCommand = launch.command
delegate.pendingFiles = launch.files

app.run()
