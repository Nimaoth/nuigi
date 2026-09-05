## Monotonic nanosecond timestamps for profiling and frame bookkeeping.
##
## The implementation selects Emscripten, SDL3, or the Nim standard monotonic
## clock at compile time. Values are suitable for elapsed-time measurements,
## not wall-clock dates.

when defined(emscripten):
  proc emscriptenGetNow(): float64 {.importc: "emscripten_get_now".}
elif defined(sdl3):
  import nuigi/backend/sdl3/sdl3
else:
  import std/monotimes

proc getTicksNS*(): uint64 {.inline, raises: [].} =
  when defined(emscripten):
    uint64(emscriptenGetNow() * 1e6)
  elif defined(sdl3):
    sdl3.getTicksNS()
  else:
    getMonoTime().ticks.uint64
