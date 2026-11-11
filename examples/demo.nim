## Nuigi demo built on the SDL3/Nuigi host (`nuigi/sdl3_app`). The host owns
## the window, GPU device (SDL renderer on Emscripten), fonts, input
## translation, the main loop (requestAnimationFrame on Emscripten) and the
## built-in tool windows: settings, demo, gamepad, profiler overlay, theme
## editor and debug panels. This file only configures the app, enables the
## tool windows and registers the demo's custom material.
import nuigi
import nuigi/sdl3_app
import nuigi/backend/sdl3/sdl3
when not defined(emscripten):
  import std/os
  import nuigi/rendering/render2d

include nuigi/util/compat2

when defined(nimony):
  {.feature: "assumeSync".}

when defined(nimony):
  when defined(nimNativeBackend):
    const title = "nuigi (nimony native)"
  else:
    const title = "nuigi (nimony)"
elif defined(nlvm):
  const title = "nuigi (nlvm)"
elif defined(ic):
  const title = "nuigi (nim2ic)"
else:
  const title = "nuigi (nim2)"

# The app must live at a stable address until deinit; on Emscripten the
# browser callbacks keep using it after `run` unwinds to the browser.
var app: Sdl3App

proc renderUi(app: var Sdl3App) =
  # All demo content comes from the host's built-in tool windows.
  discard

when not defined(emscripten):
  proc registerCustomMaterial() =
    # The demo window's "CustomMat" page draws with the first registered
    # Render2D material (MaterialId 1), so register it before any other.
    when defined(linux):
      const customFragPath = "./assets/custom.frag.spv"
    else:
      const customFragPath = "./assets/custom.frag.dxil"
    if fileExists(customFragPath):
      try:
        var customFrag = readFile(customFragPath)
        if customFrag.len > 0:
          var customBytes = newSeq[uint8](customFrag.len)
          copyMem(customBytes[0].addr, customFrag.readRawData(), customFrag.len)
          let materialId = app.render2D.registerMaterial(customBytes,
            numUniformBuffers = 1)
          echo "Registered custom material: ", materialId
      except:
        discard

proc main(quitImmediately: bool) =
  sdl3.setLogPriorities(LOG_PRIORITY_VERBOSE)

  var config = defaultSdl3AppConfig(title, 1920, 1080)
  config.shaderDirectory = "./assets"
  when not defined(emscripten):
    config.fontPaths = @[
      "assets/dontuse/fonts/DejaVuSansMono.ttf",
      # "assets/dontuse/fonts/DejaVuSansMono-Bold.ttf",
      # "assets/dontuse/fonts/DejaVuSansMono-Oblique.ttf",
      # "assets/dontuse/fonts/DejaVuSansMono-BoldOblique.ttf",
    ]

  assumeSyncBlock:
    app.init(config, renderUi)

  echo "SDL3 version: ", sdl3.getVersion().int
  echo "SDL3 revision: ", $sdl3.getRevision()
  discard setCurrentThreadPriority(THREAD_PRIORITY_TIME_CRITICAL)
  setGamepadEventsEnabled(true)

  app.showSettingsWindow = true
  app.showDemoWindow = true
  app.showGamepadWindow = true
  when defined(emscripten):
    # The browser renderer has no MSAA; antialias meshes instead.
    app.ui.antialiasMeshWidth = 1.0'f32
  when not defined(emscripten):
    registerCustomMaterial()

  if quitImmediately:
    assumeSyncBlock:
      app.deinit()
    return

  assumeSyncBlock:
    app.run()
  # On Emscripten `run` unwinds to the browser; the host deinitializes the
  # app from the browser tick when it quits.
  when not defined(emscripten):
    assumeSyncBlock:
      app.deinit()

var quitImmediately = false

when not defined(emscripten) and not defined(nimony):
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
