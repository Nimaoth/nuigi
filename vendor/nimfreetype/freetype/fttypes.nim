# Copyright (c) 2017 Andri Lim
#
# Distributed under the MIT license
# (See accompanying file LICENSE.txt)
#
#-----------------------------------------

include ftimport

type
  FT_Uint8* = uint8
  FT_Uint32* = uint32
  FT_Int32* = int32
  FT_Bool* = uint8
  FT_FWord* = cshort
  FT_UFWord* = cushort
  FT_Char* = cchar
  FT_Byte* = uint8
  FT_Bytes* = ptr uint8
  FT_Tag* = uint32
  FT_String* = cchar
  FT_Short* = cshort
  FT_UShort* = cushort
  FT_Int* = cint
  FT_UInt* = cuint
  FT_Long* = clong
  FT_ULong* = culong
  FT_F2Dot14* = cshort
  FT_F26Dot6* = clong
  FT_Fixed* = clong
  FT_Error* = cint
  FT_Pointer* = pointer
  FT_Offset* = csize_t

  #ft_ptrdiff_t  FT_PtrDist;

template FT_MAKE_TAG*(x1, x2, x3, x4: untyped): untyped =
  (uint32(x1) shl 24) or (uint32(x2) shl 16) or (uint32(x3) shl 8) or uint32(x4)


type
  FT_Generic_Finalizer* = proc(obj: pointer) {.ftcallback.}

  FT_Generic* = object
    data: pointer
    finalizer: FT_Generic_Finalizer

  FT_UnitVector* = object
    x, y: FT_F2Dot14

  FT_Matrix* = object
    xx, xy: FT_Fixed
    yx, yy: FT_Fixed

  FT_Data* = object
    pointer: ptr FT_Byte
    length: FT_Int

  FT_ListNode* = ptr FT_ListNodeRec

  FT_List* = ptr FT_ListRec

  FT_ListNodeRec* = object
    prev, next: FT_ListNode
    data: pointer

  FT_ListRec* = object
    head, tail: FT_ListNode

template FT_IS_EMPTY*(list: untyped): untyped =
  ( (list).head == nil )
