import std/strutils
import mymath
import arena, array_view, profiler, nui, nui_mesh

type
  PlotPointFn* = proc (x: float32, userData: int): float32

  PlotSeries* = object
    fn*: PlotPointFn
    userData*: int
    label*: UiString
    lineColor*: UiColor
    fillTopColor*: UiColor
    fillBottomColor*: UiColor

proc buildPlotVertices*(b: var UiBuilder, pos, size: Vec2,
    xRange, yRange: Vec2, series: openArray[PlotSeries],
    resolution: int = 256, lineThickness: float32 = 2.0'f32,
    mousePos: Vec2 = vec2(-1.0'f32, -1.0'f32)
  ): ArrayView[UiRenderCommand] =
  if b.frame.arena == nil or series.len == 0 or resolution < 2:
    return default(ArrayView[UiRenderCommand])
  prof("buildPlotVertices")

  let circleSegs = 16
  let circleRadius = 4.0'f32
  let mouseLineVtx = 6
  let circleVtxPerSeries = circleSegs * 3
  let useMouse = mousePos.x >= pos.x and mousePos.x <= pos.x + size.x
  let overlayVtx = if useMouse:
    mouseLineVtx + series.len * circleVtxPerSeries
  else:
    0

  let segCount = resolution - 1
  let perSeries = segCount * 6 * 2
  let total = perSeries * series.len + overlayVtx
  let data = cast[nil ptr UncheckedArray[UiVertex]](b.frame.arena[].alloc(total * sizeof(UiVertex)))
  if data == nil:
    return default(ArrayView[UiRenderCommand])

  let invX = 1.0'f32 / max(1e-6'f32, xRange.y - xRange.x)
  let invY = 1.0'f32 / max(1e-6'f32, yRange.y - yRange.x)
  let baseY = pos.y + size.y

  let points = cast[ptr UncheckedArray[Vec2]](b.frame.arena[].alloc(series.len * resolution * sizeof(Vec2)))
  if points == nil:
    return default(ArrayView[UiRenderCommand])
  for s in 0 ..< series.len:
    let fn = series[s].fn
    let ud = series[s].userData
    for i in 0 ..< resolution:
      let t = i.float32 / segCount.float32
      let dataX = xRange.x + t * (xRange.y - xRange.x)
      let dataY = fn(dataX, ud)
      let sx = pos.x + (dataX - xRange.x) * invX * size.x
      let sy = pos.y + size.y - (dataY - yRange.x) * invY * size.y
      points[s * resolution + i] = vec2(sx, sy)

  var vertexIndex = 0

  for s in 0 ..< series.len:
    let top = series[s].fillTopColor
    let bottom = series[s].fillBottomColor
    for i in 0 ..< segCount:
      let a = points[s * resolution + i]
      let bpt = points[s * resolution + i + 1]
      let aBase = vec2(a.x, baseY)
      let bBase = vec2(bpt.x, baseY)
      data[vertexIndex] = UiVertex(pos: a, color: top); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: bpt, color: top); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: bBase, color: bottom); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: a, color: top); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: bBase, color: bottom); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: aBase, color: bottom); inc vertexIndex

  let half = lineThickness * 0.5'f32
  for s in 0 ..< series.len:
    let col = series[s].lineColor
    for i in 0 ..< segCount:
      let a = points[s * resolution + i]
      let bpt = points[s * resolution + i + 1]
      var dir = bpt - a
      let len = dir.length
      if len <= 0.0'f32:
        continue
      let n = vec2(-dir.y, dir.x) * (half / len)
      let a0 = a + n
      let a1 = a - n
      let b0 = bpt + n
      let b1 = bpt - n
      data[vertexIndex] = UiVertex(pos: a0, color: col); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: b0, color: col); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: b1, color: col); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: a0, color: col); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: b1, color: col); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: a1, color: col); inc vertexIndex

  let cmdCount = 1 + (if useMouse: series.len else: 0)
  var commands = b.frame.arena[].allocEmptyArray(max(1, cmdCount), UiRenderCommand)

  if useMouse:
    let x0 = mousePos.x - 0.5'f32
    let x1 = mousePos.x + 0.5'f32
    let y0 = pos.y
    let y1 = pos.y + size.y
    let lineCol = UiColor(r: 0.7'f32, g: 0.7'f32, b: 0.7'f32, a: 0.8'f32)
    data[vertexIndex] = UiVertex(pos: vec2(x0, y0), color: lineCol); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: vec2(x1, y0), color: lineCol); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: vec2(x1, y1), color: lineCol); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: vec2(x0, y0), color: lineCol); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: vec2(x1, y1), color: lineCol); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: vec2(x0, y1), color: lineCol); inc vertexIndex

    let plotNodeIdx = b.currentNodeIndex()
    let plotNode = b.frame.nodes[plotNodeIdx].addr
    let plotStyle = b.nodeStyle(plotNode)
    let plotTopLeft = b.absoluteNodePos(plotNodeIdx)
    let plotContentOrigin = plotTopLeft + vec2(plotStyle.paddingX, plotStyle.paddingY)

    for s in 0 ..< series.len:
      let fnm = series[s].fn
      let udm = series[s].userData
      let dataXm = xRange.x + (mousePos.x - pos.x) / size.x * (xRange.y - xRange.x)
      let avgRadius = 10
      var dataYm = 0.0'f32
      var sampleCnt = 0
      for d in -avgRadius .. avgRadius:
        let sx = dataXm + d.float32 / size.x * (xRange.y - xRange.x)
        if sx >= xRange.x and sx <= xRange.y:
          dataYm += fnm(sx, udm)
          inc sampleCnt
      if sampleCnt > 0:
        dataYm /= sampleCnt.float32
      let cy = pos.y + size.y - (dataYm - yRange.x) * invY * size.y
      let c = series[s].lineColor
      for k in 0 ..< circleSegs:
        let a0 = (3.14159265'f32 * 2.0'f32) * (k.float32 / circleSegs.float32)
        let a1 = (3.14159265'f32 * 2.0'f32) * ((k + 1).float32 / circleSegs.float32)
        let p0 = vec2(mousePos.x + cos(a0).float32 * circleRadius, cy + sin(a0).float32 * circleRadius)
        let p1 = vec2(mousePos.x + cos(a1).float32 * circleRadius, cy + sin(a1).float32 * circleRadius)
        data[vertexIndex] = UiVertex(pos: vec2(mousePos.x, cy), color: c); inc vertexIndex
        data[vertexIndex] = UiVertex(pos: p0, color: c); inc vertexIndex
        data[vertexIndex] = UiVertex(pos: p1, color: c); inc vertexIndex

      let labelText = if series[s].label.value.len > 0:
        series[s].label.value & ": " & formatFloat(dataYm, ffDecimal, 2)
      else:
        formatFloat(dataYm, ffDecimal, 2)
      b.frame.texts.add(UiNodeText(
        text: uiString(labelText),
        fontSize: 12.0'f32,
        fontId: b.defaultText.fontId,
        textColor: c,
        measuredTextDirty: true,
      ))
      let textIdx = b.frame.texts.len.uint16
      let textPos = vec2(mousePos.x, cy) - plotContentOrigin + vec2(circleRadius + 4.0'f32, -20.0'f32)
      commands.add UiRenderCommand(
        kind: CmdText,
        pos: textPos,
        textIndex: textIdx,
      )

  commands.add UiRenderCommand(
    kind: CmdRawVertices,
    vertexData: data,
    vertexCount: vertexIndex.int32,
  )

  commands
