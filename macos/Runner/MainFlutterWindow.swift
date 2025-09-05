import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Force dark appearance for the window
    self.appearance = NSAppearance(named: .darkAqua)
    
    // Configure title bar appearance
    self.titlebarAppearsTransparent = false
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    
    super.awakeFromNib()
  }
}
