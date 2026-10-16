import Testing

struct MenuBarClickActionTests {
    @Test func primaryClickOpensContextMenuWhenSideNotchIsEnabled() {
        #expect(MenuBarClickAction.primary(sideNotchEnabled: true) == .contextMenu)
    }

    @Test func primaryClickOpensFullPanelWhenSideNotchIsDisabled() {
        #expect(MenuBarClickAction.primary(sideNotchEnabled: false) == .panel)
    }
}
