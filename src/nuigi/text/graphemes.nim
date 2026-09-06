## UTF-8 grapheme boundary helpers shared by editing and rendering code.

import std/unicode

func inRange(value, first, last: int): bool {.inline.} =
  value >= first and value <= last

func isGraphemeExtend*(rune: Rune): bool =
  case rune.int
  of 0x0300..0x036f, 0x0483..0x0489, 0x0591..0x05bd, 0x05bf,
      0x05c1..0x05c2, 0x05c4..0x05c5, 0x05c7, 0x0610..0x061a,
      0x064b..0x065f, 0x0670, 0x06d6..0x06ed, 0x0711,
      0x0730..0x074a, 0x07a6..0x07b0, 0x07eb..0x07f3,
      0x0816..0x082d, 0x0859..0x085b, 0x08d3..0x0903,
      0x093a..0x093c, 0x093e..0x094f, 0x0951..0x0957,
      0x0962..0x0963, 0x0981..0x0983, 0x09bc, 0x09be..0x09cd,
      0x09d7, 0x0a01..0x0a03, 0x0a3c..0x0a51, 0x0abc..0x0acd,
      0x0b01..0x0b4d, 0x0bbe..0x0bcd, 0x0c00..0x0c4d,
      0x0d00..0x0d4d, 0x0e31..0x0e4e, 0x0eb1..0x0ecd,
      0x0f18..0x0fbc, 0x102b..0x103e, 0x1056..0x1059,
      0x135d..0x135f, 0x1712..0x1715, 0x1ab0..0x1aff,
      0x1dc0..0x1dff, 0x20d0..0x20ff, 0xfe00..0xfe0f,
      0xfe20..0xfe2f, 0xe0100..0xe01ef:
    true
  else:
    false

func isEmojiModifier*(rune: Rune): bool {.inline.} =
  rune.int.inRange(0x1f3fb, 0x1f3ff)

func isRegionalIndicator*(rune: Rune): bool {.inline.} =
  rune.int.inRange(0x1f1e6, 0x1f1ff)

func isVirama*(rune: Rune): bool =
  case rune.int
  of 0x094d, 0x09cd, 0x0a4d, 0x0acd, 0x0b4d, 0x0bcd, 0x0c4d,
      0x0ccd, 0x0d4d, 0x0dca, 0x0e3a, 0x0f84, 0x1039, 0x103a,
      0x1714, 0x1734, 0x17d2, 0x1a60, 0x1b44, 0x1baa, 0xa806,
      0xa8c4, 0xa953, 0xa9c0, 0xaaf6, 0xabed, 0x10a3f, 0x11046:
    true
  else:
    false

proc graphemeBoundaries*(text: string): seq[int] =
  result = @[0]
  var byteOffset = 0
  var clusterStarted = false
  var joinNext = false
  var regionalCount = 0

  for rune in text.runes:
    let runeBytes = ($rune).len
    if rune == Rune(0x0a) or rune == Rune(0x0d):
      if result[^1] != byteOffset:
        result.add(byteOffset)
      byteOffset += runeBytes
      result.add(byteOffset)
      clusterStarted = false
      joinNext = false
      regionalCount = 0
      continue

    let attaches = rune.isGraphemeExtend or rune.isEmojiModifier or
      rune.int == 0x200d or joinNext or
      (rune.isRegionalIndicator and regionalCount == 1)
    if clusterStarted and not attaches:
      result.add(byteOffset)
      regionalCount = 0

    clusterStarted = true
    if rune.isRegionalIndicator:
      inc regionalCount
    elif not rune.isGraphemeExtend and not rune.isEmojiModifier and rune.int != 0x200d:
      regionalCount = 0
    joinNext = rune.int == 0x200d or rune.isVirama
    byteOffset += runeBytes

  if result[^1] != text.len:
    result.add(text.len)

proc graphemeBoundaryAtOrBefore*(text: string, position: int): int =
  let clamped = clamp(position, 0, text.len)
  result = 0
  for boundary in text.graphemeBoundaries:
    if boundary > clamped:
      break
    result = boundary

proc previousGraphemeBoundary*(text: string, position: int): int =
  let clamped = clamp(position, 0, text.len)
  result = 0
  for boundary in text.graphemeBoundaries:
    if boundary >= clamped:
      break
    result = boundary

proc nextGraphemeBoundary*(text: string, position: int): int =
  let clamped = clamp(position, 0, text.len)
  result = text.len
  for boundary in text.graphemeBoundaries:
    if boundary > clamped:
      return boundary
