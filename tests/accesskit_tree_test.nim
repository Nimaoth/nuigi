## Tests the Nuigi -> AccessKit tree generation in nuigi_accesskit.nim by
## building a small frame headlessly and inspecting the AccessKit debug dump
## of the generated tree update. Requires the AccessKit shared library next
## to the test executable (`./build.exe accesskit`).

import std/strutils
import nuigi, nuigi/core/vecmath, nuigi/widgets
import nuigi/nuigi_accesskit
import nuigi/backend/accesskit/accesskit

include nuigi/util/compat2

when defined(nimony):
  import std/assertions

proc require(cond: bool, msg: string) =
  when defined(nimony):
    assert cond, msg
  else:
    doAssert(cond, msg)

proc fixedMeasureText(text: openArray[char], fontId: int16, fontSize: float32,
    maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.gcsafe, raises: [].} =
  let _ = fontId
  let _ = maxWidth
  result = UiTextArrangement()
  result.fontSize = fontSize
  result.size = vec2(text.len.float32 * 10.0'f32, 20.0'f32)

proc countOccurrences(haystack, needle: string): int =
  # Nimony's strutils has no `count`, so implement it manually.
  result = 0
  if needle.len == 0:
    return 0
  var i = 0
  while i + needle.len <= haystack.len:
    var match = true
    for j in 0 ..< needle.len:
      if haystack[i + j] != needle[j]:
        match = false
        break
    if match:
      inc result
      i += needle.len
    else:
      inc i

proc treeDebugDump(update: ptr AccessKitTreeUpdate): string =
  let debug = treeUpdateDebug(update)
  result = $debug
  stringFree(debug)

proc buildTestUi(b: var UiBuilder) =
  b.node("accesskit-test-root"):
    discard b.size(400.0'f32, 400.0'f32)
    b.layoutVertical:
      discard b.fillX().fitY()
      b.label("Hello AccessKit")
      discard b.button("Press me")

proc testEmptyBuilderFallsBackToWindowTree() =
  var b = newBuilder(fixedMeasureText)
  let update = buildTreeSnapshot(b.addr)
  require(update != nil, "fallback tree update should be created")
  let dump = treeDebugDump(update)
  treeUpdateFree(update)
  require("Window" in dump, "fallback tree should contain a window root")

proc testActionRouting() =
  var b = newBuilder(fixedMeasureText)
  var ak = default(NuigiAccessKit)
  let target = UiNodeId(987)
  let logical = UiNodeId(654)
  var expanded = false
  var number = 1.0'f32
  discard b.beginUiFrame(400, 300)
  discard b.beginNodeWithId(target)
  discard b.size(100, 20).semanticRole(SemanticSpinButton)
  discard b.semanticActions({SemanticActivate, SemanticExpand, SemanticCollapse,
    SemanticSetNumericValue})
  discard b.semanticValue(number, 0, 10)
  discard b.registerFocusItem(logical, b.currentNodeIndex)
  discard b.endNode()
  b.endUiFrame(buildRenderCommands = false)
  let update = buildTreeSnapshot(b.addr, ak.addr)
  var request = AccessKitActionRequest(
    targetTree: treeUpdateGetTreeId(update), targetNode: AccessKitNodeId(uint64(target)),
    action: ACTION_CLICK)
  require(ak.dispatchRequest(request.addr, 1), "Click decoded")
  request.action = ACTION_FOCUS
  require(ak.dispatchRequest(request.addr, 1), "Focus decoded")
  request.action = ACTION_EXPAND
  require(ak.dispatchRequest(request.addr, 1), "Expand decoded")
  request.action = ACTION_SET_VALUE
  request.data = AccessKitOptActionData(hasValue: true, value: AccessKitActionData(
    tag: ACTION_DATA_NUMERIC_VALUE, anon0: AccessKitActionDataAnon0(numericValue: 30)))
  require(ak.dispatchRequest(request.addr, 1), "typed numeric value decoded")
  request.data.value.tag = ACTION_DATA_SCROLL_UNIT
  require(not ak.dispatchRequest(request.addr, 1), "wrong value tag rejected")
  request.targetTree.bytes[0] = request.targetTree.bytes[0] xor 1'u8
  require(not ak.dispatchRequest(request.addr, 1), "foreign tree rejected")
  treeUpdateFree(update)
  discard b.beginUiFrame(400, 300)
  discard b.beginNodeWithId(target)
  discard b.size(100, 20)
  discard b.registerFocusItem(logical, b.currentNodeIndex)
  require(b.semanticActivateCount(target) == 1, "decoded activation applied")
  require(b.applySemanticExpanded(target, expanded) and expanded, "decoded expansion applied")
  require(b.applySemanticNumeric(target, number, 0, 10) and number == 10, "decoded value applied")
  discard b.endNode()
  b.endUiFrame(buildRenderCommands = false)
  require(b.focusedNode == logical, "decoded focus applied to logical item")
  discard b.beginUiFrame(400, 300)
  b.endUiFrame(buildRenderCommands = false)
  let removed = buildTreeSnapshot(b.addr, ak.addr)
  treeUpdateFree(removed)
  discard b.beginUiFrame(400, 300)
  discard b.beginNodeWithId(target)
  discard b.semanticActions({SemanticActivate})
  discard b.endNode()
  b.endUiFrame(buildRenderCommands = false)
  let reincarnated = buildTreeSnapshot(b.addr, ak.addr)
  request.targetTree = treeUpdateGetTreeId(reincarnated)
  request.action = ACTION_CLICK
  request.data.hasValue = false
  require(not ak.dispatchRequest(request.addr, 1), "previous incarnation rejected")
  require(ak.dispatchRequest(request.addr, 3), "current incarnation accepted")
  treeUpdateFree(reincarnated)
  ak.deinit()

proc testFrameTreeContainsWidgets() =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(400.0'f32, 400.0'f32)
  b.buildTestUi()
  b.endUiFrame(buildRenderCommands = false)

  let update = buildTreeSnapshot(b.addr)
  require(update != nil, "tree update should be created")
  let dump = treeDebugDump(update)
  treeUpdateFree(update)

  require("Window" in dump, "root node should have the Window role")
  require("Hello AccessKit" in dump, "label text should be in the tree")
  require("Label" in dump, "label node should have the Label role")
  require("Press me" in dump, "button label should be in the tree")
  require("Button" in dump, "button node should have the Button role")
  require("Nuigi" in dump, "tree info should carry the toolkit name")

proc testFocusedNodeIsReported() =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(400.0'f32, 400.0'f32)
  b.buildTestUi()
  b.endUiFrame(buildRenderCommands = false)
  require(b.frame.focusItems.len > 0, "button should register a focus item")
  let buttonId = b.frame.focusItems[0].nodeId
  b.focusedNode = buttonId

  let update = buildTreeSnapshot(b.addr)
  require(update != nil, "tree update should be created")
  let dump = treeDebugDump(update)
  treeUpdateFree(update)
  require($uint64(buttonId) in dump,
    "focused node id should appear in the tree update")

proc testFilteredTreeAndLabelMerging() =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(400.0'f32, 400.0'f32)
  # Layout wrappers around an annotated checkbox whose name comes from a
  # descendant label; a hidden subtree with text.
  b.node("wrapper-a"):
    discard b.fill()
    b.node("wrapper-b"):
      discard b.fill()
      b.layoutHorizontal:
        discard b.fitX().fitY()
        discard b.focusable({FocusTabStop, FocusActivatable})
        discard b.semanticRole(SemanticCheckBox)
        discard b.semanticState({SemanticChecked})
        b.node("checkbox-box"):
          discard b.size(10.0'f32, 10.0'f32)
        b.node("checkbox-label"):
          discard b.fitX().fitY()
          discard b.text("Mute audio")
  b.node("hidden-subtree"):
    discard b.fitX().fitY()
    discard b.semanticHidden()
    b.node("hidden-text"):
      discard b.fitX().fitY()
      discard b.text("Secret text")
  b.endUiFrame(buildRenderCommands = false)

  let update = buildTreeSnapshot(b.addr)
  require(update != nil, "tree update should be created")
  let dump = treeDebugDump(update)
  treeUpdateFree(update)

  require("CheckBox" in dump, "checkbox role should be reported")
  require(countOccurrences(dump, "Mute audio") == 1,
    "descendant label should be merged into the checkbox name exactly once")
  require("GenericContainer" notin dump,
    "layout wrappers should not appear in the tree")
  require("Secret text" notin dump,
    "hidden subtrees should not appear in the tree")
  require("Toggled" in dump or "toggled" in dump,
    "checked state should be reported")

proc testSliderValuesAndExplicitLabel() =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(400.0'f32, 400.0'f32)
  b.node("slider"):
    discard b.size(100.0'f32, 10.0'f32)
    discard b.focusable({FocusTabStop})
    discard b.semanticRole(SemanticSlider)
    discard b.semanticLabel("Volume")
    discard b.semanticValue(0.25'f32, 0.0'f32, 1.0'f32, 0.05'f32)
  b.endUiFrame(buildRenderCommands = false)

  let update = buildTreeSnapshot(b.addr)
  require(update != nil, "tree update should be created")
  let dump = treeDebugDump(update)
  treeUpdateFree(update)

  require("Slider" in dump, "slider role should be reported")
  require("Volume" in dump, "explicit label should be reported")
  require("0.25" in dump, "numeric value should be reported")

proc testExternalLabelledByStaysLinked() =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(400.0'f32, 400.0'f32)
  var captionId = noneNodeId()
  b.node("caption"):
    discard b.fitX().fitY()
    discard b.text("External Caption")
    captionId = b.currentNode.id
  b.node("field"):
    discard b.size(100.0'f32, 20.0'f32)
    discard b.focusable({FocusTabStop, FocusTextInput})
    discard b.semanticRole(SemanticTextInput)
    discard b.semanticLabelledBy(captionId)
    discard b.semanticValueText("hello")
  b.endUiFrame(buildRenderCommands = false)

  let update = buildTreeSnapshot(b.addr)
  require(update != nil, "tree update should be created")
  let dump = treeDebugDump(update)
  treeUpdateFree(update)

  require("TextInput" in dump, "text input role should be reported")
  require(countOccurrences(dump, "External Caption") == 2,
    "external label should both name the control and stay in the tree")
  require("hello" in dump, "textual value should be reported")

proc testAnnotatedWidgets() =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(400.0'f32, 400.0'f32)
  b.layoutVertical:
    discard b.fillX().fitY()
    var checked = true
    discard b.checkbox("Mute audio", checked)
    var volume = 0.5'f32
    discard b.slider(volume)
    var selectedOption = 1
    discard b.dropdown(["Red", "Green", "Blue"], selectedOption)
    var fieldText = "hello world"
    discard b.textField(fieldText, hint = "Name")
    var activeTab = 1
    b.tabBar(["One", "Two"], activeTab):
      b.label("tab content")
  b.endUiFrame(buildRenderCommands = false)

  let update = buildTreeSnapshot(b.addr)
  require(update != nil, "tree update should be created")
  let dump = treeDebugDump(update)
  treeUpdateFree(update)

  require("CheckBox" in dump, "checkbox widget should report its role")
  require(countOccurrences(dump, "Mute audio") == 1,
    "checkbox label should be merged exactly once")
  require("Toggled" in dump or "toggled" in dump,
    "checkbox should report its checked state")
  require("Slider" in dump, "slider widget should report its role")
  require("0.5" in dump, "slider should report its numeric value")
  require("ComboBox" in dump, "dropdown should report its role")
  require("Green" in dump, "dropdown should report the selected entry")
  require("TextInput" in dump, "text field should report its role")
  require("hello world" in dump, "text field should report its value")
  require("Name" in dump, "text field hint should serve as its label")
  require("TabList" in dump and "TabPanel" in dump,
    "tab bar should report tab list and panel roles")

testEmptyBuilderFallsBackToWindowTree()
testActionRouting()
testFrameTreeContainsWidgets()
testFocusedNodeIsReported()
testFilteredTreeAndLabelMerging()
testSliderValuesAndExplicitLabel()
testExternalLabelledByStaysLinked()
testAnnotatedWidgets()
echo "accesskit tree test passed"
