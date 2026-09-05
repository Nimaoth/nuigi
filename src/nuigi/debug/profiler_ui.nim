## Nuigi visualization and controls for the optional profiler.
##
## Converts recorded event ranges into a flame graph and rolling statistics
## into plot series, with controls for capture, scale, frame selection, and
## stop conditions. The module mirrors some profiler fields in widget-friendly
## scalar state and has useful data only when profiling was compiled in.

import std/[strutils]
import nuigi/core/[vecmath, arena, array_view]
import nuigi
import nuigi/widgets
import nuigi/widgets/plot
import nuigi/debug/profiler

include nuigi/util/compat2

const NS_PER_MS: uint64     = 1000000
const NS_PER_US: uint64     = 1000
var gShowNuiProfiler* = false

# Proxy state used by the nuigi controls (the underlying `gprof` fields use the
# same types, but some widgets only accept `var float32`, so we mirror them).
var profFrameIndexFloat* = 0.0'f32
var profPlottedStatsCsv* = "frame,tick"
const MaxPlotStats* = 64
var profPlotSampleData*: array[MaxPlotStats, array[512, float32]]
var profPlotSampleCount* = 0

# y-range of a single flame-graph row in pixels
const FlameRowHeight* = 20.0'f32

func hsvToRgba*(h, s, v: float32, a: float32 = 1.0'f32): UiColor =
  ## Convert an HSV color (h in [0,1), s/v in [0,1]) to a UiColor.
  let hh = h - floor(h)
  let i = int(hh * 6.0'f32)
  let f = hh * 6.0'f32 - i.float32
  let p = v * (1.0'f32 - s)
  let q = v * (1.0'f32 - f * s)
  let t = v * (1.0'f32 - (1.0'f32 - f) * s)
  case i mod 6
  of 0: rgba(v, t, p, a)
  of 1: rgba(q, v, p, a)
  of 2: rgba(p, v, t, a)
  of 3: rgba(p, q, v, a)
  of 4: rgba(t, p, v, a)
  else: rgba(v, p, q, a)

proc profSampleFn*(x: float32, userData: int): float32 =
  let i = clamp(x.int32, 0'i32, profPlotSampleCount.int32 - 1'i32)
  if i < 0 or i >= profPlotSampleCount:
    return 0.0'f32
  let s = clamp(userData, 0, MaxPlotStats - 1)
  return profPlotSampleData[s][i]

when defined(profiler) and not defined(nimony):
  proc buildFlameDeferred(b: var UiBuilder, nodeIdx: int, userData: int) =
    prof "buildFlameDeferred"
    if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
      return
    let n = b.frame.nodes[nodeIdx].addr
    let style = b.nodeStyle(n)
    let contentSize = vec2(
      max(0.0'f32, n.size.x - style.paddingX * 2.0'f32),
      max(0.0'f32, n.size.y - style.paddingY * 2.0'f32),
    )
    if contentSize.x <= 0 or contentSize.y <= 0:
      return

    let nowTicks = lastEventTimestamp("frame", gprof.frameIndex)
    let now = nowTicks.float64 / NS_PER_US.float64
    let width = contentSize.x
    let xOffset: float32 = width - 25.0'f32

    proc toMs(ticks: uint64): float64 =
      ticks.float64 / NS_PER_MS.float64

    proc timeStampToX(timestamp, now: float64, xOffset: float32): float32 =
      let offset = -(now - timestamp)
      return offset.float32 * gprof.scaleX + xOffset + gprof.scrollX

    proc pixelToTimestamp(x, now: float64, xOffset: float32): float64 =
      let offset = (x - xOffset.float64 - gprof.scrollX.float64) / gprof.scaleX.float64
      return now + offset

    # --- interaction (zoom / pan) using the previous frame's node position ---------
    let nodeId = n.id
    let prevIdx = b.previousNodeIndex(nodeId, nodeIdx)
    let nodeAbs = if prevIdx >= 0:
      b.absoluteNodePosPrev(nodeId, nodeIdx)
    else:
      b.absoluteNodePos(nodeIdx)
    let mouseLocal = b.frameCtx.input.mouse - (nodeAbs + vec2(style.paddingX, style.paddingY))
    if b.previousOutput.scrolledId == b.currentNode.id:
      let input = b.frameCtx.input
      if ModAlt in input.modsDown:
        gprof.scrollX += input.wheel.y * 20.0'f32
      else:
        let mts = pixelToTimestamp(mouseLocal.x.float64, now, xOffset)
        gprof.scaleX *= (1.0'f32 + input.wheel.y * 0.1'f32)
        if gprof.scaleX < 0.001'f32:
          gprof.scaleX = 0.001'f32
        if gprof.scaleX > 1000.0'f32:
          gprof.scaleX = 1000.0'f32
        let newX = timeStampToX(mts, now, xOffset)
        gprof.scrollX += mouseLocal.x - newX

    # --- gather visible frames -------------------------------------------------------
    type RectInfo = tuple
      depth: int
      x1, y1, x2, y2: float32
      color: UiColor
      tag: string
      ms: float64

    var rects: seq[RectInfo] = @[]
    var maxDepth = 0

    for (pIndex, depth, frame) in profileFrames():
      let y1 = depth.float32 * FlameRowHeight
      let y2 = (depth.float32 + 1.0'f32) * FlameRowHeight
      let x1 = timeStampToX(frame.first.float64 / NS_PER_US.float64, now, xOffset)
      let x2 = timeStampToX(frame.last.float64 / NS_PER_US.float64, now, xOffset)
      if x1 >= width:
        continue
      maxDepth = max(maxDepth, depth)
      let color = hsvToRgba(depth.float32 * 0.1'f32, 0.8'f32, 0.8'f32)
      if (depth == 0 and x2 < 0) or rects.len > 50000:
        rects.add((
          depth,
          x1, y1, x2, y2,
          color,
          frame.location.tag,
          toMs(frame.last - frame.first),
        ))
        break
      if x2 < 0:
        continue
      if x2 - x1 < 2:
        continue
      rects.add((
        depth,
        x1, y1, x2, y2,
        color,
        frame.location.tag,
        toMs(frame.last - frame.first),
      ))

    # --- emit custom render commands for the flame graph --------------------------
    let cap = max(1, rects.len * 2)
    var commands = b.frame.arena[].allocEmptyArray(cap, UiRenderCommand)
    let record = gprof.record
    gprof.record = false
    for r in rects:
      let x = min(r.x1, r.x2)
      let w = abs(r.x2 - r.x1)
      let h = r.y2 - r.y1
      let (vertexData, vertexCount) = buildRectFillVertices(b.frame.arena, nodeAbs + vec2(x, r.y1), vec2(w, h), r.color, 0)
      if vertexData != nil and vertexCount > 0:
        commands.add UiRenderCommand(
          kind: CmdRawVertices,
          nodeIndex: nodeIdx.int32,
          vertexData: vertexData,
          vertexCount: vertexCount.int32,
        )

      block:
        let (vertexData, vertexCount) = buildRectStrokeVertices(b.frame.arena, nodeAbs + vec2(x, r.y1), vec2(w, h), b.themeStyle(UiStyleIndexStage)[].borderColor, 0, 1)
        if vertexData != nil and vertexCount > 0:
          commands.add UiRenderCommand(
            kind: CmdRawVertices,
            nodeIndex: nodeIdx.int32,
            vertexData: vertexData,
            vertexCount: vertexCount.int32,
          )

    discard b.customRenderCommands(commands)

    # --- overlay a text label for rects wide enough to fit one ----------------------
    for r in rects:
      let w = abs(r.x2 - r.x1)
      if w <= 10.0'f32:
        continue
      let label = r.tag
      b.node:
        discard b.anchors(r.x1 / width, r.y1 / contentSize.y, r.x2 / width, r.y2 / contentSize.y)
        discard b.offsets(vec2(2.0'f32, 2.0'f32), vec2(-2.0'f32, -2.0'f32))
        discard b.finishAnchors()
        discard b.noChildHover().maskChildren()
        discard b.textColor(rgba(0.0'f32, 0.0'f32, 0.0'f32, 1.0'f32)).fontSize(12).padding(1)
        discard b.text(label)
        if b.wasRightClicked(b.currentNode):
          let i = gprof.plottedStats.find(r.tag)
          if i != -1:
            gprof.plottedStats.del(i)
          else:
            gprof.plottedStats.add(r.tag)
          profPlottedStatsCsv = gprof.plottedStats.join(",")
        if b.wasHovered(b.currentNode):
          b.tooltip:
            discard b.fit().padding(4)
            discard b.backgroundColor(b.themeStyle(UiStyleIndexTooltip)[].fillColor).borderWidth(1).borderColor(b.themeStyle(UiStyleIndexTooltip)[].borderColor)
            b.label(r.tag & " " & $(r.ms) & "ms")

    gprof.record = record

  proc buildPlotDeferred(b: var UiBuilder, nodeIdx: int, userData: int) =
    prof "buildPlotDeferred"
    if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
      return
    let node = b.frame.nodes[nodeIdx].addr
    let style = b.nodeStyle(node)
    let contentSize = vec2(
      max(0.0'f32, node.size.x - style.paddingX * 2.0'f32),
      max(0.0'f32, node.size.y - style.paddingY * 2.0'f32),
    )
    if contentSize.x <= 0 or contentSize.y <= 0:
      return

    if gprof.stopOnShow and b.previousNodeIndex(b.currentNode.id, nodeIdx) == -1:
      gprof.record = false

    if gprof.plottedStats.len == 0:
      gprof.plottedStats = @["frame", "tick"]
    if gprof.timeHistory.len != gprof.plottedStats.len:
      gprof.timeHistory.setLen(gprof.plottedStats.len)

    let n = gprof.timeHistory[0].len
    let fi = frameTimeIndex

    let lineColors = [
      rgba(0.95'f32, 0.85'f32, 0.20'f32, 1.0'f32),
      rgba(0.20'f32, 0.85'f32, 0.30'f32, 1.0'f32),
      rgba(0.35'f32, 0.55'f32, 0.95'f32, 1.0'f32),
      rgba(0.90'f32, 0.35'f32, 0.35'f32, 1.0'f32),
    ]
    let fillColors = [
      rgba(0.95'f32, 0.85'f32, 0.20'f32, 0.25'f32),
      rgba(0.20'f32, 0.85'f32, 0.30'f32, 0.25'f32),
      rgba(0.35'f32, 0.55'f32, 0.95'f32, 0.25'f32),
      rgba(0.90'f32, 0.35'f32, 0.35'f32, 0.25'f32),
    ]

    let nodeAbs = b.absoluteNodePos(nodeIdx)
    let statCount = min(gprof.plottedStats.len, MaxPlotStats)
    profPlotSampleCount = n

    # fill one sample buffer per plotted stat (newest sample at the right edge)
    for s in 0 ..< statCount:
      for i in 0 ..< n:
        let sampleIdx = (fi - i + n) mod n
        profPlotSampleData[s][profPlotSampleData[s].len - i - 1] = gprof.timeHistory[s][sampleIdx]

    var series: array[MaxPlotStats, PlotSeries]
    for s in 0 ..< statCount:
      series[s] = PlotSeries(
        fn: profSampleFn,
        userData: s,
        label: uiString(gprof.plottedStats[s]),
        lineColor: lineColors[s mod lineColors.len],
        fillTopColor: fillColors[s mod fillColors.len],
        fillBottomColor: rgba(0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32),
      )

    if b.previousOutput.scrolledId == b.currentNode.id:
      gprof.plotScale *= (1.0'f32 - b.frameCtx.input.wheel.y * 0.1'f32)

    let commands = buildPlotVertices(
      b,
      nodeAbs,
      contentSize,
      vec2(0.0'f32, (n - 1).float32),
      vec2(0.0'f32, gprof.plotScale),
      series.toOpenArray(0, statCount - 1),
      resolution = 500,
      lineThickness = 1.5'f32,
      mousePos = b.frameCtx.input.mouse,
    )

    discard b.customRenderCommands(commands)

proc buildNuiProfiler*(b: var UiBuilder) =
  ## Build the nuigi-based profiler UI (flame graph + per-tag time plot).
  ## Reference implementation: `drawProfiler` in `profiler.nim` (dear imgui renderer).
  when defined(profiler) and not defined(nimony):
    prof "buildNuiProfiler"
    b.layoutVertical("nuigi-profiler"):
      discard b.fillX().fitY().gap(4).padding(4)

      b.layoutHorizontal("profiler-controls-1"):
        discard b.fillX().fitY().gap(6)
        if b.checkbox("Record", gprof.record):
          discard
        if b.checkbox("Stop on hitch", gprof.stopOnThreshold):
          discard
        if b.checkbox("Stop on show", gprof.stopOnShow):
          discard
        if b.button("Reset"):
          gprof.scaleX = 0.7'f32
          gprof.scrollX = 0.0'f32
        profFrameIndexFloat = gprof.frameIndex.float32
        b.layoutHorizontal:
          discard b.fitX().fitY()
          b.label("Frame")
          if b.dragFloat(profFrameIndexFloat, 0.5'f32, 0.0'f32, 50.0'f32):
            gprof.frameIndex = profFrameIndexFloat.int32
        b.layoutHorizontal:
          discard b.fitX().fitY()
          b.label("Scale")
          if b.dragFloat(gprof.scaleX, 1, 0.0'f32, 1000.0'f32):
            discard

      b.layoutHorizontal("profiler-controls-2"):
        discard b.fillX().fitY().gap(6)
        b.layoutHorizontal:
          discard b.fitX().fitY()
          b.label("Plot Scale")
          if b.dragFloat(gprof.plotScale, 0.5'f32, 1.0'f32, 32.0'f32):
            discard
        if profPlottedStatsCsv.len == 0:
          profPlottedStatsCsv = gprof.plottedStats.join(",")
        if b.textField(profPlottedStatsCsv, "comma-separated tags, e.g. frame, tickGame, drawEntities"):
          let parsed = parsePlottedStatsCsv(profPlottedStatsCsv)
          if parsed.len > 0:
            gprof.plottedStats = parsed

      b.node("profiler-plot"):
        discard b.fillX().height(300.0'f32).maskChildren().scrollable()
        discard b.backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
        discard b.deferBuild(buildPlotDeferred)

      b.node("profiler-flame"):
        # discard b.fill().maskChildren()
        discard b.fillX().height(500.0'f32).maskChildren().scrollable()
        discard b.backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
        discard b.deferBuild(buildFlameDeferred)
