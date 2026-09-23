import AppKit

let application = NSApplication.shared
// NSApplication.delegate は weak 参照のため、トップレベル定数で生存期間を保持する
let appDelegate = AppDelegate()
application.delegate = appDelegate
// Info.plist の LSUIElement に頼らず、`swift run` などバンドル外からの起動でも Dock に出さないよう明示する
application.setActivationPolicy(.accessory)
application.run()
