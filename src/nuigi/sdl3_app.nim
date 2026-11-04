## SDL3/Nuigi desktop host. Keep the initialized app at a stable address until
## deinit: the font callbacks and Render2D refer to its font renderer.
import std/[os, math, strutils, tables, hashes]
import nuigi
import nuigi/backend/sdl3/sdl3
import nuigi/core/vecmath
import nuigi/rendering/render2d
import nuigi/text/fonts
import nuigi/widgets
import nuigi/widgets/[windows, plot]
import nuigi/debug/[debug_panel, profiler, profiler_ui]
import nuigi/styling/theme_editor
import nuigi/demo/[demo_window, gamepad_window]

include nuigi/util/compat2

const metricHistoryLength = 256

type
  Sdl3AppConfig* = object
    title*: string
    width*, height*: int
    initFlags*: uint32
    windowFlags*: uint64
    backgroundColor*: UiColor
    shaderDirectory*: string
    fontPaths*: seq[string]
    systemFonts*: bool
    renderOnDemand*: bool
    sampleCount*: GPUSampleCount
    idleDelayMs*: uint32
    trayEnabled*: bool
      ## Create a system tray icon whose menu shows/hides the window and
      ## quits. Left-clicking the icon toggles window visibility.
    trayTooltip*: string
      ## Defaults to the window title when empty.
    closeToTray*: bool
      ## Initial value of `Sdl3App.closeToTray`.
    iconPixels*: seq[uint8]
      ## Optional square RGBA32 icon (`iconSize` x `iconSize`) used for the
      ## window and tray. The tray uses a generated icon when empty.
    iconSize*: int

  TrayRequest = enum
    TrayToggleWindow, TrayQuit

  Sdl3TrayActionCallback* = proc(app: var Sdl3App, action: int, checked: bool)
    ## Runs on the main thread during `tick`, after the event pump. `checked`
    ## is the entry's new state (SDL toggles checkable entries before this).

  TrayAction = object
    label: string
    checkable, checked, enabled: bool
    callback: Sdl3TrayActionCallback
    entry: TrayEntry
    clicked: bool

  MetricHistory = object
    values: array[metricHistoryLength, float32]
    write, count: int

  Sdl3RenderUiCallback* = proc(app: var Sdl3App)
  Sdl3EventCallback* = proc(app: var Sdl3App, event: var Event): bool
    ## Return true to consume an event before Nuigi input translation.
    ## Quit and close requests are always honored; a close request hides the
    ## window instead of quitting when `closeToTrayActive` is true.
  Sdl3UpdateCallback* = proc(app: var Sdl3App, dt: float64)
    ## Called on every tick, even when on-demand rendering skips a frame.

  Sdl3App* = object
    window*: Window
    gpu*: GPUDevice
    render2D*: Render2D
    fontRender*: FontRender
    ui*: UiBuilder
    input*: UiInputSnapshot
    running*: bool
    renderOnDemand*: bool
    showSettingsWindow*, showDemoWindow*, showGamepadWindow*: bool
    dockSpace*: DockSpace
      ## Optional dock space for the app's window space. When set, windows
      ## can be docked into its layout; tool windows start floating.
    sampleCount*: GPUSampleCount
    backgroundColor*: UiColor
    frameMs*, tickMs*, fps*: float64
    renderedFrames*: uint64
    onRenderUi*: Sdl3RenderUiCallback
    onEvent*: Sdl3EventCallback
    onUpdate*: Sdl3UpdateCallback
    closeToTray*: bool
      ## Hide the window instead of quitting when it is closed. Only takes
      ## effect while a tray icon exists, so the app stays reachable.
    trayError*: string
      ## Why the requested tray icon could not be created, if it failed.
    tray: Tray
    trayIcon: ptr Surface
    trayToggleEntry, trayCloseEntry: TrayEntry
    trayMenu: TrayMenu
    trayActions: seq[TrayAction]
    trayRequests: set[TrayRequest]
    trayWindowShown, trayCloseShown: bool
    dirty: bool
    initialized: bool
    sdlInitialized: bool
    sdlInitializedFlags: uint32
    windowClaimed: bool
    lastTick: uint64
    idleDelayMs: uint32
    debugPanel, debugPanel2: DebugPanel
    themeEditor: ThemeEditor
    gamepad: DemoGamepadInput
    inputAccum: UiInputSnapshot
    metrics: array[3, MetricHistory]

proc defaultSdl3AppConfig*(title = "Nuigi", width = 1280,
    height = 720): Sdl3AppConfig =
  Sdl3AppConfig(title: title, width: width, height: height,
    initFlags: INIT_VIDEO or INIT_EVENTS or INIT_GAMEPAD,
    windowFlags: WINDOW_RESIZABLE,
    backgroundColor: rgba(0, 0, 0, 1),
    shaderDirectory: getAppDir() / "assets", systemFonts: true,
    renderOnDemand: true, sampleCount: GPU_SAMPLECOUNT_8, idleDelayMs: 10)

proc sdlFailure(operation: string) =
  raise newException(IOError, operation & ": " & $getError())

func toUiKey*(key: Keycode): tuple[found: bool, uiKey: UiKey] =
  case key.uint32
  of uint32(SDLK_A)..uint32(SDLK_Z):
    (true, UiKey(ord(KeyA) + int(key.uint32 - uint32(SDLK_A))))
  of uint32(SDLK_0)..uint32(SDLK_9):
    (true, UiKey(ord(Key0) + int(key.uint32 - uint32(SDLK_0))))
  of uint32(SDLK_F1)..uint32(SDLK_F12):
    (true, UiKey(ord(KeyF1) + int(key.uint32 - uint32(SDLK_F1))))
  of uint32(SDLK_KP_1)..uint32(SDLK_KP_9):
    (true, UiKey(ord(KeyKp1) + int(key.uint32 - uint32(SDLK_KP_1))))
  of uint32(SDLK_SPACE): (true, KeySpace)
  of uint32(SDLK_RETURN): (true, KeyEnter)
  of uint32(SDLK_ESCAPE): (true, KeyEscape)
  of uint32(SDLK_BACKSPACE): (true, KeyBackspace)
  of uint32(SDLK_TAB): (true, KeyTab)
  of uint32(SDLK_LEFT): (true, KeyLeft)
  of uint32(SDLK_RIGHT): (true, KeyRight)
  of uint32(SDLK_UP): (true, KeyUp)
  of uint32(SDLK_DOWN): (true, KeyDown)
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
  of uint32(SDLK_KP_0): (true, KeyKp0)
  of uint32(SDLK_KP_DIVIDE): (true, KeyKpDivide)
  of uint32(SDLK_KP_MULTIPLY): (true, KeyKpMultiply)
  of uint32(SDLK_KP_MINUS): (true, KeyKpSubtract)
  of uint32(SDLK_KP_PLUS): (true, KeyKpAdd)
  of uint32(SDLK_KP_PERIOD): (true, KeyKpDecimal)
  of uint32(SDLK_KP_ENTER): (true, KeyKpEnter)
  else: (false, default(UiKey))

func toUiModifiers*(mods: Keymod): UiModifiers =
  if (mods.uint32 and KMOD_SHIFT) != 0: result.incl ModShift
  if (mods.uint32 and KMOD_CTRL) != 0: result.incl ModControl
  if (mods.uint32 and KMOD_ALT) != 0: result.incl ModAlt
  if (mods.uint32 and KMOD_GUI) != 0: result.incl ModSuper

proc beginInputFrame*(input: var UiInputSnapshot) =
  inc input.frameIndex
  input.mousePressed = {}
  input.mouseReleased = {}
  input.mouseClickCount = 0
  input.mouseDelta = vec2(0)
  input.wheel = vec2(0)
  input.keysPressed = {}
  input.keysReleased = {}
  input.keysRepeated = {}
  input.navigationPressed = {}
  input.textInput.setLen(0)
  if input.externalDropped:
    input.externalDropped = false
    input.droppedFiles.setLen(0)
    input.droppedTexts.setLen(0)

proc accumulateSdlInput*(input: var UiInputSnapshot, event: Event) =
  case event.`type`
  of EVENT_MOUSE_MOTION:
    input.mouse = vec2(event.motion.x, event.motion.y)
    input.mouseDelta += vec2(event.motion.xrel, event.motion.yrel)
  of EVENT_MOUSE_BUTTON_DOWN, EVENT_MOUSE_BUTTON_UP:
    input.mouse = vec2(event.button.x, event.button.y)
    if event.button.button notin 1'u8..3'u8:
      return # Nuigi has no extra-button representation.
    let button = case event.button.button
      of 1: MouseLeft
      of 2: MouseMiddle
      else: MouseRight
    if event.`type` == EVENT_MOUSE_BUTTON_DOWN:
      input.mouseDown.incl button
      input.mousePressed.incl button
      if button == MouseLeft: input.mouseClickCount = event.button.clicks
    else:
      input.mouseDown.excl button
      input.mouseReleased.incl button
  of EVENT_MOUSE_WHEEL:
    let direction = if event.wheel.direction == MOUSEWHEEL_FLIPPED: -1.0'f32 else: 1.0'f32
    input.wheel += vec2(event.wheel.x, event.wheel.y) * direction
  of EVENT_KEY_DOWN, EVENT_KEY_UP:
    let (found, key) = toUiKey(event.key.key)
    if found:
      if event.`type` == EVENT_KEY_DOWN:
        input.keysDown.incl key
        if event.key.repeat: input.keysRepeated.incl key
        else: input.keysPressed.incl key
      else:
        input.keysDown.excl key
        input.keysReleased.incl key
    input.modsDown = toUiModifiers(event.key.`mod`)
  of EVENT_TEXT_INPUT:
    if event.text.text != nil: input.textInput.add($event.text.text)
  of EVENT_DROP_BEGIN:
    # OS drag and drop: BEGIN, POSITION*, then (FILE | TEXT)* and COMPLETE on
    # drop, or a bare COMPLETE when the drag leaves the window or is cancelled.
    input.externalDragActive = true
    input.externalDropped = false
    input.droppedFiles.setLen(0)
    input.droppedTexts.setLen(0)
  of EVENT_DROP_POSITION:
    input.externalDragActive = true
    let pos = vec2(event.drop.x, event.drop.y)
    input.mouseDelta += pos - input.mouse
    input.mouse = pos
  of EVENT_DROP_FILE:
    if event.drop.data != nil: input.droppedFiles.add($event.drop.data)
  of EVENT_DROP_TEXT:
    if event.drop.data != nil: input.droppedTexts.add($event.drop.data)
  of EVENT_DROP_COMPLETE:
    input.externalDragActive = false
    input.externalDropped = input.droppedFiles.len > 0 or input.droppedTexts.len > 0
  of EVENT_WINDOW_FOCUS_LOST:
    input.keysReleased = input.keysReleased + input.keysDown
    input.mouseReleased = input.mouseReleased + input.mouseDown
    input.keysDown = {}
    input.mouseDown = {}
    input.modsDown = {}
  else: discard

proc requestRender*(app: var Sdl3App) =
  app.dirty = true

proc needsRender*(app: var Sdl3App, hadEvents: bool): bool =
  let activity = app.ui.shouldRender(hadEvents or app.dirty or
    app.fontRender.glyphPackingDeferredCount > 0 or app.fontRender.fontAtlasNeedsReset)
  not app.renderOnDemand or activity

func defaultTrayIconPixels*(size: int): seq[uint8] =
  ## Generated RGBA32 icon: an accent-colored disc with a light center.
  result = newSeq[uint8](size * size * 4)
  let center = (size.float32 - 1) * 0.5'f32
  let radius = size.float32 * 0.5'f32 - 0.5'f32
  for y in 0 ..< size:
    for x in 0 ..< size:
      let distance = hypot(x.float32 - center, y.float32 - center)
      let alpha = clamp(radius - distance + 0.5'f32, 0, 1)
      let inner = clamp(radius * 0.4'f32 - distance + 0.5'f32, 0, 1)
      let rgb = [0.30'f32 + 0.65'f32 * inner, 0.78'f32 + 0.2'f32 * inner,
        0.98'f32 + 0.02'f32 * inner]
      let offset = (y * size + x) * 4
      for channel in 0..2: result[offset + channel] = uint8(rgb[channel] * 255)
      result[offset + 3] = uint8(alpha * 255)

func closeToTrayActive*(app: Sdl3App): bool =
  ## True when closing the window hides it instead of quitting.
  app.closeToTray and app.tray != nil

func hasTray*(app: Sdl3App): bool = app.tray != nil

proc windowVisible*(app: Sdl3App): bool =
  app.window != nil and (getWindowFlags(app.window) and WINDOW_HIDDEN) == 0

proc syncTrayMenu(app: var Sdl3App) =
  if app.tray == nil: return
  let shown = app.windowVisible
  if shown != app.trayWindowShown:
    app.trayWindowShown = shown
    setTrayEntryLabel(app.trayToggleEntry,
      if shown: cstring"Hide window" else: cstring"Show window")
  if app.closeToTray != app.trayCloseShown:
    app.trayCloseShown = app.closeToTray
    setTrayEntryChecked(app.trayCloseEntry, app.closeToTray)

proc showAppWindow*(app: var Sdl3App) =
  ## Shows, restores and raises the window, e.g. after it was hidden to the tray.
  if app.window == nil: return
  if not showWindow(app.window): sdlFailure("Could not show window")
  if (getWindowFlags(app.window) and WINDOW_MINIMIZED) != 0:
    discard restoreWindow(app.window)
  discard raiseWindow(app.window)
  app.requestRender()
  app.syncTrayMenu()

proc hideAppWindow*(app: var Sdl3App) =
  ## Hides the window; ticks keep running updates but skip rendering.
  if app.window == nil: return
  if not hideWindow(app.window): sdlFailure("Could not hide window")
  app.syncTrayMenu()

proc requestQuit*(app: var Sdl3App) =
  app.running = false

proc trayToggleClicked(userdata: pointer, entry: TrayEntry) {.cdecl.} =
  cast[ptr Sdl3App](userdata)[].trayRequests.incl TrayToggleWindow

proc trayCloseClicked(userdata: pointer, entry: TrayEntry) {.cdecl.} =
  # SDL toggles checkbox entries before invoking the callback.
  let app = cast[ptr Sdl3App](userdata)
  app[].closeToTray = getTrayEntryChecked(entry)
  app[].trayCloseShown = app[].closeToTray

proc trayQuitClicked(userdata: pointer, entry: TrayEntry) {.cdecl.} =
  cast[ptr Sdl3App](userdata)[].trayRequests.incl TrayQuit

proc trayLeftClicked(userdata: pointer, tray: Tray): bool {.cdecl.} =
  cast[ptr Sdl3App](userdata)[].trayRequests.incl TrayToggleWindow
  false

proc trayActionClicked(userdata: pointer, entry: TrayEntry) {.cdecl.} =
  let app = cast[ptr Sdl3App](userdata)
  for action in app[].trayActions.mitems:
    if action.entry == entry:
      action.clicked = true
      if action.checkable: action.checked = getTrayEntryChecked(entry)

const trayBuiltinEntries = 3 # Show/hide, keep running, separator.

proc trayActionFlags(action: TrayAction): TrayEntryFlags =
  result = if action.checkable: TRAYENTRY_CHECKBOX else: TRAYENTRY_BUTTON
  if action.checkable and action.checked: result = result or TRAYENTRY_CHECKED
  if not action.enabled: result = result or TRAYENTRY_DISABLED

proc addTrayAction*(app: var Sdl3App, label: string,
    callback: Sdl3TrayActionCallback, checkable = false, checked = false,
    enabled = true): int =
  ## Appends an entry to the flat list of custom tray menu actions, shown
  ## between the built-in window entries and Quit. Returns its id. Without a
  ## tray the action is still recorded, so updates are harmless no-ops.
  if callback == nil:
    raise newException(ValueError, "Tray action requires a callback")
  result = app.trayActions.len
  app.trayActions.add TrayAction(label: label, checkable: checkable,
    checked: checked, enabled: enabled, callback: callback)
  if app.trayMenu == nil: return
  let position = cint(trayBuiltinEntries + result)
  var text = label
  let entry = insertTrayEntryAt(app.trayMenu, position, toCString(text),
    app.trayActions[result].trayActionFlags)
  if entry == nil: sdlFailure("Could not create tray menu entry")
  setTrayEntryCallback(entry, trayActionClicked, app.addr)
  app.trayActions[result].entry = entry
  if result == 0 and insertTrayEntryAt(app.trayMenu, position + 1, nil,
      TRAYENTRY_BUTTON) == nil:
    sdlFailure("Could not create tray menu separator")

proc checkTrayAction(app: Sdl3App, action: int) =
  if action notin 0 ..< app.trayActions.len:
    raise newException(IndexDefect, "Unknown tray action: " & $action)

proc trayActionChecked*(app: Sdl3App, action: int): bool =
  app.checkTrayAction(action)
  app.trayActions[action].checked

proc setTrayActionChecked*(app: var Sdl3App, action: int, checked: bool) =
  app.checkTrayAction(action)
  if app.trayActions[action].checked == checked: return
  app.trayActions[action].checked = checked
  if app.trayActions[action].entry != nil:
    setTrayEntryChecked(app.trayActions[action].entry, checked)

proc setTrayActionEnabled*(app: var Sdl3App, action: int, enabled: bool) =
  app.checkTrayAction(action)
  if app.trayActions[action].enabled == enabled: return
  app.trayActions[action].enabled = enabled
  if app.trayActions[action].entry != nil:
    setTrayEntryEnabled(app.trayActions[action].entry, enabled)

proc setTrayActionLabel*(app: var Sdl3App, action: int, label: string) =
  app.checkTrayAction(action)
  if app.trayActions[action].label == label: return
  app.trayActions[action].label = label
  if app.trayActions[action].entry != nil:
    var text = label
    setTrayEntryLabel(app.trayActions[action].entry, toCString(text))

proc clickTrayAction*(app: var Sdl3App, action: int) =
  ## Simulates a menu click: toggles checkable actions and queues the
  ## callback for the next `tick`.
  app.checkTrayAction(action)
  if not app.trayActions[action].enabled: return
  if app.trayActions[action].checkable:
    app.setTrayActionChecked(action, not app.trayActions[action].checked)
  app.trayActions[action].clicked = true

proc dispatchTrayActions(app: var Sdl3App): bool =
  ## Returns true if any action callback ran.
  var index = 0
  while index < app.trayActions.len:
    if app.trayActions[index].clicked:
      app.trayActions[index].clicked = false
      result = true
      let callback = app.trayActions[index].callback
      callback(app, index, app.trayActions[index].checked)
    inc index

proc createIconSurface(app: var Sdl3App, config: Sdl3AppConfig) =
  let generated = config.iconPixels.len == 0
  let size = if generated: 32 else: config.iconSize
  if not generated and (size <= 0 or config.iconPixels.len != size * size * 4):
    raise newException(ValueError,
      "iconPixels must contain iconSize x iconSize RGBA32 pixels")
  let pixels = if generated: defaultTrayIconPixels(size) else: config.iconPixels
  app.trayIcon = createSurface(size.cint, size.cint, PIXELFORMAT_RGBA32)
  if app.trayIcon == nil: sdlFailure("Could not create icon surface")
  for y in 0 ..< size:
    copyMem(app.trayIcon.pixels[y * app.trayIcon.pitch].addr,
      pixels[y * size * 4].addr, size * 4)

proc setTrayIconPixels*(app: var Sdl3App, pixels: openArray[uint8], size: int) =
  ## Replaces the tray icon with `size` x `size` RGBA32 pixels. No-op without a tray.
  if app.tray == nil: return
  if size <= 0 or pixels.len != size * size * 4:
    raise newException(ValueError,
      "pixels must contain size x size RGBA32 pixels")
  let surface = createSurface(size.cint, size.cint, PIXELFORMAT_RGBA32)
  if surface == nil: sdlFailure("Could not create icon surface")
  for y in 0 ..< size:
    copyMem(surface.pixels[y * surface.pitch].addr,
      pixels[y * size * 4].unsafeAddr, size * 4)
  setTrayIcon(app.tray, surface)
  destroySurface(surface)

proc initTray(app: var Sdl3App, tooltip: string) =
  ## Tray failures are reported through `trayError` rather than aborting, as
  ## some desktops have no tray; the window then closes normally.
  let props = createProperties()
  if props == 0: sdlFailure("Could not create tray properties")
  var tip = tooltip
  discard setPointerProperty(props, PROP_TRAY_CREATE_ICON_POINTER, app.trayIcon)
  discard setStringProperty(props, PROP_TRAY_CREATE_TOOLTIP_STRING, toCString(tip))
  discard setPointerProperty(props, PROP_TRAY_CREATE_USERDATA_POINTER, app.addr)
  discard setPointerProperty(props, PROP_TRAY_CREATE_LEFTCLICK_CALLBACK_POINTER,
    cast[pointer](trayLeftClicked))
  app.tray = createTrayWithProperties(props)
  destroyProperties(props)
  if app.tray == nil:
    app.trayError = "Could not create tray icon: " & $getError()
    return
  let menu = createTrayMenu(app.tray)
  if menu == nil:
    app.trayError = "Could not create tray menu: " & $getError()
    destroyTray(app.tray)
    app.tray = nil
    return
  template entry(label: cstring, flags: TrayEntryFlags, callback: TrayCallback): TrayEntry =
    let created = insertTrayEntryAt(menu, -1, label, flags)
    let entryCallback: TrayCallback = callback
    if created == nil: sdlFailure("Could not create tray menu entry")
    if entryCallback != nil: setTrayEntryCallback(created, entryCallback, app.addr)
    created
  app.trayWindowShown = app.windowVisible
  app.trayCloseShown = app.closeToTray
  app.trayToggleEntry = entry(if app.trayWindowShown: cstring"Hide window"
    else: cstring"Show window", TRAYENTRY_BUTTON, trayToggleClicked)
  app.trayCloseEntry = entry("Keep running when window is closed",
    TRAYENTRY_CHECKBOX or (if app.closeToTray: TRAYENTRY_CHECKED else: 0'u32),
    trayCloseClicked)
  discard entry(nil, TRAYENTRY_BUTTON, nil)
  for action in app.trayActions.mitems:
    var text = action.label
    action.entry = entry(toCString(text), action.trayActionFlags, trayActionClicked)
  if app.trayActions.len > 0: discard entry(nil, TRAYENTRY_BUTTON, nil)
  discard entry("Quit", TRAYENTRY_BUTTON, trayQuitClicked)
  app.trayMenu = menu
  # Close requests are handled by the app, which decides whether to hide.
  discard setHint(HINT_QUIT_ON_LAST_WINDOW_CLOSE, "0")

proc deinit*(app: var Sdl3App) =
  app.running = false
  app.gamepad.shutdown()
  if app.tray != nil:
    destroyTray(app.tray)
    app.tray = nil
    app.trayToggleEntry = nil
    app.trayCloseEntry = nil
    discard resetHint(HINT_QUIT_ON_LAST_WINDOW_CLOSE)
  app.trayMenu = nil
  app.trayActions.setLen(0)
  app.trayRequests = {}
  if app.gpu != nil:
    discard waitForGPUIdle(app.gpu)
    app.render2D.deinitRender2D()
    if app.windowClaimed:
      releaseWindowFromGPUDevice(app.gpu, app.window)
      app.windowClaimed = false
    destroyGPUDevice(app.gpu)
    app.gpu = nil
  app.fontRender.deinit()
  if app.window != nil:
    destroyWindow(app.window)
    app.window = nil
  if app.trayIcon != nil:
    destroySurface(app.trayIcon)
    app.trayIcon = nil
  if app.sdlInitialized:
    sdl3.quitSubSystem(app.sdlInitializedFlags)
  app.initialized = false
  app.sdlInitialized = false

proc init*(app: var Sdl3App, config: Sdl3AppConfig,
    renderUi: Sdl3RenderUiCallback, update: Sdl3UpdateCallback = nil,
    handleEvent: Sdl3EventCallback = nil) =
  if app.initialized or app.sdlInitialized:
    raise newException(ValueError, "SDL3 app is already initialized")
  if config.width <= 0 or config.height <= 0:
    raise newException(ValueError, "SDL3 window dimensions must be positive")
  if renderUi == nil:
    raise newException(ValueError, "SDL3 app requires a UI render callback")
  app.onRenderUi = renderUi
  app.onUpdate = update
  app.onEvent = handleEvent
  app.renderOnDemand = config.renderOnDemand
  app.sampleCount = config.sampleCount
  app.backgroundColor = config.backgroundColor
  app.idleDelayMs = config.idleDelayMs
  app.closeToTray = config.closeToTray
  app.trayError = ""
  try:
    if not sdl3.init(config.initFlags or INIT_VIDEO or INIT_EVENTS):
      sdlFailure("Could not initialize SDL3")
    app.sdlInitialized = true
    app.sdlInitializedFlags = config.initFlags or INIT_VIDEO or INIT_EVENTS
    var title = config.title
    app.window = createWindow(toCString(title), config.width.cint,
      config.height.cint, config.windowFlags)
    if app.window == nil: sdlFailure("Could not create SDL window")
    if config.trayEnabled or config.iconPixels.len > 0:
      app.createIconSurface(config)
      if config.iconPixels.len > 0 and not setWindowIcon(app.window, app.trayIcon):
        sdlFailure("Could not set window icon")
    if config.trayEnabled:
      app.initTray(if config.trayTooltip.len > 0: config.trayTooltip else: config.title)
    when defined(linux):
      app.gpu = createGPUDevice(render2DShaderFormat, defined(sdlDebug), "vulkan")
    else:
      app.gpu = createGPUDevice(render2DShaderFormat, defined(sdlDebug), "direct3d12")
    if app.gpu == nil: sdlFailure("Could not create SDL GPU device")
    if not claimWindowForGPUDevice(app.gpu, app.window):
      sdlFailure("Could not claim SDL window")
    app.windowClaimed = true
    if not setGPUSwapchainParameters(app.gpu, app.window,
        GPU_SWAPCHAINCOMPOSITION_SDR, GPU_PRESENTMODE_VSYNC):
      sdlFailure("Could not enable GPU vsync")
    if not app.fontRender.init():
      raise newException(IOError, "Could not initialize Nuigi font rendering")
    if config.systemFonts: discard app.fontRender.addSystemDefaultFonts()
    for path in config.fontPaths:
      if app.fontRender.addFontFace(path) < 0:
        raise newException(IOError, "Could not load font: " & path)
    if app.fontRender.fonts.len == 0:
      raise newException(IOError, "No fonts loaded; configure fontPaths or systemFonts")
    for path in [basicVertShaderPath, basicFragShaderPath]:
      let resolved = config.shaderDirectory / extractFilename(path)
      if not fileExists(resolved):
        raise newException(IOError, "Missing Render2D shader: " & resolved)
    if not app.render2D.initRender2D(app.fontRender.addr, app.gpu,
        shaderDirectory = config.shaderDirectory):
      sdlFailure("Could not initialize Render2D")
    let font = app.fontRender.addr
    proc arrange(text: openArray[char], fontId: UiFontId, fontSize, maxWidth: float32,
        flags: UiTextFlags): UiTextArrangement {.gcsafe, raises: [].} =
      font[].arrangeText(text, fontSize, fontId, maxWidth, flags)
    proc mesh(arrangement: UiTextArrangement, pos, offset: Vec2, color: UiColor,
        transform: UiAffine2): tuple[data: ptr UncheckedArray[UiVertex], count: int]
        {.gcsafe, raises: [].} =
      let vertices = font[].buildTextMesh(arrangement, pos, offset, color, transform)
      (cast[ptr UncheckedArray[UiVertex]](vertices.data), vertices.count)
    proc listFonts(): seq[(string, UiFontId)] {.gcsafe, raises: [].} =
      font[].listFontFaces()
    proc resolveFont(name: string): UiFontId {.gcsafe, raises: [].} =
      max(0'i16, font[].findFont(name))
    proc openUrl(url: string): bool {.nimcall, raises: [].} =
      var value = url
      sdl3.openURL(toCString(value))
    proc readClipboard(): string {.nimcall, raises: [].} =
      let text = sdl3.getClipboardText()
      if text != nil:
        result = $text
        sdl3.sdlFree(text)
    proc writeClipboard(text: string): bool {.nimcall, raises: [].} =
      var value = text
      sdl3.setClipboardText(toCString(value))
    app.ui = newBuilder(arrange, mesh)
    app.ui.openUrlFn = openUrl
    app.ui.readClipboardFn = readClipboard
    app.ui.writeClipboardFn = writeClipboard
    app.themeEditor.listFonts = listFonts
    app.themeEditor.resolveFont = resolveFont
    for (name, id) in app.fontRender.listFontFaces(): app.ui.fonts[name] = id
    app.lastTick = sdl3.getTicksNS()
    app.fps = 60
    app.dirty = true
    app.running = true
    app.initialized = true
  except:
    app.deinit()
    raise

proc metricPoint(x: float32, userData: int): float32 {.gcsafe, raises: [].} =
  let history = cast[ptr MetricHistory](userData)
  if history[].count == 0: return 0
  let index = clamp(x.int, 0, history[].count - 1)
  history[].values[(history[].write + metricHistoryLength - history[].count + index) mod metricHistoryLength]

proc buildMetricRow(app: var Sdl3App, name: string, metric: int) =
  let history = app.metrics[metric].addr
  var average = 0.0'f32
  var maximum = 1.0'f32
  let recent = min(50, history[].count)
  for i in 0 ..< history[].count:
    let value = history[].values[(history[].write - 1 - i + metricHistoryLength) mod metricHistoryLength]
    maximum = max(maximum, value)
    if i < recent: average += value
  if recent > 0: average /= recent.float32
  template b: untyped = app.ui
  b.layoutHorizontal:
    discard b.fillX().fitY().gap(8)
    b.node:
      discard b.size(100, 50)
      let pos = b.absoluteNodePos(b.currentNodeIndex())
      let series = [PlotSeries(fn: metricPoint, userData: cast[int](history),
        label: uiString(name), lineColor: b.themeStyle(UiStyleIndexAccent)[].fillColor)]
      discard b.customRenderCommands(b.buildPlotVertices(pos, vec2(100, 50),
        vec2(0, max(1, history[].count - 1).float32), vec2(0, maximum * 1.1'f32),
        series, resolution = max(2, min(100, history[].count)), mousePos = b.frameCtx.input.mouse))
    b.label(name & ": " & formatFloat(average.float64, ffDecimal, if metric == 0: 0 else: 1))

proc buildSettingsWindow*(app: var Sdl3App) =
  template b: untyped = app.ui
  b.window("Settings", 0, 0, 420, 640):
    b.scrollBox():
      discard b.fillX().fitY()
      b.layoutVertical:
        discard b.fillX().fitY().padding(12).gap(12)
        b.label("Performance")
        app.buildMetricRow("FPS", 0)
        app.buildMetricRow("Frame (ms)", 1)
        app.buildMetricRow("Tick (ms)", 2)
        b.label("Rendering")
        b.tableLayout([tableColumnFit(), tableColumnFill()], 14, 10):
          discard b.fillX().fitY()
          b.label("MSAA Samples")
          var msaaSelected = ord(app.sampleCount)
          if b.dropdown(["1x", "2x", "4x", "8x"], msaaSelected):
            app.sampleCount = GPUSampleCount(msaaSelected)
          b.label("Mesh AA Width")
          discard b.dragFloat(b.antialiasMeshWidth, 0.0'f32, 0.0'f32, 4.0'f32)
          b.label("Render On Demand")
          discard b.checkbox("", app.renderOnDemand)
          b.label("Profiler Overlay")
          discard b.checkbox("", gShowNuiProfiler)
          b.label("Demo")
          discard b.checkbox("", app.showDemoWindow)
          b.label("Gamepad Input")
          discard b.checkbox("", app.showGamepadWindow)
          b.label("Theme Editor")
          discard b.checkbox("", b.showThemeEditor)
          b.label("Debug Panel")
          discard b.checkbox("", b.showDebugPanel)
          b.label("Debug Panel 2")
          discard b.checkbox("", b.showDebugPanel2)
          if app.hasTray:
            b.label("Close to Tray")
            discard b.checkbox("", app.closeToTray)
        if app.trayError.len > 0:
          b.label(app.trayError)
        b.label("Text")
        b.label("Font Hinting")
        var fontSelected = if FontRenderFlag.SubpixelPhasing in app.fontRender.flags: 0
          elif FontRenderFlag.PixelSnapping in app.fontRender.flags: 1
          else: 2
        if b.dropdown(["Subpixel", "Pixel snapped", "Fractional"], fontSelected):
          case fontSelected
          of 0: app.fontRender.flags = {FontRenderFlag.SubpixelPhasing, FontRenderFlag.PixelSnapping}
          of 1: app.fontRender.flags = {FontRenderFlag.PixelSnapping}
          else: app.fontRender.flags = {}

proc buildTools(app: var Sdl3App) =
  template b: untyped = app.ui
  if app.showSettingsWindow: app.buildSettingsWindow()
  if app.showDemoWindow:
    b.window("Demo", 400, 100, 800, 900): b.buildDemoUi()
  if app.showGamepadWindow: app.gamepad.buildGamepadWindow(b)
  if gShowNuiProfiler:
    b.window("Profiler", 1200, 100, 700, 1000): b.buildNuiProfiler()
  if b.showThemeEditor: discard b.themeEditor(app.themeEditor)
  if b.showDebugPanel:
    let viewport = b.frameCtx.viewportSize
    let left = if b.showDebugPanel2: 0.4'f32 else: 0.6'f32
    let width = if b.showDebugPanel2: 0.3'f32 else: 0.4'f32
    b.window("Debug Panel", viewport.x * left, 0, viewport.x * width, viewport.y):
      discard b.debugPanel(app.debugPanel)
      b.flushDeferredNodes()
    if b.showDebugPanel2:
      b.window("Debug Panel 2", viewport.x * 0.7'f32, 0, viewport.x * 0.3'f32, viewport.y):
        discard b.debugPanel(app.debugPanel2)
  b.keepAlive(themeEditorId)
  b.keepAlive("Examples".hashChars.UiNodeId)

proc syncTextInput(app: var Sdl3App) =
  let request = app.ui.textInputRequest
  if request.active:
    if not app.window.textInputActive() and not app.window.startTextInput():
      sdlFailure("Could not start text input")
    var rect = Rect(x: floor(request.rectPos.x).cint, y: floor(request.rectPos.y).cint,
      w: max(1.0'f32, ceil(request.rectSize.x)).cint,
      h: max(1.0'f32, ceil(request.rectSize.y)).cint)
    if not app.window.setTextInputArea(rect.addr, max(0.0'f32, round(request.cursorOffset)).cint):
      sdlFailure("Could not set text input area")
  elif app.window.textInputActive():
    if not app.window.stopTextInput(): sdlFailure("Could not stop text input")

func gpuTextureToImageId*(texture: GPUTexture): UiImageId =
  cast[UiImageId](texture)

func textureToImageId*(texture: Texture): UiImageId =
  UiImageId(cast[uint64](texture) or (1'u64 shl 62))

proc resolveTexture(id: UiImageId): GPUTexture =
  if (id.uint64 shr 62) == 1:
    let texture = cast[Texture](id.uint64 and not (3'u64 shl 62))
    if texture == nil: return nil
    cast[GPUTexture](getPointerProperty(getTextureProperties(texture), "SDL.texture.gpu.texture", nil))
  else: cast[GPUTexture](id)

func sampler(mode: TextureSamplerMode): Render2DSamplerMode =
  if mode == TextureSamplerMode.Linear: Render2DSamplerMode.Linear
  else: Render2DSamplerMode.Nearest

proc renderCommands(app: var Sdl3App) =
  var transforms = @[identityAffine2()]
  let renderer = app.render2D.addr
  template r: untyped = renderer[]
  proc quad(transform: UiAffine2, pos, size: Vec2, color: UiColor,
      image = UiImageId(0), uv0 = vec2(0), uv1 = vec2(1),
      mode = TextureSamplerMode.Linear) =
    if size.x <= 0 or size.y <= 0: return
    let points = [pos, pos + vec2(size.x, 0), pos + size, pos + vec2(0, size.y)]
    let uvs = [uv0, vec2(uv1.x, uv0.y), uv1, vec2(uv0.x, uv1.y)]
    const indices = [0, 1, 2, 0, 2, 3]
    var vertices: array[6, UiVertex]
    for i, index in indices:
      vertices[i] = UiVertex(pos: transform.transformPoint2(points[index]), uv: uvs[index], color: color)
    if not r.drawVertices(cast[ptr UncheckedArray[Render2DVertex]](vertices[0].addr).toOpenArray(0, 5),
        resolveTexture(image), sampler(mode)):
      sdlFailure("Could not draw UI quad")
  for command in app.ui.frameOutput.commands:
    let transform = transforms[^1]
    case command.kind
    of CmdTransformPush:
      transforms.add applyNodeRenderTransform(transform, command.pivot,
        command.offset, command.rotation, command.scale)
    of CmdTransformPop:
      if transforms.len > 1: discard transforms.pop()
    of CmdRawVertices:
      if command.vertexData != nil and command.vertexCount > 0:
        if not r.drawVertices(cast[ptr UncheckedArray[Render2DVertex]](command.vertexData)
            .toOpenArray(0, command.vertexCount - 1), resolveTexture(command.imageId),
            sampler(command.samplerMode), command.materialId, command.materialUniform):
          sdlFailure("Could not draw UI vertices")
    of CmdRectFill: quad(transform, command.pos, command.size, command.color)
    of CmdRectStroke:
      let thickness = min(max(1.0'f32, command.thickness), min(command.size.x, command.size.y) * 0.5'f32)
      let innerHeight = max(0.0'f32, command.size.y - thickness * 2)
      quad(transform, command.pos, vec2(command.size.x, thickness), command.color)
      quad(transform, command.pos + vec2(0, command.size.y - thickness),
        vec2(command.size.x, thickness), command.color)
      quad(transform, command.pos + vec2(0, thickness), vec2(thickness, innerHeight), command.color)
      quad(transform, command.pos + vec2(command.size.x - thickness, thickness),
        vec2(thickness, innerHeight), command.color)
    of CmdClipPush:
      let rect = transformedRectAabb(transform, command.pos, command.size)
      r.pushClipRect(floor(rect.pos.x).cint, floor(rect.pos.y).cint,
        max(0.0'f32, ceil(rect.size.x)).cint, max(0.0'f32, ceil(rect.size.y)).cint)
    of CmdClipPop: r.popClipRect()
    of CmdLine:
      let start = transform.transformPoint2(command.pos)
      let finish = transform.transformPoint2(command.pos2)
      if (finish - start).length > 0.0001'f32 and not r.drawLine(start, finish,
          command.thickness, FColor(r: command.color.r, g: command.color.g, b: command.color.b, a: command.color.a)):
        sdlFailure("Could not draw UI line")
    of CmdImage:
      quad(transform, command.pos, command.size, command.color,
        command.imageId, command.uv0, command.uv1, command.samplerMode)
    of CmdText:
      if command.textIndex > 0:
        let text = app.ui.frame.texts[command.textIndex - 1].addr
        let arrangement = app.ui.getTextArrangement(text, -1)
        let mesh = app.fontRender.buildTextMesh(arrangement[], command.pos, vec2(0), text.textColor, transform)
        if mesh.count > 0:
          if not r.drawVertices(cast[ptr UncheckedArray[Render2DVertex]](mesh.data)
              .toOpenArray(0, mesh.count - 1), cast[GPUTexture](1), sampler(command.samplerMode)):
            sdlFailure("Could not draw UI text")
    of CmdCircleFill:
      var vertices: array[72, UiVertex]
      for i in 0 ..< 24:
        vertices[i * 3] = UiVertex(pos: transform.transformPoint2(command.pos), color: command.color)
        for j in 0..1:
          let angle = 2 * PI.float32 * (i + j).float32 / 24
          vertices[i * 3 + j + 1] = UiVertex(pos: transform.transformPoint2(
            command.pos + vec2(cos(angle), sin(angle)) * command.radius), color: command.color)
      if not r.drawVertices(cast[ptr UncheckedArray[Render2DVertex]](vertices[0].addr).toOpenArray(0, 71)):
        sdlFailure("Could not draw UI circle")

proc tick*(app: var Sdl3App): bool =
  ## Pump events and update once. Returns true if a frame was presented.
  if not app.initialized:
    raise newException(ValueError, "SDL3 app is not initialized")
  if not app.running: return false
  let started = sdl3.getTicksNS()
  # The profiler UI derives frame times from the "frame" scope and plots the
  # "frame" and "tick" scopes by default.
  when defined(nuigiProfiler):
    gprof.frameStart = eventHistoryIndex
  profilerFrameStart()
  prof("frame")
  when defined(nuigiProfiler):
    profilerBeginFrame(false)
  let dt = (started - app.lastTick).float64 / 1_000_000_000.0
  app.lastTick = started
  var hadEvents = false
  block:
    prof("tick")
    block:
      prof("events")
      app.inputAccum.beginInputFrame()
      app.gamepad.beginFrame()
      var event: Event
      while pollEvent(event):
        let eventWindow = getWindowFromEvent(event.addr)
        if eventWindow != nil and eventWindow != app.window: continue
        hadEvents = true
        if event.`type` == EVENT_QUIT:
          app.running = false
        elif event.`type` == EVENT_WINDOW_CLOSE_REQUESTED:
          if app.closeToTrayActive: app.hideAppWindow()
          else: app.running = false
        let handler = app.onEvent
        let consumed = handler != nil and handler(app, event)
        if not consumed and not app.gamepad.handleEvent(event):
          app.inputAccum.accumulateSdlInput(event)
      # Tray callbacks run inside the event pump above.
      let trayRequests = app.trayRequests
      app.trayRequests = {}
      if TrayQuit in trayRequests:
        app.running = false
      elif TrayToggleWindow in trayRequests:
        hadEvents = true
        if app.windowVisible: app.hideAppWindow()
        else: app.showAppWindow()
      if TrayQuit notin trayRequests and app.dispatchTrayActions():
        hadEvents = true
      app.syncTrayMenu()
    if not app.running: return false
    app.input = app.inputAccum
    app.gamepad.applyToSnapshot(app.input)
    let update = app.onUpdate
    if update != nil:
      prof("update")
      update(app, dt)
    if not app.running: return false
  if not app.needsRender(hadEvents):
    prof("idle")
    sdl3.delay(app.idleDelayMs)
    return false
  var width, height: cint
  if not app.window.getWindowSize(width, height): sdlFailure("Could not read window size")
  if width <= 0 or height <= 0 or
      (getWindowFlags(app.window) and (WINDOW_MINIMIZED or WINDOW_HIDDEN)) != 0:
    sdl3.delay(app.idleDelayMs)
    return false
  app.dirty = false
  prof("render")
  if not app.render2D.beginRender(nil, width.uint32, height.uint32,
      sample_count = app.sampleCount):
    sdlFailure("Could not begin UI render")
  block:
    prof("buildUi")
    app.ui.fontAtlasImageId = gpuTextureToImageId(app.render2D.fontTexture)
    discard app.ui.beginUiFrame(width.float32, height.float32, app.input)
    app.ui.windowSpace(app.dockSpace)
    app.ui.node:
      discard app.ui.fill().noHover()
      app.ui.overlays = app.ui.currentNode.id
    block:
      prof("renderUi")
      app.onRenderUi(app)
    block:
      prof("buildTools")
      app.buildTools()
    block:
      prof("endUiFrame")
      app.ui.endUiFrame(buildMeshRenderCommands = true)
    app.syncTextInput()
  app.render2D.clear()
  var background = [
    Render2DVertex(x: 0, y: 0),
    Render2DVertex(x: width.float32, y: 0),
    Render2DVertex(x: width.float32, y: height.float32),
    Render2DVertex(x: 0, y: 0),
    Render2DVertex(x: width.float32, y: height.float32),
    Render2DVertex(x: 0, y: height.float32),
  ]
  for vertex in background.mitems:
    vertex.r = app.backgroundColor.r
    vertex.g = app.backgroundColor.g
    vertex.b = app.backgroundColor.b
    vertex.a = app.backgroundColor.a
  if not app.render2D.drawVertices(background): sdlFailure("Could not draw UI background")
  block:
    prof("renderCommands")
    app.renderCommands()
  let deferred = app.fontRender.glyphPackingDeferredCount
  app.tickMs = (sdl3.getTicksNS() - started).float64 / 1_000_000.0
  let atlasReset = app.fontRender.fontAtlasNeedsReset
  block:
    prof("submit")
    if not app.render2D.endRender(): sdlFailure("Could not submit UI render")
  block:
    prof("present")
    if not app.render2D.presentToSwapchain(app.window): sdlFailure("Could not present UI render")
  if atlasReset or deferred > 0: app.requestRender()
  app.frameMs = (sdl3.getTicksNS() - started).float64 / 1_000_000.0
  if dt > 0: app.fps = app.fps * 0.5 + 0.5 / dt
  for i, value in [app.fps, dt * 1000, app.tickMs]:
    app.metrics[i].values[app.metrics[i].write] = value.float32
    app.metrics[i].write = (app.metrics[i].write + 1) mod metricHistoryLength
    app.metrics[i].count = min(metricHistoryLength, app.metrics[i].count + 1)
  inc app.renderedFrames
  true

proc run*(app: var Sdl3App) =
  if not app.initialized:
    raise newException(ValueError, "SDL3 app is not initialized")
  while app.running: discard app.tick()
