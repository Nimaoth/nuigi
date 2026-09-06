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

proc runTests() =
  testTerminalTextFieldIsOneRowHigh()
  testTextFieldKeyboardFocus()
  testTextFieldShowsFocus()

when isMainModule:
  runTests()
