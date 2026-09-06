import nuigi
import nuigi/backend/terminal/terminal
import nuigi/core/[timer, vecmath]
import nuigi/demo/demo_window
import nuigi/widgets/windows

when defined(windows):
  proc sleepMillis(milliseconds: uint32) {.stdcall, dynlib: "kernel32", importc: "Sleep".}
else:
  proc posixUsleep(microseconds: uint32): int32 {.cdecl, importc: "usleep", header: "<unistd.h>".}
  proc sleepMillis(milliseconds: uint32) =
    discard posixUsleep(milliseconds * 1000'u32)

var backend: TerminalBackend
var builder = newTerminalBuilder()
var running = true
var lastTicks = getTicksNS()
var firstFrame = true

proc configureTerminalTheme(builder: var UiBuilder) =
  builder.defaultText.fontSize = 1.0'f32
  for styleIndex in low(UiStyleIndex) .. high(UiStyleIndex):
    let style = builder.themeStyle(styleIndex)
    style.paddingX = min(style.paddingX, 1.0'f32)
    style.paddingY = 0.0'f32
    style.borderWidth = min(style.borderWidth, 1.0'f32)
    style.cornerRadius = 0.0'f32
  for styleIndex in low(UiTextStyleIndex) .. high(UiTextStyleIndex):
    builder.themeTextStyle(styleIndex).fontSize = 1.0'f32

proc buildDemo(builder: var UiBuilder) =
  builder.windowSpace()

  builder.node("overlays"):
    discard builder.fill()
    discard builder.noHover()
    builder.overlays = builder.currentNode.id

  builder.window("Demo", 0.0'f32, 0.0'f32,
      builder.frameCtx.viewportSize.x, builder.frameCtx.viewportSize.y):
    builder.buildDemoUi()

proc main() =
  backend.init()
  defer: backend.deinit()
  builder.configureTerminalTheme()

  while running:
    let input = backend.pollInput()
    if not builder.shouldRender(firstFrame or backend.hadEvents):
      sleepMillis(8)
      continue
    firstFrame = false

    if KeyEscape in input.keysPressed or KeyQ in input.keysPressed:
      running = false
      continue

    let nowTicks = getTicksNS()
    let delta = min(0.1'f32, (nowTicks - lastTicks).float32 / 1_000_000_000.0'f32)
    lastTicks = nowTicks
    discard builder.beginUiFrame(UiFrameContext(
      viewportSize: vec2(backend.width.float32, backend.height.float32),
      animationTick: delta,
      time: nowTicks.float32 / 1_000_000_000.0'f32,
      input: input,
    ))
    builder.buildDemo()
    builder.endUiFrame()
    backend.render(builder)
    sleepMillis(8)

main()
