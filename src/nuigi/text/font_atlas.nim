## Allocation and bookkeeping for the rasterized glyph atlas.
##
## `FontAtlas` tracks packed glyph rectangles by font and integer size, grows
## up to a configured maximum, and records dirty bounds for partial GPU
## uploads. Packing and rasterization are performed by `text/fonts`; this
## module only owns atlas placement, cache records, and reset/resize state.

import std/tables
include nuigi/util/compat2

const
  defaultFontAtlasSize* = 2048
  defaultMaxFontAtlasSize* = 8192

type
  PackedChar* = object
    x0*, y0*, x1*, y1*: int       # atlas rect (pixels)
    xoff*, yoff*, xadvance*: cfloat
    xoff2*, yoff2*: cfloat

  FontDataSized = object
    glyphIndexChars: Table[uint64, PackedChar] # Glyph index and horizontal raster phase cache

  FontData* = object
    sizedData: seq[FontDataSized] # One per integer font size, slots maybe empty

  FontAtlas* = object
    width*: int
    height*: int
    maxSize*: int
    packX*: int
    packY*: int
    packRowH*: int
    needsReset*: bool
    needsResize*: bool
    dirty*: bool
    dirtyMinX*: int
    dirtyMinY*: int
    dirtyMaxX*: int
    dirtyMaxY*: int
    sized*: seq[FontData]

proc initFontAtlas*(atlas: var FontAtlas, maxFontAtlasSize: int = defaultMaxFontAtlasSize) {.raises: [].} =
  atlas.maxSize = max(1, maxFontAtlasSize)
  atlas.width = min(defaultFontAtlasSize, atlas.maxSize)
  atlas.height = min(defaultFontAtlasSize, atlas.maxSize)
  atlas.packX = 0
  atlas.packY = 0
  atlas.packRowH = 0
  atlas.needsReset = false
  atlas.needsResize = false
  atlas.dirty = false
  atlas.dirtyMinX = 0
  atlas.dirtyMinY = 0
  atlas.dirtyMaxX = 0
  atlas.dirtyMaxY = 0
  atlas.sized.setLen(0)

proc markFontAtlasDirty*(atlas: var FontAtlas, x, y, w, h: int) {.raises: [].} =
  if w <= 0 or h <= 0:
    return
  let minX = clamp(x, 0, atlas.width)
  let minY = clamp(y, 0, atlas.height)
  let maxX = clamp(x + w, 0, atlas.width)
  let maxY = clamp(y + h, 0, atlas.height)
  if minX >= maxX or minY >= maxY:
    return

  if not atlas.dirty:
    atlas.dirtyMinX = minX
    atlas.dirtyMinY = minY
    atlas.dirtyMaxX = maxX
    atlas.dirtyMaxY = maxY
    atlas.dirty = true
  else:
    atlas.dirtyMinX = min(atlas.dirtyMinX, minX)
    atlas.dirtyMinY = min(atlas.dirtyMinY, minY)
    atlas.dirtyMaxX = max(atlas.dirtyMaxX, maxX)
    atlas.dirtyMaxY = max(atlas.dirtyMaxY, maxY)

proc markFullFontAtlasDirty*(atlas: var FontAtlas) {.raises: [].} =
  atlas.dirty = false
  atlas.markFontAtlasDirty(0, 0, atlas.width, atlas.height)

proc clearFontAtlasDirty*(atlas: var FontAtlas) {.raises: [].} =
  atlas.dirty = false
  atlas.dirtyMinX = 0
  atlas.dirtyMinY = 0
  atlas.dirtyMaxX = 0
  atlas.dirtyMaxY = 0

func canGrowFontAtlas*(atlas: FontAtlas): bool {.inline, raises: [].} =
  atlas.width < atlas.maxSize or atlas.height < atlas.maxSize

func nextFontAtlasSize*(atlas: FontAtlas): tuple[width, height: int] {.inline, raises: [].} =
  (min(atlas.width * 2, atlas.maxSize), min(atlas.height * 2, atlas.maxSize))

func glyphCacheKey(glyphId: uint32, subpixelPhase: int): uint64 {.inline, raises: [].} =
  (glyphId.uint64 shl 2) or subpixelPhase.uint64

proc ensureSizedSlot(fd: var FontData, fontSize: int) {.raises: [].} =
  while fd.sizedData.len <= fontSize:
    fd.sizedData.add(FontDataSized())

proc getPackedGlyphPtr*(atlas: var FontAtlas, fontIndex: int, glyphId: uint32, fontSize, subpixelPhase: int): nil ptr PackedChar {.raises: [].} =
  if fontIndex < 0 or fontIndex >= atlas.sized.len:
    echo "getPackedGlyphPtr fontIndex ", fontIndex, ", ", atlas.sized.len
    return nil
  if fontSize < 0 or fontSize >= atlas.sized[fontIndex].sizedData.len:
    echo "getPackedGlyphPtr fontSize ", fontSize, ", ", atlas.sized[fontIndex].sizedData.len
    return nil
  let slot = atlas.sized[fontIndex].sizedData[fontSize].addr
  let key = glyphCacheKey(glyphId, subpixelPhase)
  if not slot.glyphIndexChars.hasKey(key):
    # echo "getPackedGlyphPtr hasKey ", key, ", ", fontIndex, ", ", glyphId, ", ", fontSize, ", ", subpixelPhase
    return nil
  try:
    return slot.glyphIndexChars[key].addr
  except:
    echo "getPackedGlyphPtr [] "
    return nil

# Allocates an atlas rect for a glyph and stores its location. Only deals with
# glyph locations (rect placement + cache key); metric/offsets are filled by the
# caller. Returns nil if the glyph is already cached, does not fit and the atlas
# cannot grow, or the size is invalid.
proc packGlyphLocation*(atlas: var FontAtlas, fontIndex: int, glyphId: uint32, fontSize, subpixelPhase, w, h: int): nil ptr PackedChar {.raises: [].} =
  if fontIndex < 0 or fontIndex >= atlas.sized.len:
    echo "f"
    return nil
  atlas.sized[fontIndex].ensureSizedSlot(fontSize)
  let slot = atlas.sized[fontIndex].sizedData[fontSize].addr
  let key = glyphCacheKey(glyphId, subpixelPhase)
  if onRaiseQuit(slot.glyphIndexChars.hasKey(key)):
    try:
      echo "packGlyphLocation hasKey ", key, ", ", fontIndex, ", ", glyphId, ", ", fontSize, ", ", subpixelPhase
      return slot.glyphIndexChars[key].addr
    except:
      echo "e"
      return nil

  let pad = 1
  let gw = w + pad
  let gh = h + pad
  if gw <= 0 or gh <= 0:
    echo "d"
    return nil
  if gw > atlas.width or gh > atlas.height:
    atlas.needsResize = atlas.canGrowFontAtlas()
    atlas.needsReset = atlas.needsReset or atlas.needsResize
    echo "a"
    return nil
  if atlas.packX + gw > atlas.width:
    atlas.packX = 0
    atlas.packY += atlas.packRowH + pad
    atlas.packRowH = 0
  if atlas.packY + gh > atlas.height:
    atlas.needsReset = true
    atlas.needsResize = atlas.canGrowFontAtlas()
    echo "b"
    return nil

  var pc = PackedChar()
  pc.x0 = atlas.packX
  pc.y0 = atlas.packY
  pc.x1 = atlas.packX + w
  pc.y1 = atlas.packY + h
  atlas.packX += gw
  if gh > atlas.packRowH:
    atlas.packRowH = gh
  atlas.markFontAtlasDirty(pc.x0, pc.y0, w, h)
  slot.glyphIndexChars[key] = pc
  try:
    echo "packGlyphLocation pack ", key, ", ", fontIndex, ", ", glyphId, ", ", fontSize, ", ", subpixelPhase
    return slot.glyphIndexChars[key].addr
  except:
    echo "c"
    return nil

