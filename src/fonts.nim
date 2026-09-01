import std/[os, syncio, tables, unicode, strutils, math, hashes, assertions]
import sdl3, profiler, mymath, text, mesh
export text

include compat2
import freetype/[
  freetype, ftadvanc,
  ftautoh, ftbbox,
  ftbdf, ftbitmap,
  ftbzip2, ftcache,
  ftcid,
  ftfntfmt,
  ftgasp, ftglyph,
  ftgxval, ftgzip,
  ftimage, ftimport,
  ftincrem, ftlcdfil,
  ftlist, ftlzw,
  ftmac, ftmm,
  ftmodapi,
  ftotval, ftoutln,
  ftpfr, ftsizes,
  ftsnames, ftstroke,
  ftsynth, ftsystem,
  fttrigon,
  fttypes, ftwinfnt,
  otsvg,
  t1tables,
  tttables,
  ]

when not defined(nimony):
  const useHarfbuzz = not defined(wasm) and not defined(nuiNoHarfbuzz)
else:
  const useHarfbuzz = false

when not defined(nimony):
  when useHarfbuzz:
    import harfbuzzy as hb

const
  defaultFontAtlasSize* = 2048
  defaultMaxFontAtlasSize* = 8192
  defaultGlyphPackingBudgetNs* = 4_000_000'u64
  defaultTextMeshCacheCapacity* = 2048
  glyphSubpixelPhases = 4
  glyphSubpixelStep26Dot6 = 64 div glyphSubpixelPhases

type
  FontRenderFlag* {.pure.} = enum
    SubpixelPhasing
    PixelSnapping

  FontRenderFlags* = set[FontRenderFlag]

  FontId* = int16

  TextMetrics* = object
    width*: cfloat
    height*: cfloat
    ascent*: cfloat
    descent*: cfloat

  PackedChar = object
    x0*, y0*, x1*, y1*: int       # atlas rect (pixels)
    xoff*, yoff*, xadvance*: cfloat
    xoff2*, yoff2*: cfloat

  FontDataSized = object
    fontPackedChars: array[128, PackedChar]  # ASCII 0-127
    packedAscii: array[128, bool]
    unicodeChars: Table[uint32, PackedChar]  # Unicode > 127
    glyphIndexChars: Table[uint64, PackedChar] # Glyph index and horizontal raster phase cache

  FontData = object
    sizedData: seq[FontDataSized] # One per integer font size, slots maybe empty

  LoadedFont = object
    name: string
    children: seq[FontId]
    data: seq[uint8]
    face: FT_Face
    sized: FontData
    activePixelSize: int
    hasColor: bool
    when useHarfbuzz:
      hbTypeface: hb.Typeface
      hbReady: bool

  TextMeshVertex* = object
    pos*: Vec2
    uv*: Vec2
    color*: FColor

  TextMesh* = object
    data*: nil ptr UncheckedArray[TextMeshVertex]
    count*: int

  TextMeshCacheEntry = ref object
    key: uint64
    arrangement: UiTextArrangement
    pos: Vec2
    screenOffset: Vec2
    color: FColor
    transform: UiAffine2
    flags: FontRenderFlags
    vertices: seq[TextMeshVertex]
    lastUsedTick: uint64
    complete: bool
    prev {.cursor.}: TextMeshCacheEntry
    next {.cursor.}: TextMeshCacheEntry

  FontRender* = object
    flags*: FontRenderFlags
    fonts*: seq[LoadedFont]
    fontAtlasWidth*: int
    fontAtlasHeight*: int
    maxFontAtlasSize*: int
    fontAtlasPixels*: seq[uint8]
    fontAtlasNeedsReset*: bool
    fontAtlasNeedsResize*: bool
    atlasPackX*: int
    atlasPackY*: int
    atlasPackRowH*: int
    fontAtlasDirty*: bool
    fontAtlasDirtyMinX*: int
    fontAtlasDirtyMinY*: int
    fontAtlasDirtyMaxX*: int
    fontAtlasDirtyMaxY*: int
    glyphPackingBudgetNs*: uint64
    glyphPackingTimeNs*: uint64
    glyphPackingDeferredCount*: uint32
    textMeshCacheCapacity*: int
    textMeshCache: Table[uint64, TextMeshCacheEntry]
    textMeshLruHead: nil TextMeshCacheEntry
    textMeshCacheTick: uint64
    glyphAdvanceCache: Table[(int, int, FT_UInt), cfloat] # (fontIndex, sizeIdx, glyphIndex) -> advance
    fontLibrary*: FT_Library

proc markFontAtlasDirty*(r: var FontRender, x, y, w, h: int) {.raises: [].} =
  if w <= 0 or h <= 0:
    return
  let minX = clamp(x, 0, r.fontAtlasWidth)
  let minY = clamp(y, 0, r.fontAtlasHeight)
  let maxX = clamp(x + w, 0, r.fontAtlasWidth)
  let maxY = clamp(y + h, 0, r.fontAtlasHeight)
  if minX >= maxX or minY >= maxY:
    return

  if not r.fontAtlasDirty:
    r.fontAtlasDirtyMinX = minX
    r.fontAtlasDirtyMinY = minY
    r.fontAtlasDirtyMaxX = maxX
    r.fontAtlasDirtyMaxY = maxY
    r.fontAtlasDirty = true
  else:
    r.fontAtlasDirtyMinX = min(r.fontAtlasDirtyMinX, minX)
    r.fontAtlasDirtyMinY = min(r.fontAtlasDirtyMinY, minY)
    r.fontAtlasDirtyMaxX = max(r.fontAtlasDirtyMaxX, maxX)
    r.fontAtlasDirtyMaxY = max(r.fontAtlasDirtyMaxY, maxY)

proc markFullFontAtlasDirty*(r: var FontRender) {.raises: [].} =
  r.fontAtlasDirty = false
  r.markFontAtlasDirty(0, 0, r.fontAtlasWidth, r.fontAtlasHeight)

proc clearFontAtlasDirty*(r: var FontRender) {.raises: [].} =
  r.fontAtlasDirty = false
  r.fontAtlasDirtyMinX = 0
  r.fontAtlasDirtyMinY = 0
  r.fontAtlasDirtyMaxX = 0
  r.fontAtlasDirtyMaxY = 0

func canGrowFontAtlas*(r: FontRender): bool {.inline.} =
  r.fontAtlasWidth < r.maxFontAtlasSize or r.fontAtlasHeight < r.maxFontAtlasSize

func nextFontAtlasSize*(r: FontRender): tuple[width, height: int] {.inline.} =
  (min(r.fontAtlasWidth * 2, r.maxFontAtlasSize), min(r.fontAtlasHeight * 2, r.maxFontAtlasSize))

func glyphCacheKey(glyphIndex: FT_UInt, subpixelPhase: int): uint64 {.inline.} =
  (glyphIndex.uint64 shl 2) or subpixelPhase.uint64

proc beginFontRenderFrame*(r: var FontRender) {.inline, raises: [].} =
  r.glyphPackingTimeNs = 0
  r.glyphPackingDeferredCount = 0
  let cacheCapacity = max(1, r.textMeshCacheCapacity)
  # LRU eviction: head.next is the least-recently-used node.
  while r.textMeshCache.len > cacheCapacity:
    let head = r.textMeshLruHead
    if head != nil:
      var oldest = head.next
      oldest.prev.next = oldest.next   # unlink oldest from the ring
      oldest.next.prev = oldest.prev
      r.textMeshCache.del(oldest.key)
  inc r.textMeshCacheTick

func glyphPackingBudgetExhausted(r: FontRender): bool {.inline.} =
  r.glyphPackingBudgetNs > 0 and r.glyphPackingTimeNs >= r.glyphPackingBudgetNs

proc ensureFtPixelSize(r: var FontRender, fontIndex, fontSize: int): bool {.raises: [].} =
  if fontIndex < 0 or fontIndex >= r.fonts.len:
    return false
  if r.fonts[fontIndex].children.len > 0:
    for c in r.fonts[fontIndex].children:
      discard r.ensureFtPixelSize(c, fontSize)
    r.fonts[fontIndex].activePixelSize = fontSize
    return true
  if r.fonts[fontIndex].face == nil:
    return false
  if r.fonts[fontIndex].activePixelSize == fontSize:
    return true
  if FT_Set_Pixel_Sizes(r.fonts[fontIndex].face, fontSize.cuint, fontSize.cuint) != 0:
    return false
  r.fonts[fontIndex].activePixelSize = fontSize
  true

func glyphLoadFlags(font: LoadedFont): FT_Int32 {.inline.} =
  if font.hasColor:
    FT_Int32(FT_LOAD_COLOR)
  else:
    FT_Int32(FT_LOAD_DEFAULT)

proc ftSetupSize(r: var FontRender, fontSize: int) {.raises: [].} =
  for i in 0 ..< r.fonts.len:
    discard r.ensureFtPixelSize(i, fontSize)

proc ftAscentDescent(r: var FontRender, primaryFont: int = 0): tuple[asc: cfloat, desc: cfloat] {.raises: [].} =
  if r.fonts[primaryFont].children.len > 0:
    return r.ftAscentDescent(r.fonts[primaryFont].children[0])
  let faceIdx = if primaryFont >= 0 and primaryFont < r.fonts.len and r.fonts[primaryFont].face != nil: primaryFont else: 0
  if r.fonts.len == 0 or r.fonts[faceIdx].face == nil or r.fonts[faceIdx].face.size == nil:
    return (0, 0)
  let m = r.fonts[faceIdx].face.size.metrics
  return (m.ascender.cfloat / 64.0, m.descender.cfloat / 64.0)

# Returns the index of the first loaded font that can render `codepoint`.
# The requested `primaryFont` is checked first (so it acts as the main font),
# then every other loaded font is used as a fallback. Returns `primaryFont`
# when no font has the glyph (so the main face is still used).
proc resolveFontIndex(r: var FontRender, codepoint: int, sizeIdx: int, primaryFont: int): int {.raises: [].} =
  result = 0
  if r.fonts.len == 0:
    return
  if primaryFont >= 0 and primaryFont < r.fonts.len and r.fonts[primaryFont].face != nil:
    if r.ensureFtPixelSize(primaryFont, sizeIdx):
      if FT_Get_Char_Index(r.fonts[primaryFont].face, codepoint.culong) != 0:
        return primaryFont
  for i in 0 ..< r.fonts.len:
    if i == primaryFont:
      continue
    if r.fonts[i].face == nil:
      continue
    if not r.ensureFtPixelSize(i, sizeIdx):
      continue
    if FT_Get_Char_Index(r.fonts[i].face, codepoint.culong) != 0:
      return i
  if primaryFont >= 0 and primaryFont < r.fonts.len:
    result = primaryFont

when useHarfbuzz:
  proc hbPixelScale(typeface: hb.Typeface, fontSize: float32): float32 {.inline, raises: [].} =
    try:
      let upem = typeface.face.upem
      if upem <= 0:
        return 1.0'f32
      fontSize / upem.float32
    except CatchableError:
      1.0'f32

when useHarfbuzz:
  func isEmojiSequenceCodepoint(cp: uint32): bool {.inline, raises: [].} =
    cp == 0x200D'u32 or  # ZWJ
    cp == 0xFE0F'u32 or  # VS16
    cp == 0x20E3'u32 or  # keycap combining mark
    cp in 0x1F1E6'u32 .. 0x1F1FF'u32 or  # regional indicators
    cp in 0x1F3FB'u32 .. 0x1F3FF'u32 or  # skin tone modifiers
    cp in 0xE0020'u32 .. 0xE007F'u32 or  # tag chars
    cp in 0x1F300'u32 .. 0x1FAFF'u32 or
    cp in 0x2600'u32 .. 0x27BF'u32

  func isEmojiBaseCodepoint(cp: uint32): bool {.inline, raises: [].} =
    cp in 0x1F300'u32 .. 0x1FAFF'u32 or
    cp in 0x2600'u32 .. 0x27BF'u32 or
    cp in 0x1F1E6'u32 .. 0x1F1FF'u32

  func isUnicodeFallbackCodepoint(cp: uint32): bool {.inline, raises: [].} =
    cp > 0x7F'u32 or cp.isEmojiSequenceCodepoint or cp.isEmojiBaseCodepoint

  proc unicodeTypefaceFallback(text: string, run: hb.TextRun, typefaces: seq[hb.Typeface]): int {.nimcall, raises: [].} =
    if typefaces.len <= 1:
      return 0
    if run.byteStart < 0 or run.byteEnd < run.byteStart or run.byteEnd > text.len:
      return 0

    let runText = text[run.byteStart ..< run.byteEnd]
    for rune in runText.runes:
      let cp = rune.uint32
      if not cp.isUnicodeFallbackCodepoint:
        continue

      try:
        if typefaces[0].font.hasGlyph(cp):
          continue
      except CatchableError:
        discard

      for i in 1 ..< typefaces.len:
        try:
          if typefaces[i].font.hasGlyph(cp):
            # echo "HarfBuzz fallback used: selecting typeface index ", i, " text=\"", runText, "\" for U+", cp.toHex
            return i
        except CatchableError:
          discard

    0

proc getPackedGlyphPtr(r: var FontRender, fontIndex: int, glyphIndex: FT_UInt, fontSize, subpixelPhase: int): nil ptr PackedChar {.raises: [].} =
  if fontIndex < 0 or fontIndex >= r.fonts.len:
    return nil
  assert r.fonts[fontIndex].children.len == 0
  if fontSize < 0 or fontSize >= r.fonts[fontIndex].sized.sizedData.len:
    return nil
  let slot = r.fonts[fontIndex].sized.sizedData[fontSize].addr
  let key = glyphCacheKey(glyphIndex, subpixelPhase)
  if not onRaiseQuit(slot.glyphIndexChars.hasKey(key)):
    return nil
  try:
    return slot.glyphIndexChars[key].addr
  except:
    return nil

proc packFtGlyph(r: var FontRender, bm: FT_Bitmap, outX, outY: var int): bool {.raises: [].} =
  let pad: int = 1
  let w = bm.width.int + pad
  let h = bm.rows.int + pad
  if w <= 0 or h <= 0:
    return false
  if w > r.fontAtlasWidth or h > r.fontAtlasHeight:
    r.fontAtlasNeedsResize = r.canGrowFontAtlas()
    r.fontAtlasNeedsReset = r.fontAtlasNeedsResize
    return false
  if r.atlasPackX + w > r.fontAtlasWidth:
    r.atlasPackX = 0
    r.atlasPackY += r.atlasPackRowH + pad
    r.atlasPackRowH = 0
  if r.atlasPackY + h > r.fontAtlasHeight:
    r.fontAtlasNeedsReset = true
    r.fontAtlasNeedsResize = r.canGrowFontAtlas()
    return false
  outX = r.atlasPackX
  outY = r.atlasPackY
  r.atlasPackX += w
  if h > r.atlasPackRowH:
    r.atlasPackRowH = h
  true

proc ftBitmapRgbaAt(bm: FT_Bitmap, x, y: int): array[4, uint8] {.raises: [].} =
  if bm.buffer == nil:
    return [0'u8, 0'u8, 0'u8, 0'u8]
  if x < 0 or x >= bm.width.int or y < 0 or y >= bm.rows.int:
    return [0'u8, 0'u8, 0'u8, 0'u8]

  let src = cast[ptr UncheckedArray[uint8]](bm.buffer)
  let rowOffset = y * bm.pitch.int
  let pixelMode = bm.pixel_mode

  case pixelMode
  of uint8(FT_PIXEL_MODE_GRAY):
    let a = src[rowOffset + x]
    result = [255'u8, 255'u8, 255'u8, a]
  of uint8(FT_PIXEL_MODE_BGRA):
    let b = src[rowOffset + x * 4 + 0]
    let g = src[rowOffset + x * 4 + 1]
    let r = src[rowOffset + x * 4 + 2]
    let a = src[rowOffset + x * 4 + 3]
    result = [r, g, b, a]
  of uint8(FT_PIXEL_MODE_MONO):
    let byteIndex = rowOffset + (x div 8)
    let bit = 7 - (x and 7)
    let byte = src[byteIndex]
    let a = if ((byte shr bit) and 1) != 0: 255'u8 else: 0'u8
    result = [255'u8, 255'u8, 255'u8, a]
  else:
    let a = src[rowOffset + x]
    result = [255'u8, 255'u8, 255'u8, a]

proc blitFtGlyph(r: var FontRender, px, py: int, bm: FT_Bitmap) {.raises: [].} =
  if bm.buffer == nil:
    return
  for row in 0 ..< bm.rows.int:
    for col in 0 ..< bm.width.int:
      let dstIdx = ((py + row) * r.fontAtlasWidth + (px + col)) * 4
      if dstIdx >= 0 and dstIdx + 3 < r.fontAtlasPixels.len:
        let rgba = ftBitmapRgbaAt(bm, col, row)
        r.fontAtlasPixels[dstIdx + 0] = rgba[0]
        r.fontAtlasPixels[dstIdx + 1] = rgba[1]
        r.fontAtlasPixels[dstIdx + 2] = rgba[2]
        r.fontAtlasPixels[dstIdx + 3] = rgba[3]

proc ensureSizedSlot(fd: var FontData, fontSize: int) {.raises: [].} =
  while fd.sizedData.len <= fontSize:
    fd.sizedData.add(FontDataSized())

proc packFontGlyphOnDemand(r: var FontRender, fontIndex: int, glyphIndex: FT_UInt, fontSize, subpixelPhase: int) {.raises: [].} =
  if r.fontAtlasPixels.len == 0:
    return
  if fontIndex < 0 or fontIndex >= r.fonts.len:
    return
  assert r.fonts[fontIndex].children.len == 0
  if r.fonts[fontIndex].face == nil or glyphIndex == 0:
    return

  r.fonts[fontIndex].sized.ensureSizedSlot(fontSize)
  let slot = r.fonts[fontIndex].sized.sizedData[fontSize].addr
  let key = glyphCacheKey(glyphIndex, subpixelPhase)
  if onRaiseQuit(slot.glyphIndexChars.hasKey(key)):
    return
  if r.glyphPackingBudgetExhausted():
    inc r.glyphPackingDeferredCount
    return

  prof("packFontGlyphOnDemand")
  let packingStart = getTicksNS()
  if not r.ensureFtPixelSize(fontIndex, fontSize):
    r.glyphPackingTimeNs += getTicksNS() - packingStart
    return
  let face = r.fonts[fontIndex].face
  var delta = FT_Vector(x: (subpixelPhase * glyphSubpixelStep26Dot6).clong, y: 0)
  FT_Set_Transform(face, nil, delta)

  block:
    discard FT_Load_Glyph(face, glyphIndex, glyphLoadFlags(r.fonts[fontIndex]))
  var pc = PackedChar()
  pc.xadvance = face.glyph.advance.x.cfloat / 64.0
  block:
    prof("FT_Render_Glyph")
    discard FT_Render_Glyph(face.glyph, FT_RENDER_MODE_NORMAL)
  let bm = face.glyph.bitmap
  pc.xoff = face.glyph.bitmap_left.cfloat
  pc.yoff = -face.glyph.bitmap_top.cfloat
  pc.xoff2 = pc.xoff + bm.width.cfloat
  pc.yoff2 = pc.yoff + bm.rows.cfloat
  if bm.width > 0 and bm.rows > 0:
    var ax = 0
    var ay = 0
    if r.packFtGlyph(bm, ax, ay):
      blitFtGlyph(r, ax, ay, bm)
      pc.x0 = ax
      pc.y0 = ay
      pc.x1 = ax + bm.width.int
      pc.y1 = ay + bm.rows.int
      r.markFontAtlasDirty(ax, ay, bm.width.int, bm.rows.int)

  slot.glyphIndexChars[key] = pc

  var resetDelta = FT_Vector()
  FT_Set_Transform(face, nil, resetDelta)
  r.glyphPackingTimeNs += getTicksNS() - packingStart

when useHarfbuzz:
  proc tryBuildArrangementWithHarfBuzz(r: var FontRender, text: string, fontSize: float32, sizeIdx: int, asc: cfloat, desc: cfloat, arrangement: var UiTextArrangement, primaryFont: int, maxWidth: float32 = -1.0'f32): bool {.raises: [].} =
    if r.fonts.len == 0:
      return false

    var typefaces: seq[hb.Typeface] = @[]
    var fontIndices: seq[int] = @[]
    if r.fonts[primaryFont].children.len > 0:
      for i in r.fonts[primaryFont].children:
        if r.fonts[i].hbReady:
          fontIndices.add(i)
    else:
      for i in 0 ..< r.fonts.len:
        if r.fonts[i].hbReady:
          fontIndices.add(i)

      # Move the requested main font to the front so it is the primary typeface;
      # every other font then acts as a (searchable) fallback.
      if primaryFont >= 0 and primaryFont < r.fonts.len and r.fonts[primaryFont].hbReady:
        let pos = fontIndices.find(primaryFont)
        if pos > 0:
          swap(fontIndices[pos], fontIndices[0])
        elif pos < 0:
          fontIndices.insert(primaryFont, 0)

    for fi in fontIndices:
      typefaces.add(r.fonts[fi].hbTypeface)

    if typefaces.len == 0:
      return false

    try:
      let context = hb.initShapeContext(
        typefaces,
        hb.ParagraphOptions(
          flags: {hb.beginningOfText, hb.endOfText},
        ),
        unicodeTypefaceFallback,
      )

      const hbGlyphFlagUnsafeToBreak = 0x00000001'u32

      type HbGlyphPlacement = object
        fi: int
        gi: FT_UInt
        xAdvance: float32
        xOffset: float32
        yOffset: float32
        sourceStart: int
        sourceEnd: int
        flags: uint32

      type HbLineLayout = object
        glyphs: seq[HbGlyphPlacement]
        runes: seq[Rune]
        byteStarts: seq[int]
        byteEnds: seq[int]

      proc decodeLineRunes(lineText: string): tuple[runes: seq[Rune], byteStarts: seq[int], byteEnds: seq[int]] =
        var byteOffset = 0
        for rune in lineText.runes:
          result.runes.add(rune)
          result.byteStarts.add(byteOffset)
          byteOffset += ($rune).len
          result.byteEnds.add(byteOffset)

      proc isCjkLineBreakRune(rune: Rune): bool =
        let cp = rune.uint32
        cp in 0x1100'u32 .. 0x11ff'u32 or cp in 0x2e80'u32 .. 0x30ff'u32 or
          cp in 0x3400'u32 .. 0x4dbf'u32 or cp in 0x4e00'u32 .. 0x9fff'u32 or
          cp in 0xac00'u32 .. 0xd7af'u32 or cp in 0xf900'u32 .. 0xfaff'u32 or
          cp in 0xff65'u32 .. 0xff9f'u32

      proc canBreakAfterRune(rune: Rune): bool =
        if rune.isWhiteSpace:
          return true
        case rune.uint32
        of 0x002d'u32, 0x002f'u32, 0x00ad'u32, 0x058a'u32, 0x05be'u32, 0x1400'u32,
            0x1806'u32, 0x200b'u32, 0x2053'u32, 0x207b'u32, 0x208b'u32, 0x2212'u32,
            0x2e17'u32, 0x2e1a'u32, 0x301c'u32, 0x3030'u32, 0x30a0'u32, 0xfe58'u32,
            0xfe63'u32, 0xff0d'u32:
          true
        of 0x2010'u32 .. 0x2015'u32, 0xfe31'u32 .. 0xfe32'u32:
          true
        else:
          false

      proc nextClusterBoundary(run: hb.ShapedRun, cluster: int): int =
        result = run.textRun.byteEnd
        for shapedGlyph in run.glyphRun.glyphs:
          let glyphCluster = int(shapedGlyph.cluster)
          if glyphCluster > cluster and glyphCluster < result:
            result = glyphCluster

      proc firstRuneIndexInRange(layout: HbLineLayout, startByte, endByte: int): int =
        for i in 0 ..< layout.byteStarts.len:
          if layout.byteEnds[i] > startByte and layout.byteStarts[i] < endByte:
            return i
        return -1

      proc lastRuneIndexInRange(layout: HbLineLayout, startByte, endByte: int): int =
        var i = layout.byteStarts.len - 1
        while i >= 0:
          if layout.byteEnds[i] > startByte and layout.byteStarts[i] < endByte:
            return i
          dec i
        return -1

      proc sourceIsWhitespace(layout: HbLineLayout, startByte, endByte: int): bool =
        let first = firstRuneIndexInRange(layout, startByte, endByte)
        if first < 0:
          return false
        let last = lastRuneIndexInRange(layout, startByte, endByte)
        if last < first:
          return false
        for i in first .. last:
          if not layout.runes[i].isWhiteSpace:
            return false
        true

      proc preferredBreakAfter(layout: HbLineLayout, glyphIndex: int): bool =
        if glyphIndex < 0 or glyphIndex >= layout.glyphs.len:
          return false
        let glyph = layout.glyphs[glyphIndex]
        if layout.sourceIsWhitespace(glyph.sourceStart, glyph.sourceEnd):
          return true

        let lastIdx = lastRuneIndexInRange(layout, glyph.sourceStart, glyph.sourceEnd)
        if lastIdx >= 0:
          let lastRune = layout.runes[lastIdx]
          if canBreakAfterRune(lastRune):
            return true
          if glyphIndex + 1 < layout.glyphs.len:
            let nextGlyph = layout.glyphs[glyphIndex + 1]
            if glyph.sourceEnd == nextGlyph.sourceStart:
              let nextIdx = firstRuneIndexInRange(layout, nextGlyph.sourceStart, nextGlyph.sourceEnd)
              if nextIdx >= 0:
                let nextRune = layout.runes[nextIdx]
                if isCjkLineBreakRune(lastRune) and isCjkLineBreakRune(nextRune):
                  return true
        false

      proc shapeLine(lineText: string): HbLineLayout =
        let decoded = decodeLineRunes(lineText)
        result.runes = decoded.runes
        result.byteStarts = decoded.byteStarts
        result.byteEnds = decoded.byteEnds

        let paragraph = hb.shapeParagraph(context, lineText)
        for run in paragraph.visualRuns:
          if run.typefaceIndex < 0 or run.typefaceIndex >= fontIndices.len:
            continue

          let fi = fontIndices[run.typefaceIndex]
          let scale = hbPixelScale(typefaces[run.typefaceIndex], fontSize)
          for glyph in run.glyphRun.glyphs:
            let cluster = int(glyph.cluster)
            let nextCluster = nextClusterBoundary(run, cluster)
            result.glyphs.add HbGlyphPlacement(
              fi: fi,
              gi: FT_UInt(glyph.codepoint),
              xAdvance: glyph.xAdvance.float32 * scale,
              xOffset: glyph.xOffset.float32 * scale,
              yOffset: -glyph.yOffset.float32 * scale,
              sourceStart: cluster,
              sourceEnd: nextCluster,
              flags: glyph.flags,
            )

      proc buildWrappedLines(layout: HbLineLayout, boxWidth: float32): seq[Slice[int]] =
        if layout.glyphs.len == 0:
          return
        if boxWidth <= 0.0'f32:
          result.add 0 .. layout.glyphs.high
          return

        var lineStart = 0
        var lineWidth = 0.0'f32
        var lastBreak = -1
        var lastSafeBreak = -1
        var glyphIndex = 0

        while glyphIndex < layout.glyphs.len:
          let width = abs(layout.glyphs[glyphIndex].xAdvance)
          if glyphIndex > lineStart and lineWidth + width > boxWidth:
            let breakIndex =
              if lastBreak >= lineStart and lastBreak < glyphIndex:
                lastBreak
              elif lastSafeBreak >= lineStart and lastSafeBreak < glyphIndex:
                lastSafeBreak
              else:
                glyphIndex - 1

            result.add lineStart .. breakIndex
            lineStart = breakIndex + 1
            lineWidth = 0.0'f32
            lastBreak = -1
            lastSafeBreak = -1
            glyphIndex = lineStart
            continue

          lineWidth += width
          let nextGlyphUnsafeToBreak =
            glyphIndex + 1 < layout.glyphs.len and
            (layout.glyphs[glyphIndex + 1].flags and hbGlyphFlagUnsafeToBreak) != 0'u32
          let breakAfter = not nextGlyphUnsafeToBreak
          let preferredBreak = layout.preferredBreakAfter(glyphIndex)
          let clusterBoundary =
            glyphIndex == layout.glyphs.high or
            layout.glyphs[glyphIndex].sourceStart != layout.glyphs[glyphIndex + 1].sourceStart or
            layout.glyphs[glyphIndex].sourceEnd != layout.glyphs[glyphIndex + 1].sourceEnd

          if breakAfter and clusterBoundary:
            lastSafeBreak = glyphIndex
          if preferredBreak and breakAfter and clusterBoundary:
            lastBreak = glyphIndex
          inc glyphIndex

        if lineStart <= layout.glyphs.high:
          result.add lineStart .. layout.glyphs.high

      var inputLines = text.splitLines()
      if inputLines.len == 0:
        inputLines.add("")

      var lineY: float32 = 0.0'f32
      var maxLineWidth: float32 = 0.0'f32
      let lineHeight = (asc - desc).float32

      for rawLine in inputLines:
        let layout = shapeLine(rawLine)
        let wrapped = layout.buildWrappedLines(maxWidth)

        if wrapped.len == 0:
          lineY += lineHeight
          continue

        for line in wrapped:
          var penX: float32 = 0.0'f32
          for glyphIndex in line:
            let glyph = layout.glyphs[glyphIndex]
            if glyph.gi != 0:
              arrangement.glyphs.add UiTextArrangementGlyph(
                fontIndex: glyph.fi.int32,
                glyphIndex: glyph.gi.uint32,
                pos: vec2(penX + glyph.xOffset, lineY + asc.float32 + glyph.yOffset),
              )
            penX += glyph.xAdvance

          if penX > maxLineWidth:
            maxLineWidth = penX
          lineY += lineHeight

      arrangement.size = vec2(max(0.0'f32, maxLineWidth), max(1.0'f32, lineY))
      arrangement.contentHash = arrangement.glyphs.hash
      return true
    except Exception:
      echo "HarfBuzz shaping failed: ", getCurrentExceptionMsg(), " (textLen=", text.len, ", fontSize=", fontSize, ")"
      return false

proc ftGlyphAdvanceCached(r: var FontRender, fontIndex: int, glyphIndex: FT_UInt, sizeIdx: int): cfloat {.raises: [].} =
  let key = (fontIndex, sizeIdx, glyphIndex)
  if onRaiseQuit(r.glyphAdvanceCache.hasKey(key)):
    try:
      return r.glyphAdvanceCache[key]
    except:
      discard
  let face = r.fonts[fontIndex].face
  block:
    discard FT_Load_Glyph(face, glyphIndex, glyphLoadFlags(r.fonts[fontIndex]))
  let adv = face.glyph.advance.x.cfloat / 64.0
  try:
    r.glyphAdvanceCache[key] = adv
  except:
    discard
  adv

proc measureTextWidthLegacy(r: var FontRender, text: string, fontSize: float32, sizeIdx: int, primaryFont: int): float32 {.raises: [].} =
  prof("measureTextWidthLegacy")
  var widthAcc: cfloat = 0
  var prevGi: FT_UInt = 0
  var prevFi: int = 0
  for ch in text.runes:
    let codepoint = ch.int
    if codepoint < 0:
      prevGi = 0
      prevFi = 0
      continue
    let fi = r.resolveFontIndex(codepoint, sizeIdx, primaryFont)
    if fi < 0 or fi >= r.fonts.len or r.fonts[fi].face == nil:
      prevGi = 0
      prevFi = 0
      continue
    let face = r.fonts[fi].face
    let gi = FT_Get_Char_Index(face, codepoint.culong)
    if gi != 0:
      widthAcc += r.ftGlyphAdvanceCached(fi, gi, sizeIdx)
      if prevGi != 0 and prevFi == fi:
        var kern = FT_Vector()
        discard FT_Get_Kerning(face, prevGi, gi, FT_UInt(0), kern)
        widthAcc += kern.x.cfloat / 64.0
    prevGi = gi
    prevFi = fi
  widthAcc.float32

proc buildArrangementGlyphsAt(r: var FontRender, text: openArray[char], sizeIdx: int, asc: cfloat, offsetX, offsetY: cfloat, result: var UiTextArrangement, primaryFont: int) {.raises: [].} =
  prof("buildArrangementGlyphsAt")
  var xpos: cfloat = offsetX
  var prevGi: FT_UInt = 0
  var prevFi = -1
  for ch in text.runes:
    let codepoint = ch.int
    if codepoint < 0:
      prevGi = 0
      prevFi = -1
      continue
    let fi = r.resolveFontIndex(codepoint, sizeIdx, primaryFont)
    if fi < 0 or fi >= r.fonts.len or r.fonts[fi].face == nil:
      prevGi = 0
      prevFi = -1
      continue
    let face = r.fonts[fi].face
    let gi = FT_Get_Char_Index(face, codepoint.culong)
    if gi == 0:
      prevGi = 0
      prevFi = -1
      continue
    if prevGi != 0 and prevFi == fi:
      var kern = FT_Vector()
      discard FT_Get_Kerning(face, prevGi, gi, FT_UInt(0), kern)
      xpos += kern.x.cfloat / 64.0
    result.glyphs.add UiTextArrangementGlyph(
      fontIndex: fi.int32,
      glyphIndex: gi.uint32,
      pos: vec2(xpos.float32, (asc + offsetY).float32),
    )
    xpos += r.ftGlyphAdvanceCached(fi, gi, sizeIdx)
    prevGi = gi
    prevFi = fi

proc buildArrangementLegacy(r: var FontRender, text: string, sizeIdx: int,
    asc, desc: cfloat, maxWidth: float32, arrangement: var UiTextArrangement,
    primaryFont: int) {.raises: [].} =
  type LegacyGlyph = object
    rune: Rune
    fontIndex: int
    glyphIndex: FT_UInt
    advance: cfloat

  proc canBreakAfter(rune: Rune): bool {.inline.} =
    if rune.isWhiteSpace:
      return true
    case rune.uint32
    of 0x002d'u32, 0x002f'u32, 0x00ad'u32, 0x058a'u32, 0x05be'u32, 0x1400'u32,
        0x1806'u32, 0x200b'u32, 0x2053'u32, 0x207b'u32, 0x208b'u32, 0x2212'u32,
        0x2e17'u32, 0x2e1a'u32, 0x301c'u32, 0x3030'u32, 0x30a0'u32, 0xfe58'u32,
        0xfe63'u32, 0xff0d'u32:
      true
    of 0x2010'u32 .. 0x2015'u32, 0xfe31'u32 .. 0xfe32'u32:
      true
    else:
      false

  proc isCjk(rune: Rune): bool {.inline.} =
    let codepoint = rune.uint32
    codepoint in 0x1100'u32 .. 0x11ff'u32 or codepoint in 0x2e80'u32 .. 0x30ff'u32 or
      codepoint in 0x3400'u32 .. 0x4dbf'u32 or codepoint in 0x4e00'u32 .. 0x9fff'u32 or
      codepoint in 0xac00'u32 .. 0xd7af'u32 or codepoint in 0xf900'u32 .. 0xfaff'u32 or
      codepoint in 0xff65'u32 .. 0xff9f'u32

  proc kerning(renderer: var FontRender, left, right: LegacyGlyph): cfloat {.inline.} =
    if left.glyphIndex == 0 or right.glyphIndex == 0 or
        left.fontIndex != right.fontIndex:
      return 0
    var kern = FT_Vector()
    discard FT_Get_Kerning(renderer.fonts[right.fontIndex].face, left.glyphIndex,
      right.glyphIndex, FT_UInt(0), kern)
    kern.x.cfloat / 64.0

  proc emitLine(renderer: var FontRender, glyphs: seq[LegacyGlyph], first, last: int,
      baselineY: cfloat, output: var UiTextArrangement): cfloat =
    var penX: cfloat = 0
    var previous = LegacyGlyph(fontIndex: -1)
    for glyphIndex in first .. last:
      let glyph = glyphs[glyphIndex]
      penX += kerning(renderer, previous, glyph)
      if glyph.glyphIndex != 0:
        output.glyphs.add UiTextArrangementGlyph(
          fontIndex: glyph.fontIndex.int32,
          glyphIndex: glyph.glyphIndex.uint32,
          pos: vec2(penX.float32, baselineY.float32),
        )
        penX += glyph.advance
      previous = glyph
    penX

  assert maxWidth == maxWidth, "legacy text maxWidth must not be NaN"
  let lineHeight = asc - desc
  var lineY: cfloat = 0
  var maxLineWidth: cfloat = 0
  var hasOverwideGlyphLine = false
  var inputLines = text.splitLines()
  if inputLines.len == 0:
    inputLines.add("")

  for rawLine in inputLines:
    var glyphs: seq[LegacyGlyph] = @[]
    for rune in rawLine.runes:
      let fontIndex = r.resolveFontIndex(rune.int, sizeIdx, primaryFont)
      var glyphIndex: FT_UInt = 0
      if fontIndex >= 0 and fontIndex < r.fonts.len and r.fonts[fontIndex].face != nil:
        glyphIndex = FT_Get_Char_Index(r.fonts[fontIndex].face, rune.int.culong)
      let advance =
        if glyphIndex != 0:
          r.ftGlyphAdvanceCached(fontIndex, glyphIndex, sizeIdx)
        else:
          0
      glyphs.add LegacyGlyph(
        rune: rune,
        fontIndex: fontIndex,
        glyphIndex: glyphIndex,
        advance: advance,
      )

    if glyphs.len == 0:
      lineY += lineHeight
      continue

    var lineStart = 0
    while lineStart < glyphs.len:
      var lineEnd = lineStart
      var lineWidth: cfloat = 0
      var lastBreak = -1
      var previous = LegacyGlyph(fontIndex: -1)

      while lineEnd < glyphs.len:
        let glyph = glyphs[lineEnd]
        let nextWidth = lineWidth + kerning(r, previous, glyph) + glyph.advance
        if maxWidth > 0.0'f32 and lineEnd > lineStart and nextWidth > maxWidth:
          break
        lineWidth = nextWidth
        if canBreakAfter(glyph.rune) or
            (lineEnd + 1 < glyphs.len and isCjk(glyph.rune) and isCjk(glyphs[lineEnd + 1].rune)):
          lastBreak = lineEnd
        previous = glyph
        inc lineEnd

      var nextLineStart = lineEnd
      if lineEnd < glyphs.len:
        if lastBreak >= lineStart:
          assert lastBreak < lineEnd, "legacy text break must be inside the measured line"
          if glyphs[lastBreak].rune.isWhiteSpace and lastBreak > lineStart:
            lineEnd = lastBreak
          else:
            lineEnd = lastBreak + 1
          nextLineStart = lastBreak + 1
        elif lineEnd > lineStart and glyphs[lineEnd].rune.isWhiteSpace:
          nextLineStart = lineEnd + 1
        elif lineEnd == lineStart:
          inc lineEnd
          nextLineStart = lineEnd

        while nextLineStart < glyphs.len and glyphs[nextLineStart].rune.isWhiteSpace:
          inc nextLineStart

      assert lineEnd > lineStart and lineEnd <= glyphs.len,
        "legacy text wrapping must emit a non-empty in-bounds line"
      assert nextLineStart >= lineEnd and nextLineStart <= glyphs.len,
        "legacy text continuation must advance past the emitted line"
      let width = emitLine(r, glyphs, lineStart, lineEnd - 1, lineY + asc, arrangement)
      let singleOverwideGlyph =
        lineEnd == lineStart + 1 and glyphs[lineStart].advance > maxWidth
      hasOverwideGlyphLine = hasOverwideGlyphLine or singleOverwideGlyph
      assert maxWidth <= 0.0'f32 or width <= maxWidth + 0.01'f32 or singleOverwideGlyph,
        "legacy text line exceeds maxWidth without an overwide glyph"
      maxLineWidth = max(maxLineWidth, width)
      lineY += lineHeight
      lineStart = nextLineStart

  arrangement.size = vec2(max(0.0'f32, maxLineWidth.float32), max(1.0'f32, lineY.float32))
  assert maxWidth <= 0.0'f32 or arrangement.size.x <= maxWidth + 0.01'f32 or
    hasOverwideGlyphLine,
    "legacy text arrangement width must reflect its emitted lines"
  arrangement.contentHash = arrangement.glyphs.hash

proc mixTextMeshHash(state: var uint64, value: uint64) {.inline, raises: [].} =
  state = (state xor value) * 1099511628211'u64

proc mixTextMeshHash(state: var uint64, value: float32) {.inline, raises: [].} =
  state.mixTextMeshHash(cast[uint32](value).uint64)

proc textMeshFlagsBits(flags: FontRenderFlags): uint64 {.inline, raises: [].} =
  result = 0
  if FontRenderFlag.SubpixelPhasing in flags:
    result = result or 1'u64
  if FontRenderFlag.PixelSnapping in flags:
    result = result or 2'u64

proc textMeshCacheKey(arrangement: UiTextArrangement, pos, screenOffset: Vec2,
    color: FColor, transform: UiAffine2, flags: FontRenderFlags): uint64 {.raises: [].} =
  result = 14695981039346656037'u64
  result.mixTextMeshHash(arrangement.fontSize)
  result.mixTextMeshHash(arrangement.contentHash.uint64)
  result.mixTextMeshHash(pos.x)
  result.mixTextMeshHash(pos.y)
  result.mixTextMeshHash(screenOffset.x)
  result.mixTextMeshHash(screenOffset.y)
  result.mixTextMeshHash(color.r)
  result.mixTextMeshHash(color.g)
  result.mixTextMeshHash(color.b)
  result.mixTextMeshHash(color.a)
  result.mixTextMeshHash(transform.m00)
  result.mixTextMeshHash(transform.m01)
  result.mixTextMeshHash(transform.m10)
  result.mixTextMeshHash(transform.m11)
  result.mixTextMeshHash(transform.tx)
  result.mixTextMeshHash(transform.ty)
  result.mixTextMeshHash(flags.textMeshFlagsBits)
  result.mixTextMeshHash(arrangement.glyphs.len.uint64)

proc cachedTextMesh(r: var FontRender, key: uint64, arrangement: UiTextArrangement,
    pos, screenOffset: Vec2, color: FColor, transform: UiAffine2): TextMesh {.raises: [].} =
  prof("cachedTextMesh")
  result = TextMesh()
  if r.textMeshCache.hasKey(key):
    let entry = r.textMeshCache.getOrQuit(key)
    if entry.complete or entry.lastUsedTick == r.textMeshCacheTick:
      entry.lastUsedTick = r.textMeshCacheTick
      # Move-to-front: unlink entry, then reinsert it right after head
      # (head = MRU, so the touched entry becomes the new MRU).
      if entry != r.textMeshLruHead:
        let head = r.textMeshLruHead
        if head != nil:
          entry.next.prev = entry.prev
          entry.prev.next = entry.next
          entry.next = head.next
          entry.prev = head
          head.next.prev = entry
          head.next = entry
          r.textMeshLruHead = entry
      if entry.vertices.len > 0:
        result.data = cast[ptr UncheckedArray[TextMeshVertex]](entry.vertices[0].addr)
        result.count = entry.vertices.len
      else:
        result.data = nil
        result.count = 0

proc storeTextMesh(r: var FontRender, key: uint64, arrangement: UiTextArrangement,
    pos, screenOffset: Vec2, color: FColor, transform: UiAffine2,
    vertices: seq[TextMeshVertex], complete: bool): TextMesh {.raises: [].} =
  prof("storeTextMesh")
  result = TextMesh()

  var entry = TextMeshCacheEntry(
    key: key,
    arrangement: arrangement,
    pos: pos,
    screenOffset: screenOffset,
    color: color,
    transform: transform,
    flags: r.flags,
    vertices: vertices,
    lastUsedTick: r.textMeshCacheTick,
    complete: complete,
  )
  r.textMeshCache[key] = entry

  # Insert new entry as the MRU: link it between head and head.next.
  let head = r.textMeshLruHead
  if head == nil:
    entry.next = entry
    entry.prev = entry
    r.textMeshLruHead = entry
  else:
    entry.next = head.next
    entry.prev = head
    head.next.prev = entry
    head.next = entry
    r.textMeshLruHead = entry

  if entry.vertices.len > 0:
    result.data = cast[ptr UncheckedArray[TextMeshVertex]](
      entry.vertices[0].addr)
    result.count = entry.vertices.len

proc buildTextMesh*(r: var FontRender, arrangement: UiTextArrangement,
  pos, screenOffset: Vec2, color: FColor, transform: UiAffine2): TextMesh {.raises: [].} =
  if arrangement.glyphs.len == 0:
    return TextMesh()

  let cacheKey = textMeshCacheKey(arrangement, pos, screenOffset, color, transform, r.flags)
  result = r.cachedTextMesh(cacheKey, arrangement, pos, screenOffset, color, transform)
  if result.data != nil:
    return

  prof("buildTextMesh")
  var vertices = newSeq[TextMeshVertex](arrangement.glyphs.len * 6)
  let ipw = 1.0'f32 / r.fontAtlasWidth.float32
  let iph = 1.0'f32 / r.fontAtlasHeight.float32
  var vertexIndex = 0
  var complete = true

  template emitGlyph(packed: ptr PackedChar, x0, y0: float32) =
    let x1 = x0 + (packed.xoff2 - packed.xoff)
    let y1 = y0 + (packed.yoff2 - packed.yoff)
    let uv0 = vec2(packed.x0.float32 * ipw, packed.y0.float32 * iph)
    let uv1 = vec2(packed.x1.float32 * ipw, packed.y1.float32 * iph)

    let p0 = transform * vec2(x0, y0)
    let p1 = transform * vec2(x1, y0)
    let p2 = transform * vec2(x1, y1)
    let p3 = transform * vec2(x0, y1)

    vertices[vertexIndex + 0] = TextMeshVertex(pos: p0, uv: vec2(uv0.x, uv0.y), color: color)
    vertices[vertexIndex + 1] = TextMeshVertex(pos: p1, uv: vec2(uv1.x, uv0.y), color: color)
    vertices[vertexIndex + 2] = TextMeshVertex(pos: p2, uv: vec2(uv1.x, uv1.y), color: color)
    vertices[vertexIndex + 3] = TextMeshVertex(pos: p0, uv: vec2(uv0.x, uv0.y), color: color)
    vertices[vertexIndex + 4] = TextMeshVertex(pos: p2, uv: vec2(uv1.x, uv1.y), color: color)
    vertices[vertexIndex + 5] = TextMeshVertex(pos: p3, uv: vec2(uv0.x, uv1.y), color: color)
    vertexIndex += 6

  if FontRenderFlag.SubpixelPhasing in r.flags:
    for glyph in arrangement.glyphs:
      let fontIndex = glyph.fontIndex.int
      let glyphIndex = FT_UInt(glyph.glyphIndex)
      let targetQuarterX = round((pos.x + glyph.pos.x + screenOffset.x) * glyphSubpixelPhases.float32).int
      let integerPenX = floor(targetQuarterX.float32 / glyphSubpixelPhases.float32).int
      let subpixelPhase = targetQuarterX - integerPenX * glyphSubpixelPhases
      r.packFontGlyphOnDemand(fontIndex, glyphIndex, arrangement.fontSize.int, subpixelPhase)
      let packed = r.getPackedGlyphPtr(fontIndex, glyphIndex, arrangement.fontSize.int, subpixelPhase)
      if packed == nil:
        complete = false
        continue
      if packed.x0 == packed.x1 or packed.y0 == packed.y1:
        continue

      let x0 = integerPenX.float32 - screenOffset.x + packed.xoff
      let y0 = round(pos.y + glyph.pos.y + screenOffset.y + packed.yoff) - screenOffset.y
      emitGlyph(packed, x0, y0)

  elif FontRenderFlag.PixelSnapping in r.flags:
    for glyph in arrangement.glyphs:
      let fontIndex = glyph.fontIndex.int
      let glyphIndex = FT_UInt(glyph.glyphIndex)
      r.packFontGlyphOnDemand(fontIndex, glyphIndex, arrangement.fontSize.int, 0)
      let packed = r.getPackedGlyphPtr(fontIndex, glyphIndex, arrangement.fontSize.int, 0)
      if packed == nil:
        complete = false
        continue
      if packed.x0 == packed.x1 or packed.y0 == packed.y1:
        continue

      let x0 = round(pos.x + glyph.pos.x + screenOffset.x + packed.xoff) - screenOffset.x
      let y0 = round(pos.y + glyph.pos.y + screenOffset.y + packed.yoff) - screenOffset.y
      emitGlyph(packed, x0, y0)

  else:
    for glyph in arrangement.glyphs:
      let fontIndex = glyph.fontIndex.int
      let glyphIndex = FT_UInt(glyph.glyphIndex)
      r.packFontGlyphOnDemand(fontIndex, glyphIndex, arrangement.fontSize.int, 0)
      let packed = r.getPackedGlyphPtr(fontIndex, glyphIndex, arrangement.fontSize.int, 0)
      if packed == nil:
        complete = false
        continue
      if packed.x0 == packed.x1 or packed.y0 == packed.y1:
        continue

      let x0 = pos.x + glyph.pos.x + packed.xoff
      let y0 = pos.y + glyph.pos.y + packed.yoff
      emitGlyph(packed, x0, y0)

  vertices.setLen(vertexIndex)
  result = r.storeTextMesh(cacheKey, arrangement, pos, screenOffset, color, transform,
    vertices, complete)

proc arrangeText*(r: var FontRender, text: openArray[char], fontSize: float32, fontId: FontId, maxWidth: float32 = -1.0'f32): UiTextArrangement {.raises: [].} =
  prof("arrangeText")
  result = UiTextArrangement(
    fontSize: fontSize,
  )

  if r.fonts.len == 0:
    return

  let primaryFont = if fontId.int >= 0 and fontId.int < r.fonts.len: fontId.int else: 0

  let sizeIdx = fontSize.int
  r.ftSetupSize(sizeIdx)
  let (asc, desc) = r.ftAscentDescent(primaryFont)
  result.ascent = asc.float32
  result.descent = desc.float32
  result.size.y = (asc - desc).float32

  let textString = newStringOfCap(text.len)
  var textOwned = textString
  for ch in text:
    textOwned.add(ch)

  when useHarfbuzz:
    if r.tryBuildArrangementWithHarfBuzz(textOwned, fontSize, sizeIdx, asc, desc, result, primaryFont, maxWidth):
      return

  r.buildArrangementLegacy(textOwned, sizeIdx, asc, desc, maxWidth, result, primaryFont)

proc addFontFace*(r: var FontRender, name: string, content: string): FontId {.raises: [].} =
  if cast[pointer](r.fontLibrary) == nil:
    return -1

  if content.len == 0:
    echo "Empty font content"
    return -1

  var entry = LoadedFont()
  entry.name = name
  entry.data.setLen(content.len)
  if content.len > 0:
    copyMem(entry.data[0].addr, readRawData(content), content.len)

  if FT_New_Memory_Face(r.fontLibrary, cast[cstring](entry.data[0].addr), entry.data.len.clong, 0, entry.face) != 0:
    echo "Failed to initialize font face: ", name
    return -1

  entry.activePixelSize = -1
  entry.hasColor = entry.face.hasColor

  when useHarfbuzz:
    entry.hbReady = false
    try:
      let hbBlob = hb.initBlob(entry.data)
      let hbFace = hb.initFace(hbBlob, 0)
      entry.hbTypeface = hb.initTypeface(hbFace)
      entry.hbReady = not hb.isNil(entry.hbTypeface.font)
    except CatchableError:
      entry.hbReady = false
      echo "HarfBuzz init failed for font: ", name, " - ", getCurrentExceptionMsg()

  r.fonts.add(entry)
  echo "Loaded font: ", name
  r.fonts.high.FontId

proc addFontFace*(r: var FontRender, path: string): FontId {.raises: [].} =
  if cast[pointer](r.fontLibrary) == nil:
    return -1
  if not fileExists(path):
    echo "Font file not found: ", path
    return -1

  try:
    let content = readFile(path)
    return r.addFontFace(splitFile(path).name, content)
  except:
    echo "Failed to read font file: ", path
    return -1

proc listFontFaces*(r: FontRender): seq[(string, FontId)] {.raises: [], gcsafe.} =
  result = @[]
  for i in 0 ..< r.fonts.len:
    if r.fonts[i].name != "":
      result.add((r.fonts[i].name, FontId(i)))

proc addFontGroup*(r: var FontRender, fonts: seq[FontId]): FontId {.raises: [].} =
  assert fonts.len > 0
  r.fonts.add(LoadedFont(children: fonts))
  r.fonts.high.FontId

proc resetFontAtlas*(r: var FontRender, grow: bool) {.raises: [].} =
  if not r.fontAtlasNeedsReset:
    return

  if grow and r.canGrowFontAtlas():
    let nextSize = r.nextFontAtlasSize()
    r.fontAtlasWidth = nextSize.width
    r.fontAtlasHeight = nextSize.height
  r.fontAtlasPixels = newSeq[uint8](r.fontAtlasWidth * r.fontAtlasHeight * 4)
  r.atlasPackX = 0
  r.atlasPackY = 0
  r.atlasPackRowH = 0
  r.markFullFontAtlasDirty()
  r.fontAtlasNeedsReset = false
  r.fontAtlasNeedsResize = false

  for fontIndex in 0 ..< r.fonts.len:
    r.fonts[fontIndex].sized = FontData()
  r.textMeshCache.clear()
  r.textMeshLruHead = nil   # drop the LRU ring so it can't dangle into stale nodes

proc init*(r: var FontRender, flags: FontRenderFlags = {
  FontRenderFlag.SubpixelPhasing, FontRenderFlag.PixelSnapping},
  maxFontAtlasSize: int = defaultMaxFontAtlasSize,
  glyphPackingBudgetNs: uint64 = defaultGlyphPackingBudgetNs): bool =
  prof("initFontRenderer")
  r.flags = flags
  r.glyphPackingBudgetNs = glyphPackingBudgetNs
  r.textMeshCacheCapacity = defaultTextMeshCacheCapacity
  r.beginFontRenderFrame()

  r.maxFontAtlasSize = max(1, maxFontAtlasSize)
  r.fontAtlasWidth = min(defaultFontAtlasSize, r.maxFontAtlasSize)
  r.fontAtlasHeight = min(defaultFontAtlasSize, r.maxFontAtlasSize)

  r.fontAtlasPixels = newSeq[uint8](r.fontAtlasWidth * r.fontAtlasHeight * 4)
  r.markFullFontAtlasDirty()
  r.fontAtlasNeedsReset = false
  r.fontAtlasNeedsResize = false
  r.atlasPackX = 0
  r.atlasPackY = 0
  r.atlasPackRowH = 0

  if FT_Init_FreeType(r.fontLibrary) != 0:
    echo "Failed to initialize FreeType library"
    return false

  echo "Initialized font render"

  return true

proc addSystemDefaultFonts*(r: var FontRender): bool =
  # todo: other platforms (Linux, macOS, Android, iOS)
  let fonts = @[
    "C:/WINDOWS/Fonts/verdana.ttf",
    "C:/WINDOWS/Fonts/seguiemj.ttf",          # Segoe UI Emoji
    "C:/WINDOWS/Fonts/seguisym.ttf",          # Segoe UI Symbol
    "C:/WINDOWS/Fonts/seguihis.ttf",          # Segoe UI Historic
    "C:/WINDOWS/Fonts/arial.ttf",             # Arial
    "C:/WINDOWS/Fonts/leelawui.ttf",           # Thai: Leelawadee UI
    "C:/WINDOWS/Fonts/malgun.ttf",             # Korean: Malgun Gothic
    "C:/WINDOWS/Fonts/malgunsl.ttf",           # Korean: Malgun Gothic Slim
    "C:/WINDOWS/Fonts/msyh.ttc",               # Microsoft YaHei
    "C:/WINDOWS/Fonts/simsun.ttc",             # SimSun
    "C:/WINDOWS/Fonts/Nirmala.ttf",            # Nirmala
    "C:/WINDOWS/Fonts/NirmalaB.ttf",           # Nirmala Bold
  ]
  for font in fonts:
    discard r.addFontFace(font)

  return r.fonts.len > 0

proc deinit*(r: var FontRender) =
  for i in 0 ..< r.fonts.len:
    if r.fonts[i].face != nil:
      discard FT_Done_Face(r.fonts[i].face)
      r.fonts[i].face = nil
  if cast[pointer](r.fontLibrary) != nil:
    discard FT_Done_FreeType(r.fontLibrary)
    r.fontLibrary = FT_Library(nil)
  r.fonts.setLen(0)

  r.fontAtlasPixels.setLen(0)
  r.textMeshCache.clear()
  r.textMeshLruHead = nil
  r.glyphAdvanceCache.clear()
  r.clearFontAtlasDirty()
