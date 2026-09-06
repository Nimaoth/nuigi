## ANSI terminal backend for nuigi.
##
## The backend uses one terminal cell as one nuigi layout unit. It consumes the
## ordinary non-mesh render command stream produced by `endUiFrame`.

import std/[math, syncio]
import nuigi
import nuigi/core/vecmath
import nuigi/rendering/mesh
import ./[terminal_input, terminal_unicode]

export terminal_input, terminal_unicode

when defined(windows):
  type
    WinHandle = pointer
    WinDword = uint32
    WinBool = int32
    WinCoord = object
      x, y: int16
    WinSmallRect = object
      left, top, right, bottom: int16
    WinConsoleScreenBufferInfo = object
      size, cursorPosition: WinCoord
      attributes: uint16
      window: WinSmallRect
      maximumWindowSize: WinCoord

  proc getStdHandle(kind: int32): WinHandle {.
    stdcall, dynlib: "kernel32", importc: "GetStdHandle".}
  proc getConsoleMode(handle: WinHandle, mode: ptr WinDword): WinBool {.
    stdcall, dynlib: "kernel32", importc: "GetConsoleMode".}
  proc setConsoleMode(handle: WinHandle, mode: WinDword): WinBool {.
    stdcall, dynlib: "kernel32", importc: "SetConsoleMode".}
  proc getConsoleScreenBufferInfo(handle: WinHandle,
    info: ptr WinConsoleScreenBufferInfo): WinBool {.
    stdcall, dynlib: "kernel32", importc: "GetConsoleScreenBufferInfo".}

  const
    StdInputHandle = -10'i32
    StdOutputHandle = -11'i32
    EnableVirtualTerminalProcessing = 0x0004.WinDword
    EnableVirtualTerminalInput = 0x0200.WinDword
    EnableLineInput = 0x0002.WinDword
    EnableEchoInput = 0x0004.WinDword

  var oldInputMode, oldOutputMode: WinDword

  proc terminalKbhit(): cint {.cdecl, dynlib: "msvcrt", importc: "_kbhit".}
  proc terminalGetch(): cint {.cdecl, dynlib: "msvcrt", importc: "_getch".}

  proc initConsole() =
    let inputHandle = getStdHandle(StdInputHandle)
    let outputHandle = getStdHandle(StdOutputHandle)
    if getConsoleMode(inputHandle, oldInputMode.addr) != 0:
      discard setConsoleMode(inputHandle,
        (oldInputMode or EnableVirtualTerminalInput) and not (EnableLineInput or EnableEchoInput))
    if getConsoleMode(outputHandle, oldOutputMode.addr) != 0:
      discard setConsoleMode(outputHandle, oldOutputMode or EnableVirtualTerminalProcessing)

  proc deinitConsole() =
    if oldInputMode != 0:
      discard setConsoleMode(getStdHandle(StdInputHandle), oldInputMode)
    if oldOutputMode != 0:
      discard setConsoleMode(getStdHandle(StdOutputHandle), oldOutputMode)
else:
  import std/terminal
  import posix, termios

  var oldTerminalMode: Termios
  var hasOldTerminalMode = false

  proc terminalKbhit(): cint =
    var timeout = Timeval(tv_sec: Time(0), tv_usec: 0)
    var descriptors: TFdSet
    FD_ZERO(descriptors)
    FD_SET(STDIN_FILENO, descriptors)
    discard select(STDIN_FILENO + 1, descriptors.addr, nil, nil, timeout.addr)
    FD_ISSET(STDIN_FILENO, descriptors)

  proc terminalGetch(): cint =
    var value: char
    if posix.read(STDIN_FILENO, value.addr, 1) == 1:
      return value.ord.cint
    -1

  proc initConsole() =
    if tcGetAttr(STDIN_FILENO, oldTerminalMode.addr) == 0:
      hasOldTerminalMode = true
      var mode = oldTerminalMode
      mode.c_lflag = mode.c_lflag and not Cflag(ICANON or ECHO)
      mode.c_cc[VMIN] = 0.char
      mode.c_cc[VTIME] = 0.char
      discard tcSetAttr(STDIN_FILENO, TCSANOW, mode.addr)

  proc deinitConsole() =
    if hasOldTerminalMode:
      discard tcSetAttr(STDIN_FILENO, TCSANOW, oldTerminalMode.addr)

const
  EnterAlternateScreen = "\e[?47h\e[?1049h"
  ExitAlternateScreen = "\e[?47l\e[?1049l"
  DisableAutoWrap = "\e[?7l"
  EnableAutoWrap = "\e[?7h"
  EnableMouse = "\e[?1002h\e[?1003h\e[?1006h"
  DisableMouse = "\e[?1002l\e[?1003l\e[?1006l"
  EnableKittyKeyboard = "\e[>11u"
  DisableKittyKeyboard = "\e[<u"

type
  TerminalColor = object
    r, g, b: uint8

  TerminalCell = object
    grapheme: string
    foreground, background: TerminalColor
    continuation: bool

  CellRect = object
    x, y, w, h: int

  TerminalBackend* = object
    width*, height*: int
    hadEvents*: bool
    cells: seq[TerminalCell]
    inputParser: TerminalInputParser
    input*: UiInputSnapshot
    kittyKeyboard: bool
    active*: bool

proc rgb(color: UiColor): TerminalColor =
  return TerminalColor(
    r: uint8(clamp(round(color.r * 255.0'f32), 0.0'f32, 255.0'f32)),
    g: uint8(clamp(round(color.g * 255.0'f32), 0.0'f32, 255.0'f32)),
    b: uint8(clamp(round(color.b * 255.0'f32), 0.0'f32, 255.0'f32)),
  )

func intersection(a, b: CellRect): CellRect =
  let x2 = min(a.x + a.w, b.x + b.w)
  let y2 = min(a.y + a.h, b.y + b.h)
  let x = max(a.x, b.x)
  let y = max(a.y, b.y)
  return CellRect(x: x, y: y, w: max(0, x2 - x), h: max(0, y2 - y))

func contains(rect: CellRect, x, y: int): bool {.inline.} =
  return x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h

proc transformedCellRect(transform: UiAffine2, pos, size: Vec2): CellRect =
  let bounds = transformedRectAabb(transform, pos, size)
  let x = floor(bounds.pos.x).int
  let y = floor(bounds.pos.y).int
  return CellRect(
    x: x,
    y: y,
    w: max(0, ceil(bounds.pos.x + bounds.size.x).int - x),
    h: max(0, ceil(bounds.pos.y + bounds.size.y).int - y),
  )

proc terminalMeasureText*(text: openArray[char], fontId: UiFontId,
    fontSize: float32, maxWidth: float32): UiTextArrangement {.raises: [].} =
  let cellLimit = if maxWidth > 0: max(1, floor(maxWidth).int) else: 0
  let measured = terminalTextSize(text, cellLimit)
  return UiTextArrangement(
    fontSize: 1.0'f32,
    size: vec2(measured.width.float32, measured.height.float32),
    ascent: 1.0'f32,
    descent: 0.0'f32,
  )

proc newTerminalBuilder*(): UiBuilder =
  return newBuilder(terminalMeasureText, textHeight = 1.0'f32,
    backendType = UiBackendType.Terminal)

proc resize(backend: var TerminalBackend, width, height: int) =
  backend.width = max(1, width)
  backend.height = max(1, height)
  backend.cells.setLen(backend.width * backend.height)

proc terminalSize(): tuple[width, height: int] =
  when defined(windows):
    var info = default(WinConsoleScreenBufferInfo)
    if getConsoleScreenBufferInfo(getStdHandle(StdOutputHandle), info.addr) != 0:
      return (width: max(1, info.window.right.int - info.window.left.int + 1),
        height: max(1, info.window.bottom.int - info.window.top.int + 1))
    return (width: 80, height: 24)
  else:
    try:
      return (width: max(1, terminalWidth()), height: max(1, terminalHeight()))
    except CatchableError:
      return (width: 80, height: 24)

proc init*(backend: var TerminalBackend) =
  if backend.active:
    return
  let size = terminalSize()
  backend.resize(size.width, size.height)
  backend.inputParser.escapeTimeoutMs = DefaultEscapeTimeoutMs
  backend.active = true
  when defined(nimony):
    initConsole()
    stdout.write(EnterAlternateScreen & DisableAutoWrap & "\e[2J\e[H\e[?25l")
    stdout.write(EnableMouse)
    stdout.write(EnableKittyKeyboard)
    stdout.write("\e[18t")
    stdout.flushFile()
  else:
    try:
      initConsole()
      stdout.write(EnterAlternateScreen & DisableAutoWrap & "\e[2J\e[H\e[?25l")
      stdout.write(EnableMouse)
      stdout.write(EnableKittyKeyboard)
      stdout.write("\e[18t")
      stdout.flushFile()
    except CatchableError:
      discard

proc deinit*(backend: var TerminalBackend) =
  if not backend.active:
    return
  backend.active = false
  when defined(nimony):
    stdout.write(DisableKittyKeyboard)
    stdout.write(DisableMouse)
    stdout.write("\e[0m\e[?25h" & EnableAutoWrap & ExitAlternateScreen)
    stdout.flushFile()
    deinitConsole()
  else:
    try:
      stdout.write(DisableKittyKeyboard)
      stdout.write(DisableMouse)
      stdout.write("\e[0m\e[?25h" & EnableAutoWrap & ExitAlternateScreen)
      stdout.flushFile()
      deinitConsole()
    except CatchableError:
      discard

proc readAvailableInput(): string =
  var input = ""
  when defined(nimony):
    while terminalKbhit() != 0:
      let value = terminalGetch()
      if value >= 0:
        input.add char(value)
  else:
    try:
      while terminalKbhit() != 0:
        let value = terminalGetch()
        if value >= 0:
          input.add char(value)
    except CatchableError:
      discard
  return input

proc beginInputFrame(backend: var TerminalBackend) =
  inc backend.input.frameIndex
  backend.input.mouseDelta = vec2(0.0'f32)
  backend.input.wheel = vec2(0.0'f32)
  backend.input.mousePressed = {}
  backend.input.mouseReleased = {}
  backend.input.keysPressed = {}
  backend.input.keysReleased = {}
  backend.input.keysRepeated = {}
  backend.input.textInput.setLen(0)
  if not backend.kittyKeyboard:
    backend.input.keysDown = {}

proc applyInputEvent(backend: var TerminalBackend, event: TerminalInputEvent) =
  case event.kind
  of TerminalText:
    backend.input.textInput.add event.text
    backend.input.modsDown = event.textMods
  of TerminalKey:
    backend.input.modsDown = event.keyMods
    case event.action
    of InputPress:
      backend.input.keysDown.incl event.key
      backend.input.keysPressed.incl event.key
    of InputRepeat:
      backend.input.keysDown.incl event.key
      backend.input.keysRepeated.incl event.key
    of InputRelease:
      backend.input.keysDown.excl event.key
      backend.input.keysReleased.incl event.key
  of TerminalMouseButton:
    let oldMouse = backend.input.mouse
    backend.input.mouse = vec2(event.buttonX.float32, event.buttonY.float32)
    backend.input.mouseDelta += backend.input.mouse - oldMouse
    backend.input.modsDown = event.buttonMods
    case event.mouseAction
    of InputPress:
      backend.input.mouseDown.incl event.button
      backend.input.mousePressed.incl event.button
    of InputRelease:
      backend.input.mouseDown.excl event.button
      backend.input.mouseReleased.incl event.button
    of InputRepeat:
      discard
  of TerminalMouseMove:
    let oldMouse = backend.input.mouse
    backend.input.mouse = vec2(event.moveX.float32, event.moveY.float32)
    backend.input.mouseDelta += backend.input.mouse - oldMouse
    backend.input.modsDown = event.moveMods
  of TerminalMouseWheel:
    backend.input.mouse = vec2(event.wheelX.float32, event.wheelY.float32)
    backend.input.wheel.y += event.wheelDelta.float32
    backend.input.modsDown = event.wheelMods
  of TerminalGridSize:
    backend.resize(event.width, event.height)
  of TerminalKittyFlags:
    backend.kittyKeyboard = event.kittyFlags != 0
  of TerminalPixelSize, TerminalCellPixelSize:
    discard

proc pollInput*(backend: var TerminalBackend): UiInputSnapshot =
  backend.beginInputFrame()
  backend.hadEvents = false
  let inputBytes = readAvailableInput()
  let events = backend.inputParser.parseInput(inputBytes)
  backend.hadEvents = events.len > 0
  for event in events:
    backend.applyInputEvent(event)

  let size = terminalSize()
  if size.width != backend.width or size.height != backend.height:
    backend.resize(size.width, size.height)
    backend.hadEvents = true
  backend.input

proc clear(backend: var TerminalBackend) =
  let blank = TerminalCell(grapheme: " ", foreground: TerminalColor(r: 255, g: 255, b: 255))
  for cell in backend.cells.mitems:
    cell = blank

proc clearWideCell(backend: var TerminalBackend, x, y: int) =
  if x < 0 or x >= backend.width or y < 0 or y >= backend.height:
    return
  let index = y * backend.width + x
  if backend.cells[index].continuation and x > 0:
    backend.cells[index - 1].grapheme = " "
  if x + 1 < backend.width and backend.cells[index + 1].continuation:
    backend.cells[index + 1] = TerminalCell(grapheme: " ")

proc putCell(backend: var TerminalBackend, x, y: int, grapheme: string, width: int,
    foreground: TerminalColor, clip: CellRect) =
  if width <= 0 or not clip.contains(x, y) or x < 0 or x >= backend.width or
      y < 0 or y >= backend.height or x + width > min(backend.width, clip.x + clip.w):
    return
  backend.clearWideCell(x, y)
  let index = y * backend.width + x
  backend.cells[index].grapheme = grapheme
  backend.cells[index].foreground = foreground
  backend.cells[index].continuation = false
  for offset in 1 ..< width:
    backend.clearWideCell(x + offset, y)
    backend.cells[index + offset].grapheme = ""
    backend.cells[index + offset].foreground = foreground
    backend.cells[index + offset].continuation = true

proc fillRect(backend: var TerminalBackend, rect, clip: CellRect, color: UiColor) =
  if color.a <= 0.0'f32:
    return
  let area = intersection(intersection(rect, clip), CellRect(x: 0, y: 0, w: backend.width, h: backend.height))
  let background = color.rgb
  for y in area.y ..< area.y + area.h:
    for x in area.x ..< area.x + area.w:
      backend.clearWideCell(x, y)
      let index = y * backend.width + x
      backend.cells[index].grapheme = " "
      backend.cells[index].background = background
      backend.cells[index].continuation = false

proc drawLine(backend: var TerminalBackend, first, last: Vec2, color: UiColor, clip: CellRect) =
  var x0 = round(first.x).int
  var y0 = round(first.y).int
  let x1 = round(last.x).int
  let y1 = round(last.y).int
  let dx = abs(x1 - x0)
  let sx = if x0 < x1: 1 else: -1
  let dy = -abs(y1 - y0)
  let sy = if y0 < y1: 1 else: -1
  var error = dx + dy
  let glyph = if dx > -dy * 2: "─" elif -dy > dx * 2: "│" elif sx == sy: "╲" else: "╱"
  while true:
    backend.putCell(x0, y0, glyph, 1, color.rgb, clip)
    if x0 == x1 and y0 == y1:
      break
    let doubled = error * 2
    if doubled >= dy:
      error += dy
      x0 += sx
    if doubled <= dx:
      error += dx
      y0 += sy

proc drawStroke(backend: var TerminalBackend, rect, clip: CellRect, color: UiColor) =
  if rect.w <= 0 or rect.h <= 0:
    return
  let right = rect.x + rect.w - 1
  let bottom = rect.y + rect.h - 1
  for x in rect.x .. right:
    backend.putCell(x, rect.y, (if x == rect.x: "┌" elif x == right: "┐" else: "─"), 1, color.rgb, clip)
    if bottom != rect.y:
      backend.putCell(x, bottom, (if x == rect.x: "└" elif x == right: "┘" else: "─"), 1, color.rgb, clip)
  for y in rect.y + 1 ..< bottom:
    backend.putCell(rect.x, y, "│", 1, color.rgb, clip)
    if right != rect.x:
      backend.putCell(right, y, "│", 1, color.rgb, clip)

proc drawText(backend: var TerminalBackend, pos: Vec2, text: string, color: UiColor,
    clip: CellRect, wrap: bool) =
  var x = floor(pos.x).int
  var y = floor(pos.y).int
  let lineStart = x
  for grapheme in text.terminalGraphemes:
    if grapheme.newline:
      x = lineStart
      inc y
      continue
    if wrap and x > lineStart and x + grapheme.width > clip.x + clip.w:
      x = lineStart
      inc y
    backend.putCell(x, y, grapheme.text, grapheme.width, color.rgb, clip)
    x += grapheme.width

proc render*(backend: var TerminalBackend, builder: UiBuilder) =
  backend.clear()
  let screen = CellRect(x: 0, y: 0, w: backend.width, h: backend.height)
  var clips = @[screen]
  var transforms = @[identityAffine2()]

  for command in builder.frameOutput.commands:
    let transform = transforms[^1]
    case command.kind
    of CmdTransformPush:
      transforms.add applyNodeRenderTransform(transform, command.pivot, command.offset,
        command.rotation, command.scale)
    of CmdTransformPop:
      if transforms.len > 1:
        discard transforms.pop()
    of CmdClipPush:
      clips.add intersection(clips[^1], transformedCellRect(transform, command.pos, command.size))
    of CmdClipPop:
      if clips.len > 1:
        discard clips.pop()
    of CmdRectFill:
      backend.fillRect(transformedCellRect(transform, command.pos, command.size), clips[^1], command.color)
    of CmdRectStroke:
      backend.drawStroke(transformedCellRect(transform, command.pos, command.size), clips[^1], command.color)
    of CmdCircleFill:
      let center = transform.transformPoint2(command.pos)
      let radius = max(0, round(command.radius).int)
      for y in -radius .. radius:
        let span = floor(sqrt(max(0.0, float(radius * radius - y * y)))).int
        backend.fillRect(CellRect(x: round(center.x).int - span, y: round(center.y).int + y,
          w: span * 2 + 1, h: 1), clips[^1], command.color)
    of CmdLine:
      backend.drawLine(transform.transformPoint2(command.pos), transform.transformPoint2(command.pos2),
        command.color, clips[^1])
    of CmdText:
      let textIndex = command.textIndex.int - 1
      if textIndex >= 0 and textIndex < builder.frame.texts.len:
        let nodeText = builder.frame.texts[textIndex]
        let wrap = command.nodeIndex >= 0 and command.nodeIndex.int < builder.frame.nodes.len and
          WrapText in builder.frame.nodes[command.nodeIndex.int].flags
        backend.drawText(transform.transformPoint2(command.pos), nodeText.text.value,
          nodeText.textColor, clips[^1], wrap)
    of CmdImage:
      let rect = transformedCellRect(transform, command.pos, command.size)
      backend.fillRect(rect, clips[^1], command.color)
      for y in rect.y ..< rect.y + rect.h:
        for x in rect.x ..< rect.x + rect.w:
          backend.putCell(x, y, "░", 1, command.color.rgb, clips[^1])
    of CmdRawVertices:
      discard

  var output = newStringOfCap(backend.width * backend.height * 2)
  output.add "\e[H"
  var previousForeground = TerminalColor(r: 255, g: 255, b: 255)
  var previousBackground = TerminalColor()
  var firstStyle = true
  for y in 0 ..< backend.height:
    for x in 0 ..< backend.width:
      let cell = backend.cells[y * backend.width + x]
      if cell.continuation:
        continue
      if firstStyle or cell.foreground != previousForeground or cell.background != previousBackground:
        output.add "\e[38;2;" & $cell.foreground.r & ";" & $cell.foreground.g & ";" & $cell.foreground.b & "m"
        output.add "\e[48;2;" & $cell.background.r & ";" & $cell.background.g & ";" & $cell.background.b & "m"
        previousForeground = cell.foreground
        previousBackground = cell.background
        firstStyle = false
      output.add cell.grapheme
    if y + 1 < backend.height:
      output.add "\e[0m\r\n"
      firstStyle = true
  output.add "\e[0m"
  stdout.write(output)
  stdout.flushFile()
