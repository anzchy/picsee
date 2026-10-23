/// Window effects only; visibility rules remain in the Session.
@MainActor public protocol ViewerChromeHost: AnyObject {
    func applyChrome(toolsVisible: Bool, trafficLightsVisible: Bool)
    func focusChromeTool(reverse: Bool, entering: Bool) -> Bool
}
public enum ChromePointerRegion: Sendable { case canvas, bottom, top, outside }
