## Unicode grapheme clustering and terminal-cell width helpers.
##
## Terminals render grapheme clusters rather than scalar values. This module keeps
## combining marks, variation selectors, emoji modifiers, ZWJ sequences, and pairs
## of regional indicators together so measuring and drawing use identical widths.

import std/unicode

func inRange(value, first, last: int): bool {.inline.} =
  return value >= first and value <= last

func isCombining*(rune: Rune): bool =
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
    return true
  else:
    return false

func isEmojiModifier(rune: Rune): bool {.inline.} =
  return rune.int.inRange(0x1f3fb, 0x1f3ff)

func isRegionalIndicator(rune: Rune): bool {.inline.} =
  return rune.int.inRange(0x1f1e6, 0x1f1ff)

func isVirama(rune: Rune): bool =
  case rune.int
  of 0x094d, 0x09cd, 0x0a4d, 0x0acd, 0x0b4d, 0x0bcd, 0x0c4d,
      0x0ccd, 0x0d4d, 0x0dca, 0x0e3a, 0x0f84, 0x1039, 0x103a,
      0x1714, 0x1734, 0x17d2, 0x1a60, 0x1b44, 0x1baa, 0xa806,
      0xa8c4, 0xa953, 0xa9c0, 0xaaf6, 0xabed, 0x10a3f, 0x11046:
    return true
  else:
    return false

func runeCellWidth*(rune: Rune): int =
  let value = rune.int
  if value == 0 or value < 32 or inRange(value, 0x7f, 0x9f) or rune.isCombining or
      rune.isEmojiModifier or value == 0x200d:
    return 0
  case value
  of 0x1100..0x115f, 0x231a..0x231b, 0x2329..0x232a,
      0x23e9..0x23ec, 0x23f0, 0x23f3, 0x25fd..0x25fe,
      0x2614..0x2615, 0x2648..0x2653, 0x267f, 0x2693, 0x26a1,
      0x26aa..0x26ab, 0x26bd..0x26be, 0x26c4..0x26c5, 0x26ce,
      0x26d4, 0x26ea, 0x26f2..0x26f3, 0x26f5, 0x26fa, 0x26fd,
      0x2705, 0x270a..0x270b, 0x2728, 0x274c, 0x274e,
      0x2753..0x2755, 0x2757, 0x2795..0x2797, 0x27b0, 0x27bf,
      0x2b1b..0x2b1c, 0x2b50, 0x2b55, 0x2e80..0x303e,
      0x3040..0xa4cf, 0xac00..0xd7a3, 0xf900..0xfaff,
      0xfe10..0xfe19, 0xfe30..0xfe6f, 0xff00..0xff60,
      0xffe0..0xffe6, 0x1f000..0x1faff, 0x20000..0x3fffd:
    return 2
  else:
    discard
  return 1

type TerminalGrapheme* = object
  text*: string
  width*: int
  newline*: bool

proc terminalGraphemes*(text: openArray[char]): seq[TerminalGrapheme] =
  var graphemes: seq[TerminalGrapheme] = @[]
  var cluster = ""
  var width = 0
  var joinNext = false
  var regionalCount = 0

  for rune in text.runes:
    if rune == Rune(0x0a):
      if cluster.len > 0:
        graphemes.add TerminalGrapheme(text: cluster, width: max(1, width))
        cluster.setLen(0)
        width = 0
        regionalCount = 0
      graphemes.add TerminalGrapheme(newline: true)
      joinNext = false
      continue
    if rune == Rune(0x0d):
      continue

    let attaches = rune.isCombining or rune.isEmojiModifier or rune.int == 0x200d or joinNext or
      (rune.isRegionalIndicator and regionalCount == 1)
    if cluster.len > 0 and not attaches:
      graphemes.add TerminalGrapheme(text: cluster, width: max(1, width))
      cluster.setLen(0)
      width = 0
      regionalCount = 0

    cluster.add($rune)
    width = max(width, if rune.int == 0xfe0f: 2 else: rune.runeCellWidth)
    if rune.isRegionalIndicator:
      inc regionalCount
    elif not rune.isCombining and not rune.isEmojiModifier and rune.int != 0x200d:
      regionalCount = 0
    joinNext = rune.int == 0x200d or rune.isVirama

  if cluster.len > 0:
    graphemes.add TerminalGrapheme(text: cluster, width: max(1, width))
  return graphemes

proc terminalTextSize*(text: openArray[char], maxWidth = 0): tuple[width, height: int] =
  var measured = (width: 0, height: 1)
  var x = 0
  let graphemes = text.terminalGraphemes
  for grapheme in graphemes:
    if grapheme.newline:
      measured.width = max(measured.width, x)
      x = 0
      inc measured.height
    else:
      if maxWidth > 0 and x > 0 and x + grapheme.width > maxWidth:
        measured.width = max(measured.width, x)
        x = 0
        inc measured.height
      x += grapheme.width
  measured.width = max(measured.width, x)
  return measured
