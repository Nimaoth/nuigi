import nuigi
when not defined(nuiNoSemantics):
  import nuigi/widgets
  import nuigi/widgets/[windows, tree_table]
  import nuigi/core/vecmath
include nuigi/util/compat2

proc require(condition: bool, message: string) =
  if not condition: quit("semantic actions: " & message, 1)

template actionNode(b: var UiBuilder, target: UiNodeId, body: untyped) =
  discard b.beginNodeWithId(target)
  body
  discard b.endNode()

proc testRequests() =
  var b = newBuilder(nil)
  let target = UiNodeId(42)
  var expanded = false
  var value = 0.0'f32
  b.enqueueSemanticRequest(UiSemanticRequest(target: target, action: SemanticExpand))
  b.enqueueSemanticRequest(UiSemanticRequest(target: target, action: SemanticExpand))
  b.enqueueSemanticRequest(UiSemanticRequest(target: target, action: SemanticSetNumericValue, numericValue: 100))
  b.enqueueSemanticRequest(UiSemanticRequest(target: target, action: SemanticActivate))
  b.enqueueSemanticRequest(UiSemanticRequest(target: target, action: SemanticActivate))
  discard b.beginUiFrame(400, 300)
  b.actionNode(target):
    discard b.size(100, 20).semanticRole(SemanticButton)
    require(b.applySemanticExpanded(target, expanded), "expand changed")
    require(expanded, "expand idempotence")
    require(b.applySemanticNumeric(target, value, 0, 10), "numeric changed")
    require(value == 10, "numeric clamping")
    require(b.semanticActivateCount(target) == 2, "exactly two activations")
    require(b.semanticActivateCount(target) == 0, "no duplicate consumption")
    let sem = b.nodeSemantics(b.currentNodeIndex)
    require(sem != nil and SemanticExpanded in sem.states and sem.numericValue == 10,
      "final metadata")
  b.endUiFrame(buildRenderCommands = false)
  b.enqueueSemanticRequest(UiSemanticRequest(target: target, action: SemanticCollapse))
  discard b.beginUiFrame(400, 300)
  b.actionNode(target):
    discard b.size(100, 20).semanticState({SemanticReadOnly})
    require(not b.applySemanticExpanded(target, expanded), "read-only rejects mutation")
    require(expanded, "read-only preserved")
  b.endUiFrame(buildRenderCommands = false)

proc testFocusAndExpiry() =
  var b = newBuilder(nil)
  let physical = UiNodeId(123)
  let logical = UiNodeId(456)
  b.enqueueSemanticRequest(UiSemanticRequest(target: physical, action: SemanticFocus))
  discard b.beginUiFrame(400, 300)
  b.actionNode(physical):
    discard b.size(100, 20)
    discard b.registerFocusItem(logical, b.currentNodeIndex)
  b.endUiFrame(buildRenderCommands = false)
  require(b.focusedNode == logical, "logical focus resolved")
  b.enqueueSemanticRequest(UiSemanticRequest(target: physical, action: SemanticActivate))
  discard b.beginUiFrame(400, 300)
  b.endUiFrame(buildRenderCommands = false)
  discard b.beginUiFrame(400, 300)
  b.actionNode(physical):
    require(b.semanticActivateCount(physical) == 0, "removed target request expired")
  b.endUiFrame(buildRenderCommands = false)
  b.enqueueSemanticRequest(UiSemanticRequest(target: physical, action: SemanticActivate))
  discard b.beginUiFrame(400, 300)
  b.actionNode(physical):
    discard b.semanticHidden()
    require(b.semanticActivateCount(physical) == 0, "hidden rejects activation")
  b.endUiFrame(buildRenderCommands = false)

when not defined(nuiNoSemantics):
  proc fixedMeasureText(text: openArray[char], fontId: int16, fontSize: float32,
      maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.gcsafe, raises: [].} =
    result = UiTextArrangement(fontSize: fontSize,
      size: vec2(text.len.float32 * 10.0'f32, 20.0'f32))

  proc roleIndex(b: UiBuilder, role: UiSemanticRole, occurrence = 0): int =
    var remaining = occurrence
    for i in 0 ..< b.frame.nodes.len:
      let semantics = b.nodeSemantics(i)
      if semantics != nil and semantics.role == role:
        if remaining == 0:
          return i
        dec remaining
    quit("semantic actions: missing widget role", 1)

  proc send(b: var UiBuilder, target: UiNodeId, action: UiSemanticAction) =
    b.enqueueSemanticRequest(UiSemanticRequest(target: target, action: action))

  type Controls = object
    checked: bool
    sliderValue, dragValue: float32
    text: string
    selected: int
    pressed, toggled, sliderChanged, dragChanged, submitted, selectionChanged: bool
    textState: TextFieldStorage

  proc buildControls(b: var UiBuilder, controls: var Controls) =
    discard b.beginUiFrame(800, 600)
    b.node("controls"):
      discard b.fill().layout(LayoutVertical)
      controls.pressed = b.button("Action button")
      controls.toggled = b.checkbox("Action checkbox", controls.checked)
      controls.sliderChanged = b.slider(controls.sliderValue, 0, 10)
      controls.dragChanged = b.dragFloat(controls.dragValue, 5, -10, 10)
      controls.submitted = b.textField(controls.text, "Action text", controls.textState,
        maxWidth = 100)
      controls.selectionChanged = b.dropdown(["First", "Second"], controls.selected)
    b.endUiFrame(buildRenderCommands = false)

  proc testBasicWidgets() =
    var b = newBuilder(fixedMeasureText)
    var controls = Controls(sliderValue: 5, dragValue: 5, text: "old",
      textState: TextFieldStorage())
    b.buildControls(controls)
    let buttonId = b.nodes[b.roleIndex(SemanticButton)].id
    let checkboxId = b.nodes[b.roleIndex(SemanticCheckBox)].id
    let sliderId = b.nodes[b.roleIndex(SemanticSlider)].id
    let dragId = b.nodes[b.roleIndex(SemanticSpinButton)].id
    let textId = b.nodes[b.roleIndex(SemanticTextInput)].id
    require(not controls.pressed and not controls.toggled, "inactive widget returns")
    b.send(buttonId, SemanticActivate)
    b.send(buttonId, SemanticActivate)
    b.send(checkboxId, SemanticActivate)
    b.send(checkboxId, SemanticActivate)
    b.enqueueSemanticRequest(UiSemanticRequest(target: sliderId,
      action: SemanticSetNumericValue, numericValue: 100))
    b.enqueueSemanticRequest(UiSemanticRequest(target: dragId,
      action: SemanticSetNumericValue, numericValue: -100))
    b.enqueueSemanticRequest(UiSemanticRequest(target: textId,
      action: SemanticSetTextValue, textValue: "new\r\ntext"))
    b.buildControls(controls)
    require(controls.pressed, "button batches report activation")
    require(controls.toggled and not controls.checked, "checkbox toggles exactly twice")
    require(SemanticChecked notin b.nodeSemantics(b.roleIndex(SemanticCheckBox)).states,
      "checkbox final unchecked metadata")
    require(controls.sliderChanged and controls.sliderValue == 10, "slider clamps high")
    require(controls.dragChanged and controls.dragValue == -10, "dragFloat clamps low")
    require(b.nodeSemantics(b.roleIndex(SemanticSlider)).numericValue == 10,
      "slider final numeric metadata")
    require(b.nodeSemantics(b.roleIndex(SemanticSpinButton)).numericValue == -10,
      "dragFloat final numeric metadata")
    require(controls.text == "newtext" and not controls.submitted,
      "text replacement changes content without submission")
    require(b.nodeSemantics(b.roleIndex(SemanticTextInput)).valueText.value == "newtext",
      "text replacement final metadata")
    require(controls.textState.cursorPos == controls.text.len and
      not controls.textState.selectionActive,
      "text replacement resets caret and selection")
    b.buildControls(controls)
    require(not controls.pressed and not controls.toggled and not controls.sliderChanged and
      not controls.dragChanged, "widget requests are not replayed")
    b.send(checkboxId, SemanticActivate)
    b.enqueueSemanticRequest(UiSemanticRequest(target: textId,
      action: SemanticSetTextValue, textValue: ""))
    b.buildControls(controls)
    require(controls.checked and controls.toggled and
      SemanticChecked in b.nodeSemantics(b.roleIndex(SemanticCheckBox)).states,
      "checkbox single activation and final checked metadata")
    require(controls.text.len == 0 and controls.textState.cursorPos == 0 and
      not controls.submitted, "empty text replacement")
    b.enqueueSemanticRequest(UiSemanticRequest(target: sliderId,
      action: SemanticSetNumericValue, numericValue: 0))
    b.enqueueSemanticRequest(UiSemanticRequest(target: sliderId,
      action: SemanticSetNumericValue, numericValue: 10))
    b.enqueueSemanticRequest(UiSemanticRequest(target: dragId,
      action: SemanticSetNumericValue, numericValue: 10))
    b.enqueueSemanticRequest(UiSemanticRequest(target: dragId,
      action: SemanticSetNumericValue, numericValue: -10))
    b.buildControls(controls)
    require(not controls.sliderChanged and not controls.dragChanged,
      "numeric batches returning to the original value do not report changes")

  proc testDropdown() =
    var b = newBuilder(fixedMeasureText)
    var controls = Controls(textState: TextFieldStorage(), text: "")
    b.buildControls(controls)
    let comboId = b.nodes[b.roleIndex(SemanticComboBox)].id
    b.send(comboId, SemanticExpand)
    b.send(comboId, SemanticExpand)
    b.buildControls(controls)
    require(SemanticExpanded in b.nodeSemantics(b.roleIndex(SemanticComboBox)).states,
      "dropdown repeated Expand remains open")
    let optionId = b.nodes[b.roleIndex(SemanticListItem, 1)].id
    b.send(optionId, SemanticSelect)
    b.buildControls(controls)
    require(controls.selected == 1 and controls.selectionChanged,
      "dropdown Select changes selection")
    let combo = b.nodeSemantics(b.roleIndex(SemanticComboBox))
    require(SemanticCollapsed in combo.states and combo.valueText.value == "Second",
      "dropdown selection closes popup and updates metadata")
    require(SemanticSelected in b.nodeSemantics(b.roleIndex(SemanticListItem, 1)).states and
      SemanticSelected notin b.nodeSemantics(b.roleIndex(SemanticListItem)).states,
      "dropdown publishes only the final selected option")
    b.send(comboId, SemanticExpand)
    b.buildControls(controls)
    let firstOption = b.nodes[b.roleIndex(SemanticListItem)].id
    b.send(firstOption, SemanticActivate)
    b.buildControls(controls)
    require(controls.selected == 0 and controls.selectionChanged,
      "dropdown option Activate selects")
    b.send(comboId, SemanticCollapse)
    b.send(comboId, SemanticCollapse)
    b.buildControls(controls)
    require(SemanticCollapsed in b.nodeSemantics(b.roleIndex(SemanticComboBox)).states,
      "dropdown repeated Collapse remains closed")
    b.send(comboId, SemanticExpand)
    b.send(comboId, SemanticActivate)
    b.buildControls(controls)
    require(SemanticCollapsed in b.nodeSemantics(b.roleIndex(SemanticComboBox)).states,
      "dropdown Expand then Activate preserves same-control FIFO")

  proc buildHeaderTabs(b: var UiBuilder, expanded: var bool, tab: var int) =
    discard b.beginUiFrame(800, 600)
    b.node("header-tabs"):
      discard b.fill().layout(LayoutVertical)
      b.collapsingHeader("Action header", expanded):
        b.label("Header contents")
      b.tabBar(["Tab one", "Tab two"], tab):
        b.label("Tab contents")
    b.endUiFrame(buildRenderCommands = false)

  proc testHeaderAndTabs() =
    var b = newBuilder(fixedMeasureText)
    var expanded = false
    var tab = 0
    b.buildHeaderTabs(expanded, tab)
    let headerId = b.nodes[b.roleIndex(SemanticButton)].id
    let tabId = b.nodes[b.roleIndex(SemanticTab, 1)].id
    b.send(headerId, SemanticExpand)
    b.send(headerId, SemanticExpand)
    b.send(tabId, SemanticSelect)
    b.buildHeaderTabs(expanded, tab)
    require(expanded and SemanticExpanded in b.nodeSemantics(b.roleIndex(SemanticButton)).states,
      "header expands idempotently with final metadata")
    require(tab == 1 and SemanticSelected in b.nodeSemantics(b.roleIndex(SemanticTab, 1)).states and
      SemanticSelected notin b.nodeSemantics(b.roleIndex(SemanticTab)).states,
      "tab Select changes active tab and final states")
    b.send(headerId, SemanticCollapse)
    b.send(headerId, SemanticCollapse)
    b.buildHeaderTabs(expanded, tab)
    require(not expanded and SemanticCollapsed in b.nodeSemantics(b.roleIndex(SemanticButton)).states,
      "header collapses idempotently")
    b.send(headerId, SemanticExpand)
    b.send(headerId, SemanticActivate)
    b.buildHeaderTabs(expanded, tab)
    require(not expanded, "header Expand then Activate preserves same-control FIFO")

  proc buildWindow(b: var UiBuilder) =
    discard b.beginUiFrame(800, 600)
    b.windowSpace()
    b.window("Action window", 0, 0, 300, 200):
      discard
    b.endUiFrame(buildRenderCommands = false)

  proc testWindowCollapse() =
    var b = newBuilder(fixedMeasureText)
    b.buildWindow()
    let buttonId = b.nodes[b.roleIndex(SemanticButton)].id
    b.send(buttonId, SemanticCollapse)
    b.send(buttonId, SemanticCollapse)
    b.buildWindow()
    let windowIndex = b.roleIndex(SemanticWindow)
    let storage = cast[WindowStorage](b.nodeStorageGet(b.nodes[windowIndex].addr))
    require(storage != nil and storage.collapsed, "window repeated Collapse closes")
    let collapsedSem = b.nodeSemantics(b.roleIndex(SemanticButton))
    require(SemanticCollapsed in collapsedSem.states and collapsedSem.label.value == "Expand window",
      "window final collapsed state and label")
    b.send(buttonId, SemanticExpand)
    b.send(buttonId, SemanticExpand)
    b.buildWindow()
    let expandedSem = b.nodeSemantics(b.roleIndex(SemanticButton))
    require(not storage.collapsed and SemanticExpanded in expandedSem.states and
      expandedSem.label.value == "Collapse window", "window repeated Expand opens")
    b.send(buttonId, SemanticCollapse)
    b.send(buttonId, SemanticActivate)
    b.buildWindow()
    require(not storage.collapsed, "window Collapse then Activate preserves same-control FIFO")

  type ActionTreeCursor = ref object of TreeCursor

  method clone(c: ActionTreeCursor): TreeCursor {.gcsafe, raises: [].} =
    ActionTreeCursor(fieldName: c.fieldName, index: c.index, path: c.path)

  method childCount(c: ActionTreeCursor): int {.gcsafe, raises: [].} =
    if c.path.len == 0: 1 else: 0

  method enterChild(c: ActionTreeCursor): bool {.gcsafe, raises: [].} =
    if c.path.len > 0:
      return false
    c.path.add(0)
    c.index = 0
    c.fieldName = "Child"
    true

  method moveNext(c: ActionTreeCursor, count: int = 1): bool {.gcsafe, raises: [].} =
    false

  method exitChild(c: ActionTreeCursor): bool {.gcsafe, raises: [].} =
    if c.path.len == 0:
      return false
    c.path.setLen(0)
    c.index = 0
    c.fieldName = "Root"
    true

  proc renderTreeRow(b: var UiBuilder, cursor: TreeCursor, index: int)
      {.nimcall, gcsafe, raises: [].} =
    b.label(cursor.fieldName)

  proc buildTree(b: var UiBuilder, cursor: TreeCursor): TreeTable =
    discard b.beginUiFrame(800, 600)
    b.node("action-tree"):
      discard b.fill()
      b.treeTable(cursor, renderTreeRow)
      result = cast[TreeTable](b.nodeStorageGet(b.currentNode))
    b.endUiFrame(buildRenderCommands = false)

  proc testTreeExpansion() =
    var b = newBuilder(fixedMeasureText)
    let cursor = ActionTreeCursor(fieldName: "Root", path: @[])
    var tree = b.buildTree(cursor)
    let rowId = b.nodes[b.roleIndex(SemanticTreeItem)].id
    b.send(rowId, SemanticCollapse)
    b.send(rowId, SemanticCollapse)
    tree = b.buildTree(cursor)
    require(SemanticCollapsed in b.nodeSemantics(b.roleIndex(SemanticTreeItem)).states,
      "tree Collapse publishes collapsed state immediately")
    tree = b.buildTree(cursor)
    require(tree.expandedCount == 0, "tree deferred collapse uses existing cursor topology")
    b.send(rowId, SemanticExpand)
    b.send(rowId, SemanticExpand)
    tree = b.buildTree(cursor)
    require(SemanticExpanded in b.nodeSemantics(b.roleIndex(SemanticTreeItem)).states,
      "tree repeated Expand publishes expanded state")
    tree = b.buildTree(cursor)
    require(tree.expandedCount == 1, "tree deferred expansion is idempotent")
    b.send(rowId, SemanticExpand)
    b.send(rowId, SemanticActivate)
    tree = b.buildTree(cursor)
    require(SemanticCollapsed in b.nodeSemantics(b.roleIndex(SemanticTreeItem)).states,
      "tree Expand then Activate preserves same-control FIFO")
    tree = b.buildTree(cursor)
    require(tree.expandedCount == 0, "tree mixed requests apply final topology")

  proc buildMenu(b: var UiBuilder, activations: var int, readOnly: bool,
      disableAfterClick = false) =
    discard b.beginUiFrame(800, 600)
    b.menuItem:
      discard b.semanticLabel("Action menu")
      if readOnly:
        discard b.semanticState({SemanticReadOnly})
      b.label("Action menu")
    do:
      discard
    do:
      inc activations
      if disableAfterClick:
        discard b.semanticState({SemanticDisabled})
    b.endUiFrame(buildRenderCommands = false)

  proc testMenuActivation() =
    var b = newBuilder(fixedMeasureText)
    var activations = 0
    b.buildMenu(activations, false)
    let menuId = b.nodes[b.roleIndex(SemanticMenuItem)].id
    b.send(menuId, SemanticActivate)
    b.send(menuId, SemanticActivate)
    b.buildMenu(activations, false)
    require(activations == 2, "menu invokes callback for each activation")
    b.send(menuId, SemanticActivate)
    b.buildMenu(activations, true)
    require(activations == 2, "menu rechecks read-only declared in its body")
    b.send(menuId, SemanticActivate)
    b.send(menuId, SemanticActivate)
    b.buildMenu(activations, false, true)
    require(activations == 3, "menu rechecks state after each callback")

  proc buildDockTabs(b: var UiBuilder, dock: DockSpace) =
    discard b.beginUiFrame(800, 600)
    b.windowSpace(dock)
    b.window("Dock one", 0, 0, 300, 200):
      discard
    b.window("Dock two", 0, 0, 300, 200):
      discard
    b.endUiFrame(buildRenderCommands = false)

  proc testDockTabSelection() =
    var b = newBuilder(fixedMeasureText)
    let dock = newDockSpace()
    dock.layout.dockWindow("Dock one")
    dock.layout.dockWindow("Dock two", "Dock one")
    dock.layout.activateTab("Dock one")
    b.buildDockTabs(dock)
    b.buildDockTabs(dock)
    let secondId = dockTabId("Dock two")
    require(b.nodeIndex(secondId) >= 0, "docked second tab is available")
    b.send(secondId, SemanticSelect)
    b.buildDockTabs(dock)
    let tabs = dock.layout.findTabs("Dock two")
    require(dock.layout.nodes[tabs].windows[dock.layout.nodes[tabs].activeTab] == "Dock two",
      "dock tab Select changes active window")
    require(SemanticSelected in b.nodeSemantics(b.nodeIndex(secondId)).states,
      "dock tab final selected metadata")
    require(SemanticSelected notin b.nodeSemantics(b.nodeIndex(dockTabId("Dock one"))).states,
      "dock tab clears previous selection")

when not defined(nuiNoSemantics):
  testRequests()
  testFocusAndExpiry()
  testBasicWidgets()
  testDropdown()
  testHeaderAndTabs()
  testWindowCollapse()
  testTreeExpansion()
  testMenuActivation()
  testDockTabSelection()
else:
  var b = newBuilder(nil)
  let target = UiNodeId(42)
  b.enqueueSemanticRequest(UiSemanticRequest(target: target, action: SemanticActivate))
  discard b.beginUiFrame(400, 300)
  b.actionNode(target):
    require(b.semanticActivateCount(target) == 0, "semantics opt-out")
  b.endUiFrame(buildRenderCommands = false)
echo "Semantic action tests passed"
