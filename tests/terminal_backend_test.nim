import nuigi
import nuigi/backend/terminal/terminal
import nuigi/core/vecmath
import nuigi/widgets

when defined(nimony):
  import std/assertions

proc require(condition: bool, message: string) =
  when defined(nimony):
    assert condition, message
  else:
    doAssert(condition, message)

proc testUnicodeWidths() =
  require(terminalTextSize("ASCII").width == 5, "ASCII width")
  require(terminalTextSize("cafe\u0301").width == 4, "combining mark width")
  require(terminalTextSize("日本語").width == 6, "CJK width")
  require(terminalTextSize("👩‍💻").width == 2, "ZWJ emoji width")
  require(terminalTextSize("🇳🇿").width == 2, "regional-indicator pair width")
  let wrapped = terminalTextSize("日本a", 4)
  require(wrapped.width == 4 and wrapped.height == 2, "cell-aware wrapping")

proc testTerminalBuilderType() =
  let builder = newTerminalBuilder()
  require(builder.backendType == UiBackendType.Terminal,
    "terminal builder should select terminal backend behavior")

proc testTerminalTableGaps() =
  var builder = newTerminalBuilder()
  discard builder.beginUiFrame(20.0'f32, 10.0'f32)
  var firstIndex = -1
  var secondIndex = -1
  var thirdIndex = -1
  builder.tableLayout([tableColumnFixed(2), tableColumnFixed(2)], 8.0'f32, 4.0'f32):
    discard builder.width(20.0'f32).fitY()
    firstIndex = builder.nodes.len
    builder.node:
      discard builder.size(2.0'f32, 1.0'f32)
    secondIndex = builder.nodes.len
    builder.node:
      discard builder.size(2.0'f32, 1.0'f32)
    thirdIndex = builder.nodes.len
    builder.node:
      discard builder.size(2.0'f32, 1.0'f32)
  builder.endUiFrame(buildRenderCommands = false)

  require(builder.nodes[secondIndex].pos.x - builder.nodes[firstIndex].pos.x == 3.0'f32,
    "terminal tables should use a one-cell column gap")
  require(builder.nodes[thirdIndex].pos.y - builder.nodes[firstIndex].pos.y == 1.0'f32,
    "terminal tables should use a zero-cell row gap")

proc testChunkedUtf8() =
  var parser = default(TerminalInputParser)
  var events = parser.parseInput("\xf0\x9f")
  require(events.len == 0, "partial UTF-8 must be buffered")
  events = parser.parseInput("\x98\x80")
  require(events.len == 1, "completed UTF-8 must emit once")
  require(events[0].kind == TerminalText and events[0].text == "😀", "UTF-8 payload")

proc testKeyboardSequences() =
  var parser = default(TerminalInputParser)
  let arrowEvents = parser.parseInput("\e[1;5A")
  require(arrowEvents.len == 1, "modified arrow event count")
  require(arrowEvents[0].kind == TerminalKey, "modified arrow kind")
  require(arrowEvents[0].key == KeyUp and arrowEvents[0].keyMods == {ModControl},
    "modified arrow payload")

  let kittyEvents = parser.parseInput("\e[13;1:3u")
  require(kittyEvents.len == 1, "Kitty release event count")
  require(kittyEvents[0].kind == TerminalKey and kittyEvents[0].key == KeyEnter and
    kittyEvents[0].action == InputRelease, "Kitty release payload")

proc testEscapeTimeout() =
  var parser = default(TerminalInputParser)
  parser.setEscapeTimeout(1_000)
  require(parser.parseInput("\e").len == 0,
    "a lone escape should wait for a possible sequence")
  let altEvents = parser.parseInput("a")
  require(altEvents.len == 1 and altEvents[0].kind == TerminalKey and
    altEvents[0].key == KeyA and altEvents[0].keyMods == {ModAlt},
    "input before the escape timeout should form an Alt chord")

  var backend = default(TerminalBackend)
  backend.setEscapeTimeout(0)
  let escapeInput = backend.pollInput("\e")
  require(KeyEscape in escapeInput.keysPressed,
    "the backend should emit Escape when its timeout expires")
  require(backend.hadEvents,
    "a timed-out Escape should mark the backend as active")

proc testExternalInputAndKittyNegotiation() =
  var backend = default(TerminalBackend)
  discard backend.pollInput("\e[?25u")
  require(backend.lastEvents.len == 1 and
    backend.lastEvents[0].kind == TerminalKittyFlags,
    "the backend should expose parsed events from the latest poll")
  let pressed = backend.pollInput("\e[97;1:1u")
  require(KeyA in pressed.keysPressed and KeyA in pressed.keysDown,
    "negotiated Kitty press should set held key state")
  let idle = backend.pollInput("")
  require(backend.lastEvents.len == 0,
    "an idle poll should clear the previous parsed-event batch")
  require(KeyA in idle.keysDown,
    "negotiated Kitty held key should survive an idle frame")
  let released = backend.pollInput("\e[97;1:3u")
  require(KeyA in released.keysReleased and KeyA notin released.keysDown,
    "negotiated Kitty release should clear held key state")

  discard backend.pollInput("\e[97;1:1u\e[97;1:1u")
  require(backend.lastEvents.len == 2 and
    backend.lastEvents[0].kind == TerminalKey and
    backend.lastEvents[1].kind == TerminalKey,
    "the parsed event batch should preserve duplicate rapid key presses")

  var legacyBackend = default(TerminalBackend)
  discard legacyBackend.pollInput("\e[?0u")
  discard legacyBackend.pollInput("\e[97;1:1u")
  let legacyIdle = legacyBackend.pollInput("")
  require(KeyA notin legacyIdle.keysDown,
    "unsupported Kitty keys should remain frame-local")

proc testMouseSequence() =
  var parser = default(TerminalInputParser)
  let events = parser.parseInput("\e[<0;4;3M")
  require(events.len == 1, "mouse event count")
  require(events[0].kind == TerminalMouseButton, "mouse event kind")
  require(events[0].button == MouseLeft and events[0].mouseAction == InputPress,
    "mouse button payload")
  require(events[0].buttonX == 3 and events[0].buttonY == 2, "mouse coordinates")

proc testShouldRender() =
  var builder = default(UiBuilder)
  require(not builder.shouldRender(false), "idle builder should not render")
  require(builder.shouldRender(true), "host events should render")
  require(builder.shouldRender(false), "one frame after host events should render")
  require(not builder.shouldRender(false), "second idle frame should not render")

  builder.anythingAnimating = true
  require(builder.shouldRender(false), "explicit animation activity should render")
  builder.anythingAnimating = false
  require(builder.shouldRender(false), "one frame after explicit activity should render")
  require(not builder.shouldRender(false), "explicit activity grace should expire")

  builder.middleDragScroll = vec2(0.0'f32, 1.0'f32)
  require(builder.shouldRender(false), "middle-drag scrolling should render")
  builder.middleDragScroll = vec2(0.0'f32)
  require(builder.shouldRender(false), "one frame after middle-drag should render")
  require(not builder.shouldRender(false), "middle-drag grace should expire")

  builder.virtualNodes = @[default(UiVirtualTree)]
  require(builder.shouldRender(false), "virtual nodes should render")
  builder.virtualNodes.setLen(0)
  require(builder.shouldRender(false), "one frame after virtual nodes should render")
  require(not builder.shouldRender(false), "virtual-node grace should expire")

  builder.animations = @[UiAnimation(
    unchangedFrames: 0,
    fields: @[UiFieldAnimation(currentValue: 0.0'f32, targetValue: 1.0'f32)],
  )]
  require(builder.shouldRender(false), "active field animations should render")
  builder.animations[0].fields[0].currentValue = 1.0'f32
  require(builder.shouldRender(false), "one frame after settled animations should render")
  require(not builder.shouldRender(false), "settled animation grace should expire")
  builder.animations[0].fields[0].currentValue = 0.0'f32
  builder.animations[0].unchangedFrames = 1
  require(not builder.shouldRender(false), "untouched animations should not render")

proc main() =
  testTerminalBuilderType()
  testTerminalTableGaps()
  testUnicodeWidths()
  testChunkedUtf8()
  testKeyboardSequences()
  testEscapeTimeout()
  testExternalInputAndKittyNegotiation()
  testMouseSequence()
  testShouldRender()

main()
