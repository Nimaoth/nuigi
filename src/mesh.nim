import mymath
import arena, profiler

type
  UiColor* = object
    r*, g*, b*, a*: float32

  UiCornerRadii* = object
    topLeft*, topRight*, bottomRight*, bottomLeft*: float32

  UiBorderWidths* = object
    left*, top*, right*, bottom*: float32

  UiBorderColors* = object
    left*, top*, right*, bottom*: UiColor

  UiVertex* = object
    pos*: Vec2
    uv*: Vec2
    color*: UiColor

func uniformCornerRadii*(radius: float32): UiCornerRadii {.inline.} =
  UiCornerRadii(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)

func uniformBorderWidths*(width: float32): UiBorderWidths {.inline.} =
  UiBorderWidths(left: width, top: width, right: width, bottom: width)

func uniformBorderColors*(color: UiColor): UiBorderColors {.inline.} =
  UiBorderColors(left: color, top: color, right: color, bottom: color)

type
  UiAffine2* = object
    m00*, m01*: float32
    m10*, m11*: float32
    tx*, ty*: float32

func identityAffine2*(): UiAffine2 {.inline.} =
  UiAffine2(m00: 1.0'f32, m01: 0.0'f32, m10: 0.0'f32, m11: 1.0'f32, tx: 0.0'f32, ty: 0.0'f32)

func isIdentity*(transform: UiAffine2, epsilon: float32 = 1e-5'f32): bool {.inline.} =
  abs(transform.m00 - 1.0'f32) <= epsilon and
  abs(transform.m01) <= epsilon and
  abs(transform.m10) <= epsilon and
  abs(transform.m11 - 1.0'f32) <= epsilon and
  abs(transform.tx) <= epsilon and
  abs(transform.ty) <= epsilon

func translateAffine2*(offset: Vec2): UiAffine2 {.inline.} =
  UiAffine2(m00: 1.0'f32, m01: 0.0'f32, m10: 0.0'f32, m11: 1.0'f32, tx: offset.x, ty: offset.y)

func rotateScaleAffine2*(rotation: float32, scale: Vec2): UiAffine2 {.inline.} =
  let c = cos(rotation.float64).float32
  let s = sin(rotation.float64).float32
  UiAffine2(
    m00: c * scale.x,
    m01: -s * scale.y,
    m10: s * scale.x,
    m11: c * scale.y,
    tx: 0.0'f32,
    ty: 0.0'f32,
  )

func mulAffine2*(a, b: UiAffine2): UiAffine2 {.inline.} =
  UiAffine2(
    m00: a.m00 * b.m00 + a.m01 * b.m10,
    m01: a.m00 * b.m01 + a.m01 * b.m11,
    m10: a.m10 * b.m00 + a.m11 * b.m10,
    m11: a.m10 * b.m01 + a.m11 * b.m11,
    tx: a.m00 * b.tx + a.m01 * b.ty + a.tx,
    ty: a.m10 * b.tx + a.m11 * b.ty + a.ty,
  )

func transformPoint2*(transform: UiAffine2, p: Vec2): Vec2 {.inline.} =
  vec2(
    transform.m00 * p.x + transform.m01 * p.y + transform.tx,
    transform.m10 * p.x + transform.m11 * p.y + transform.ty,
  )

func `*`*(transform: UiAffine2, p: Vec2): Vec2 {.inline.} =
  vec2(
    transform.m00 * p.x + transform.m01 * p.y + transform.tx,
    transform.m10 * p.x + transform.m11 * p.y + transform.ty,
  )

func inverseAffine2*(transform: UiAffine2): UiAffine2 {.inline.} =
  let det = transform.m00 * transform.m11 - transform.m01 * transform.m10
  if det == 0.0'f32:
    return identityAffine2()
  let invDet = 1.0'f32 / det
  let i00 = transform.m11 * invDet
  let i01 = -transform.m01 * invDet
  let i10 = -transform.m10 * invDet
  let i11 = transform.m00 * invDet
  UiAffine2(
    m00: i00,
    m01: i01,
    m10: i10,
    m11: i11,
    tx: -(i00 * transform.tx + i01 * transform.ty),
    ty: -(i10 * transform.tx + i11 * transform.ty),
  )

func linearScaleMagnitude*(transform: UiAffine2): float32 {.inline.} =
  let sx = sqrt((transform.m00 * transform.m00 + transform.m10 * transform.m10).float64).float32
  let sy = sqrt((transform.m01 * transform.m01 + transform.m11 * transform.m11).float64).float32
  max(0.0'f32, (sx + sy) * 0.5'f32)

func applyNodeRenderTransform*(parentTransform: UiAffine2, pivot, offset: Vec2, rotation: float32, scale: Vec2): UiAffine2 {.inline.} =
  let toLocal = translateAffine2(vec2(-pivot.x, -pivot.y))
  let rotateScale = rotateScaleAffine2(rotation, scale)
  let fromLocal = translateAffine2(pivot + offset)
  mulAffine2(parentTransform, mulAffine2(fromLocal, mulAffine2(rotateScale, toLocal)))

proc transformedRectAabb*(transform: UiAffine2, pos, size: Vec2): tuple[pos: Vec2, size: Vec2] =
  let quad = [
    transform.transformPoint2(pos),
    transform.transformPoint2(pos + vec2(size.x, 0.0'f32)),
    transform.transformPoint2(pos + size),
    transform.transformPoint2(pos + vec2(0.0'f32, size.y)),
  ]
  let minX = min(min(quad[0].x, quad[1].x), min(quad[2].x, quad[3].x))
  let minY = min(min(quad[0].y, quad[1].y), min(quad[2].y, quad[3].y))
  let maxX = max(max(quad[0].x, quad[1].x), max(quad[2].x, quad[3].x))
  let maxY = max(max(quad[0].y, quad[1].y), max(quad[2].y, quad[3].y))
  (vec2(minX, minY), vec2(max(0.0'f32, maxX - minX), max(0.0'f32, maxY - minY)))

func normalizedCornerRadii(radii: UiCornerRadii, size: Vec2): UiCornerRadii =
  result = UiCornerRadii(
    topLeft: max(0.0'f32, radii.topLeft),
    topRight: max(0.0'f32, radii.topRight),
    bottomRight: max(0.0'f32, radii.bottomRight),
    bottomLeft: max(0.0'f32, radii.bottomLeft),
  )
  var scale = 1.0'f32
  template limit(sum, available: float32) =
    if sum > 0.0'f32:
      scale = min(scale, max(0.0'f32, available) / sum)
  limit(result.topLeft + result.topRight, size.x)
  limit(result.bottomLeft + result.bottomRight, size.x)
  limit(result.topLeft + result.bottomLeft, size.y)
  limit(result.topRight + result.bottomRight, size.y)
  if scale < 1.0'f32:
    result.topLeft *= scale
    result.topRight *= scale
    result.bottomRight *= scale
    result.bottomLeft *= scale

func mixColor(a, b: UiColor, t: float32): UiColor {.inline.} =
  UiColor(
    r: a.r + (b.r - a.r) * t,
    g: a.g + (b.g - a.g) * t,
    b: a.b + (b.b - a.b) * t,
    a: a.a + (b.a - a.a) * t,
  )

proc cornerSegments(radius: float32): int {.inline.} =
  if radius > 0.0'f32: clamp(radius.int, 1, 50) else: 1

proc writeRoundedBoundary(points: ptr UncheckedArray[Vec2], colors: nil ptr UncheckedArray[UiColor],
    pos, size: Vec2, radii: UiCornerRadii, segments: array[4, int],
    sideColors: UiBorderColors) =
  let x = pos.x
  let y = pos.y
  let w = size.x
  let h = size.y
  let cornerRadii = [radii.topRight, radii.bottomRight, radii.bottomLeft, radii.topLeft]
  let centers = [
    vec2(x + w - radii.topRight, y + radii.topRight),
    vec2(x + w - radii.bottomRight, y + h - radii.bottomRight),
    vec2(x + radii.bottomLeft, y + h - radii.bottomLeft),
    vec2(x + radii.topLeft, y + radii.topLeft),
  ]
  let startAngles = [-PI * 0.5'f32, 0.0'f32, PI * 0.5'f32, PI]
  let startColors = [sideColors.top, sideColors.right, sideColors.bottom, sideColors.left]
  let endColors = [sideColors.right, sideColors.bottom, sideColors.left, sideColors.top]
  var pointIndex = 0
  for corner in 0 ..< 4:
    let segmentCount = segments[corner]
    let radius = cornerRadii[corner]
    for segment in 0 .. segmentCount:
      let t = segment.float32 / segmentCount.float32
      let angle = startAngles[corner] + PI * 0.5'f32 * t
      points[pointIndex] = centers[corner] + vec2(cos(angle), sin(angle)) * radius
      if colors != nil:
        colors[pointIndex] = mixColor(startColors[corner], endColors[corner], t)
      inc pointIndex

proc buildRectFillVertices*(arena: ptr Arena, pos, size: Vec2, color: UiColor,
  radii: UiCornerRadii, antialiasMeshWidth = 0.0'f32): tuple[data: nil ptr UncheckedArray[UiVertex], count: int] =
  ## Generate a filled rectangle with independently rounded corners.
  if arena == nil:
    return (nil, 0)
  prof("buildRectFillVertices")
  let rectSize = vec2(max(0.0'f32, size.x), max(0.0'f32, size.y))
  if rectSize.x <= 0.0'f32 or rectSize.y <= 0.0'f32:
    return (nil, 0)

  let normalized = normalizedCornerRadii(radii, rectSize)
  let aaWidth = max(0.0'f32, antialiasMeshWidth)
  let aaHalfWidth = aaWidth * 0.5'f32
  let segments = [
    cornerSegments(normalized.topRight),
    cornerSegments(normalized.bottomRight),
    cornerSegments(normalized.bottomLeft),
    cornerSegments(normalized.topLeft),
  ]
  let boundaryCount = segments[0] + segments[1] + segments[2] + segments[3] + 4
  let aaRing = aaWidth > 0.0'f32
  let vertexCount = boundaryCount * 3 + (if aaRing: boundaryCount * 6 else: 0)
  let data = cast[nil ptr UncheckedArray[UiVertex]](arena[].alloc(vertexCount * sizeof(UiVertex)))
  let points = cast[ptr UncheckedArray[Vec2]](arena[].alloc(boundaryCount * sizeof(Vec2)))
  let outerPoints = if aaRing:
    cast[ptr UncheckedArray[Vec2]](arena[].alloc(boundaryCount * sizeof(Vec2)))
  else:
    nil
  if data == nil or points == nil or (aaRing and outerPoints == nil):
    return (nil, 0)
  let innerSize = rectSize - vec2(aaWidth)
  let innerRadii = normalizedCornerRadii(UiCornerRadii(
    topLeft: max(0.0'f32, normalized.topLeft - aaHalfWidth),
    topRight: max(0.0'f32, normalized.topRight - aaHalfWidth),
    bottomRight: max(0.0'f32, normalized.bottomRight - aaHalfWidth),
    bottomLeft: max(0.0'f32, normalized.bottomLeft - aaHalfWidth),
  ), innerSize)
  points.writeRoundedBoundary(nil, pos + vec2(aaHalfWidth), innerSize,
    innerRadii, segments, uniformBorderColors(color))
  if aaRing:
    let outerRadii = UiCornerRadii(
      topLeft: normalized.topLeft + aaHalfWidth,
      topRight: normalized.topRight + aaHalfWidth,
      bottomRight: normalized.bottomRight + aaHalfWidth,
      bottomLeft: normalized.bottomLeft + aaHalfWidth,
    )
    outerPoints.writeRoundedBoundary(nil, pos - vec2(aaHalfWidth),
      rectSize + vec2(aaWidth), outerRadii, segments,
      uniformBorderColors(color))

  let center = pos + rectSize * 0.5'f32
  var vertexIndex = 0
  for i in 0 ..< boundaryCount:
    let next = (i + 1) mod boundaryCount
    data[vertexIndex] = UiVertex(pos: center, color: color); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: points[i], color: color); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: points[next], color: color); inc vertexIndex

  if aaRing:
    let clearColor = UiColor(r: color.r, g: color.g, b: color.b, a: 0.0'f32)
    for i in 0 ..< boundaryCount:
      let next = (i + 1) mod boundaryCount
      data[vertexIndex] = UiVertex(pos: points[i], color: color); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: points[next], color: color); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: outerPoints[i], color: clearColor); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: points[next], color: color); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: outerPoints[next], color: clearColor); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: outerPoints[i], color: clearColor); inc vertexIndex
  (data, vertexCount)

proc buildRectFillVertices*(arena: ptr Arena, pos, size: Vec2, color: UiColor,
    radius: float32, antialiasMeshWidth = 0.0'f32): tuple[data: nil ptr UncheckedArray[UiVertex], count: int] =
  if radius == 0 and antialiasMeshWidth <= 0.0'f32:
    if arena == nil:
      return (nil, 0)
    prof("buildRectFillVerticesOpt")
    let w = max(0.0'f32, size.x)
    let h = max(0.0'f32, size.y)
    if w <= 0.0'f32 or h <= 0.0'f32:
      return (nil, 0)
    const vertexCount = 6
    let data = cast[nil ptr UncheckedArray[UiVertex]](arena[].alloc(vertexCount * sizeof(UiVertex)))
    if data == nil:
      return (nil, 0)
    let x0 = pos.x
    let y0 = pos.y
    let x1 = pos.x + w
    let y1 = pos.y + h
    data[0] = UiVertex(pos: vec2(x0, y0), color: color)
    data[1] = UiVertex(pos: vec2(x1, y0), color: color)
    data[2] = UiVertex(pos: vec2(x1, y1), color: color)
    data[3] = UiVertex(pos: vec2(x0, y0), color: color)
    data[4] = UiVertex(pos: vec2(x1, y1), color: color)
    data[5] = UiVertex(pos: vec2(x0, y1), color: color)
    return (data, vertexCount)

  buildRectFillVertices(arena, pos, size, color, uniformCornerRadii(radius),
    antialiasMeshWidth)

proc buildRectStrokeVertices*(arena: ptr Arena, pos, size: Vec2,
    colors: UiBorderColors, radii: UiCornerRadii,
  widths: UiBorderWidths, antialiasMeshWidth = 0.0'f32): tuple[data: nil ptr UncheckedArray[UiVertex], count: int] =
  ## Generate a rectangle border with per-side widths/colors and per-corner radii.
  if arena == nil:
    return (nil, 0)
  prof("buildRectStrokeVertices")
  let rectSize = vec2(max(0.0'f32, size.x), max(0.0'f32, size.y))
  if rectSize.x <= 0.0'f32 or rectSize.y <= 0.0'f32:
    return (nil, 0)
  let borderWidths = UiBorderWidths(
    left: max(0.0'f32, widths.left),
    top: max(0.0'f32, widths.top),
    right: max(0.0'f32, widths.right),
    bottom: max(0.0'f32, widths.bottom),
  )
  if borderWidths.left <= 0 and borderWidths.top <= 0 and
      borderWidths.right <= 0 and borderWidths.bottom <= 0:
    return (nil, 0)

  let outerRadii = normalizedCornerRadii(radii, rectSize)
  let aaWidth = max(0.0'f32, antialiasMeshWidth)
  let aaHalfWidth = aaWidth * 0.5'f32
  let segments = [
    cornerSegments(outerRadii.topRight),
    cornerSegments(outerRadii.bottomRight),
    cornerSegments(outerRadii.bottomLeft),
    cornerSegments(outerRadii.topLeft),
  ]
  let boundaryCount = segments[0] + segments[1] + segments[2] + segments[3] + 4
  let innerPos = pos + vec2(borderWidths.left, borderWidths.top)
  let innerSize = vec2(
    max(0.0'f32, rectSize.x - borderWidths.left - borderWidths.right),
    max(0.0'f32, rectSize.y - borderWidths.top - borderWidths.bottom),
  )
  let innerRadii = normalizedCornerRadii(UiCornerRadii(
    topLeft: max(0.0'f32, outerRadii.topLeft - max(borderWidths.left, borderWidths.top)),
    topRight: max(0.0'f32, outerRadii.topRight - max(borderWidths.right, borderWidths.top)),
    bottomRight: max(0.0'f32, outerRadii.bottomRight - max(borderWidths.right, borderWidths.bottom)),
    bottomLeft: max(0.0'f32, outerRadii.bottomLeft - max(borderWidths.left, borderWidths.bottom)),
  ), innerSize)

  let hasAaRing = aaWidth > 0.0'f32
  let innerAaRing = hasAaRing and
    innerSize.x > aaWidth and innerSize.y > aaWidth
  let vertexCount = boundaryCount * 6 +
    (if hasAaRing: boundaryCount * 6 else: 0) +
    (if innerAaRing: boundaryCount * 6 else: 0)
  let data = cast[nil ptr UncheckedArray[UiVertex]](arena[].alloc(vertexCount * sizeof(UiVertex)))
  let outer = cast[ptr UncheckedArray[Vec2]](arena[].alloc(boundaryCount * sizeof(Vec2)))
  let inner = cast[ptr UncheckedArray[Vec2]](arena[].alloc(boundaryCount * sizeof(Vec2)))
  let pointColors = cast[ptr UncheckedArray[UiColor]](arena[].alloc(boundaryCount * sizeof(UiColor)))
  let outerAa = if hasAaRing:
    cast[ptr UncheckedArray[Vec2]](arena[].alloc(boundaryCount * sizeof(Vec2)))
  else:
    nil
  let innerAa = if innerAaRing:
    cast[ptr UncheckedArray[Vec2]](arena[].alloc(boundaryCount * sizeof(Vec2)))
  else:
    nil
  if data == nil or outer == nil or inner == nil or pointColors == nil or
      (hasAaRing and outerAa == nil) or (innerAaRing and innerAa == nil):
    return (nil, 0)
  let solidOuterRadii = normalizedCornerRadii(UiCornerRadii(
    topLeft: max(0.0'f32, outerRadii.topLeft - aaHalfWidth),
    topRight: max(0.0'f32, outerRadii.topRight - aaHalfWidth),
    bottomRight: max(0.0'f32, outerRadii.bottomRight - aaHalfWidth),
    bottomLeft: max(0.0'f32, outerRadii.bottomLeft - aaHalfWidth),
  ), rectSize - vec2(aaWidth))
  let solidInnerRadii = UiCornerRadii(
    topLeft: innerRadii.topLeft + aaHalfWidth,
    topRight: innerRadii.topRight + aaHalfWidth,
    bottomRight: innerRadii.bottomRight + aaHalfWidth,
    bottomLeft: innerRadii.bottomLeft + aaHalfWidth,
  )
  outer.writeRoundedBoundary(pointColors, pos + vec2(aaHalfWidth),
    rectSize - vec2(aaWidth), solidOuterRadii, segments, colors)
  inner.writeRoundedBoundary(nil, innerPos - vec2(aaHalfWidth),
    innerSize + vec2(aaWidth), solidInnerRadii, segments, colors)
  if hasAaRing:
    let expandedRadii = UiCornerRadii(
      topLeft: outerRadii.topLeft + aaHalfWidth,
      topRight: outerRadii.topRight + aaHalfWidth,
      bottomRight: outerRadii.bottomRight + aaHalfWidth,
      bottomLeft: outerRadii.bottomLeft + aaHalfWidth,
    )
    outerAa.writeRoundedBoundary(nil, pos - vec2(aaHalfWidth),
      rectSize + vec2(aaWidth), expandedRadii, segments, colors)
  if innerAaRing:
    let insetRadii = UiCornerRadii(
      topLeft: max(0.0'f32, innerRadii.topLeft - aaHalfWidth),
      topRight: max(0.0'f32, innerRadii.topRight - aaHalfWidth),
      bottomRight: max(0.0'f32, innerRadii.bottomRight - aaHalfWidth),
      bottomLeft: max(0.0'f32, innerRadii.bottomLeft - aaHalfWidth),
    )
    innerAa.writeRoundedBoundary(nil, innerPos + vec2(aaHalfWidth),
      innerSize - vec2(aaWidth), insetRadii, segments, colors)

  var vertexIndex = 0
  for i in 0 ..< boundaryCount:
    let next = (i + 1) mod boundaryCount
    data[vertexIndex] = UiVertex(pos: outer[i], color: pointColors[i]); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: outer[next], color: pointColors[next]); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: inner[i], color: pointColors[i]); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: inner[i], color: pointColors[i]); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: outer[next], color: pointColors[next]); inc vertexIndex
    data[vertexIndex] = UiVertex(pos: inner[next], color: pointColors[next]); inc vertexIndex

  if hasAaRing:
    for i in 0 ..< boundaryCount:
      let next = (i + 1) mod boundaryCount
      let clear0 = UiColor(r: pointColors[i].r, g: pointColors[i].g, b: pointColors[i].b, a: 0.0'f32)
      let clear1 = UiColor(r: pointColors[next].r, g: pointColors[next].g, b: pointColors[next].b, a: 0.0'f32)
      data[vertexIndex] = UiVertex(pos: outer[i], color: pointColors[i]); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: outer[next], color: pointColors[next]); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: outerAa[i], color: clear0); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: outer[next], color: pointColors[next]); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: outerAa[next], color: clear1); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: outerAa[i], color: clear0); inc vertexIndex

  if innerAaRing:
    for i in 0 ..< boundaryCount:
      let next = (i + 1) mod boundaryCount
      let clear0 = UiColor(r: pointColors[i].r, g: pointColors[i].g, b: pointColors[i].b, a: 0.0'f32)
      let clear1 = UiColor(r: pointColors[next].r, g: pointColors[next].g, b: pointColors[next].b, a: 0.0'f32)
      data[vertexIndex] = UiVertex(pos: inner[i], color: pointColors[i]); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: innerAa[i], color: clear0); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: innerAa[next], color: clear1); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: inner[i], color: pointColors[i]); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: innerAa[next], color: clear1); inc vertexIndex
      data[vertexIndex] = UiVertex(pos: inner[next], color: pointColors[next]); inc vertexIndex
  (data, vertexCount)

proc buildRectStrokeVertices*(arena: ptr Arena, pos, size: Vec2, color: UiColor,
    radius, thickness: float32, antialiasMeshWidth = 0.0'f32): tuple[data: nil ptr UncheckedArray[UiVertex], count: int] =
  if radius == 0.0'f32 and thickness > 0.0'f32 and antialiasMeshWidth <= 0.0'f32:
    if arena == nil:
      return (nil, 0)
    prof("buildRectStrokeVertices")
    let w = max(0.0'f32, size.x)
    let h = max(0.0'f32, size.y)
    if w <= 0.0'f32 or h <= 0.0'f32:
      return (nil, 0)
    let t = max(0.0'f32, thickness)
    let x0 = pos.x
    let y0 = pos.y
    let x1 = pos.x + w
    let y1 = pos.y + h
    let innerX = x0 + t
    let innerY = y0 + t
    let innerX2 = x1 - t
    let innerY2 = y1 - t
    if innerX2 <= innerX or innerY2 <= innerY:
      const fillCount = 6
      let data = cast[nil ptr UncheckedArray[UiVertex]](arena[].alloc(fillCount * sizeof(UiVertex)))
      if data == nil:
        return (nil, 0)
      data[0] = UiVertex(pos: vec2(x0, y0), color: color)
      data[1] = UiVertex(pos: vec2(x1, y0), color: color)
      data[2] = UiVertex(pos: vec2(x1, y1), color: color)
      data[3] = UiVertex(pos: vec2(x0, y0), color: color)
      data[4] = UiVertex(pos: vec2(x1, y1), color: color)
      data[5] = UiVertex(pos: vec2(x0, y1), color: color)
      return (data, fillCount)
    const vertexCount = 24
    let data = cast[nil ptr UncheckedArray[UiVertex]](arena[].alloc(vertexCount * sizeof(UiVertex)))
    if data == nil:
      return (nil, 0)
    var i = 0
    template emit(p: Vec2) =
      data[i] = UiVertex(pos: p, color: color); inc i
    emit(vec2(x0, y0)); emit(vec2(x1, y0)); emit(vec2(innerX2, innerY))
    emit(vec2(x0, y0)); emit(vec2(innerX2, innerY)); emit(vec2(innerX, innerY))
    emit(vec2(x1, y0)); emit(vec2(x1, y1)); emit(vec2(innerX2, innerY2))
    emit(vec2(x1, y0)); emit(vec2(innerX2, innerY2)); emit(vec2(innerX2, innerY))
    emit(vec2(x0, y1)); emit(vec2(x1, y1)); emit(vec2(innerX2, innerY2))
    emit(vec2(x0, y1)); emit(vec2(innerX2, innerY2)); emit(vec2(innerX, innerY2))
    emit(vec2(x0, y0)); emit(vec2(x0, y1)); emit(vec2(innerX, innerY2))
    emit(vec2(x0, y0)); emit(vec2(innerX, innerY2)); emit(vec2(innerX, innerY))
    return (data, vertexCount)

  buildRectStrokeVertices(arena, pos, size, uniformBorderColors(color),
    uniformCornerRadii(radius), uniformBorderWidths(thickness), antialiasMeshWidth)

func cross2(a, b: Vec2): float32 {.inline.} =
  a.x * b.y - a.y * b.x

func offsetChevronPolygon(points: array[6, Vec2], distance: float32): array[6, Vec2] =
  var signedArea = 0.0'f32
  for pointIndex in 0 ..< points.len:
    signedArea += points[pointIndex].cross2(points[(pointIndex + 1) mod points.len])
  let normalSign = if signedArea < 0.0'f32: 1.0'f32 else: -1.0'f32

  for pointIndex in 0 ..< points.len:
    let previous = points[(pointIndex + points.len - 1) mod points.len]
    let current = points[pointIndex]
    let following = points[(pointIndex + 1) mod points.len]
    let previousDirection = (current - previous).normalize()
    let followingDirection = (following - current).normalize()
    let previousNormal = vec2(-previousDirection.y, previousDirection.x) * normalSign
    let followingNormal = vec2(-followingDirection.y, followingDirection.x) * normalSign
    let previousLine = current + previousNormal * distance
    let followingLine = current + followingNormal * distance
    let denominator = previousDirection.cross2(followingDirection)
    if abs(denominator) <= 1e-6'f32:
      result[pointIndex] = current + previousNormal * distance
    else:
      let lineDistance = (followingLine - previousLine).cross2(followingDirection) / denominator
      result[pointIndex] = previousLine + previousDirection * lineDistance

proc buildChevronVertices*(arena: ptr Arena, pos, size: Vec2, direction: Vec2,
    color: UiColor, thickness: float32 = -1.0'f32, angle: float32 = PI * 0.5'f32,
    antialiasMeshWidth = 0.0'f32): tuple[data: nil ptr UncheckedArray[UiVertex], count: int] =
  ## Build a thick "V" / ">" chevron symbol.
  ##
  ## `pos`/`size` define the bounding box of the symbol (top-left + extent).
  ## `direction` is the Vec2 the chevron points toward (`(1,0)` = `>`,
  ## `(0,1)` = `V`, `(-1,0)` = `<`, etc.). It is normalized internally; a zero
  ## vector defaults to `(1,0)`. `angle` is the opening angle at the tip in
  ## radians (default `PI/2` = 90°); it is clamped to `(0, PI)` and preserved
  ## by uniformly scaling the chevron to fit inside `size`. Collapsed should
  ## use `vec2(1,0)`, expanded `vec2(0,1)`.
  ##
  ## `color` tints all vertices, `thickness` is the stroke width in pixels.
  ## When `thickness <= 0` it defaults to `min(size.x,size.y) * 0.18`.
  ## A positive `antialiasMeshWidth` adds a centered alpha-gradient border.
  ## Returns a triangle list (`count` vertices, `count mod 3 == 0`) allocated
  ## from `arena`, or `(nil,0)` on failure.
  if arena == nil:
    return (nil, 0)
  prof("buildChevronVertices")
  let w = size.x
  let h = size.y
  if w <= 0.0'f32 or h <= 0.0'f32:
    return (nil, 0)
  let dirLenSq = direction.x * direction.x + direction.y * direction.y
  var dir: Vec2
  if dirLenSq < 1e-8'f32:
    dir = vec2(1.0'f32, 0.0'f32)
  else:
    dir = direction.normalize()
  let perp = vec2(-dir.y, dir.x)
  var t = thickness
  if t <= 0.0'f32:
    t = min(w, h) * 0.18'f32
  t = clamp(t, 1.0'f32, min(w, h) * 0.45'f32)
  # angle handling: preserve angle by scaling chevron to fit
  var effAngle = angle
  if effAngle <= 0.05'f32 or effAngle >= PI - 0.05'f32 or effAngle != effAngle:
    effAngle = PI * 0.5'f32
  effAngle = clamp(effAngle, 0.1'f32, PI - 0.1'f32)
  let halfAngle = effAngle * 0.5'f32
  let tanHalf = tan(halfAngle.float64).float32
  var effW = w
  var desiredHalfH = effW * tanHalf
  # scale uniformly to fit inside h if needed (preserves angle)
  let totalH = desiredHalfH * 2.0'f32
  if totalH > h and totalH > 1e-5'f32:
    let scale = h / totalH
    effW *= scale
    desiredHalfH *= scale
    # also scale thickness to keep proportion? keep as is but clamp again
    t = clamp(t, 1.0'f32, min(effW, desiredHalfH * 2.0'f32) * 0.45'f32)
  let center = pos + size * 0.5'f32
  let halfW = effW * 0.5'f32
  let halfH = desiredHalfH
  let tip = center + dir * halfW
  let backCenter = center - dir * halfW
  let backTop = backCenter + perp * halfH
  let backBottom = backCenter - perp * halfH

  var topDir = backTop - tip
  var bottomDir = backBottom - tip
  let topLen = topDir.length
  let bottomLen = bottomDir.length
  if topLen < 1e-5'f32 or bottomLen < 1e-5'f32:
    return (nil, 0)
  topDir = topDir / topLen
  bottomDir = bottomDir / bottomLen

  # interior normals (point inside the V)
  var nTop = vec2(-topDir.y, topDir.x)
  let midTop = (tip + backTop) * 0.5'f32
  if (center - midTop).dot(nTop) < 0.0'f32:
    nTop = -nTop
  var nBottom = vec2(-bottomDir.y, bottomDir.x)
  let midBottom = (tip + backBottom) * 0.5'f32
  if (center - midBottom).dot(nBottom) < 0.0'f32:
    nBottom = -nBottom

  # inner lines: offset outer lines by thickness along interior normal
  let p1 = tip + nTop * t
  let p2 = tip + nBottom * t
  # intersection of p1 + topDir * s  and  p2 + bottomDir * s2
  let crossDir = topDir.x * bottomDir.y - topDir.y * bottomDir.x
  var innerNotch: Vec2
  if abs(crossDir) < 1e-6'f32:
    innerNotch = tip - dir * t
  else:
    let delta = p2 - p1
    let s = (delta.x * bottomDir.y - delta.y * bottomDir.x) / crossDir
    innerNotch = p1 + topDir * s
    # clamp notch to not pass behind backCenter when thickness is huge
    if (innerNotch - tip).dot(dir) > 0.0'f32:
      innerNotch = tip - dir * t
    let maxBack = (backCenter - tip).dot(dir)
    if (innerNotch - tip).dot(dir) < maxBack:
      # keep inside
      discard

  let outerTip = tip
  let outerBackTop = backTop
  let outerBackBottom = backBottom
  let innerBackTop = backTop + nTop * t
  let innerBackBottom = backBottom + nBottom * t

  let polygon = [outerTip, outerBackTop, innerBackTop, innerNotch,
    innerBackBottom, outerBackBottom]
  let aaHalfWidth = min(max(0.0'f32, antialiasMeshWidth) * 0.5'f32, t * 0.45'f32)
  let hasAaRing = aaHalfWidth > 0.0'f32
  let innerPolygon = if hasAaRing: polygon.offsetChevronPolygon(-aaHalfWidth) else: polygon
  let outerPolygon = if hasAaRing: polygon.offsetChevronPolygon(aaHalfWidth) else: polygon
  let vertexCount = 12 + (if hasAaRing: polygon.len * 6 else: 0)
  let data = cast[nil ptr UncheckedArray[UiVertex]](arena[].alloc(vertexCount * sizeof(UiVertex)))
  if data == nil:
    return (nil, 0)
  var i = 0
  template emit(p: Vec2) =
    data[i] = UiVertex(pos: p, color: color); inc i
  emit(innerPolygon[0]); emit(innerPolygon[1]); emit(innerPolygon[2])
  emit(innerPolygon[0]); emit(innerPolygon[2]); emit(innerPolygon[3])
  emit(innerPolygon[0]); emit(innerPolygon[3]); emit(innerPolygon[4])
  emit(innerPolygon[0]); emit(innerPolygon[4]); emit(innerPolygon[5])
  if hasAaRing:
    let clearColor = UiColor(r: color.r, g: color.g, b: color.b, a: 0.0'f32)
    template emitClear(point: Vec2) =
      data[i] = UiVertex(pos: point, color: clearColor); inc i
    for pointIndex in 0 ..< polygon.len:
      let nextIndex = (pointIndex + 1) mod polygon.len
      emit(innerPolygon[pointIndex]); emit(innerPolygon[nextIndex]); emitClear(outerPolygon[pointIndex])
      emit(innerPolygon[nextIndex]); emitClear(outerPolygon[nextIndex]); emitClear(outerPolygon[pointIndex])
  return (data, vertexCount)

proc buildChevronVertices*(arena: ptr Arena, pos, size: Vec2,
    direction: Vec2): tuple[data: nil ptr UncheckedArray[UiVertex], count: int] =
  ## Convenience overload with default white color and auto thickness.
  buildChevronVertices(arena, pos, size, direction, UiColor(r: 1.0'f32, g: 1.0'f32, b: 1.0'f32, a: 1.0'f32), -1.0'f32)

when not defined(nimony):
  static:
    doAssert sizeof(UiVertex) == sizeof(float32) * 8

