/// The primary menu-bar click opens the UI available for the current layout.
enum MenuBarClickAction {
    case panel
    case contextMenu

    static func primary(sideNotchEnabled: Bool) -> Self {
        sideNotchEnabled ? .contextMenu : .panel
    }
}
