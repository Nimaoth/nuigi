# Monotonic timestamps in nanoseconds across supported backends.
when defined(emscripten):
  proc emscriptenGetNow(): float64 {.importc: "emscripten_get_now".}
elif defined(sdl3):
  import sdl3
else:
  import std/monotimes

proc getTicksNS*(): uint64 {.inline, raises: [].} =
  when defined(emscripten):
    uint64(emscriptenGetNow() * 1e6)
  elif defined(sdl3):
    sdl3.getTicksNS()
  else:
    getMonoTime().ticks.uint64
