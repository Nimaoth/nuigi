## Renderer-independent records for measured and shaped text.
##
## A `UiTextArrangement` stores the glyph IDs, font selection, positions,
## metrics, and content hash produced by the application's text measurement
## callback. The UI core caches these arrangements before a renderer turns
## them into atlas-backed meshes.

import std/hashes, nuigi/core/vecmath

type
  UiTextArrangementGlyph* = object
    fontIndex*: int32
    glyphIndex*: uint32
    pos*: Vec2

  UiTextArrangement* = object
    fontSize*: float32
    size*: Vec2
    ascent*: float32
    descent*: float32
    glyphs*: seq[UiTextArrangementGlyph]
    contentHash*: Hash

func hash*(g: UiTextArrangementGlyph): Hash =
  !$(g.fontIndex.hash !& g.glyphIndex.hash !& g.pos.hash)
