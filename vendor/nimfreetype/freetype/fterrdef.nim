# Copyright (c) 2017 Andri Lim
#
# Distributed under the MIT license
# (See accompanying file LICENSE.txt)
#
#-----------------------------------------

import fttypes, std/tables

const
  FT_Err_Ok* = 0x00
  FT_Err_Cannot_Open_Resource* = 0x01
  FT_Err_Unknown_File_Format* = 0x02
  FT_Err_Invalid_File_Format* = 0x03
  FT_Err_Invalid_Version* = 0x04
  FT_Err_Lower_Module_Version* = 0x05
  FT_Err_Invalid_Argument* = 0x06
  FT_Err_Unimplemented_Feature* = 0x07
  FT_Err_Invalid_Table* = 0x08
  FT_Err_Invalid_Offset* = 0x09
  FT_Err_Array_Too_Large* = 0x0A
  FT_Err_Missing_Module* = 0x0B
  FT_Err_Missing_Property* = 0x0C
  FT_Err_Invalid_Glyph_Index* = 0x10
  FT_Err_Invalid_Character_Code* = 0x11
  FT_Err_Invalid_Glyph_Format* = 0x12
  FT_Err_Cannot_Render_Glyph* = 0x13
  FT_Err_Invalid_Outline* = 0x14
  FT_Err_Invalid_Composite* = 0x15
  FT_Err_Too_Many_Hints* = 0x16
  FT_Err_Invalid_Pixel_Size* = 0x17
  FT_Err_Invalid_Handle* = 0x20
  FT_Err_Invalid_Library_Handle* = 0x21
  FT_Err_Invalid_Driver_Handle* = 0x22
  FT_Err_Invalid_Face_Handle* = 0x23
  FT_Err_Invalid_Size_Handle* = 0x24
  FT_Err_Invalid_Slot_Handle* = 0x25
  FT_Err_Invalid_CharMap_Handle* = 0x26
  FT_Err_Invalid_Cache_Handle* = 0x27
  FT_Err_Invalid_Stream_Handle* = 0x28
  FT_Err_Too_Many_Drivers* = 0x30
  FT_Err_Too_Many_Extensions* = 0x31
  FT_Err_Out_Of_Memory* = 0x40
  FT_Err_Unlisted_Object* = 0x41
  FT_Err_Cannot_Open_Stream* = 0x51
  FT_Err_Invalid_Stream_Seek* = 0x52
  FT_Err_Invalid_Stream_Skip* = 0x53
  FT_Err_Invalid_Stream_Read* = 0x54
  FT_Err_Invalid_Stream_Operation* = 0x55
  FT_Err_Invalid_Frame_Operation* = 0x56
  FT_Err_Nested_Frame_Access* = 0x57
  FT_Err_Invalid_Frame_Read* = 0x58
  FT_Err_Raster_Uninitialized* = 0x60
  FT_Err_Raster_Corrupted* = 0x61
  FT_Err_Raster_Overflow* = 0x62
  FT_Err_Raster_Negative_Height* = 0x63
  FT_Err_Too_Many_Caches* = 0x70
  FT_Err_Invalid_Opcode* = 0x80
  FT_Err_Too_Few_Arguments* = 0x81
  FT_Err_Stack_Overflow* = 0x82
  FT_Err_Code_Overflow* = 0x83
  FT_Err_Bad_Argument* = 0x84
  FT_Err_Divide_By_Zero* = 0x85
  FT_Err_Invalid_Reference* = 0x86
  FT_Err_Debug_OpCode* = 0x87
  FT_Err_ENDF_In_Exec_Stream* = 0x88
  FT_Err_Nested_DEFS* = 0x89
  FT_Err_Invalid_CodeRange* = 0x8A
  FT_Err_Execution_Too_Long* = 0x8B
  FT_Err_Too_Many_Function_Defs* = 0x8C
  FT_Err_Too_Many_Instruction_Defs* = 0x8D
  FT_Err_Table_Missing* = 0x8E
  FT_Err_Horiz_Header_Missing* = 0x8F
  FT_Err_Locations_Missing* = 0x90
  FT_Err_Name_Table_Missing* = 0x91
  FT_Err_CMap_Table_Missing* = 0x92
  FT_Err_Hmtx_Table_Missing* = 0x93
  FT_Err_Post_Table_Missing* = 0x94
  FT_Err_Invalid_Horiz_Metrics* = 0x95
  FT_Err_Invalid_CharMap_Format* = 0x96
  FT_Err_Invalid_PPem* = 0x97
  FT_Err_Invalid_Vert_Metrics* = 0x98
  FT_Err_Could_Not_Find_Context* = 0x99
  FT_Err_Invalid_Post_Table_Format* = 0x9A
  FT_Err_Invalid_Post_Table* = 0x9B
  FT_Err_Syntax_Error* = 0xA0
  FT_Err_Stack_Underflow* = 0xA1
  FT_Err_Ignore* = 0xA2
  FT_Err_No_Unicode_Glyph_Name* = 0xA3
  FT_Err_Glyph_Too_Big* = 0xA4
  FT_Err_Missing_Startfont_Field* = 0xB0
  FT_Err_Missing_Font_Field* = 0xB1
  FT_Err_Missing_Size_Field* = 0xB2
  FT_Err_Missing_Fontboundingbox_Field* = 0xB3
  FT_Err_Missing_Chars_Field* = 0xB4
  FT_Err_Missing_Startchar_Field* = 0xB5
  FT_Err_Missing_Encoding_Field* = 0xB6
  FT_Err_Missing_Bbx_Field* = 0xB7
  FT_Err_Bbx_Too_Big* = 0xB8
  FT_Err_Corrupted_Font_Header* = 0xB9
  FT_Err_Corrupted_Font_Glyphs* = 0xBA

const
  FT_Err_Table* = {
    0x00: "no error",
    0x01: "cannot open resource",
    0x02: "unknown file format",
    0x03: "broken file",
    0x04: "invalid FreeType version",
    0x05: "module version is too low",
    0x06: "invalid argument",
    0x07: "unimplemented feature",
    0x08: "broken table",
    0x09: "broken offset within table",
    0x0A: "array allocation size too large",
    0x0B: "missing module",
    0x0C: "missing property",
    0x10: "invalid glyph index",
    0x11: "invalid character code",
    0x12: "unsupported glyph image format",
    0x13: "cannot render this glyph format",
    0x14: "invalid outline",
    0x15: "invalid composite glyph",
    0x16: "too many hints",
    0x17: "invalid pixel size",
    0x20: "invalid object handle",
    0x21: "invalid library handle",
    0x22: "invalid module handle",
    0x23: "invalid face handle",
    0x24: "invalid size handle",
    0x25: "invalid glyph slot handle",
    0x26: "invalid charmap handle",
    0x27: "invalid cache manager handle",
    0x28: "invalid stream handle",
    0x30: "too many modules",
    0x31: "too many extensions",
    0x40: "out of memory",
    0x41: "unlisted object",
    0x51: "cannot open stream",
    0x52: "invalid stream seek",
    0x53: "invalid stream skip",
    0x54: "invalid stream read",
    0x55: "invalid stream operation",
    0x56: "invalid frame operation",
    0x57: "nested frame access",
    0x58: "invalid frame read",
    0x60: "raster uninitialized",
    0x61: "raster corrupted",
    0x62: "raster overflow",
    0x63: "negative height while rastering",
    0x70: "too many registered caches",
    0x80: "invalid opcode",
    0x81: "too few arguments",
    0x82: "stack overflow",
    0x83: "code overflow",
    0x84: "bad argument",
    0x85: "division by zero",
    0x86: "invalid reference",
    0x87: "found debug opcode",
    0x88: "found ENDF opcode in execution stream",
    0x89: "nested DEFS",
    0x8A: "invalid code range",
    0x8B: "execution context too long",
    0x8C: "too many function definitions",
    0x8D: "too many instruction definitions",
    0x8E: "SFNT font table missing",
    0x8F: "horizontal header (hhea) table missing",
    0x90: "locations (loca) table missing",
    0x91: "name table missing",
    0x92: "character map (cmap) table missing",
    0x93: "horizontal metrics (hmtx) table missing",
    0x94: "PostScript (post) table missing",
    0x95: "invalid horizontal metrics",
    0x96: "invalid character map (cmap) format",
    0x97: "invalid ppem value",
    0x98: "invalid vertical metrics",
    0x99: "could not find context",
    0x9A: "invalid PostScript (post) table format",
    0x9B: "invalid PostScript (post) table",
    0xA0: "opcode syntax error",
    0xA1: "argument stack underflow",
    0xA2: "ignore",
    0xA3: "no Unicode glyph name found",
    0xA4: "glyph too big for hinting",
    0xB0: "STARTFONT' field missing",
    0xB1: "FONT' field missing",
    0xB2: "SIZE' field missing",
    0xB3: "FONTBOUNDINGBOX' field missing",
    0xB4: "CHARS' field missing",
    0xB5: "STARTCHAR' field missing",
    0xB6: "ENCODING' field missing",
    0xB7: "BBX' field missing",
    0xB8: "BBX' too big",
    0xB9: "Font header corrupted or missing fields",
    0xBA: "Font glyphs corrupted or missing fields",
  }

type
  FT_Error_Msg* = object
    errors: Table[int, string]

proc newErrorMsg*(): FT_Error_Msg =
  var t = initTable[int, string]()
  for (code, msg) in FT_Err_Table:
    t[code] = msg
  result = FT_Error_Msg(errors: t)

proc errorMessage*(self: FT_Error_Msg, errorCode: int): string =
  result = self.errors.getOrDefault(errorCode, "")
