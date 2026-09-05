import nuigi, nuigi/core/vecmath, nuigi/widgets, nuigi/widgets/colorpicker
import nuigi/widgets/tree_table

include nuigi/util/compat2

when defined(nimony):
  import std/assertions

proc require(cond: bool, msg: string) =
  when defined(nimony):
    assert cond, msg
  else:
    doAssert(cond, msg)

proc fixedMeasureText(text: openArray[char], fontId: int16, fontSize: float32,
    maxWidth: float32): UiTextArrangement {.gcsafe, raises: [].} =
  let _ = fontId
  let _ = maxWidth
  result = UiTextArrangement()
  result.fontSize = fontSize
  result.size = vec2(text.len.float32 * 10.0'f32, 20.0'f32)

proc hasAccentFocusHighlight(b: UiBuilder): bool =
  let accent = b.themeStyle(UiStyleIndexAccent)[].borderColor
  for index in 0 ..< b.frame.nodes.len:
    let style = b.nodeStyle(index)
    if style.borderWidth >= 2.0'f32 and style.borderColor == accent:
      return true
  false

type FocusTreeCursor = ref object of TreeCursor
  maxDepth: int
  childrenPerNode: int

method clone(c: FocusTreeCursor): TreeCursor =
  FocusTreeCursor(
    fieldName: c.fieldName,
    index: c.index,
    path: c.path,
    maxDepth: c.maxDepth,
    childrenPerNode: c.childrenPerNode)

method cursorKey(c: FocusTreeCursor): string =
  result = "root"
  for childIndex in c.path:
    result.add("/")
    result.add($childIndex)

method childCount(c: FocusTreeCursor): int =
  if c.path.len < c.maxDepth: c.childrenPerNode else: 0

method enterChild(c: FocusTreeCursor): bool =
  if c.path.len >= c.maxDepth:
    return false
  c.path.add(0)
  c.index = 0
  true

method exitChild(c: FocusTreeCursor): bool =
  if c.path.len == 0:
    return false
  c.path.setLen(c.path.len - 1)
  c.index = if c.path.len > 0: c.path[^1] else: 0
  true

method moveNext(c: FocusTreeCursor, count: int = 1): bool =
  if c.path.len == 0 or c.index + count >= c.childrenPerNode:
    return false
  c.index += count
  c.path[c.path.high] = c.index
  true

method movePrev(c: FocusTreeCursor, count: int = 1): bool =
  if c.path.len == 0 or c.index - count < 0:
    return false
  c.index -= count
  c.path[c.path.high] = c.index
  true

proc testTreeTableFocusNavigation() =
  var b = newBuilder(fixedMeasureText)
  let root = FocusTreeCursor(maxDepth: 2, childrenPerNode: 2)
  var initialized = false
  var treeStorage: TreeTable

  proc renderRow(b: var UiBuilder, cursor: TreeCursor, index: int) {.canRaise, nimcall.} =
    let _ = index
    b.label(cursor.cursorKey())

  proc buildTree(b: var UiBuilder) {.closure.} =
    b.node("focus-tree-table"):
      discard b.size(400.0'f32, 400.0'f32)
      if not initialized:
        treeStorage = TreeTable(cursor: root)
        treeStorage.expandAll()
        b.nodeStorage(b.currentNode, treeStorage)
        initialized = true
      b.treeTable(root, renderRow)

  proc rowFocusItem(b: UiBuilder, row: int): UiFocusItem =
    for item in b.frame.focusItems:
      if item.tabOrder == row and item.nodeIndex >= 0 and
          FocusActivatable notin item.flags:
        return item
    require(false, "missing tree-table focus item for row " & $row)
    UiFocusItem()

  discard b.beginUiFrame(400.0'f32, 400.0'f32)
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  let rootItem = b.rowFocusItem(0)
  let firstChildItem = b.rowFocusItem(1)
  let firstGrandchildItem = b.rowFocusItem(2)
  let secondGrandchildItem = b.rowFocusItem(3)
  let secondChildItem = b.rowFocusItem(4)
  require(firstChildItem.scopeId == rootItem.nodeId,
    "tree child should belong to its expanded parent scope")
  require(firstGrandchildItem.scopeId == firstChildItem.nodeId,
    "tree grandchild should belong to its expanded parent scope")

  b.focusedNode = rootItem.nodeId
  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyRight}))
  require(b.focusedNode == firstChildItem.nodeId,
    "Right should move tree focus to the first child")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyDown}, modsDown: {ModShift}))
  require(b.focusedNode == secondChildItem.nodeId,
    "Shift+Down should move to the next sibling instead of entering children")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyUp}, modsDown: {ModShift}))
  require(b.focusedNode == firstChildItem.nodeId,
    "Shift+Up should move to the previous sibling instead of its deepest child")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyDown}))
  require(b.focusedNode == firstGrandchildItem.nodeId,
    "Down should enter the first child of an expanded row")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyDown}))
  require(b.focusedNode == secondGrandchildItem.nodeId,
    "Down should move tree focus to the next sibling when there is no expanded child")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyDown}))
  require(b.focusedNode == secondChildItem.nodeId,
    "Down should leave a completed subtree in visible preorder")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyUp}))
  require(b.focusedNode == secondGrandchildItem.nodeId,
    "Up should enter the deepest previous visible subtree")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyUp}))
  require(b.focusedNode == firstGrandchildItem.nodeId,
    "Up should follow visible preorder between siblings")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyLeft}))
  require(b.focusedNode == firstChildItem.nodeId,
    "Left should move from a leaf to its parent")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyLeft}))
  require(b.focusedNode == firstChildItem.nodeId,
    "Left should keep focus on an expanded row while collapsing it")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyLeft}))
  require(b.focusedNode == rootItem.nodeId,
    "Left should move to the parent after the row is collapsed")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  b.focusedNode = firstChildItem.nodeId
  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyRight}))
  require(b.focusedNode == firstChildItem.nodeId,
    "Right should keep focus on a collapsed row while expanding it")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)
  let expandedGrandchildItem = b.rowFocusItem(2)

  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyRight}))
  require(b.focusedNode == expandedGrandchildItem.nodeId,
    "Right should enter the first child after expansion")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)

  b.focusedNode = rootItem.nodeId
  discard b.beginUiFrame(400.0'f32, 400.0'f32,
    input = UiInputSnapshot(keysPressed: {KeyLeft}))
  require(b.focusedNode == rootItem.nodeId,
    "Left should keep focus on the root while collapsing it")
  buildTree(b)
  b.endUiFrame(buildRenderCommands = false)
  let collapsedRootItem = b.rowFocusItem(0)
  require(collapsedRootItem.nodeId == rootItem.nodeId,
    "collapsed root should remain rendered and focusable")

proc testKeyboardFocusTraversal() =
  var b = newBuilder(fixedMeasureText)
  var firstId = noneNodeId()
  var secondId = noneNodeId()

  proc buildFocusItems(b: var UiBuilder) {.closure.} =
    b.node("first-focus-item"):
      firstId = b.currentNode.id
      discard b.focusable()
    b.node("second-focus-item"):
      secondId = b.currentNode.id
      discard b.focusable()

  discard b.beginUiFrame(200.0, 120.0)
  buildFocusItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  require(b.focusedNode == firstId, "Tab should focus the first registered item")
  require(b.wasFocusChangedByKeyboard(),
    "Tab focus movement should report a keyboard-driven focus change")
  buildFocusItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0)
  require(not b.wasFocusChangedByKeyboard(),
    "steady keyboard focus should not report a focus change")
  buildFocusItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  require(b.focusedNode == secondId, "Tab should advance to the next registered item")
  buildFocusItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}, modsDown: {ModShift}))
  require(b.focusedNode == firstId, "Shift+Tab should move to the previous registered item")
  buildFocusItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysRepeated: {KeyTab}))
  require(b.focusedNode == secondId, "repeated Tab should advance focus")
  buildFocusItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysRepeated: {KeyTab}, modsDown: {ModShift}))
  require(b.focusedNode == firstId, "repeated Shift+Tab should move focus backwards")

proc testExplicitTabOrder() =
  var b = newBuilder(fixedMeasureText)
  var firstId = noneNodeId()
  var secondId = noneNodeId()

  proc buildItems(b: var UiBuilder) {.closure.} =
    b.node("built-first"):
      secondId = b.currentNode.id
      discard b.focusable(tabOrder = 20)
    b.node("built-second"):
      firstId = b.currentNode.id
      discard b.focusable(tabOrder = 10)

  discard b.beginUiFrame(200.0, 120.0)
  buildItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  require(b.focusedNode == firstId, "Tab should use explicit order before build order")
  buildItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  require(b.focusedNode == secondId, "Tab should advance by explicit order")

proc testExplicitDirectionalNavigation() =
  var b = newBuilder(fixedMeasureText)
  var leftId = noneNodeId()
  var rightId = noneNodeId()

  proc buildItems(b: var UiBuilder, requestLeft = false) {.closure.} =
    b.node("left-item"):
      leftId = b.currentNode.id
      discard b.focusable()
      if requestLeft:
        b.requestFocus()
    b.node("right-item"):
      rightId = b.currentNode.id
      discard b.focusable()
    b.focusNavigationTarget(leftId, NavRight, rightId)
    b.focusNavigationTarget(rightId, NavLeft, leftId)

  discard b.beginUiFrame(200.0, 120.0)
  buildItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0)
  buildItems(b, requestLeft = true)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyRight}))
  require(b.focusedNode == rightId, "Right arrow should follow the explicit navigation target")
  buildItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysRepeated: {KeyLeft}))
  require(b.focusedNode == leftId, "repeated Left arrow should follow the explicit navigation target")
  buildItems(b)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(navigationPressed: {NavRight}))
  require(b.focusedNode == rightId, "controller navigation should use the same explicit target")

proc testFocusRestorationAcrossUnrenderedScope() =
  var b = newBuilder(fixedMeasureText)
  var scopeAId = noneNodeId()
  var itemAId = noneNodeId()
  var itemBId = noneNodeId()

  discard b.beginUiFrame(200.0, 120.0)
  b.node("tabs-root"):
    discard b.focusScope()
    b.node("scope-a"):
      scopeAId = b.currentNode.id
      discard b.focusScope()
      b.node("item-a"):
        itemAId = b.currentNode.id
        discard b.focusable()
        b.requestFocus()
  b.endUiFrame(buildRenderCommands = false)
  require(b.focusedNode == itemAId, "requestFocus should focus the current item")

  discard b.beginUiFrame(200.0, 120.0)
  b.node("tabs-root"):
    discard b.focusScope()
    b.node("scope-b"):
      discard b.focusScope()
      b.node("item-b"):
        itemBId = b.currentNode.id
        discard b.focusable()
        b.requestFocus()
  b.endUiFrame(buildRenderCommands = false)
  require(b.focusedNode == itemBId, "focus should move while the first scope is absent")

  discard b.beginUiFrame(200.0, 120.0)
  b.node("tabs-root"):
    discard b.focusScope()
    b.node("scope-a"):
      require(b.currentNode.id == scopeAId, "focus scope IDs should be stable")
      discard b.focusScope()
      b.restoreFocus()
      b.node("item-a"):
        discard b.focusable()
  require(b.focusedNode == itemAId,
    "restoreFocus should recover the remembered item after its scope was absent")

proc testKeyboardFocusActivation() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(200.0, 120.0)
  b.node("activatable-item"):
    discard b.focusable({FocusTabStop, FocusActivatable})
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  b.node("activatable-item"):
    discard b.focusable({FocusTabStop, FocusActivatable})
    require(not b.wasFocusActivated(), "Tab should move focus without activating it")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyEnter}))
  b.node("activatable-item"):
    discard b.focusable({FocusTabStop, FocusActivatable})
    require(b.wasFocusActivated(), "Enter should activate the focused item")

proc testButtonKeyboardActivation() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(200.0, 120.0)
  require(not b.button("Action"), "button should start inactive")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  require(not b.button("Action"), "Tab should focus without activating the button")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyEnter}))
  require(b.button("Action"), "Enter should activate the focused button")

proc testCheckboxKeyboardActivation() =
  var b = newBuilder(fixedMeasureText)
  var checked = false

  discard b.beginUiFrame(200.0, 120.0)
  require(not b.checkbox("Choice", checked), "checkbox should start inactive")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  require(not b.checkbox("Choice", checked), "Tab should focus without toggling the checkbox")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeySpace}))
  require(b.checkbox("Choice", checked), "Space should activate the focused checkbox")
  require(checked, "keyboard activation should toggle the checkbox value")

proc testTextFieldKeyboardFocus() =
  var b = newBuilder(fixedMeasureText)
  var text = ""

  discard b.beginUiFrame(200.0, 120.0)
  discard b.textField(text, "Name")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}, textInput: "x"))
  discard b.textField(text, "Name")
  require(text == "x", "Tab-focused text fields should receive same-frame text input")

proc testTabBarKeyboardFocus() =
  var b = newBuilder(fixedMeasureText)
  var activeTab = 0
  var firstContentId = noneNodeId()

  template buildTabs() =
    b.tabBar(["First", "Second"], activeTab):
      b.node("first-content-item"):
        firstContentId = b.currentNode.id
        discard b.focusable()
      b.node("second-content-item"):
        discard b.focusable()

  discard b.beginUiFrame(200.0, 120.0)
  buildTabs()
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  buildTabs()
  require(activeTab == 0, "Tab should focus the first tab button")
  require(b.hasAccentFocusHighlight(), "focused tab buttons should show an accent border")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyEnter}))
  buildTabs()
  require(b.focusedNode == firstContentId,
    "activating a tab should focus its first content item")

proc testTabBarActivationSkipsDisabledContent() =
  var b = newBuilder(fixedMeasureText)
  var activeTab = 0
  var enabledContentId = noneNodeId()

  template buildTabs() =
    b.tabBar(["Only"], activeTab):
      b.node("disabled-content-item"):
        discard b.focusable({FocusTabStop, FocusDisabled})
      b.node("enabled-content-item"):
        enabledContentId = b.currentNode.id
        discard b.focusable()

  discard b.beginUiFrame(200.0, 120.0)
  buildTabs()
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  buildTabs()
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyEnter}))
  buildTabs()
  require(b.focusedNode == enabledContentId,
    "tab activation should skip disabled content items")

proc testSliderKeyboardFocus() =
  var b = newBuilder(fixedMeasureText)
  var value = 0.5'f32

  discard b.beginUiFrame(200.0, 120.0)
  discard b.slider(value)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  discard b.slider(value)
  require(b.hasAccentFocusHighlight(), "focused sliders should show an accent border")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyRight}))
  require(b.slider(value), "Right arrow should change the focused slider")
  require(value > 0.5'f32, "Right arrow should increase the slider value")

proc testDragFloatKeyboardFocus() =
  var b = newBuilder(fixedMeasureText)
  var value = 0.5'f32

  discard b.beginUiFrame(200.0, 120.0)
  discard b.dragFloat(value, default = 0.5'f32, minValue = 0.0'f32, maxValue = 1.0'f32)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  discard b.dragFloat(value, default = 0.5'f32, minValue = 0.0'f32, maxValue = 1.0'f32)
  require(b.hasAccentFocusHighlight(), "focused drag floats should show an accent border")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(navigationPressed: {NavLeft}))
  require(b.dragFloat(value, default = 0.5'f32, minValue = 0.0'f32, maxValue = 1.0'f32),
    "controller Left should change the focused drag float")
  require(value < 0.5'f32, "controller Left should decrease the drag-float value")

proc testMultiDragFloatFocusStops() =
  var b = newBuilder(fixedMeasureText)
  var value = vec2(0.25'f32, 0.75'f32)

  discard b.beginUiFrame(300.0, 120.0)
  discard b.dragFloat2(value, default = 0.0'f32, minValue = 0.0'f32, maxValue = 1.0'f32)
  require(b.frame.focusItems.len == 2,
    "each drag-float component should register an independent focus stop")

proc testFocusableWidgetsShowFocus() =
  block:
    var b = newBuilder(fixedMeasureText)
    discard b.beginUiFrame(200.0, 120.0)
    discard b.button("Action")
    b.endUiFrame(buildRenderCommands = false)
    discard b.beginUiFrame(200.0, 120.0,
      input = UiInputSnapshot(keysPressed: {KeyTab}))
    discard b.button("Action")
    require(b.hasAccentFocusHighlight(), "focused buttons should show an accent border")

  block:
    var b = newBuilder(fixedMeasureText)
    var checked = false
    discard b.beginUiFrame(200.0, 120.0)
    discard b.checkbox("Choice", checked)
    b.endUiFrame(buildRenderCommands = false)
    discard b.beginUiFrame(200.0, 120.0,
      input = UiInputSnapshot(keysPressed: {KeyTab}))
    discard b.checkbox("Choice", checked)
    require(b.hasAccentFocusHighlight(), "focused checkboxes should show an accent border")

  block:
    var b = newBuilder(fixedMeasureText)
    var text = ""
    discard b.beginUiFrame(200.0, 120.0)
    discard b.textField(text, "Name")
    b.endUiFrame(buildRenderCommands = false)
    discard b.beginUiFrame(200.0, 120.0,
      input = UiInputSnapshot(keysPressed: {KeyTab}))
    discard b.textField(text, "Name")
    require(b.hasAccentFocusHighlight(), "focused text fields should show an accent border")

  block:
    var b = newBuilder(fixedMeasureText)
    var color = UiColor(r: 1.0'f32, g: 0.0'f32, b: 0.0'f32, a: 1.0'f32)
    discard b.beginUiFrame(200.0, 120.0)
    discard b.colorPicker(color)
    b.endUiFrame(buildRenderCommands = false)
    discard b.beginUiFrame(200.0, 120.0,
      input = UiInputSnapshot(keysPressed: {KeyTab}))
    discard b.colorPicker(color)
    require(b.hasAccentFocusHighlight(), "focused color pickers should show an accent border")

proc runTests() =
  testKeyboardFocusTraversal()
  testExplicitTabOrder()
  testExplicitDirectionalNavigation()
  testFocusRestorationAcrossUnrenderedScope()
  testKeyboardFocusActivation()
  testButtonKeyboardActivation()
  testCheckboxKeyboardActivation()
  testTextFieldKeyboardFocus()
  testTabBarKeyboardFocus()
  testTabBarActivationSkipsDisabledContent()
  testSliderKeyboardFocus()
  testDragFloatKeyboardFocus()
  testMultiDragFloatFocusStops()
  testFocusableWidgetsShowFocus()
  testTreeTableFocusNavigation()

when isMainModule:
  runTests()
