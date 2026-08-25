
{.compile: "../vendor/stb_truetype.c".}
{.compile: "../vendor/stb_rect_pack.c".}

type
  VertexType* {.size: sizeof(cint).} = enum
    vmove = 1,
    vline,
    vcurve,
    vcubic

  PlatformID* {.size: sizeof(cint).} = enum
    PLATFORM_ID_UNICODE   = 0,
    PLATFORM_ID_MAC       = 1,
    PLATFORM_ID_ISO       = 2,
    PLATFORM_ID_MICROSOFT = 3

  UnicodeEncodingID* {.size: sizeof(cint).} = enum
    UNICODE_EID_UNICODE_1_0     = 0,
    UNICODE_EID_UNICODE_1_1     = 1,
    UNICODE_EID_ISO_10646       = 2,
    UNICODE_EID_UNICODE_2_0_BMP = 3,
    UNICODE_EID_UNICODE_2_0_FULL = 4

  MSEncodingID* {.size: sizeof(cint).} = enum
    MS_EID_SYMBOL       = 0,
    MS_EID_UNICODE_BMP  = 1,
    MS_EID_SHIFTJIS     = 2,
    MS_EID_UNICODE_FULL = 10

  MacEncodingID* {.size: sizeof(cint).} = enum
    MAC_EID_ROMAN        = 0,
    MAC_EID_JAPANESE     = 1,
    MAC_EID_CHINESE_TRAD = 2,
    MAC_EID_KOREAN       = 3,
    MAC_EID_ARABIC       = 4,
    MAC_EID_HEBREW       = 5,
    MAC_EID_GREEK        = 6,
    MAC_EID_RUSSIAN      = 7

  MSLanguageID* {.size: sizeof(cint).} = enum
    MS_LANG_ENGLISH    = 0x0409,
    MS_LANG_ITALIAN    = 0x0410,
    MS_LANG_DUTCH      = 0x0413,
    MS_LANG_FRENCH     = 0x040c,
    MS_LANG_GERMAN     = 0x0407,
    MS_LANG_HEBREW     = 0x040d,
    MS_LANG_CHINESE    = 0x0804,
    MS_LANG_JAPANESE   = 0x0411,
    MS_LANG_KOREAN     = 0x0412,
    MS_LANG_RUSSIAN    = 0x0419,
    MS_LANG_SWEDISH    = 0x041D

  MacLanguageID* {.size: sizeof(cint).} = enum
    MAC_LANG_ENGLISH                = 0,
    MAC_LANG_FRENCH                 = 1,
    MAC_LANG_GERMAN                 = 2,
    MAC_LANG_ITALIAN                = 3,
    MAC_LANG_DUTCH                  = 4,
    MAC_LANG_SWEDISH                = 5,
    MAC_LANG_SPANISH                = 6,
    MAC_LANG_HEBREW                 = 10,
    MAC_LANG_JAPANESE               = 11,
    MAC_LANG_ARABIC                 = 12,
    MAC_LANG_KOREAN                 = 23,
    MAC_LANG_CHINESE_TRAD           = 19,
    MAC_LANG_CHINESE_SIMPLIFIED     = 33,
    MAC_LANG_RUSSIAN                = 32

const
  MS_LANG_SPANISH* = MSLanguageID(0x0409) # same value as ENGLISH in C header
  MACSTYLE_DONTCARE*   = 0
  MACSTYLE_BOLD*       = 1
  MACSTYLE_ITALIC*     = 2
  MACSTYLE_UNDERSCORE* = 4
  MACSTYLE_NONE*       = 8

template POINT_SIZE*(x: cfloat): cfloat = -x

type
  BufObj {.bycopy.} = object
    data*: nil ptr UncheckedArray[uint8]
    cursor*: cint
    size*: cint

  BakedChar* {.bycopy.} = object
    x0*, y0*, x1*, y1*: uint16
    xoff*, yoff*, xadvance*: cfloat

  AlignedQuad* {.bycopy.} = object
    x0*, y0*, s0*, t0*: cfloat
    x1*, y1*, s1*, t1*: cfloat

  PackedChar* {.bycopy.} = object
    x0*, y0*, x1*, y1*: uint16
    xoff*, yoff*, xadvance*: cfloat
    xoff2*, yoff2*: cfloat

  PackRange* {.bycopy.} = object
    font_size*: cfloat
    first_unicode_codepoint_in_range*: cint
    array_of_unicode_codepoints*: ptr cint
    num_chars*: cint
    chardata_for_range*: ptr PackedChar
    h_oversample*, v_oversample*: uint8

  KerningEntry* {.bycopy.} = object
    glyph1*: cint
    glyph2*: cint
    advance*: cint

  Vertex* {.bycopy.} = object
    x*, y*, cx*, cy*, cx1*, cy1*: cshort
    `type`*, padding*: uint8

  Bitmap* {.bycopy.} = object
    w*, h*, stride*: cint
    pixels*: ptr UncheckedArray[uint8]

  FontInfo* {.bycopy.} = object
    userdata*: nil pointer
    data*: nil ptr UncheckedArray[uint8]
    fontstart*: cint
    numGlyphs*: cint
    loca*, head*, glyf*, hhea*, hmtx*, kern*, gpos*, svg*: cint
    index_map*: cint
    indexToLocFormat*: cint
    cff*: BufObj
    charstrings*: BufObj
    gsubrs*: BufObj
    subrs*: BufObj
    fontdicts*: BufObj
    fdselect*: BufObj

  PackContext* {.bycopy.} = object
    user_allocator_context*: nil pointer
    pack_info*: nil pointer
    width*, height*: cint
    stride_in_bytes*: cint
    padding*: cint
    skip_missing*: cint
    h_oversample*, v_oversample*: cuint
    pixels*: ptr UncheckedArray[uint8]
    nodes*: nil pointer

  RectObj* {.bycopy.} = object
    id*, w*, h*: cint
    x*, y*: cint
    was_packed*: cint

# --- stb_rect_pack ---

type
  RectCoord* = cint

  NodeObj* {.bycopy.} = object
    x*, y*: RectCoord
    next*: ptr NodeObj

  ContextObj* {.bycopy.} = object
    width*, height*: cint
    align*: cint
    init_mode*, heuristic*: cint
    num_nodes*: cint
    active_head*, free_head*: ptr NodeObj
    extra*: array[2, NodeObj]

const
  RECT_PACK_VERSION* = 1
  BRP_MAXVAL* = 0x7fffffff
  BRP_HEURISTIC_Skyline_default* = 0
  BRP_HEURISTIC_Skyline_BL_sortHeight* = 0
  BRP_HEURISTIC_Skyline_BF_sortHeight* = 1

proc packRects*(context: ptr ContextObj, rects: ptr RectObj,
    num_rects: cint): cint {.importc: "stbrp_pack_rects".}

proc initTarget*(context: ptr ContextObj, width, height: cint,
    nodes: ptr NodeObj, num_nodes: cint) {.
    importc: "stbrp_init_target".}

proc setupAllowOutOfMem*(context: ptr ContextObj,
    allow_out_of_mem: cint) {.importc: "stbrp_setup_allow_out_of_mem".}

proc setupHeuristic*(context: ptr ContextObj, heuristic: cint) {.
    importc: "stbrp_setup_heuristic".}

# --- Texture Baking API (old) ---

proc bakeFontBitmap*(data: ptr UncheckedArray[uint8], offset: cint,
    pixel_height: cfloat, pixels: ptr UncheckedArray[uint8], pw, ph: cint,
    first_char, num_chars: cint, chardata: ptr BakedChar): cint {.
    importc: "stbtt_BakeFontBitmap".}

proc getBakedQuad*(chardata: ptr BakedChar, pw, ph, char_index: cint,
    xpos, ypos: ptr cfloat, q: ptr AlignedQuad,
    opengl_fillrule: cint) {.importc: "stbtt_GetBakedQuad".}

proc getScaledFontVMetrics*(fontdata: ptr UncheckedArray[uint8], index: cint,
    size: cfloat, ascent, descent, lineGap: ptr cfloat) {.
    importc: "stbtt_GetScaledFontVMetrics".}

# --- Texture Baking API (new, packed) ---

proc packBegin*(spc: ptr PackContext, pixels: ptr UncheckedArray[uint8],
    width, height, stride_in_bytes, padding: cint,
    alloc_context: nil pointer): cint {.importc: "stbtt_PackBegin".}

proc packEnd*(spc: ptr PackContext) {.importc: "stbtt_PackEnd".}

proc packFontRange*(spc: ptr PackContext,
    fontdata: ptr UncheckedArray[uint8], font_index: cint,
    font_size: cfloat, first_unicode_char_in_range, num_chars_in_range: cint,
    chardata_for_range: ptr PackedChar): cint {.
    importc: "stbtt_PackFontRange".}

proc packFontRanges*(spc: ptr PackContext,
    fontdata: ptr UncheckedArray[uint8], font_index: cint,
    ranges: ptr PackRange, num_ranges: cint): cint {.
    importc: "stbtt_PackFontRanges".}

proc packSetOversampling*(spc: ptr PackContext,
    h_oversample, v_oversample: cuint) {.
    importc: "stbtt_PackSetOversampling".}

proc packSetSkipMissingCodepoints*(spc: ptr PackContext, skip: cint) {.
    importc: "stbtt_PackSetSkipMissingCodepoints".}

proc getPackedQuad*(chardata: ptr PackedChar, pw, ph, char_index: cint,
    xpos, ypos: ptr cfloat, q: ptr AlignedQuad,
    align_to_integer: cint) {.importc: "stbtt_GetPackedQuad".}

proc packFontRangesGatherRects*(spc: ptr PackContext,
    info: ptr FontInfo, ranges: ptr PackRange, num_ranges: cint,
    rects: ptr RectObj): cint {.importc: "stbtt_PackFontRangesGatherRects".}

proc packFontRangesPackRects*(spc: ptr PackContext,
    rects: ptr RectObj, num_rects: cint) {.
    importc: "stbtt_PackFontRangesPackRects".}

proc packFontRangesRenderIntoRects*(spc: ptr PackContext,
    info: ptr FontInfo, ranges: ptr PackRange, num_ranges: cint,
    rects: ptr RectObj): cint {.importc: "stbtt_PackFontRangesRenderIntoRects".}

# --- Font Loading ---

proc getNumberOfFonts*(data: ptr UncheckedArray[uint8]): cint {.
    importc: "stbtt_GetNumberOfFonts".}

proc getFontOffsetForIndex*(data: ptr UncheckedArray[uint8], index: cint): cint {.
    importc: "stbtt_GetFontOffsetForIndex".}

proc initFont*(info: ptr FontInfo, data: ptr UncheckedArray[uint8],
    offset: cint): cint {.importc: "stbtt_InitFont".}

# --- Character to Glyph-Index Conversion ---

proc findGlyphIndex*(info: ptr FontInfo, unicode_codepoint: cint): cint {.
    importc: "stbtt_FindGlyphIndex".}

# --- Character Properties ---

proc scaleForPixelHeight*(info: ptr FontInfo, pixels: cfloat): cfloat {.
    importc: "stbtt_ScaleForPixelHeight".}

proc scaleForMappingEmToPixels*(info: ptr FontInfo, pixels: cfloat): cfloat {.
    importc: "stbtt_ScaleForMappingEmToPixels".}

proc getFontVMetrics*(info: ptr FontInfo, ascent, descent, lineGap: ptr cint) {.
    importc: "stbtt_GetFontVMetrics".}

proc getFontVMetricsOS2*(info: ptr FontInfo, typoAscent, typoDescent,
    typoLineGap: ptr cint): cint {.importc: "stbtt_GetFontVMetricsOS2".}

proc getFontBoundingBox*(info: ptr FontInfo, x0, y0, x1, y1: ptr cint) {.
    importc: "stbtt_GetFontBoundingBox".}

proc getCodepointHMetrics*(info: ptr FontInfo, codepoint: cint,
    advanceWidth: ptr cint, leftSideBearing: nil pointer) {.
    importc: "stbtt_GetCodepointHMetrics".}

proc getCodepointKernAdvance*(info: ptr FontInfo, ch1, ch2: cint): cint {.
    importc: "stbtt_GetCodepointKernAdvance".}

proc getCodepointBox*(info: ptr FontInfo, codepoint: cint,
    x0, y0, x1, y1: ptr cint): cint {.importc: "stbtt_GetCodepointBox".}

proc getGlyphHMetrics*(info: ptr FontInfo, glyph_index: cint,
    advanceWidth, leftSideBearing: ptr cint) {.
    importc: "stbtt_GetGlyphHMetrics".}

proc getGlyphKernAdvance*(info: ptr FontInfo, glyph1, glyph2: cint): cint {.
    importc: "stbtt_GetGlyphKernAdvance".}

proc getGlyphBox*(info: ptr FontInfo, glyph_index: cint,
    x0, y0, x1, y1: ptr cint): cint {.importc: "stbtt_GetGlyphBox".}

proc getKerningTableLength*(info: ptr FontInfo): cint {.
    importc: "stbtt_GetKerningTableLength".}

proc getKerningTable*(info: ptr FontInfo, table: ptr KerningEntry,
    table_length: cint): cint {.importc: "stbtt_GetKerningTable".}

# --- Glyph Shapes ---

proc isGlyphEmpty*(info: ptr FontInfo, glyph_index: cint): cint {.
    importc: "stbtt_IsGlyphEmpty".}

proc getCodepointShape*(info: ptr FontInfo, unicode_codepoint: cint,
    vertices: ptr ptr Vertex): cint {.importc: "stbtt_GetCodepointShape".}

proc getGlyphShape*(info: ptr FontInfo, glyph_index: cint,
    vertices: ptr ptr Vertex): cint {.importc: "stbtt_GetGlyphShape".}

proc freeShape*(info: ptr FontInfo, vertices: ptr Vertex) {.
    importc: "stbtt_FreeShape".}

proc findSVGDoc*(info: ptr FontInfo, gl: cint): ptr UncheckedArray[uint8] {.
    importc: "stbtt_FindSVGDoc".}

proc getCodepointSVG*(info: ptr FontInfo, unicode_codepoint: cint,
    svg: ptr cstring): cint {.importc: "stbtt_GetCodepointSVG".}

proc getGlyphSVG*(info: ptr FontInfo, gl: cint,
    svg: ptr cstring): cint {.importc: "stbtt_GetGlyphSVG".}

# --- Bitmap Rendering ---

proc freeBitmap*(bitmap: ptr UncheckedArray[uint8], userdata: pointer) {.
    importc: "stbtt_FreeBitmap".}

proc getCodepointBitmap*(info: ptr FontInfo, scale_x, scale_y: cfloat,
    codepoint: cint, width, height, xoff, yoff: ptr cint): ptr UncheckedArray[uint8] {.
    importc: "stbtt_GetCodepointBitmap".}

proc getCodepointBitmapSubpixel*(info: ptr FontInfo,
    scale_x, scale_y, shift_x, shift_y: cfloat, codepoint: cint,
    width, height, xoff, yoff: ptr cint): ptr UncheckedArray[uint8] {.
    importc: "stbtt_GetCodepointBitmapSubpixel".}

proc makeCodepointBitmap*(info: ptr FontInfo,
    output: ptr UncheckedArray[uint8], out_w, out_h, out_stride: cint,
    scale_x, scale_y: cfloat, codepoint: cint) {.
    importc: "stbtt_MakeCodepointBitmap".}

proc makeCodepointBitmapSubpixel*(info: ptr FontInfo,
    output: ptr UncheckedArray[uint8], out_w, out_h, out_stride: cint,
    scale_x, scale_y, shift_x, shift_y: cfloat, codepoint: cint) {.
    importc: "stbtt_MakeCodepointBitmapSubpixel".}

proc makeCodepointBitmapSubpixelPrefilter*(info: ptr FontInfo,
    output: ptr UncheckedArray[uint8], out_w, out_h, out_stride: cint,
    scale_x, scale_y, shift_x, shift_y: cfloat,
    oversample_x, oversample_y: cint,
    sub_x, sub_y: ptr cfloat, codepoint: cint) {.
    importc: "stbtt_MakeCodepointBitmapSubpixelPrefilter".}

proc getCodepointBitmapBox*(font: ptr FontInfo, codepoint: cint,
    scale_x, scale_y: cfloat, ix0, iy0, ix1, iy1: ptr cint) {.
    importc: "stbtt_GetCodepointBitmapBox".}

proc getCodepointBitmapBoxSubpixel*(font: ptr FontInfo, codepoint: cint,
    scale_x, scale_y, shift_x, shift_y: cfloat,
    ix0, iy0, ix1, iy1: ptr cint) {.
    importc: "stbtt_GetCodepointBitmapBoxSubpixel".}

# --- Glyph Bitmap Rendering (glyph index variants) ---

proc getGlyphBitmap*(info: ptr FontInfo, scale_x, scale_y: cfloat,
    glyph: cint, width, height, xoff, yoff: ptr cint): ptr UncheckedArray[uint8] {.
    importc: "stbtt_GetGlyphBitmap".}

proc getGlyphBitmapSubpixel*(info: ptr FontInfo,
    scale_x, scale_y, shift_x, shift_y: cfloat, glyph: cint,
    width, height, xoff, yoff: ptr cint): ptr UncheckedArray[uint8] {.
    importc: "stbtt_GetGlyphBitmapSubpixel".}

proc makeGlyphBitmap*(info: ptr FontInfo,
    output: ptr UncheckedArray[uint8], out_w, out_h, out_stride: cint,
    scale_x, scale_y: cfloat, glyph: cint) {.
    importc: "stbtt_MakeGlyphBitmap".}

proc makeGlyphBitmapSubpixel*(info: ptr FontInfo,
    output: ptr UncheckedArray[uint8], out_w, out_h, out_stride: cint,
    scale_x, scale_y, shift_x, shift_y: cfloat, glyph: cint) {.
    importc: "stbtt_MakeGlyphBitmapSubpixel".}

proc makeGlyphBitmapSubpixelPrefilter*(info: ptr FontInfo,
    output: ptr UncheckedArray[uint8], out_w, out_h, out_stride: cint,
    scale_x, scale_y, shift_x, shift_y: cfloat,
    oversample_x, oversample_y: cint,
    sub_x, sub_y: ptr cfloat, glyph: cint) {.
    importc: "stbtt_MakeGlyphBitmapSubpixelPrefilter".}

proc getGlyphBitmapBox*(font: ptr FontInfo, glyph: cint,
    scale_x, scale_y: cfloat, ix0, iy0, ix1, iy1: ptr cint) {.
    importc: "stbtt_GetGlyphBitmapBox".}

proc getGlyphBitmapBoxSubpixel*(font: ptr FontInfo, glyph: cint,
    scale_x, scale_y, shift_x, shift_y: cfloat,
    ix0, iy0, ix1, iy1: ptr cint) {.
    importc: "stbtt_GetGlyphBitmapBoxSubpixel".}

# --- Rasterize ---

proc rasterize*(result: ptr Bitmap, flatness_in_pixels: cfloat,
    vertices: ptr Vertex, num_verts: cint,
    scale_x, scale_y, shift_x, shift_y: cfloat,
    x_off, y_off, invert: cint, userdata: pointer) {.
    importc: "stbtt_Rasterize".}

# --- Signed Distance Function ---

proc freeSDF*(bitmap: ptr UncheckedArray[uint8], userdata: pointer) {.
    importc: "stbtt_FreeSDF".}

proc getGlyphSDF*(info: ptr FontInfo, scale: cfloat, glyph, padding: cint,
    onedge_value: uint8, pixel_dist_scale: cfloat,
    width, height, xoff, yoff: ptr cint): ptr UncheckedArray[uint8] {.
    importc: "stbtt_GetGlyphSDF".}

proc getCodepointSDF*(info: ptr FontInfo, scale: cfloat, codepoint, padding: cint,
    onedge_value: uint8, pixel_dist_scale: cfloat,
    width, height, xoff, yoff: ptr cint): ptr UncheckedArray[uint8] {.
    importc: "stbtt_GetCodepointSDF".}

# --- Finding the Right Font ---

proc findMatchingFont*(fontdata: ptr UncheckedArray[uint8], name: cstring,
    flags: cint): cint {.importc: "stbtt_FindMatchingFont".}

proc compareUTF8toUTF16Bigendian*(s1: cstring, len1: cint,
    s2: cstring, len2: cint): cint {.
    importc: "stbtt_CompareUTF8toUTF16_bigendian".}

proc getFontNameString*(font: ptr FontInfo, length: ptr cint,
    platformID, encodingID, languageID, nameID: cint): cstring {.
    importc: "stbtt_GetFontNameString".}

### stb_rect_pack