import std/math
import nuigi, array_view, arena, profiler
import mesh, mymath

include compat2

const cpTwoPi = 6.2831853'f32

type ColorPickerStorage* = ref object of UiNodeStorageData
  h*, s*, v*, a*: float32
  svIdx*, hueIdx*, alphaIdx*: int
  openPrev*: bool

proc getOrCreateColorPickerStorage(b: var UiBuilder, node: ptr UiNode): ColorPickerStorage =
  let existing = nodeStorageGet(b, node)
  if existing != nil:
    return cast[ColorPickerStorage](existing)
  var storage = ColorPickerStorage()
  nodeStorage(b, node, storage)
  storage

proc rgbToHsv*(c: UiColor): tuple[h, s, v: float32] =
  let r = c.r
  let g = c.g
  let b = c.b
  let maxc = max(r, max(g, b))
  let minc = min(r, min(g, b))
  let d = maxc - minc
  var h = 0.0'f32
  if d > 0.00001'f32:
    if maxc == r:
      h = (g - b) / d
    elif maxc == g:
      h = (b - r) / d + 2.0'f32
    else:
      h = (r - g) / d + 4.0'f32
    h = h / 6.0'f32
    if h < 0.0'f32:
      h += 1.0'f32
  let s = if maxc <= 0.00001'f32: 0.0'f32 else: d / maxc
  (h, s, maxc)

proc hsvToRgb*(h, s, v: float32, a: float32 = 1.0'f32): UiColor =
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

proc cpCompHex(v: float32): string =
  let i = clamp(int(round(v * 255.0'f32)), 0, 255)
  const hexd = "0123456789ABCDEF"
  result = $hexd[i shr 4] & $hexd[i and 0xF]

proc toHex(c: UiColor): string =
  "#" & cpCompHex(c.r) & cpCompHex(c.g) & cpCompHex(c.b) & cpCompHex(c.a)

proc cpPushQuad(v: nil ptr UncheckedArray[UiVertex], i: var int,
    x0, y0, x1, y1: float32, cTL, cTR, cBL, cBR: UiColor) =
  v[i] = UiVertex(pos: vec2(x0, y0), uv: vec2(0.0'f32, 0.0'f32), color: cTL); inc i
  v[i] = UiVertex(pos: vec2(x1, y0), uv: vec2(1.0'f32, 0.0'f32), color: cTR); inc i
  v[i] = UiVertex(pos: vec2(x0, y1), uv: vec2(0.0'f32, 1.0'f32), color: cBL); inc i
  v[i] = UiVertex(pos: vec2(x1, y0), uv: vec2(1.0'f32, 0.0'f32), color: cTR); inc i
  v[i] = UiVertex(pos: vec2(x1, y1), uv: vec2(1.0'f32, 1.0'f32), color: cBR); inc i
  v[i] = UiVertex(pos: vec2(x0, y1), uv: vec2(0.0'f32, 1.0'f32), color: cBL); inc i

proc cpPushRect(v: nil ptr UncheckedArray[UiVertex], i: var int,
    x0, y0, x1, y1: float32, c: UiColor) =
  cpPushQuad(v, i, x0, y0, x1, y1, c, c, c, c)

proc cpPushCircleFan(v: nil ptr UncheckedArray[UiVertex], i: var int,
    cx, cy, r: float32, c: UiColor, segments: int = 12) =
  for sIdx in 0 ..< segments:
    let a0 = cpTwoPi * sIdx.float32 / segments.float32
    let a1 = cpTwoPi * (sIdx + 1).float32 / segments.float32
    v[i] = UiVertex(pos: vec2(cx, cy), uv: vec2(0.0'f32), color: c); inc i
    v[i] = UiVertex(pos: vec2(cx + cos(a0) * r, cy + sin(a0) * r), uv: vec2(0.0'f32), color: c); inc i
    v[i] = UiVertex(pos: vec2(cx + cos(a1) * r, cy + sin(a1) * r), uv: vec2(0.0'f32), color: c); inc i

proc cpSetCommands(b: var UiBuilder, nodeIdx: int,
    vbuf: nil ptr UncheckedArray[UiVertex], vi: int) =
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  var cmds = b.frame.arena[].allocEmptyArray(1, UiRenderCommand)
  cmds.add UiRenderCommand(
    kind: CmdRawVertices,
    vertexData: vbuf,
    vertexCount: vi.int32)
  b.withParent(nodeIdx):
    discard b.customRenderCommands(cmds)

proc cpBuildSv(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall.} =
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let storage = getOrCreateColorPickerStorage(b, b.nodes[userData].addr)
  let n = b.frame.nodes[nodeIdx].addr
  let abs = b.absoluteNodePos(nodeIdx)
  let x0 = abs.x
  let y0 = abs.y
  let w = n.size.x
  let hgt = n.size.y
  let x1 = x0 + w
  let y1 = y0 + hgt
  let hsvH = storage.h
  let s = storage.s
  let v = storage.v
  let markerCol = b.themeTextStyle(UiStyleIndexDefaultText)[].textColor

  let cTL = hsvToRgb(hsvH, 0.0'f32, 1.0'f32)
  let cTR = hsvToRgb(hsvH, 1.0'f32, 1.0'f32)
  let cBL = hsvToRgb(hsvH, 0.0'f32, 0.0'f32)
  let cBR = hsvToRgb(hsvH, 1.0'f32, 0.0'f32)

  let vcount = 6 + 12 + 12
  let vbuf = cast[nil ptr UncheckedArray[UiVertex]](b.frame.arena[].alloc(vcount * sizeof(UiVertex)))
  var vi = 0
  cpPushQuad(vbuf, vi, x0, y0, x1, y1, cTL, cTR, cBL, cBR)

  let cx = x0 + s * w
  let cy = y0 + (1.0'f32 - v) * hgt
  cpPushCircleFan(vbuf, vi, cx, cy, 6.0'f32, markerCol, 12)
  cpPushCircleFan(vbuf, vi, cx, cy, 4.0'f32, hsvToRgb(hsvH, s, v, 1.0'f32), 12)

  cpSetCommands(b, nodeIdx, vbuf, vi)

proc cpBuildHue(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall.} =
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let storage = getOrCreateColorPickerStorage(b, b.nodes[userData].addr)
  let n = b.frame.nodes[nodeIdx].addr
  let abs = b.absoluteNodePos(nodeIdx)
  let x0 = abs.x
  let y0 = abs.y
  let w = n.size.x
  let hgt = n.size.y
  let x1 = x0 + w
  let y1 = y0 + hgt
  let markerCol = b.themeTextStyle(UiStyleIndexDefaultText)[].textColor

  let segs = 32
  let vcount = segs * 6 + 6
  let vbuf = cast[nil ptr UncheckedArray[UiVertex]](b.frame.arena[].alloc(vcount * sizeof(UiVertex)))
  var vi = 0
  for sIdx in 0 ..< segs:
    let t0 = sIdx.float32 / segs.float32
    let t1 = (sIdx + 1).float32 / segs.float32
    let x0s = x0 + t0 * w
    let x1s = x0 + t1 * w
    let c0 = hsvToRgb(t0, 1.0'f32, 1.0'f32)
    let c1 = hsvToRgb(t1, 1.0'f32, 1.0'f32)
    cpPushQuad(vbuf, vi, x0s, y0, x1s, y1, c0, c1, c0, c1)

  let ix = x0 + storage.h * w
  cpPushRect(vbuf, vi, ix - 1.0'f32, y0, ix + 1.0'f32, y1, markerCol)

  cpSetCommands(b, nodeIdx, vbuf, vi)

proc cpBuildAlpha(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall.} =
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let storage = getOrCreateColorPickerStorage(b, b.nodes[userData].addr)
  let n = b.frame.nodes[nodeIdx].addr
  let abs = b.absoluteNodePos(nodeIdx)
  let x0 = abs.x
  let y0 = abs.y
  let w = n.size.x
  let hgt = n.size.y
  let x1 = x0 + w
  let y1 = y0 + hgt
  let markerCol = b.themeTextStyle(UiStyleIndexDefaultText)[].textColor
  let tileLight = b.themeStyle(UiStyleIndexRowAlt)[].fillColor
  let tileDark = b.themeStyle(UiStyleIndexTabBarContent)[].fillColor

  let tile = 8.0'f32
  let cols = max(1, int(ceil(w / tile)))
  let rows = max(1, int(ceil(hgt / tile)))
  let vcount = cols * rows * 6 + 6 + 6
  let vbuf = cast[nil ptr UncheckedArray[UiVertex]](b.frame.arena[].alloc(vcount * sizeof(UiVertex)))
  var vi = 0
  for r in 0 ..< rows:
    for c in 0 ..< cols:
      let even = (r + c) mod 2 == 0
      let col = if even: tileLight else: tileDark
      let x0c = x0 + c.float32 * tile
      let y0c = y0 + r.float32 * tile
      cpPushRect(vbuf, vi, x0c, y0c, min(x0c + tile, x1), min(y0c + tile, y1), col)

  let base = hsvToRgb(storage.h, storage.s, storage.v, 1.0'f32)
  cpPushQuad(vbuf, vi, x0, y0, x1, y1,
    rgba(base.r, base.g, base.b, 0.0'f32),
    rgba(base.r, base.g, base.b, 1.0'f32),
    rgba(base.r, base.g, base.b, 0.0'f32),
    rgba(base.r, base.g, base.b, 1.0'f32))

  let ix = x0 + storage.a * w
  cpPushRect(vbuf, vi, ix - 1.0'f32, y0, ix + 1.0'f32, y1, markerCol)

  cpSetCommands(b, nodeIdx, vbuf, vi)

proc colorPicker*(b: var UiBuilder, value: var UiColor): bool =
  prof("colorPicker")
  var changed = false

  var swatchIdx = -1
  var swatchId = noneNodeId()
  var pickerIdx = -1

  b.node:
    b.debugName("color-picker")
    pickerIdx = b.stack[^1]
    discard b.size(38, 18)

    swatchIdx = b.stack[^1]
    swatchId = b.currentNode.id
    let swatchHovered = b.wasHovered(b.stack[^1], includeChildren = true)
    let swatchOpen = b.focusedNode == swatchId
    discard b.fillBackground()
    discard b.backgroundColor(value)
    discard b.borderWidth(if swatchOpen or swatchHovered: 2.0'f32 else: 1.0'f32)
    discard b.borderColor(if swatchOpen or swatchHovered: b.themeStyle(UiStyleIndexButtonHover)[].borderColor
                          else: b.themeStyle(UiStyleIndexButton)[].borderColor)

  if b.previousOutput.clickedId == swatchId:
    if b.focusedNode == swatchId:
      b.focusedNode = noneNodeId()
    else:
      b.focusedNode = swatchId

  let pickerOpen = b.focusedNode == swatchId
  let storage = getOrCreateColorPickerStorage(b, b.nodes[swatchIdx].addr)

  if pickerOpen and not storage.openPrev:
    let (h, s, v) = rgbToHsv(value)
    storage.h = h
    storage.s = s
    storage.v = v
    storage.a = value.a

  var popupIdx = -1
  if pickerOpen:
    let swatchAbsPos = b.absoluteNodePosPrev(swatchId, swatchIdx)
    let swatchNode = b.nodes[swatchIdx].addr

    b.withParent(b.overlays):
      b.node("color-picker-popup"):
        popupIdx = b.stack[^1]
        discard b.position(swatchAbsPos.x, swatchAbsPos.y + swatchNode.size.y + 4.0'f32)
        discard b.layout(LayoutVertical)
        discard b.width(220).fitY()
        discard b.padding(6)
        discard b.gap(6)
        discard b.fillBackground()
        discard b.backgroundColor(b.themeStyle(UiStyleIndexTooltip)[].fillColor)
        discard b.borderWidth(1)
        discard b.borderColor(b.themeStyle(UiStyleIndexTooltip)[].borderColor)
        discard b.cornerRadius(4)

        b.node("cp-sv"):
          discard b.fillX().height(140)
          storage.svIdx = b.stack[^1]
          discard b.deferBuild(cpBuildSv, cast[int](swatchIdx))

        b.node("cp-hue"):
          discard b.fillX().height(14)
          storage.hueIdx = b.stack[^1]
          discard b.deferBuild(cpBuildHue, cast[int](swatchIdx))

        b.node("cp-alpha"):
          discard b.fillX().height(14)
          storage.alphaIdx = b.stack[^1]
          discard b.deferBuild(cpBuildAlpha, cast[int](swatchIdx))

        b.node("cp-readout"):
          discard b.fitX().fitY().padding(2)
          discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexTabBarContent)[].fillColor)
          discard b.text(toHex(value))

  if pickerOpen:
    let input = b.frameCtx.input

    if storage.svIdx >= 0 and storage.svIdx < b.nodes.len:
      let svId = b.nodes[storage.svIdx].id
      let prev = b.absoluteNodePosPrev(svId, storage.svIdx)
      let sz = b.nodes[storage.svIdx].size
      let lx = input.mouse.x - prev.x
      let ly = input.mouse.y - prev.y
      let drag = (MouseLeft in input.mouseDown) and b.wasHeld(storage.svIdx, includeChildren = true)
      let click = b.wasClicked(storage.svIdx, includeChildren = true)
      if drag or click:
        let ns = clamp(lx / sz.x, 0.0'f32, 1.0'f32)
        let nv = clamp(1.0'f32 - ly / sz.y, 0.0'f32, 1.0'f32)
        if abs(ns - storage.s) > 0.0008'f32 or abs(nv - storage.v) > 0.0008'f32:
          storage.s = ns
          storage.v = nv
          changed = true

    if storage.hueIdx >= 0 and storage.hueIdx < b.nodes.len:
      let hueId = b.nodes[storage.hueIdx].id
      let prev = b.absoluteNodePosPrev(hueId, storage.hueIdx)
      let sz = b.nodes[storage.hueIdx].size
      let lx = input.mouse.x - prev.x
      let ly = input.mouse.y - prev.y
      let drag = (MouseLeft in input.mouseDown) and b.wasHeld(storage.hueIdx, includeChildren = true)
      let click = b.wasClicked(storage.hueIdx, includeChildren = true)
      if drag or click:
        let nh = clamp(lx / sz.x, 0.0'f32, 1.0'f32)
        if abs(nh - storage.h) > 0.0008'f32:
          storage.h = nh
          changed = true

    if storage.alphaIdx >= 0 and storage.alphaIdx < b.nodes.len:
      let aId = b.nodes[storage.alphaIdx].id
      let prev = b.absoluteNodePosPrev(aId, storage.alphaIdx)
      let sz = b.nodes[storage.alphaIdx].size
      let lx = input.mouse.x - prev.x
      let ly = input.mouse.y - prev.y
      let drag = (MouseLeft in input.mouseDown) and b.wasHeld(storage.alphaIdx, includeChildren = true)
      let click = b.wasClicked(storage.alphaIdx, includeChildren = true)
      if drag or click:
        let na = clamp(lx / sz.x, 0.0'f32, 1.0'f32)
        if abs(na - storage.a) > 0.0008'f32:
          storage.a = na
          changed = true

    value = hsvToRgb(storage.h, storage.s, storage.v, storage.a)

  if pickerOpen and KeyEscape in b.frameCtx.input.keysPressed:
    b.focusedNode = noneNodeId()

  if pickerOpen and MouseLeft in b.frameCtx.input.mousePressed:
    let swatchHovered = swatchIdx >= 0 and b.wasHovered(swatchIdx, includeChildren = true)
    let popupHovered = popupIdx >= 0 and b.wasHovered(popupIdx, includeChildren = true)
    if not swatchHovered and not popupHovered and not b.wasHovered(pickerIdx, includeChildren = true):
      b.focusedNode = noneNodeId()

  storage.openPrev = pickerOpen
  changed
