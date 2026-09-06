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

var testClipboard = ""

proc readTestClipboard(): string {.nimcall, raises: [].} =
  testClipboard

proc writeTestClipboard(text: string): bool {.nimcall, raises: [].} =
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

  require(b.frame.nodes[1].size.x == 35.0'f32,
    "text field should respect its maximum width")
  require(state.scrollOffsetX > 0.0'f32,
    "focused text extending past the content width should scroll horizontally")
  require(b.textInputRequest.active,
    "focused text field should request platform text input")
  require(b.textInputRequest.rectSize.x == 35.0'f32,
    "text input request should contain the final text field width")
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

  require(b.frame.nodes[1].size.x == 80.0'f32,
    "text field should respect its minimum width")

proc runTests() =
  testTerminalTextFieldIsOneRowHigh()
  testTextFieldKeyboardFocus()
  testTextFieldShowsFocus()
  testUnicodeSelectionAndReplacement()
  testClipboardShortcuts()
  testMouseSelection()
  testHorizontalScrollAndTextInputRequest()
  testMinimumWidth()

when isMainModule:
  runTests()
