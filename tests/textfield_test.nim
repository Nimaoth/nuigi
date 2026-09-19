import std/math
import nuigi, nuigi/core/vecmath
import nuigi/widgets/textfield

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

proc fractionalMeasureText(text: openArray[char], fontId: int16, fontSize: float32,
    maxWidth: float32): UiTextArrangement {.gcsafe, raises: [].} =
  result = fixedMeasureText(text, fontId, fontSize, maxWidth)
  if text.len > 0:
    result.size.x += 0.17'f32

proc fixedTerminalMeasureText(text: openArray[char], fontId: int16,
    fontSize: float32, maxWidth: float32): UiTextArrangement {.gcsafe, raises: [].} =
  let _ = fontId
  let naturalWidth = text.len.float32
  let lineCount =
    if maxWidth > 0.0'f32 and naturalWidth > maxWidth:
      int((naturalWidth + maxWidth - 1.0'f32) / maxWidth)
    else:
      1
  result = UiTextArrangement()
  result.fontSize = fontSize
  result.size = vec2(
    if maxWidth >= 0.0'f32: min(naturalWidth, maxWidth) else: naturalWidth,
    lineCount.float32)

proc hasAccentFocusHighlight(b: UiBuilder): bool =
  let accent = b.themeStyle(UiStyleIndexAccent)[].borderColor
  for index in 0 ..< b.frame.nodes.len:
    let style = b.nodeStyle(index)
    if style.borderWidth >= 2.0'f32 and style.borderColor == accent:
      return true
  false

proc hasTextCursor(b: UiBuilder): bool =
  for index in 0 ..< b.frame.nodes.len:
    if b.frame.nodes[index].styleIndex == UiStyleIndexTextCursor.uint16:
      return true
  false

proc textCursorIndex(b: UiBuilder): int =
  for index in 0 ..< b.frame.nodes.len:
    if b.frame.nodes[index].styleIndex == UiStyleIndexTextCursor.uint16:
      return index
  -1

proc textContainerIndex(b: UiBuilder): int =
  for index in 0 ..< b.frame.nodes.len:
    if MaskChildren in b.frame.nodes[index].flags:
      return index
  -1

proc textFieldIndex(b: UiBuilder): int =
  let containerIndex = b.textContainerIndex()
  if containerIndex >= 0:
    return b.frame.nodes[containerIndex].parent.int
  return -1

var testClipboard = ""

proc readTestClipboard(): string {.nimcall, gcsafe, raises: [].} =
  gcsafeb:
    testClipboard

proc writeTestClipboard(text: string): bool {.nimcall, gcsafe, raises: [].} =
  gcsafeb:
    testClipboard = text
    true

proc testTerminalTextFieldIsOneRowHigh() =
  var b = newBuilder(fixedTerminalMeasureText, backendType = UiBackendType.Terminal)
  for styleIndex in low(UiStyleIndex) .. high(UiStyleIndex):
    b.themeStyle(styleIndex).paddingY = 0.0'f32
  for styleIndex in low(UiTextStyleIndex) .. high(UiTextStyleIndex):
    b.themeTextStyle(styleIndex).fontSize = 1.0'f32
  discard b.beginUiFrame(200.0'f32, 120.0'f32)
  b.defaultText.fontSize = 1.0'f32

  var text = ""
  let nodeIndex = b.nodes.len
  discard b.textField(text, "Text")
  discard b.postProcessChildren(0)

  require(b.nodes[nodeIndex].size.y == 1.0'f32,
    "terminal text field should be exactly one row high")

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

proc testTextFieldShowsFocus() =
  var b = newBuilder(fixedMeasureText)
  var text = ""

  discard b.beginUiFrame(200.0, 120.0)
  discard b.textField(text, "Name")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  discard b.textField(text, "Name")
  require(b.hasAccentFocusHighlight(),
    "focused text fields should show an accent border")

proc testUnicodeSelectionAndReplacement() =
  var b = newBuilder(fixedMeasureText)
  var text = "a👩‍💻"
  let state = TextFieldStorage(cursorPos: text.len)

  discard b.beginUiFrame(200.0, 120.0)
  discard b.textField(text, "Name", state)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  discard b.textField(text, "Name", state)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyLeft}, modsDown: {ModShift}))
  discard b.textField(text, "Name", state)
  require(state.selectionActive, "Shift+Left should create a selection")
  require(state.selectionAnchor == text.len and state.cursorPos == 1,
    "cursor movement should select the complete joined emoji grapheme")
  require(not b.hasTextCursor(),
    "text cursor should be hidden while the selection is non-empty")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(textInput: "é"))
  discard b.textField(text, "Name", state)
  require(text == "aé", "text input should replace the selected Unicode text")
  require(state.cursorPos == text.len and not state.selectionActive,
    "replacement should place the cursor after the inserted UTF-8 text")
  require(b.hasTextCursor(),
    "text cursor should return after the selection is cleared")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyBackspace}))
  discard b.textField(text, "Name", state)
  require(text == "a", "Backspace should remove one complete multibyte rune")

proc testClipboardShortcuts() =
  var b = newBuilder(fixedMeasureText)
  b.readClipboardFn = readTestClipboard
  b.writeClipboardFn = writeTestClipboard
  var text = "copy me"
  let state = TextFieldStorage(cursorPos: text.len)
  testClipboard = ""

  discard b.beginUiFrame(200.0, 120.0)
  discard b.textField(text, "Name", state)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  discard b.textField(text, "Name", state)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyA, KeyC}, modsDown: {ModControl}))
  discard b.textField(text, "Name", state)
  require(testClipboard == "copy me", "Ctrl+A then Ctrl+C should copy all text")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyX}, modsDown: {ModControl}))
  discard b.textField(text, "Name", state)
  require(text.len == 0, "Ctrl+X should cut the selection")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyV}, modsDown: {ModSuper}))
  discard b.textField(text, "Name", state)
  require(text == "copy me", "Super+V should paste clipboard text")

proc testMouseSelection() =
  var b = newBuilder(fixedMeasureText)
  var text = "abcdef"
  let state = TextFieldStorage()

  discard b.beginUiFrame(200.0, 120.0)
  discard b.textField(text, "Name", state)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(
      mouse: vec2(31.0'f32, 10.0'f32),
      mouseDown: {MouseLeft},
      mousePressed: {MouseLeft}))
  discard b.textField(text, "Name", state)
  require(state.cursorPos == 3, "mouse press should place the cursor at the nearest boundary")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(
      mouse: vec2(11.0'f32, 10.0'f32),
      mouseDown: {MouseLeft}))
  discard b.textField(text, "Name", state)
  require(state.selectionActive and state.selectionAnchor == 3 and state.cursorPos == 1,
    "mouse drag should select text from the press position")

proc testMultipleClickSelection() =
  var b = newBuilder(fixedMeasureText)
  var text = "one two!"
  let state = TextFieldStorage()

  discard b.beginUiFrame(200.0, 120.0)
  discard b.textField(text, "Name", state)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(
      mouse: vec2(51.0'f32, 10.0'f32),
      mouseDown: {MouseLeft},
      mousePressed: {MouseLeft},
      mouseClickCount: 2))
  discard b.textField(text, "Name", state)
  require(state.selectionActive and state.selectionAnchor == 4 and state.cursorPos == 7,
    "double-click should select the word under the pointer")
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(
      mouse: vec2(51.0'f32, 10.0'f32),
      mouseDown: {MouseLeft},
      mousePressed: {MouseLeft},
      mouseClickCount: 3))
  discard b.textField(text, "Name", state)
  require(state.selectionActive and state.selectionAnchor == 0 and
      state.cursorPos == text.len,
    "triple-click should select all text")

proc testHorizontalScrollAndTextInputRequest() =
  var b = newBuilder(fixedMeasureText)
  var text = "abcdefghij"
  let state = TextFieldStorage(cursorPos: text.len)

  discard b.beginUiFrame(200.0, 120.0)
  discard b.textField(text, "Name", state, maxWidth = 35.0'f32)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  discard b.textField(text, "Name", state, maxWidth = 35.0'f32)
  b.endUiFrame(buildRenderCommands = false)

  let containerIndex = b.textContainerIndex()
  require(containerIndex >= 0 and b.frame.nodes[containerIndex].size.x == 35.0'f32,
    "text container should respect the text field maximum width")
  require(state.scrollOffsetX > 0.0'f32,
    "focused text extending past the content width should scroll horizontally")
  let cursorIndex = b.textCursorIndex()
  let fieldIndex = b.textFieldIndex()
  let fieldStyle = b.nodeStyle(fieldIndex)
  let contentWidth = b.frame.nodes[fieldIndex].size.x - fieldStyle.paddingX * 2.0'f32
  require(cursorIndex >= 0 and
      b.frame.nodes[cursorIndex].pos.x + b.frame.nodes[cursorIndex].size.x <= contentWidth,
    "cursor at the end of overflowing text should remain within the outer field")
  require(b.textInputRequest.active,
    "focused text field should request platform text input")
  require(fieldIndex >= 0 and
      b.textInputRequest.rectSize.x == b.frame.nodes[fieldIndex].size.x,
    "text input request should contain the final outer text field width")
  require(b.textInputRequest.cursorOffset >= 0.0'f32 and
      b.textInputRequest.cursorOffset <= b.textInputRequest.rectSize.x,
    "IME cursor offset should stay within the text field rectangle")

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyEscape}))
  discard b.textField(text, "Name", state, maxWidth = 35.0'f32)
  b.endUiFrame(buildRenderCommands = false)
  require(not b.textInputRequest.active,
    "clearing text field focus should stop requesting platform text input")

proc testMinimumWidth() =
  var b = newBuilder(fixedMeasureText)
  var text = "a"

  discard b.beginUiFrame(200.0, 120.0)
  discard b.textField(text, "Name", minWidth = 80.0'f32)
  b.endUiFrame(buildRenderCommands = false)

  let containerIndex = b.textContainerIndex()
  require(containerIndex >= 0 and b.frame.nodes[containerIndex].size.x == 80.0'f32,
    "text container should respect the text field minimum width")

proc testFractionalWidthDoesNotScroll() =
  var b = newBuilder(fractionalMeasureText)
  var text = "abcdef"
  let state = TextFieldStorage(cursorPos: text.len)

  discard b.beginUiFrame(200.0, 120.0)
  discard b.textField(text, "Name", state)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0, 120.0,
    input = UiInputSnapshot(keysPressed: {KeyTab}))
  discard b.textField(text, "Name", state)
  b.endUiFrame(buildRenderCommands = false)

  let fieldIndex = b.textFieldIndex()
  require(fieldIndex >= 0 and
      b.frame.nodes[fieldIndex].size.x == ceil(b.frame.nodes[fieldIndex].size.x),
    "naturally fitted text field width should round up to a whole number")
  require(state.scrollOffsetX == 0.0'f32,
    "text that fits the field exactly should not scroll to reserve cursor width")

proc runTests() =
  testTerminalTextFieldIsOneRowHigh()
  testTextFieldKeyboardFocus()
  testTextFieldShowsFocus()
  testUnicodeSelectionAndReplacement()
  testClipboardShortcuts()
  testMouseSelection()
  testMultipleClickSelection()
  testHorizontalScrollAndTextInputRequest()
  testMinimumWidth()
  testFractionalWidthDoesNotScroll()

when isMainModule:
  runTests()
