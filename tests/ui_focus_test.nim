import nuigi, mymath, widgets, colorpicker

include compat2

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

proc testKeyboardFocusTraversal() =
  var b = newBuilder(fixedMeasureText)
  var firstId = noneNodeId()
  var secondId = noneNodeId()

  proc buildFocusItems(b: var UiBuilder) =
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

  proc buildItems(b: var UiBuilder) =
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

  proc buildItems(b: var UiBuilder, requestLeft = false) =
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

when isMainModule:
  runTests()
