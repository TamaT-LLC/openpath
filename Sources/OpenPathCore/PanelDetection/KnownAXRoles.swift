/// debug ログにそのまま出してよい AX のロール・サブロール（Issue #83）。
///
/// ロール・サブロールは観測中のアプリが決める文字列で、任意の値（`AXSecretProject123` など）も設定できる。
/// そのため「AX で始まる」などの形では見分けず、SDK が定めた定数だけを許す。一覧は macOS SDK の
/// HIServices `AXRoleConstants.h`（`kAX…Role` / `kAX…Subrole`）と AppKit `NSAccessibilityConstants.h`
/// （`NSAccessibility…Role` / `…Subrole`）の値。これ以外は `<custom len: N>` として長さだけを出す。
enum KnownAXRoles {
    static let all: Set<String> = [
        "AXApplication", "AXApplicationDockItem", "AXBrowser", "AXBusyIndicator", "AXButton", "AXCell", "AXCheckBox",
        "AXCloseButton", "AXCollectionList", "AXColorWell", "AXColumn", "AXComboBox", "AXContentList", "AXDateField",
        "AXDateTimeArea", "AXDecorative", "AXDecrementArrow", "AXDecrementPage", "AXDefinitionList", "AXDescriptionList",
        "AXDialog", "AXDisclosureTriangle", "AXDockExtraDockItem", "AXDockItem", "AXDocumentDockItem", "AXDrawer",
        "AXFloatingWindow", "AXFolderDockItem", "AXFullScreenButton", "AXGrid", "AXGroup", "AXGrowArea", "AXHandle",
        "AXHeading", "AXHelpTag", "AXImage", "AXIncrementArrow", "AXIncrementPage", "AXIncrementor", "AXLayoutArea",
        "AXLayoutItem", "AXLevelIndicator", "AXLink", "AXList", "AXListMarker", "AXMatte", "AXMenu", "AXMenuBar",
        "AXMenuBarItem", "AXMenuButton", "AXMenuItem", "AXMinimizeButton", "AXMinimizedWindowDockItem", "AXOutline",
        "AXOutlineRow", "AXPage", "AXPopUpButton", "AXPopover", "AXProcessSwitcherList", "AXProgressIndicator",
        "AXRadioButton", "AXRadioGroup", "AXRatingIndicator", "AXRelevanceIndicator", "AXRow", "AXRuler", "AXRulerMarker",
        "AXScrollArea", "AXScrollBar", "AXSearchField", "AXSectionList", "AXSecureTextField", "AXSeparatorDockItem",
        "AXSheet", "AXSlider", "AXSortButton", "AXSplitGroup", "AXSplitter", "AXStandardWindow", "AXStaticText",
        "AXSuggestion", "AXSwitch", "AXSystemDialog", "AXSystemFloatingWindow", "AXSystemWide", "AXTabButton",
        "AXTabGroup", "AXTable", "AXTableRow", "AXTextArea", "AXTextAttachment", "AXTextField", "AXTextLink", "AXTimeField",
        "AXTimeline", "AXToggle", "AXToolbar", "AXToolbarButton", "AXTrashDockItem", "AXURLDockItem", "AXUnknown",
        "AXValueIndicator", "AXWebArea", "AXWindow", "AXZoomButton",
    ]
}
