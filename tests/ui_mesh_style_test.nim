import nuigi, mesh, mymath, arena, array_view, plot

when defined(nimony):
  import std/assertions

proc require(cond: bool, msg: string) =
  when defined(nimony):
    assert cond, msg
  else:
    doAssert(cond, msg)

proc sameColor(a, b: UiColor): bool =
  a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a

proc fixedMeasureText(text: openArray[char], fontId: int16, fontSize: float32,
    maxWidth: float32): UiTextArrangement {.gcsafe, raises: [].} =
  discard text
  discard fontId
  discard maxWidth
  UiTextArrangement(fontSize: fontSize)

proc flatPlotValue(x: float32, userData: int): float32 =
  discard x
  discard userData
  0.5'f32

proc testPerCornerFillGeometry() =
  var meshArena = initArena(64 * 1024)
  let mesh = buildRectFillVertices(meshArena.addr, vec2(0.0'f32), vec2(100.0'f32, 80.0'f32),
    rgba(1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32),
    UiCornerRadii(topLeft: 2.0'f32, topRight: 4.0'f32,
      bottomRight: 6.0'f32, bottomLeft: 8.0'f32))
  require(mesh.count == 72,
    "per-corner fill should segment each corner according to its own radius")
  for i in 0 ..< mesh.count:
    require(mesh.data[i].pos.x >= 0.0'f32 and mesh.data[i].pos.x <= 100.0'f32,
      "fill vertex should remain within horizontal bounds")
    require(mesh.data[i].pos.y >= 0.0'f32 and mesh.data[i].pos.y <= 80.0'f32,
      "fill vertex should remain within vertical bounds")

proc testPerSideBorderGeometryAndColors() =
  var meshArena = initArena(64 * 1024)
  let leftColor = rgba(1.0'f32, 0.0'f32, 0.0'f32, 1.0'f32)
  let topColor = rgba(0.0'f32, 1.0'f32, 0.0'f32, 1.0'f32)
  let rightColor = rgba(0.0'f32, 0.0'f32, 1.0'f32, 1.0'f32)
  let bottomColor = rgba(1.0'f32, 1.0'f32, 0.0'f32, 1.0'f32)
  let mesh = buildRectStrokeVertices(meshArena.addr, vec2(0.0'f32), vec2(100.0'f32, 80.0'f32),
    UiBorderColors(left: leftColor, top: topColor, right: rightColor, bottom: bottomColor),
    UiCornerRadii(),
    UiBorderWidths(left: 2.0'f32, top: 3.0'f32, right: 4.0'f32, bottom: 5.0'f32))
  require(mesh.count == 48, "square per-side border should emit eight boundary quads")

  var foundLeft = false
  var foundTop = false
  var foundRight = false
  var foundBottom = false
  var foundInnerTopLeft = false
  for i in 0 ..< mesh.count:
    let vertex = mesh.data[i]
    foundLeft = foundLeft or vertex.color.sameColor(leftColor)
    foundTop = foundTop or vertex.color.sameColor(topColor)
    foundRight = foundRight or vertex.color.sameColor(rightColor)
    foundBottom = foundBottom or vertex.color.sameColor(bottomColor)
    foundInnerTopLeft = foundInnerTopLeft or vertex.pos == vec2(2.0'f32, 3.0'f32)
  require(foundLeft and foundTop and foundRight and foundBottom,
    "border mesh should contain every side color")
  require(foundInnerTopLeft,
    "border inner boundary should use independent left and top widths")

proc testUniformStyleFallbacks() =
  let style = UiStyle(
    borderWidth: 3.0'f32,
    cornerRadius: 7.0'f32,
    borderColor: rgba(0.2'f32, 0.3'f32, 0.4'f32, 1.0'f32),
  )
  require(style.resolvedCornerRadii.topRight == 7.0'f32,
    "uniform corner radius should remain the default")
  require(style.resolvedBorderWidths.bottom == 3.0'f32,
    "uniform border width should remain the default")
  require(style.resolvedBorderColors.left.sameColor(style.borderColor),
    "uniform border color should remain the default")

proc testAntialiasedFillGeometry() =
  var meshArena = initArena(64 * 1024)
  let color = rgba(0.2'f32, 0.4'f32, 0.6'f32, 1.0'f32)
  let plain = buildRectFillVertices(meshArena.addr, vec2(10.0'f32),
    vec2(100.0'f32, 80.0'f32), color, 0.0'f32)
  require(plain.count == 6, "disabled fill antialiasing should retain the fast-path geometry")

  let antialiased = buildRectFillVertices(meshArena.addr, vec2(10.0'f32),
    vec2(100.0'f32, 80.0'f32), color, 0.0'f32, antialiasMeshWidth = 2.0'f32)
  require(antialiased.count > plain.count,
    "enabled fill antialiasing should append gradient fringe geometry")
  var foundTransparentOuterVertex = false
  var foundOpaqueInnerVertex = false
  for i in 0 ..< antialiased.count:
    let vertex = antialiased.data[i]
    if vertex.color.a == 0.0'f32 and
        (vertex.pos.x < 10.0'f32 or vertex.pos.x > 110.0'f32 or
         vertex.pos.y < 10.0'f32 or vertex.pos.y > 90.0'f32):
      foundTransparentOuterVertex = foundTransparentOuterVertex or
        vertex.pos.x == 9.0'f32 or vertex.pos.x == 111.0'f32 or
        vertex.pos.y == 9.0'f32 or vertex.pos.y == 91.0'f32
    if vertex.color.a == 1.0'f32:
      foundOpaqueInnerVertex = foundOpaqueInnerVertex or
        vertex.pos.x == 11.0'f32 or vertex.pos.x == 109.0'f32 or
        vertex.pos.y == 11.0'f32 or vertex.pos.y == 89.0'f32
  require(foundTransparentOuterVertex,
    "fill antialiasing should fade to transparent half a fringe outside the edge")
  require(foundOpaqueInnerVertex,
    "fill antialiasing should become opaque half a fringe inside the edge")

proc testAntialiasedBorderGeometry() =
  var meshArena = initArena(64 * 1024)
  let color = rgba(0.7'f32, 0.5'f32, 0.3'f32, 1.0'f32)
  let plain = buildRectStrokeVertices(meshArena.addr, vec2(10.0'f32),
    vec2(100.0'f32, 80.0'f32), color, 0.0'f32, 4.0'f32)
  let antialiased = buildRectStrokeVertices(meshArena.addr, vec2(10.0'f32),
    vec2(100.0'f32, 80.0'f32), color, 0.0'f32, 4.0'f32,
    antialiasMeshWidth = 2.0'f32)
  require(plain.count == 24,
    "disabled border antialiasing should retain the fast-path geometry")
  require(antialiased.count > plain.count,
    "enabled border antialiasing should append gradient fringe geometry")
  var foundOuterFringe = false
  var foundInnerFringe = false
  var foundOuterSolidEdge = false
  var foundInnerSolidEdge = false
  for i in 0 ..< antialiased.count:
    let vertex = antialiased.data[i]
    if vertex.color.a == 0.0'f32:
      foundOuterFringe = foundOuterFringe or
        vertex.pos.x == 9.0'f32 or vertex.pos.x == 111.0'f32 or
        vertex.pos.y == 9.0'f32 or vertex.pos.y == 91.0'f32
      foundInnerFringe = foundInnerFringe or
        vertex.pos.x == 15.0'f32 or vertex.pos.x == 105.0'f32 or
        vertex.pos.y == 15.0'f32 or vertex.pos.y == 85.0'f32
    else:
      foundOuterSolidEdge = foundOuterSolidEdge or
        vertex.pos.x == 11.0'f32 or vertex.pos.x == 109.0'f32 or
        vertex.pos.y == 11.0'f32 or vertex.pos.y == 89.0'f32
      foundInnerSolidEdge = foundInnerSolidEdge or
        vertex.pos.x == 13.0'f32 or vertex.pos.x == 107.0'f32 or
        vertex.pos.y == 13.0'f32 or vertex.pos.y == 87.0'f32
  require(foundOuterFringe and foundOuterSolidEdge,
    "outer border antialiasing should be centered on the edge")
  require(foundInnerFringe and foundInnerSolidEdge,
    "inner border antialiasing should be centered on the edge")

proc testAntialiasedChevronGeometry() =
  var meshArena = initArena(64 * 1024)
  let color = rgba(0.3'f32, 0.6'f32, 0.9'f32, 1.0'f32)
  let plain = buildChevronVertices(meshArena.addr, vec2(10.0'f32),
    vec2(20.0'f32), vec2(1.0'f32, 0.0'f32), color)
  let antialiased = buildChevronVertices(meshArena.addr, vec2(10.0'f32),
    vec2(20.0'f32), vec2(1.0'f32, 0.0'f32), color,
    antialiasMeshWidth = 2.0'f32)
  require(plain.count == 12,
    "disabled chevron antialiasing should retain the compact geometry")
  require(antialiased.count == 48,
    "enabled chevron antialiasing should append one gradient quad per edge")
  var maxOpaqueX = -Inf.float32
  var maxTransparentX = -Inf.float32
  for vertexIndex in 0 ..< antialiased.count:
    let vertex = antialiased.data[vertexIndex]
    if vertex.color.a == 0.0'f32:
      maxTransparentX = max(maxTransparentX, vertex.pos.x)
    else:
      maxOpaqueX = max(maxOpaqueX, vertex.pos.x)
  require(maxTransparentX > maxOpaqueX,
    "chevron gradient should fade from its inset solid edge to an exterior edge")

proc testAntialiasedPlotGeometry() =
  let plotSeries = [PlotSeries(
    fn: flatPlotValue,
    lineColor: rgba(0.3'f32, 0.6'f32, 0.9'f32, 1.0'f32),
  )]
  var plainBuilder = newBuilder(fixedMeasureText)
  discard plainBuilder.beginUiFrame(100.0'f32, 100.0'f32)
  let plainCommands = plainBuilder.buildPlotVertices(vec2(0.0'f32), vec2(100.0'f32),
    vec2(0.0'f32, 1.0'f32), vec2(0.0'f32, 1.0'f32), plotSeries,
    resolution = 2, lineThickness = 4.0'f32)
  var antialiasedBuilder = newBuilder(fixedMeasureText, antialiasMeshWidth = 2.0'f32)
  discard antialiasedBuilder.beginUiFrame(100.0'f32, 100.0'f32)
  let antialiasedCommands = antialiasedBuilder.buildPlotVertices(vec2(0.0'f32), vec2(100.0'f32),
    vec2(0.0'f32, 1.0'f32), vec2(0.0'f32, 1.0'f32), plotSeries,
    resolution = 2, lineThickness = 4.0'f32)
  require(plainCommands.high == 0 and antialiasedCommands.high == 0,
    "plot geometry should emit one raw vertex command without a mouse overlay")
  require(plainCommands[0].vertexCount == 12 and antialiasedCommands[0].vertexCount == 24,
    "plot antialiasing should add two gradient strips per line segment")
  var minOpaqueY = Inf.float32
  var minTransparentY = Inf.float32
  for vertexIndex in 0 ..< antialiasedCommands[0].vertexCount:
    let vertex = antialiasedCommands[0].vertexData[vertexIndex]
    if vertex.color.a == 0.0'f32:
      minTransparentY = min(minTransparentY, vertex.pos.y)
    elif vertex.color.a == 1.0'f32:
      minOpaqueY = min(minOpaqueY, vertex.pos.y)
  require(minTransparentY < minOpaqueY,
    "plot line gradient should fade from its inset solid edge to an exterior edge")

when isMainModule:
  testPerCornerFillGeometry()
  testPerSideBorderGeometryAndColors()
  testUniformStyleFallbacks()
  testAntialiasedFillGeometry()
  testAntialiasedBorderGeometry()
  testAntialiasedChevronGeometry()
  testAntialiasedPlotGeometry()