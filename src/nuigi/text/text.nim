## Renderer-independent records for measured and shaped text.
##
## A `UiTextArrangement` stores the glyph IDs, font selection, positions,
## metrics, and content hash produced by the application's text measurement
## callback. The UI core caches these arrangements before a renderer turns
## them into atlas-backed meshes.

import std/hashes, nuigi/core/vecmath

type
  UiTextFlag* {.pure.} = enum
    ## Style flags for a text run (stored in `UiNodeText.textFlags`).
    Bold
    Italic
    Underline
    Strikethrough

  UiTextFlags* = set[UiTextFlag]
    ## Set of `UiTextFlag` values applied to a text run.

  UiTextArrangementGlyph* = object
    fontIndex*: int32
    glyphIndex*: uint32
    pos*: Vec2

  UiTextArrangement* = object
    fontSize*: float32
    textFlags*: UiTextFlags
    size*: Vec2
    ascent*: float32
    descent*: float32
    glyphs*: seq[UiTextArrangementGlyph]
    contentHash*: Hash

func textFlagBits*(flags: UiTextFlags): uint64 {.inline.} =
  ## Bit representation of `flags` for hashing and cache keys.
  result = 0'u64
  if UiTextFlag.Bold in flags:
    result = result or 1'u64
  if UiTextFlag.Italic in flags:
    result = result or 2'u64
  if UiTextFlag.Underline in flags:
    result = result or 4'u64
  if UiTextFlag.Strikethrough in flags:
    result = result or 8'u64

func hash*(g: UiTextArrangementGlyph): Hash =
  !$(g.fontIndex.hash !& g.glyphIndex.hash !& g.pos.hash)
