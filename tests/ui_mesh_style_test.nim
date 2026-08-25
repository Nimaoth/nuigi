import nuigi, mesh, mymath, arena

when defined(nimony):
  import std/assertions

proc require(cond: bool, msg: string) =
  when defined(nimony):
    assert cond, msg
  else:
    doAssert(cond, msg)

proc sameColor(a, b: UiColor): bool =
  a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a

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

when isMainModule:
  testPerCornerFillGeometry()
  testPerSideBorderGeometryAndColors()
  testUniformStyleFallbacks()