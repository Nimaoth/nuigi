import std/[tables, assertions, os, hashes, syncio]
import sdl3
import mymath
import render2d, fonts
import nuigi, widgets, debug_panel, theme_editor, demo/demo_window, windows
import profiler
import profiler_ui
import plot

include compat2


var b: UiBuilder
var gUiExampleInitialized = false
var gShowDemoWindow = true
var gShowSettingsWindow = true
var gRender2D: Render2D
var gFontRender: FontRender
when defined(wasm):
  var gFontAtlasTexture: nil Texture = nil
var gCustomMaterial: MaterialId = 0
var testFont = 0'i16
var debugPanelState: DebugPanel = DebugPanel()
var debugPanelState2: DebugPanel = DebugPanel()
var themeEditorState: ThemeEditor = ThemeEditor()
var gSampleCount: GPUSampleCount = GPU_SAMPLECOUNT_8
var gMsaaSelected = 3
var gFontSelected = 0
var gFps = 0.0
var gFrame = 0.0
var gTick = 0.0
var gRenderOnDemand = true
var gHadInputThisFrame = false
var gNumFramesWithoutInput = 0

# --- per-frame plot history for the settings window graphs ----------------------
const PlotHistoryLen = 256
var gMetricHistory: array[3, array[PlotHistoryLen, float32]]
var gPlotHistoryWrite = 0
var gPlotHistoryCount = 0

proc plotHistoryFn*(x: float32, userData: int): float32 =
  let count = gPlotHistoryCount
  let i = clamp(x, 0, count.float32 - 1).int32
  if i < 0 or i >= count:
    return 0.0'f32
  let actualIdx = (gPlotHistoryWrite + (PlotHistoryLen - count) + i) mod PlotHistoryLen
  return gMetricHistory[userData][actualIdx]

proc plotMetricMax(metric: int): float32 =
  result = 1.0'f32
  for i in 0 ..< gPlotHistoryCount:
    let idx = (gPlotHistoryWrite + (PlotHistoryLen - gPlotHistoryCount) + i) mod PlotHistoryLen
    result = max(result, gMetricHistory[metric][idx])

proc plotMetricAvg(metric: int, samples = 10): float32 =
  let n = min(samples, gPlotHistoryCount)
  if n == 0:
    return 0.0'f32
  var sum = 0.0'f32
  for i in 0 ..< n:
    let idx = (gPlotHistoryWrite - 1 - i + PlotHistoryLen) mod PlotHistoryLen
    sum += gMetricHistory[metric][idx]
  return sum / n.float32

proc pushPlotHistory() =
  gMetricHistory[0][gPlotHistoryWrite] = gFps.float32
  gMetricHistory[1][gPlotHistoryWrite] = gFrame.float32
  gMetricHistory[2][gPlotHistoryWrite] = gTick.float32
  gPlotHistoryWrite = (gPlotHistoryWrite + 1) mod PlotHistoryLen
  if gPlotHistoryCount < PlotHistoryLen:
    gPlotHistoryCount += 1

# Shared state between `main` (one-time setup) and `mainLoop` (per-frame body).
var running = true
var last = 0.0
var fps = 60.0
var gWindow: Window

type
  UiImageKind* = enum
    imageGpuTexture
    imageTexture

const
  uiImageKindShift = 62
  uiImageKindMask = 0b11'u64 shl uiImageKindShift
  uiImageDataMask = not uiImageKindMask
  uiImageTextureTag = 0b01'u64 shl uiImageKindShift

func imageIdKind*(id: UiImageId): UiImageKind =
  case (cast[uint64](id) shr uiImageKindShift) and 0b11'u64
  of 0b01: imageTexture
  else: imageGpuTexture

func textureToImageId*(texture: nil Texture): UiImageId =
  if texture == nil:
    return UiImageId(0'u64)
  UiImageId(cast[uint64](texture) or uiImageTextureTag)

func gpuTextureToImageId*(texture: GPUTexture): UiImageId =
  if texture == nil:
    return UiImageId(0'u64)
  UiImageId(cast[uint64](texture) and uiImageDataMask)

func imageIdToTexture*(id: UiImageId): nil Texture =
  cast[Texture](cast[uint64](id) and uiImageDataMask)

func imageIdToGpuTexture*(id: UiImageId): GPUTexture =
  cast[GPUTexture](cast[uint64](id) and uiImageDataMask)

proc textureToGpuTexture*(texture: nil Texture): GPUTexture =
  if texture == nil:
    return nil
  let props = getTextureProperties(texture)
  let gpuTexPtr = getPointerProperty(props, "SDL.texture.gpu.texture", nil)
  if gpuTexPtr != nil:
    return cast[GPUTexture](gpuTexPtr)
  return nil

proc uiSdlArrangeText(text: openArray[char], fontId: FontId, fontSize: float32, maxWidth: float32): UiTextArrangement =
  gFontRender.arrangeText(text, fontSize, fontId, maxWidth)

proc uiSdlBuildTextMesh(arrangement: UiTextArrangement, pos, screenOffset: Vec2,
    color: UiColor, transform: UiAffine2): tuple[data: nil ptr UncheckedArray[UiVertex], count: int] =
  let meshColor = FColor(r: color.r, g: color.g, b: color.b, a: color.a)
  let mesh = gFontRender.buildTextMesh(arrangement, pos, screenOffset, meshColor, transform)
  return (cast[nil ptr UncheckedArray[UiVertex]](mesh.data), mesh.count)

proc themeEditorListFonts(): seq[(string, UiFontId)] {.raises: [], gcsafe.} =
  gcsafeb:
    let faces = gFontRender.listFontFaces()
    var resultSeq: seq[(string, UiFontId)] = @[]
    resultSeq.setLen(faces.len)
    for i in 0 ..< faces.len:
      resultSeq[i] = (faces[i][0], UiFontId(faces[i][1]))
    return resultSeq

proc themeEditorResolveFont(name: string): UiFontId {.raises: [], gcsafe.} =
  gcsafeb:
    let faces = gFontRender.listFontFaces()
    for i in 0 ..< faces.len:
      if faces[i][0] == name:
        return UiFontId(faces[i][1])
    return 0'i16

func toUiKey(key: Keycode): tuple[found: bool, uiKey: UiKey] =
  case key
  of uint32(SDLK_A)..uint32(SDLK_Z):
    (true, UiKey(ord(KeyA) + int(key - uint32(SDLK_A))))
  of uint32(SDLK_0)..uint32(SDLK_9):
    (true, UiKey(ord(Key0) + int(key - uint32(SDLK_0))))
  of uint32(SDLK_SPACE): (true, KeySpace)
  of uint32(SDLK_RETURN): (true, KeyEnter)
  of uint32(SDLK_ESCAPE): (true, KeyEscape)
  of uint32(SDLK_BACKSPACE): (true, KeyBackspace)
  of uint32(SDLK_TAB): (true, KeyTab)
  of uint32(SDLK_LEFT): (true, KeyLeft)
  of uint32(SDLK_RIGHT): (true, KeyRight)
  of uint32(SDLK_UP): (true, KeyUp)
  of uint32(SDLK_DOWN): (true, KeyDown)
  of uint32(SDLK_F1)..uint32(SDLK_F12):
    (true, UiKey(ord(KeyF1) + int(key - uint32(SDLK_F1))))
  of uint32(SDLK_DELETE): (true, KeyDelete)
  of uint32(SDLK_HOME): (true, KeyHome)
  of uint32(SDLK_END): (true, KeyEnd)
  of uint32(SDLK_PAGEUP): (true, KeyPageUp)
  of uint32(SDLK_PAGEDOWN): (true, KeyPageDown)
  of uint32(SDLK_LSHIFT): (true, KeyShiftLeft)
  of uint32(SDLK_RSHIFT): (true, KeyShiftRight)
  of uint32(SDLK_LCTRL): (true, KeyControlLeft)
  of uint32(SDLK_RCTRL): (true, KeyControlRight)
  of uint32(SDLK_LALT): (true, KeyAltLeft)
  of uint32(SDLK_RALT): (true, KeyAltRight)
  of uint32(SDLK_LGUI): (true, KeySuperLeft)
  of uint32(SDLK_RGUI): (true, KeySuperRight)
  of uint32(SDLK_CAPSLOCK): (true, KeyCapsLock)
  of uint32(SDLK_SCROLLLOCK): (true, KeyScrollLock)
  of uint32(SDLK_NUMLOCKCLEAR): (true, KeyNumLock)
  of uint32(SDLK_INSERT): (true, KeyInsert)
  of uint32(SDLK_PAUSE): (true, KeyPause)
  of uint32(SDLK_MENU): (true, KeyMenu)
  of uint32(SDLK_SEMICOLON): (true, KeySemicolon)
  of uint32(SDLK_APOSTROPHE): (true, KeyApostrophe)
  of uint32(SDLK_COMMA): (true, KeyComma)
  of uint32(SDLK_MINUS): (true, KeyMinus)
  of uint32(SDLK_PERIOD): (true, KeyPeriod)
  of uint32(SDLK_SLASH): (true, KeySlash)
  of uint32(SDLK_BACKSLASH): (true, KeyBackslash)
  of uint32(SDLK_LEFTBRACKET): (true, KeyLeftBracket)
  of uint32(SDLK_RIGHTBRACKET): (true, KeyRightBracket)
  of uint32(SDLK_GRAVE): (true, KeyGrave)
  of uint32(SDLK_KP_1)..uint32(SDLK_KP_9):
    (true, UiKey(ord(KeyKp1) + int(key - uint32(SDLK_KP_1))))
  of uint32(SDLK_KP_0): (true, KeyKp0)
  of uint32(SDLK_KP_DIVIDE): (true, KeyKpDivide)
  of uint32(SDLK_KP_MULTIPLY): (true, KeyKpMultiply)
  of uint32(SDLK_KP_MINUS): (true, KeyKpSubtract)
  of uint32(SDLK_KP_PLUS): (true, KeyKpAdd)
  of uint32(SDLK_KP_PERIOD): (true, KeyKpDecimal)
  of uint32(SDLK_KP_ENTER): (true, KeyKpEnter)
  else: (false, default(UiKey))

proc ensureUiExampleInitialized() =
  if gUiExampleInitialized:
    return

  b = newBuilder(uiSdlArrangeText, uiSdlBuildTextMesh)
  discard b.addThemeTextStyle UiNodeText(
    text: "hello world".uiString,
    fontId: testFont,
    fontSize: 16,
  )
  gUiExampleInitialized = true

  themeEditorState.listFonts = themeEditorListFonts
  themeEditorState.resolveFont = themeEditorResolveFont

type SdlInputAccum = object
  frameIndex: uint64
  mouse: Vec2
  mouseDelta: Vec2
  wheel: Vec2
  mouseDown: UiMouseButtons
  mousePressed: UiMouseButtons
  mouseReleased: UiMouseButtons
  keysDown: UiKeys
  keysPressed: UiKeys
  keysReleased: UiKeys
  keysRepeated: UiKeys
  modsDown: UiModifiers
  textInput: string

var gInputAccum: SdlInputAccum

func toUiMouseButton(button: uint8): UiMouseButton =
  case button
  of 1: MouseLeft
  of 2: MouseMiddle
  of 3: MouseRight
  else: MouseLeft

func toUiModifiers(m: Keymod): UiModifiers =
  let mm = m.uint32
  result = {}
  if (mm and KMOD_SHIFT) != 0: result.incl ModShift
  if (mm and KMOD_CTRL) != 0: result.incl ModControl
  if (mm and KMOD_ALT) != 0: result.incl ModAlt
  if (mm and KMOD_GUI) != 0: result.incl ModSuper

proc accumulateSdlInput(ev: var Event) =
  prof("accumulateSdlInput")
  case ev.`type`
  of EVENT_MOUSE_MOTION:
    gInputAccum.mouse = vec2(ev.motion.x, ev.motion.y)
    gInputAccum.mouseDelta.x += ev.motion.xrel
    gInputAccum.mouseDelta.y += ev.motion.yrel
  of EVENT_MOUSE_BUTTON_DOWN:
    let mb = toUiMouseButton(ev.button.button)
    gInputAccum.mouseDown.incl mb
    gInputAccum.mousePressed.incl mb
    gInputAccum.mouse = vec2(ev.button.x, ev.button.y)
  of EVENT_MOUSE_BUTTON_UP:
    let mb = toUiMouseButton(ev.button.button)
    gInputAccum.mouseDown.excl mb
    gInputAccum.mouseReleased.incl mb
    gInputAccum.mouse = vec2(ev.button.x, ev.button.y)
  of EVENT_MOUSE_WHEEL:
    gInputAccum.wheel.x += ev.wheel.x
    gInputAccum.wheel.y += ev.wheel.y
  of EVENT_KEY_DOWN:
    let (found, uk) = ev.key.key.toUiKey()
    if found:
      gInputAccum.keysDown.incl uk
      if ev.key.repeat:
        gInputAccum.keysRepeated.incl uk
      else:
        gInputAccum.keysPressed.incl uk
      gInputAccum.modsDown = toUiModifiers(ev.key.`mod`)
  of EVENT_KEY_UP:
    let (found, uk) = ev.key.key.toUiKey()
    if found:
      gInputAccum.keysDown.excl uk
      gInputAccum.keysReleased.incl uk
    gInputAccum.modsDown = toUiModifiers(ev.key.`mod`)
  of EVENT_TEXT_INPUT:
    if ev.text.text != nil:
      gInputAccum.textInput.add($ev.text.text)
  else:
    discard

when defined(wasm):
  proc syncFontAtlas(renderer: Renderer) =
    prof("syncFontAtlas")
    if gFontAtlasTexture == nil:
      gFontAtlasTexture = createTexture(renderer, PIXELFORMAT_RGBA32, TEXTUREACCESS_STATIC,
        gFontRender.fontAtlasWidth.cint, gFontRender.fontAtlasHeight.cint)
      if gFontAtlasTexture != nil:
        discard gFontAtlasTexture.setTextureBlendMode(BLENDMODE_BLEND)

    if gFontRender.fontAtlasNeedsReset:
      let shouldGrow = gFontRender.fontAtlasNeedsResize and gFontRender.canGrowFontAtlas()
      if not shouldGrow:
        gFontRender.resetFontAtlas(false)
      else:
        let nextSize = gFontRender.nextFontAtlasSize()
        if gFontAtlasTexture != nil:
          destroyTexture(gFontAtlasTexture)
        gFontAtlasTexture = createTexture(renderer, PIXELFORMAT_RGBA32, TEXTUREACCESS_STATIC,
          nextSize.width.cint, nextSize.height.cint)
        if gFontAtlasTexture != nil:
          discard gFontAtlasTexture.setTextureBlendMode(BLENDMODE_BLEND)
        gFontRender.resetFontAtlas(true)

    if gFontRender.fontAtlasDirty and gFontAtlasTexture != nil:
      let dirtyX = gFontRender.fontAtlasDirtyMinX
      let dirtyY = gFontRender.fontAtlasDirtyMinY
      let dirtyWidth = gFontRender.fontAtlasDirtyMaxX - dirtyX
      let dirtyHeight = gFontRender.fontAtlasDirtyMaxY - dirtyY
      if dirtyWidth > 0 and dirtyHeight > 0:
        var rect = Rect(x: dirtyX.cint, y: dirtyY.cint, w: dirtyWidth.cint, h: dirtyHeight.cint)
        let srcOffset = (dirtyY * gFontRender.fontAtlasWidth + dirtyX) * 4
        if srcOffset + dirtyWidth * dirtyHeight * 4 <= gFontRender.fontAtlasPixels.len:
          discard updateTexture(gFontAtlasTexture, rect.addr,
            cast[ptr UncheckedArray[uint8]](gFontRender.fontAtlasPixels[srcOffset].addr),
            (gFontRender.fontAtlasWidth * 4).cint)
      gFontRender.clearFontAtlasDirty()

    b.fontAtlasImageId = cast[UiImageId](gFontAtlasTexture)


proc beginInputFrame() =
  gInputAccum.frameIndex += 1
  gInputAccum.mousePressed = {}
  gInputAccum.mouseReleased = {}
  gInputAccum.mouseDelta = vec2(0, 0)
  gInputAccum.wheel = vec2(0, 0)
  gInputAccum.keysPressed = {}
  gInputAccum.keysReleased = {}
  gInputAccum.keysRepeated = {}
  gInputAccum.textInput.setLen(0)
  gHadInputThisFrame = false

proc makeInputSnapshot(): UiInputSnapshot =
  UiInputSnapshot(
    frameIndex: gInputAccum.frameIndex,
    mouse: gInputAccum.mouse,
    mouseDelta: gInputAccum.mouseDelta,
    wheel: gInputAccum.wheel,
    mouseDown: gInputAccum.mouseDown,
    mousePressed: gInputAccum.mousePressed,
    mouseReleased: gInputAccum.mouseReleased,
    keysDown: gInputAccum.keysDown,
    keysPressed: gInputAccum.keysPressed,
    keysReleased: gInputAccum.keysReleased,
    keysRepeated: gInputAccum.keysRepeated,
    modsDown: gInputAccum.modsDown,
    textInput: gInputAccum.textInput,
  )

proc buildSettingsMetricRow(b: var UiBuilder, prefix: string, metric: int, maxY: float32, precision: int) =
  b.layoutHorizontal:
    discard b.fit().gap(8).padding(2)
    let display = prefix & ": " & formatFloat(plotMetricAvg(metric, 50).float64, ffDecimal, precision)
    b.node:
      let plotSize = vec2(100.0'f32, 50.0'f32)
      discard b.size(plotSize).backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      let nodeIdx = b.currentNodeIndex()
      let nodeAbs = b.absoluteNodePos(nodeIdx)
      let style = b.nodeStyle(b.currentNode)
      let contentPos = nodeAbs + vec2(style.paddingX, style.paddingY)
      let contentSize = plotSize - vec2(style.paddingX * 2.0'f32, style.paddingY * 2.0'f32)
      if contentSize.x > 0 and contentSize.y > 0:
        let count = max(1, gPlotHistoryCount)
        var series = array[1, PlotSeries].default
        series[0] = PlotSeries(
          fn: plotHistoryFn,
          userData: metric,
          label: uiString(prefix),
          lineColor: rgba(0.35'f32, 0.55'f32, 0.95'f32, 1.0'f32),
          fillTopColor: rgba(0.35'f32, 0.55'f32, 0.95'f32, 0.25'f32),
          fillBottomColor: rgba(0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32),
        )
        let commands = buildPlotVertices(
          b,
          contentPos,
          contentSize,
          vec2(0.0'f32, count.float32 - 1.0'f32),
          vec2(0.0'f32, max(maxY, plotMetricMax(metric) * 1.1'f32)),
          series.toOpenArray(0, 0),
          resolution = min(gPlotHistoryCount, 100),
          lineThickness = 1.5'f32,
          mousePos = b.frameCtx.input.mouse,
        )
        discard b.customRenderCommands(commands)
    b.node:
      discard b.fit().padding(10).fontId(testFont).text(display).alignCenter()

proc buildSettingsWindow(b: var UiBuilder) =
  b.window("Settings", 0, 0, 420, 640):
    b.scrollBox():
      discard b.sizeToParentX().fitY()
      b.layoutVertical:
        discard b.fillX().fitY().padding(12).gap(12)

        b.node():
          discard b.fillX().fitY().padding(2)
          discard b.backgroundColor(b.themeStyle(UiStyleIndexHeader)[].fillColor)
          discard b.copyTextStyleIndex(UiStyleIndexHeadingText)
          discard b.text("Performance")

        b.buildSettingsMetricRow("FPS", metric = 0, maxY = 120, precision = 0)
        b.buildSettingsMetricRow("Frame", metric = 1, maxY = 8,  precision = 1)
        b.buildSettingsMetricRow("Tick", metric = 2, maxY = 8,  precision = 1)

        b.node():
          discard b.fillX().fitY().padding(2)
          discard b.backgroundColor(b.themeStyle(UiStyleIndexHeader)[].fillColor)
          discard b.copyTextStyleIndex(UiStyleIndexHeadingText)
          discard b.text("Rendering")

        b.tableLayout([tableColumnFit(), tableColumnFill()], 14, 10):
          discard b.fit()
          b.node():
            discard b.fit()
            discard b.copyTextStyleIndex(UiStyleIndexLabelText)
            discard b.text("MSAA Samples")
          if b.dropdown(["1x", "2x", "4x", "8x"], gMsaaSelected):
            case gMsaaSelected
            of 0: gSampleCount = GPU_SAMPLECOUNT_1
            of 1: gSampleCount = GPU_SAMPLECOUNT_2
            of 2: gSampleCount = GPU_SAMPLECOUNT_4
            else: gSampleCount = GPU_SAMPLECOUNT_8

          b.node():
            discard b.fit()
            discard b.copyTextStyleIndex(UiStyleIndexLabelText)
            discard b.text("Render On Demand")
          discard b.checkbox("", gRenderOnDemand)

          b.node():
            discard b.fit()
            discard b.copyTextStyleIndex(UiStyleIndexLabelText)
            discard b.text("Profiler Overlay")
          discard b.checkbox("", gShowNuiProfiler)

          b.node():
            discard b.fit()
            discard b.copyTextStyleIndex(UiStyleIndexLabelText)
            discard b.text("Demo")
          discard b.checkbox("", gShowDemoWindow)

          b.node():
            discard b.fit()
            discard b.copyTextStyleIndex(UiStyleIndexLabelText)
            discard b.text("Theme Editor")
          var x = b.showThemeEditor
          discard b.checkbox("", x)
          b.showThemeEditor = x

          b.node():
            discard b.fit()
            discard b.copyTextStyleIndex(UiStyleIndexLabelText)
            discard b.text("Debug Panel")
          x = b.showDebugPanel
          discard b.checkbox("", x)
          b.showDebugPanel = x

          b.node():
            discard b.fit()
            discard b.copyTextStyleIndex(UiStyleIndexLabelText)
            discard b.text("Debug Panel 2")
          x = b.showDebugPanel2
          discard b.checkbox("", x)
          b.showDebugPanel2 = x

        b.node():
          discard b.fillX().fitY().padding(2)
          discard b.backgroundColor(b.themeStyle(UiStyleIndexHeader)[].fillColor)
          discard b.copyTextStyleIndex(UiStyleIndexHeadingText)
          discard b.text("Text")

        b.tableLayout([tableColumnFit(), tableColumnFill()], 14, 10):
          discard b.fit()
          b.node():
            discard b.fit()
            discard b.copyTextStyleIndex(UiStyleIndexLabelText)
            discard b.text("Font Hinting")
          if b.dropdown(["Subpixel", "Pixel snapped", "Fractional"], gFontSelected):
            case gFontSelected
            of 0: gFontRender.flags = {
                FontRenderFlag.SubpixelPhasing,
                FontRenderFlag.PixelSnapping,
              }
            of 1: gFontRender.flags = {FontRenderFlag.PixelSnapping}
            else: gFontRender.flags = {}

proc buildUi(b: var UiBuilder) =
  prof("buildUi")
  block:
    prof("new ui")

    b.node("windows"):
      discard b.fillX().fillY()
      b.windowSpace()

    b.node("overlays"):
      discard b.fillX().fillY().noHover()
      b.overlays = b.currentNode.id

    if gShowSettingsWindow:
      b.buildSettingsWindow()

    if gShowDemoWindow:
      b.window("Demo", 400, 100, 800, 900):
        b.buildDemoUi()

    if gShowNuiProfiler:
      b.window("Profiler", 1200, 100, 700, 1000):
        b.buildNuiProfiler()

    if b.showThemeEditor:
      var f = b.defaultText.fontSize
      b.defaultText.fontSize = 16
      discard b.themeEditor(themeEditorState)
      b.defaultText.fontSize = f

    if b.showDebugPanel:
      let viewportW = b.frame.nodes[0].size.x
      let viewportH = b.frame.nodes[0].size.y
      let debugPanelX = viewportW * (if b.showDebugPanel2: 0.4'f32 else: 0.6'f32)
      let debugPanelWidth = viewportW * (if b.showDebugPanel2: 0.3'f32 else: 0.4'f32)
      b.window("Debug Panel", debugPanelX, 0.0'f32, debugPanelWidth, viewportH):
        discard b.debugPanel(debugPanelState)
        b.flushDeferredNodes()
      if b.showDebugPanel2:
        b.window("Debug Panel 2", viewportW * 0.7'f32, 0.0'f32, viewportW * 0.3'f32, viewportH):
          discard b.debugPanel(debugPanelState2)


  block:
    prof("keepAlive")
    b.keepAlive(themeEditorId)
    b.keepAlive("Examples".hashChars.UiNodeId)

proc renderNewUi(b: var UiBuilder) =
  prof("renderCommands")
  func uiToFColor(color: UiColor): FColor {.inline.} =
    FColor(r: color.r, g: color.g, b: color.b, a: color.a)

  func toRender2DSamplerMode(mode: TextureSamplerMode): Render2DSamplerMode {.inline.} =
    case mode
    of TextureSamplerMode.Linear: Render2DSamplerMode.Linear
    of TextureSamplerMode.Nearest: Render2DSamplerMode.Nearest

  proc renderFilledRectTransformed(renderer: var Render2D, transform: UiAffine2, pos, size: Vec2, color: UiColor,
      texture: nil GPUTexture = nil, uv0: Vec2 = vec2(0), uv1: Vec2 = vec2(1),
      samplerMode: TextureSamplerMode = TextureSamplerMode.Linear) =
    if size.x <= 0.0'f32 or size.y <= 0.0'f32:
      return
    # Fast path for axis-aligned rects: draw a tinted white texture quad.
    const identityEps = 1e-5'f32
    let isIdentity =
      abs(transform.m00 - 1.0'f32) <= identityEps and
      abs(transform.m01) <= identityEps and
      abs(transform.m10) <= identityEps and
      abs(transform.m11 - 1.0'f32) <= identityEps and
      abs(transform.tx) <= identityEps and
      abs(transform.ty) <= identityEps
    if isIdentity:
      discard renderer.renderQuad(pos.x, pos.y, size.x, size.y, FColor(r: color.r, g: color.g, b: color.b, a: color.a),
        texture = texture, uv0 = uv0, uv1 = uv1, samplerMode = samplerMode.toRender2DSamplerMode())
      return

    let edgeX = vec2(transform.m00 * size.x, transform.m10 * size.x)
    let edgeY = vec2(transform.m01 * size.y, transform.m11 * size.y)
    let width = edgeX.length
    let height = edgeY.length
    if width <= 0.0'f32 or height <= 0.0'f32:
      return

    let angleDeg = arctan2(edgeX.y, edgeX.x).radToDeg
    let centerPos = transform.transformPoint2(pos + size * 0.5'f32)
    var dstRect = FRect(
      x: centerPos.x - width * 0.5'f32,
      y: centerPos.y - height * 0.5'f32,
      w: width,
      h: height,
    )
    var rotationCenter = FPoint(x: 0.5'f32, y: 0.5'f32)

    discard renderer.renderQuad(dstRect.x, dstRect.y, dstRect.w, dstRect.h, FColor(r: color.r, g: color.g, b: color.b, a: color.a),
      angle = angleDeg, rotationCenter.x, rotationCenter.y, texture = texture, uv0 = uv0, uv1 = uv1,
      samplerMode = samplerMode.toRender2DSamplerMode())

  var transformStack: seq[UiAffine2] = @[identityAffine2()]

  for cmd in b.frameOutput.commands:
    let transform = transformStack[^1]
    case cmd.kind
    of CmdTransformPush:
      let nextTransform = applyNodeRenderTransform(
        transform,
        cmd.pivot,
        cmd.offset,
        cmd.rotation,
        cmd.scale,
      )
      transformStack.add nextTransform

    of CmdTransformPop:
      if transformStack.len > 1:
        discard transformStack.pop()

    of CmdRectFill:
      gRender2D.renderFilledRectTransformed(transform, cmd.pos, cmd.size, cmd.color)

    of CmdRawVertices:
      if cmd.vertexData != nil and cmd.vertexCount > 0:
        var gpuTexture: nil GPUTexture = nil
        case cmd.imageId.imageIdKind()
        of imageTexture:
          gpuTexture = cmd.imageId.imageIdToTexture().textureToGpuTexture()

        of imageGpuTexture:
          gpuTexture = cmd.imageId.imageIdToGpuTexture()
        discard gRender2D.drawVertices(
          cast[ptr UncheckedArray[Render2DVertex]](cmd.vertexData[0].addr).toOpenArray(0, cmd.vertexCount - 1),
          gpuTexture,
          cmd.samplerMode.toRender2DSamplerMode(),
          materialId = cmd.materialId,
          materialUniform = cmd.materialUniform,
        )

    of CmdRectStroke:
      let scaledThickness = max(1.0'f32, cmd.thickness)
      let thickness = min(scaledThickness, min(cmd.size.x, cmd.size.y) * 0.5'f32)
      if thickness > 0:
        let innerH = max(0.0'f32, cmd.size.y - thickness * 2.0'f32)
        gRender2D.renderFilledRectTransformed(transform, cmd.pos, vec2(cmd.size.x, thickness), cmd.color)
        gRender2D.renderFilledRectTransformed(transform, vec2(cmd.pos.x, cmd.pos.y + cmd.size.y - thickness), vec2(cmd.size.x, thickness), cmd.color)
        gRender2D.renderFilledRectTransformed(transform, vec2(cmd.pos.x, cmd.pos.y + thickness), vec2(thickness, innerH), cmd.color)
        gRender2D.renderFilledRectTransformed(transform, vec2(cmd.pos.x + cmd.size.x - thickness, cmd.pos.y + thickness), vec2(thickness, innerH), cmd.color)

    of CmdText:
      var text: nil ptr UiNodeText = nil
      if cmd.textIndex > 0 and b.frame.texts[cmd.textIndex - 1].text.len > 0:
        text = b.frame.texts[cmd.textIndex - 1].addr

      if text != nil:
        # let maxWidth = if WrapText in n.flags: contentSize.x else: -1.0'f32
        let arrangement = b.getTextArrangement(text, -1)
        if b.buildTextMesh != nil:
          let (vertexData, vertexCount) = b.buildTextMesh(
            arrangement[], cmd.pos, vec2(0.0'f32), text.textColor, transform)
          if vertexData != nil and vertexCount > 0:
            discard gRender2D.drawVertices(
              cast[ptr UncheckedArray[Render2DVertex]](vertexData).toOpenArray(0, vertexCount - 1),
              texture = cast[GPUTexture](1),
              cmd.samplerMode.toRender2DSamplerMode(),
              materialId = cmd.materialId,
              materialUniform = cmd.materialUniform,
            )

    of CmdClipPush:
      let transformed = transformedRectAabb(transform, cmd.pos, cmd.size)
      let clipRect = Rect(
        x: floor(transformed.pos.x).cint,
        y: floor(transformed.pos.y).cint,
        w: max(0.0'f32, ceil(transformed.size.x)).cint,
        h: max(0.0'f32, ceil(transformed.size.y)).cint,
      )
      gRender2D.pushClipRect(clipRect.x, clipRect.y, clipRect.w, clipRect.h)

    of CmdClipPop:
      gRender2D.popClipRect()

    of CmdLine:
      let p0 = transform.transformPoint2(cmd.pos)
      let p1 = transform.transformPoint2(cmd.pos2)
      discard gRender2D.drawLine(p0, p1, cmd.thickness, uiToFColor(cmd.color))

    of CmdImage:
      case cmd.imageId.imageIdKind()
      of imageTexture:
        let gpuTexture = cmd.imageId.imageIdToTexture().textureToGpuTexture()
        if gpuTexture != nil:
          gRender2D.renderFilledRectTransformed(transform, cmd.pos, cmd.size, cmd.color,
            texture = gpuTexture, uv0 = cmd.uv0, uv1 = cmd.uv1, samplerMode = cmd.samplerMode)

      of imageGpuTexture:
        let gpuTexture = cmd.imageId.imageIdToGpuTexture()
        if gpuTexture != nil:
          gRender2D.renderFilledRectTransformed(transform, cmd.pos, cmd.size, cmd.color,
            texture = gpuTexture, uv0 = cmd.uv0, uv1 = cmd.uv1, samplerMode = cmd.samplerMode)

    else:
      discard

when defined(wasm):
  proc renderNewUiRenderer(b: var UiBuilder, frameOut: UiFrameOutput, renderer: Renderer) =
    prof("renderCommands")

    # Render an already-triangulated list of vertices via the SDL renderer.
    # UiVertex and Render2DVertex share the same 32-byte interleaved layout
    # (x, y, u, v, r, g, b, a), so we can point renderGeometryRaw directly at it.
    proc drawRawVertices(renderer: Renderer, texture: nil Texture, first: ptr UiVertex, count: int) =
      if count <= 0:
        return
      let xy = cast[ptr cfloat](first)
      let color = cast[ptr FColor](cast[uint](first) + 16)
      let uv = cast[ptr cfloat](cast[uint](first) + 8)
      let stride = cint(sizeof(UiVertex))
      discard renderer.renderGeometryRaw(
        texture, xy, stride, color, stride, uv, stride,
        cint(count), nil, 0, 0)

    # Emit a filled quad (two triangles) for an axis/transformed rect.
    proc renderFilledRectTransformed(renderer: Renderer, transform: UiAffine2, pos, size: Vec2, color: UiColor, texture: nil Texture = nil) =
      if size.x <= 0.0'f32 or size.y <= 0.0'f32:
        return
      let p0 = transform.transformPoint2(pos)
      let p1 = transform.transformPoint2(pos + vec2(size.x, 0.0'f32))
      let p2 = transform.transformPoint2(pos + size)
      let p3 = transform.transformPoint2(pos + vec2(0.0'f32, size.y))
      var verts = [
        UiVertex(pos: p0, uv: vec2(0.0'f32, 0.0'f32), color: color),
        UiVertex(pos: p1, uv: vec2(1.0'f32, 0.0'f32), color: color),
        UiVertex(pos: p2, uv: vec2(1.0'f32, 1.0'f32), color: color),
        UiVertex(pos: p0, uv: vec2(0.0'f32, 0.0'f32), color: color),
        UiVertex(pos: p2, uv: vec2(1.0'f32, 1.0'f32), color: color),
        UiVertex(pos: p3, uv: vec2(0.0'f32, 1.0'f32), color: color),
      ]
      drawRawVertices(renderer, texture, verts[0].addr, 6)

    var transformStack: seq[UiAffine2] = @[identityAffine2()]
    var clipStack: seq[Rect] = @[]

    for cmd in frameOut.commands:
      let transform = transformStack[^1]
      case cmd.kind
      of CmdTransformPush:
        let nextTransform = applyNodeRenderTransform(
          transform,
          cmd.pivot,
          cmd.offset,
          cmd.rotation,
          cmd.scale,
        )
        transformStack.add nextTransform

      of CmdTransformPop:
        if transformStack.len > 1:
          discard transformStack.pop()

      of CmdRectFill:
        discard renderer.setRenderDrawColorFloat(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
        renderFilledRectTransformed(renderer, transform, cmd.pos, cmd.size, cmd.color)

      of CmdRawVertices:
        if cmd.vertexData != nil and cmd.vertexCount > 0:
          var texture: nil Texture = nil
          if cmd.imageId.uint64 == 1:
            texture = gFontAtlasTexture
          else:
            texture = cast[Texture](cmd.imageId)
          # case cmd.imageId.imageIdKind()
          # of imageTexture:
          #   texture = cmd.imageId.imageIdToTexture()

          # of imageGpuTexture:
          #   texture = cmd.imageId.imageIdToGpuTexture()
          # discard gRender2D.drawVertices(
          #   cast[ptr UncheckedArray[Render2DVertex]](cmd.vertexData[0].addr).toOpenArray(0, cmd.vertexCount - 1),
          #   texture,
          #   cmd.samplerMode.toRender2DSamplerMode(),
          #   materialId = cmd.materialId,
          #   materialUniform = cmd.materialUniform,
          # )
          drawRawVertices(renderer, texture, cast[ptr UiVertex](cmd.vertexData), cmd.vertexCount)

      of CmdRectStroke:
        discard renderer.setRenderDrawColorFloat(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
        let scaledThickness = max(1.0'f32, cmd.thickness)
        let thickness = min(scaledThickness, min(cmd.size.x, cmd.size.y) * 0.5'f32)
        if thickness > 0:
          let innerH = max(0.0'f32, cmd.size.y - thickness * 2.0'f32)
          renderFilledRectTransformed(renderer, transform, cmd.pos, vec2(cmd.size.x, thickness), cmd.color)
          renderFilledRectTransformed(renderer, transform, vec2(cmd.pos.x, cmd.pos.y + cmd.size.y - thickness), vec2(cmd.size.x, thickness), cmd.color)
          renderFilledRectTransformed(renderer, transform, vec2(cmd.pos.x, cmd.pos.y + thickness), vec2(thickness, innerH), cmd.color)
          renderFilledRectTransformed(renderer, transform, vec2(cmd.pos.x + cmd.size.x - thickness, cmd.pos.y + thickness), vec2(thickness, innerH), cmd.color)

      of CmdText:
        var text: nil ptr UiNodeText = nil
        if cmd.textIndex > 0 and b.frame.texts[cmd.textIndex - 1].text.len > 0:
          text = b.frame.texts[cmd.textIndex - 1].addr

        if text != nil:
          let arrangement = b.getTextArrangement(text, -1)
          if b.buildTextMesh != nil:
            let (vertexData, vertexCount) = b.buildTextMesh(
              arrangement[], cmd.pos, vec2(0.0'f32), text.textColor, transform)
            if vertexData != nil and vertexCount > 0:
              drawRawVertices(renderer, gFontAtlasTexture, cast[ptr UiVertex](vertexData), vertexCount)

      of CmdClipPush:
        let transformed = transformedRectAabb(transform, cmd.pos, cmd.size)
        var clipRect = Rect(
          x: floor(transformed.pos.x).cint,
          y: floor(transformed.pos.y).cint,
          w: max(0.0'f32, ceil(transformed.size.x)).cint,
          h: max(0.0'f32, ceil(transformed.size.y)).cint,
        )
        if clipStack.len > 0:
          clipRect = intersectRect(clipStack[^1], clipRect)
        clipStack.add clipRect
        discard renderer.setRenderClipRect(clipRect)

      of CmdClipPop:
        if clipStack.len > 0:
          discard clipStack.pop()
        if clipStack.len > 0:
          discard renderer.setRenderClipRect(clipStack[^1])
        else:
          discard renderer.setRenderClipRect(nil)

      of CmdLine:
        let p0 = transform.transformPoint2(cmd.pos)
        let p1 = transform.transformPoint2(cmd.pos2)
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let len = sqrt(dx * dx + dy * dy)
        let nx = if len > 0: -dy / len * cmd.thickness * 0.5'f32 else: 0.0'f32
        let ny = if len > 0: dx / len * cmd.thickness * 0.5'f32 else: 0.0'f32
        let c = cmd.color
        var verts = [
          UiVertex(pos: vec2(p0.x + nx, p0.y + ny), uv: vec2(0.0'f32, 0.0'f32), color: c),
          UiVertex(pos: vec2(p1.x + nx, p1.y + ny), uv: vec2(1.0'f32, 0.0'f32), color: c),
          UiVertex(pos: vec2(p1.x - nx, p1.y - ny), uv: vec2(1.0'f32, 1.0'f32), color: c),
          UiVertex(pos: vec2(p0.x + nx, p0.y + ny), uv: vec2(0.0'f32, 0.0'f32), color: c),
          UiVertex(pos: vec2(p1.x - nx, p1.y - ny), uv: vec2(1.0'f32, 1.0'f32), color: c),
          UiVertex(pos: vec2(p0.x - nx, p0.y - ny), uv: vec2(0.0'f32, 1.0'f32), color: c),
        ]
        drawRawVertices(renderer, nil, verts[0].addr, 6)

      of CmdImage:
        # Textures ignored for now; draw as a plain filled rect.
        var texture: nil Texture = nil
        if cmd.imageId.uint64 == 1:
          texture = gFontAtlasTexture
        else:
          texture = cast[Texture](cmd.imageId)
        renderFilledRectTransformed(renderer, transform, cmd.pos, cmd.size, cmd.color, texture)

      else:
        discard

proc perfNow*(): uint64 =
  when not defined(nimony):
    when defined(emscripten):
      return uint64(emscriptenGetNow() * 1e6)
    else:
      return getTicksNS()
  else:
    return 0

proc mainLoop() {.cdecl.} =
  try:
    var now = perfNow().float64 / NS_PER_SECOND.float64
    let dt = now - last
    last = now

    if dt != 0:
      fps = mix(fps, 1.0 / dt, 0.5)

    when defined(profiler) and not defined(nimony):
      gprof.frameStart = eventHistoryIndex
    prof("frame")
    when defined(profiler) and not defined(nimony):
      profilerBeginFrame(false)

    when defined(wasm):
      let renderer = gWindow.getRenderer()

    let tickStart = (perfNow().float64 / NS_PER_MS.float64).float32

    block:
      prof("tick")
      block:
        prof("events")
        beginInputFrame()

        var ev {.noinit.}: sdl3.Event
        while pollEvent(ev):
          gHadInputThisFrame = true
          accumulateSdlInput(ev)
          case ev.`type`
          of EVENT_WINDOW_CLOSE_REQUESTED:
            echo "EVENT_WINDOW_CLOSE_REQUESTED"
            running = false
            break

          of EVENT_QUIT:
            echo "EVENT_QUIT"
            running = false
            break

          else:
            discard

        if not running:
          when defined(wasm):
            echo "running is false"
            emscripten_cancel_main_loop()
          return

      if b.anythingAnimating or b.virtualNodes.len > 0 or b.middleDragScroll != vec2(0.0'f32, 0.0'f32):
        gHadInputThisFrame = true
      if gRenderOnDemand:
        for a in b.animations:
          var active = false
          if a.unchangedFrames == 0:
            for f in a.fields:
              if f.currentValue != f.targetValue:
                active = true
                break
          if active:
            gHadInputThisFrame = true
      if not gHadInputThisFrame:
        inc gNumFramesWithoutInput
      else:
        gNumFramesWithoutInput = 0
      if gRenderOnDemand and gNumFramesWithoutInput > 1:
        # On-demand mode: skip rebuilding and rendering when no input arrived.
        when not defined(wasm):
          when not defined(nimony):
            sleep(10)
        return

      var outputWidth: cint = 0
      var outputHeight: cint = 0
      discard gWindow.getWindowSize(outputWidth, outputHeight)

      ensureUiExampleInitialized()
      when defined(wasm):
        discard
      else:
        b.fontAtlasImageId = gpuTextureToImageId(gRender2D.fontTexture)

      let fonts = themeEditorListFonts()
      for (name, id) in fonts:
        b.fonts[name] = id

      discard b.beginUiFrame(outputWidth.float32, outputHeight.float32, makeInputSnapshot())
      b.buildUi()

      block:
        when defined(wasm):
          b.endUiFrame(buildMeshRenderCommands = true)
          syncFontAtlas(renderer)
          discard renderer.setRenderDrawColorFloat(0, 0, 0, 1)
          discard renderer.renderClear()
          b.renderNewUiRenderer(b.frameOutput, renderer)
        else:
          b.endUiFrame(buildMeshRenderCommands = true)
          if gRender2D.beginRender(nil, outputWidth.uint32, outputHeight.uint32, render2DTargetFormat, gSampleCount):
            gRender2D.clear()
            b.renderNewUi()

      let tickDt = (perfNow().float64 / NS_PER_MS.float64).float32 - tickStart
      gFps = fps
      gFrame = dt * 1000
      gTick = tickDt
      pushPlotHistory()


    when defined(wasm):
      prof("present")
      discard renderer.renderPresent()
    else:
      block:
        prof("present")
        gRender2D.endRender()
      block:
        prof("vsync")
        gRender2D.presentToSwapchain(gWindow)
  except:
    when not defined(nimony):
      echo "mainLoop exception ", getCurrentExceptionMsg()
      echo getCurrentException().getStackTrace()
    when defined(wasm):
      emscripten_cancel_main_loop()

proc main(quitImmediately: bool) =
  sdl3.setLogPriorities(LOG_PRIORITY_VERBOSE)
  assert sdl3.init(INIT_VIDEO or INIT_GAMEPAD or INIT_EVENTS or INIT_AUDIO), "std init"
  echo "sdl init ok"

  # var audioSystem = AudioSystem()
  # audioSystem.addr.init()

  echo "SDL3 version: ", sdl3.getVersion().int
  echo "SDL3 revision: ", $sdl3.getRevision()


  discard setCurrentThreadPriority(THREAD_PRIORITY_TIME_CRITICAL)

  when defined(nimony):
    let title = "nuigi (nimony)".cstring
  elif defined(nlvm):
    let title = "nuigi (nlvm)".cstring
  else:
    let title = "nuigi (nim2)".cstring

  setGamepadEventsEnabled(true)

  gWindow = createWindow(title, 1920, 1080, WINDOW_RESIZABLE)
  if gWindow == nil:
    echo "no window"
    return
  discard gWindow.startTextInput()

  const debug = defined(sdlDebug)
  when debug:
    const gpuDebugHint = cstring"SDL_RENDER_GPU_DEBUG"
    const gpuDebugVal = cstring"1"
    discard setHint(gpuDebugHint, gpuDebugVal)


  when defined(wasm):
    discard gFontRender.init({FontRenderFlag.PixelSnapping}, glyphPackingBudgetNs = 100_000_000'u64)
    const fonts = @[
      ("DejaVuSansMono", staticRead("../assets/dontuse/fonts/DejaVuSansMono.ttf")),
    ]
    for font in fonts:
      discard gFontRender.addFontFace(font[0], font[1])

    let renderer = createRenderer(gWindow, nil)
    discard renderer.setRenderDrawBlendMode(BLENDMODE_BLEND)
    echo "renderer ok: ", renderer != nil

  else:
    discard gFontRender.init()
    var gpu = createGPUDevice(GPU_SHADERFORMAT_DXIL.uint32, debug, "direct3d12")
    discard gpu.claimWindowForGPUDevice(gWindow)

    discard initRender2D(gRender2D, gFontRender.addr, gpu, render2DTargetFormat)
    if fileExists("./custom.frag.dxil"):
      try:
        var customFrag = readFile("./custom.frag.dxil")
        if customFrag.len > 0:
          var customBytes = newSeq[uint8](customFrag.len)
          copyMem(customBytes[0].addr, customFrag.readRawData(), customFrag.len)
          gCustomMaterial = gRender2D.registerMaterial(customBytes, numUniformBuffers = 1)
          echo "Registered custom material: ", gCustomMaterial
      except:
        discard

    discard gFontRender.addSystemDefaultFonts()
    discard gFontRender.addFontFace("assets/fonts/Ubuntu/Ubuntu-Regular.ttf")
    # discard gFontRender.addFontFace("assets/fonts/Ubuntu/Ubuntu-MediumItalic.ttf")
    # discard gFontRender.addFontFace("assets/fonts/Ubuntu/Ubuntu-Medium.ttf")
    # discard gFontRender.addFontFace("assets/fonts/Ubuntu/Ubuntu-LightItalic.ttf")
    # discard gFontRender.addFontFace("assets/fonts/Ubuntu/Ubuntu-Light.ttf")
    # discard gFontRender.addFontFace("assets/fonts/Ubuntu/Ubuntu-Italic.ttf")
    # discard gFontRender.addFontFace("assets/fonts/Ubuntu/Ubuntu-BoldItalic.ttf")
    # discard gFontRender.addFontFace("assets/fonts/Ubuntu/Ubuntu-Bold.ttf")
    testFont = gFontRender.addFontFace("assets/dontuse/fonts/DejaVuSansMono.ttf")
    discard gFontRender.addFontFace("assets/dontuse/fonts/DejaVuSansMono-Bold.ttf")
    discard gFontRender.addFontFace("assets/dontuse/fonts/DejaVuSansMono-Oblique.ttf")
    discard gFontRender.addFontFace("assets/dontuse/fonts/ProFont For Powerline.ttf")
    discard gFontRender.addFontFace("assets/dontuse/fonts/ProFont Bold For Powerline.ttf")

  # Initialize shared loop state and start the loop.
  last = perfNow().float64 / NS_PER_SECOND.float64 - 0.016
  fps = 60.0
  running = true

  when defined(wasm):
    emscripten_set_main_loop(mainLoop, 0, true)
  else:
    if not quitImmediately:
      while running:
        mainLoop()

    destroyWindow(gWindow)

var quitImmediately = false

when not defined(wasm) and not defined(nimony):
  import std/parseopt
  var optParser = initOptParser("")
  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      discard

    of cmdLongOption, cmdShortOption:
      case key
      of "test":
        quitImmediately = true

      else:
        discard

    of cmdEnd: assert(false) # cannot happen

main(quitImmediately)

