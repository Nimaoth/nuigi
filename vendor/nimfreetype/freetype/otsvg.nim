# Copyright (c) 2017 Andri Lim
#
# Distributed under the MIT license
# (See accompanying file LICENSE.txt)
#
#-----------------------------------------

# OpenType SVG (OT-SVG) font support bindings.
# These model the hooks FreeType expects from an external SVG rendering
# library. The actual rasterization is delegated to client callbacks.

import fttypes, freetype, ftimage
include ftimport

type
  FT_SVG_Document* = ptr FT_SVG_DocumentRec

  FT_SVG_DocumentRec* = object
    svg_document*: ptr FT_Byte
    svg_document_length*: FT_ULong
    metrics*: FT_Size_Metrics
    units_per_EM*: FT_UShort
    start_glyph_id*: FT_UShort
    end_glyph_id*: FT_UShort
    transform*: FT_Matrix
    delta*: FT_Vector

  FT_SVG_Init_Func* = proc(data_pointer: ptr FT_Pointer): FT_Error {.ftcallback.}
  FT_SVG_Free_Func* = proc(data_pointer: ptr FT_Pointer) {.ftcallback.}
  FT_SVG_Render_Func* = proc(slot: FT_GlyphSlot;
                             data_pointer: ptr FT_Pointer): FT_Error {.ftcallback.}
  FT_SVG_Preset_Slot_Func* = proc(slot: FT_GlyphSlot; cache: FT_Bool;
                                  state: ptr FT_Pointer): FT_Error {.ftcallback.}

  FT_SVG_Hooks* = object
    init_svg*: FT_SVG_Init_Func
    free_svg*: FT_SVG_Free_Func
    render_svg*: FT_SVG_Render_Func
    preset_slot*: FT_SVG_Preset_Slot_Func
