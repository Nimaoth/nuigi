# Copyright (c) 2017 Andri Lim
#
# Distributed under the MIT license
# (See accompanying file LICENSE.txt)
#
#-----------------------------------------

import fttypes, std/tables

const
  FT_ModErr_Base* = 0x000
  FT_ModErr_Autofit* = 0x100
  FT_ModErr_BDF* = 0x200
  FT_ModErr_Bzip2* = 0x300
  FT_ModErr_Cache* = 0x400
  FT_ModErr_CFF* = 0x500
  FT_ModErr_CID* = 0x600
  FT_ModErr_Gzip* = 0x700
  FT_ModErr_LZW* = 0x800
  FT_ModErr_OTvalid* = 0x900
  FT_ModErr_PCF* = 0xA00
  FT_ModErr_PFR* = 0xB00
  FT_ModErr_PSaux* = 0xC00
  FT_ModErr_PShinter* = 0xD00
  FT_ModErr_PSnames* = 0xE00
  FT_ModErr_Raster* = 0xF00
  FT_ModErr_SFNT* = 0x1000
  FT_ModErr_Smooth* = 0x1100
  FT_ModErr_TrueType* = 0x1200
  FT_ModErr_Type1* = 0x1300
  FT_ModErr_Type42* = 0x1400
  FT_ModErr_Winfonts* = 0x1500
  FT_ModErr_GXvalid* = 0x1600

const
  FT_ModErr_Table* = [
    (0x000, "base module"),
    (0x100, "autofitter module"),
    (0x200, "BDF module"),
    (0x300, "Bzip2 module"),
    (0x400, "cache module"),
    (0x500, "CFF module"),
    (0x600, "CID module"),
    (0x700, "Gzip module"),
    (0x800, "LZW module"),
    (0x900, "OpenType validation module"),
    (0xA00, "PCF module"),
    (0xB00, "PFR module"),
    (0xC00, "PS auxiliary module"),
    (0xD00, "PS hinter module"),
    (0xE00, "PS names module"),
    (0xF00, "raster module"),
    (0x1000, "SFNT module"),
    (0x1100, "smooth raster module"),
    (0x1200, "TrueType module"),
    (0x1300, "Type 1 module"),
    (0x1400, "Type 42 module"),
    (0x1500, "Windows FON/FNT module"),
    (0x1600, "GX validation module")]

type
  FT_ModErr_Msg* = object
    errors: Table[int, string]

proc newModErrMsg*(): FT_ModErr_Msg =
  var t = initTable[int, string]()
  for (code, msg) in FT_ModErr_Table:
    t[code] = msg
  result = FT_ModErr_Msg(errors: t)

proc errorMessage*(self: FT_ModErr_Msg, errorCode: int): string =
  result = self.errors.getOrDefault(errorCode, "")
