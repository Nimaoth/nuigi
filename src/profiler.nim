import std/[tables, assertions, strutils]
import sdl3, mymath

include compat2

# Timing source:
#   - native:          SDL_GetTicksNS  (nanoseconds)
#   - wasm/emscripten: emscripten_get_now() -> performance.now() (ms, sub-ms
#                      resolution), scaled to nanoseconds.
# Timestamps are always stored as nanoseconds, so the display/path code is
# identical on both backends and no precision is lost: performance.now() has
# microsecond resolution and storing ns just appends three zero digits.
when defined(emscripten):
  proc emscriptenGetNow*(): float64 {.importc: "emscripten_get_now".}

proc profNow*(): uint64 =
  when defined(emscripten):
    return uint64(emscriptenGetNow() * 1e6)
  else:
    return getTicksNS()

when defined(profiler) and not defined(nimony):

  let TimestampEndBit*: uint64 = 1'u64 shl 63
  let TimestampEndMask*: uint64 = uint64.high shr 1

  type ProfEvent* = object
    timestamp*: uint64
    location*: tuple[tag: string, file: string, line: uint32, col: uint32]

  type ProfFrame* = object
    first*: uint64
    last*: uint64
    location*: tuple[tag: string, file: string, line: uint32, col: uint32]

  type Profiler* = object
    record*: bool
    stopOnThreshold*: bool
    stopThreshold*: float32
    stopOnShow*: bool
    frameIndex*: int32
    scrollX*: float32
    scaleX*: float32
    plotScale*: float32
    plottedStats*: seq[string]
    timeHistory*: seq[array[512, float32]] # i'th entry is ms history for i'th plottedStat
    frameStart*: int

  var eventHistory* = array[1024 * 1024, ProfEvent].default
  var eventHistoryIndex*: int = 0
  var frameTimeIndex* = 0
  var plottedStatsCsvBuf*: array[1024, char]
  var plottedStatsCsvInitialized* = false

  var gprof* = Profiler(
    stopOnThreshold: false,
    stopThreshold: 10,
    record: true,
    scaleX: 0.5'f32,
    plotScale: 8.0'f32,
    frameStart: 0,
  )

when defined(profiler) and not defined(nimony):
  template prof*(tag: string) =
    # todo: make this smaller
    when defined(nimony) or defined(nlvm):
      let location = (tag, "", 0.uint32, 0.uint32)
    else:
      const info = instantiationInfo()
      const location = (tag, info.filename, info.line.uint32, info.column.uint32)

    let record = gprof.record
    if record:
      eventHistory[eventHistoryIndex] = ProfEvent(timestamp: profNow(), location: location)
      inc eventHistoryIndex
      if eventHistoryIndex >= eventHistory.len:
        eventHistoryIndex = 0

    defer:
      if record:
        eventHistory[eventHistoryIndex] = ProfEvent(timestamp: profNow() or TimestampEndBit, location: location)
        inc eventHistoryIndex
        if eventHistoryIndex >= eventHistory.len:
          eventHistoryIndex = 0

    discard
else:
  template prof*(tag: string) =
    discard

when defined(profiler) and not defined(nimony):
  template profd*(tag: string) =
    when defined(nimony) or defined(nlvm):
      let location = (tag, "", 0.uint32, 0.uint32)
    else:
      const info = instantiationInfo()
      let location = (tag, info.filename, info.line.uint32, info.column.uint32)

    let record = gprof.record
    if record:
      eventHistory[eventHistoryIndex] = ProfEvent(timestamp: profNow(), location: location)
      inc eventHistoryIndex
      if eventHistoryIndex >= eventHistory.len:
        eventHistoryIndex = 0

    defer:
      if record:
        eventHistory[eventHistoryIndex] = ProfEvent(timestamp: profNow() or TimestampEndBit, location: location)
        inc eventHistoryIndex
        if eventHistoryIndex >= eventHistory.len:
          eventHistoryIndex = 0

    discard
else:
  template profd*(tag: string) =
    discard

when defined(profiler) and not defined(nimony):
  proc lastEventTimestamp*(tag: string, frameIndex: int): uint64 =
    when defined(profiler) and not defined(nimony):
      var i = gprof.frameStart - 1
      if i < 0:
        i = eventHistory.high
      var frameIndex = frameIndex
      while i != gprof.frameStart:
        let event {.cursor.} = eventHistory[i]
        if event.timestamp == 0:
          break

        if (eventHistory[i].timestamp and TimestampEndBit) != 0 and eventHistory[i].location.tag == tag:
          if frameIndex == 0:
            return eventHistory[i].timestamp and TimestampEndMask
          dec frameIndex

        dec i
        if i < 0:
          i = eventHistory.high

      return profNow()
    else:
      return 0

  iterator profileFrames*(): (int, int, ProfFrame) {.sideEffect.} =
    var stack = newSeq[ProfEvent](0)
    var i = gprof.frameStart - 1
    if i < 0:
      i = eventHistory.high
    while i != gprof.frameStart:
      let event = eventHistory[i].addr
      if event.timestamp == 0:
        break

      let isEnd = (event.timestamp and TimestampEndBit) != 0
      if isEnd:
        stack.add(event[])
      else:
        if stack.len > 0:
          let last = stack.pop()
          yield (i, stack.len, ProfFrame(first: event.timestamp, last: last.timestamp and TimestampEndMask, location: event.location))

      dec i
      if i < 0:
        i = eventHistory.high

  # while stack.len > 0:
  #   let last = stack.pop()
  #   yield (i, stack.len, ProfFrame(first: 0, last: last.timestamp and TimestampEndMask, location: last.location))

  proc setCsvBuffer*(buf: var array[1024, char], values: openArray[string]) =
    for i in 0..<buf.len:
      buf[i] = '\0'

    var writePos = 0
    for i, value in values:
      if i > 0:
        for sepChar in ",":
          if writePos >= buf.len - 1:
            return
          buf[writePos] = sepChar
          inc writePos

      for c in value:
        if writePos >= buf.len - 1:
          return
        buf[writePos] = c
        inc writePos

  proc getCsvBuffer*(buf: array[1024, char]): string =
    var n = 0
    while n < buf.len and buf[n] != '\0':
      inc n
    result = newString(n)
    for i in 0..<n:
      result[i] = buf[i]

  proc parsePlottedStatsCsv*(csv: string): seq[string] =
    result = @[]
    for part in csv.split(','):
      let tag = part.strip()
      if tag.len > 0:
        result.add(tag)

  proc profilerBeginFrame*(setFrameStart = true) =
    proc toMs(ticks: uint64): float64 =
      return ticks.float64 / NS_PER_MS.float64
    if gprof.record:
      let nowTicks = lastEventTimestamp("frame", gprof.frameIndex)
      if setFrameStart:
        gprof.frameStart = eventHistoryIndex
      for i in 0..<gprof.timeHistory.len:
        gprof.timeHistory[i][frameTimeIndex] = 0

      var events: seq[tuple[depth: int, frame: ProfFrame]] = @[]
      for (index, depth, frame) in profileFrames():
        if frame.last <= nowTicks:
          for i, p in gprof.plottedStats:
            if frame.location.tag.startsWith(p):
              events.add (depth: depth, frame: frame)

          if depth == 0 and events.len > 1:
            break

      var current = (depth: int.high, frame: ProfFrame())
      for i in countdown(events.len - 1, 0):
        let (depth, frame) = events[i]
        if current.depth < int.high and frame.first > current.frame.last:
          current = (depth: int.high, frame: ProfFrame())
        if depth > current.depth and current.frame.location.tag == frame.location.tag:
          continue
        if frame.last <= nowTicks:
          for i, p in gprof.plottedStats:
            if frame.location.tag.startsWith(p):
              current = (depth, frame)
              gprof.timeHistory[i][frameTimeIndex] += toMs(frame.last - frame.first).float32

      inc frameTimeIndex
      if frameTimeIndex == gprof.timeHistory[0].len:
        frameTimeIndex = 0
