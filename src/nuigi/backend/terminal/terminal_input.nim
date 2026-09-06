## Incremental ANSI/VT terminal input parser.
##
## Adapted from Nev's terminal backend parser for nuigi's input types. Input may
## arrive split at any byte, including in the middle of UTF-8 and escape sequences.

import std/[strutils, unicode]
import nuigi
import nuigi/core/timer

const DefaultEscapeTimeoutMs* = 32

type
  TerminalInputAction* = enum
    InputPress, InputRepeat, InputRelease

  TerminalInputEventKind* = enum
    TerminalText, TerminalKey, TerminalMouseButton, TerminalMouseMove,
    TerminalMouseWheel, TerminalGridSize, TerminalPixelSize,
    TerminalCellPixelSize, TerminalKittyFlags

  TerminalInputEvent* = object
    case kind*: TerminalInputEventKind
    of TerminalText:
      text*: string
      textMods*: UiModifiers
    of TerminalKey:
      key*: UiKey
      keyMods*: UiModifiers
      action*: TerminalInputAction
    of TerminalMouseButton:
      button*: UiMouseButton
      mouseAction*: TerminalInputAction
      buttonMods*: UiModifiers
      buttonX*, buttonY*: int
    of TerminalMouseMove:
      moveMods*: UiModifiers
      moveX*, moveY*: int
      dragButton*: int
    of TerminalMouseWheel:
      wheelDelta*: int
      wheelMods*: UiModifiers
      wheelX*, wheelY*: int
    of TerminalGridSize, TerminalPixelSize, TerminalCellPixelSize:
      width*, height*: int
    of TerminalKittyFlags:
      kittyFlags*: int

  TerminalInputParser* = object
    pending*: string
    escapeStartedAt: uint64
    escapeTimeoutMs*: int = DefaultEscapeTimeoutMs

func utf8SequenceLength(first: char): int {.inline.} =
  let value = first.uint8
  if value < 0x80'u8: 1
  elif (value and 0xe0'u8) == 0xc0'u8: 2
  elif (value and 0xf0'u8) == 0xe0'u8: 3
  elif (value and 0xf8'u8) == 0xf0'u8: 4
  else: 1

func modifierSet(encoded: int): UiModifiers =
  var modifiers: UiModifiers = {}
  let bits = max(0, encoded - 1)
  if (bits and 1) != 0: modifiers.incl ModShift
  if (bits and 2) != 0: modifiers.incl ModAlt
  if (bits and 4) != 0: modifiers.incl ModControl
  if (bits and 8) != 0: modifiers.incl ModSuper
  return modifiers

func keyForAscii(value: int): tuple[found: bool, key: UiKey] =
  if value >= ord('a') and value <= ord('z'):
    return (true, UiKey(ord(KeyA) + value - ord('a')))
  if value >= ord('A') and value <= ord('Z'):
    return (true, UiKey(ord(KeyA) + value - ord('A')))
  if value >= ord('0') and value <= ord('9'):
    return (true, UiKey(ord(Key0) + value - ord('0')))
  return case value
  of 32: (true, KeySpace)
  of ord(';'): (true, KeySemicolon)
  of ord('\''): (true, KeyApostrophe)
  of ord(','): (true, KeyComma)
  of ord('-'): (true, KeyMinus)
  of ord('.'): (true, KeyPeriod)
  of ord('/'): (true, KeySlash)
  of ord('\\'): (true, KeyBackslash)
  of ord('['): (true, KeyLeftBracket)
  of ord(']'): (true, KeyRightBracket)
  of ord('`'): (true, KeyGrave)
  else: (false, default(UiKey))

func keyForKitty(value: int): tuple[found: bool, key: UiKey] =
  let ascii = keyForAscii(value)
  if ascii.found:
    return ascii
  return case value
  of 9: (true, KeyTab)
  of 13: (true, KeyEnter)
  of 27: (true, KeyEscape)
  of 127: (true, KeyBackspace)
  of 57399..57408: (true, UiKey(ord(KeyKp0) + value - 57399))
  of 57409: (true, KeyKpDecimal)
  of 57410: (true, KeyKpDivide)
  of 57411: (true, KeyKpMultiply)
  of 57412: (true, KeyKpSubtract)
  of 57413: (true, KeyKpAdd)
  of 57414: (true, KeyKpEnter)
  of 57417: (true, KeyLeft)
  of 57418: (true, KeyRight)
  of 57419: (true, KeyUp)
  of 57420: (true, KeyDown)
  of 57421: (true, KeyPageUp)
  of 57422: (true, KeyPageDown)
  of 57423: (true, KeyHome)
  of 57424: (true, KeyEnd)
  of 57425: (true, KeyInsert)
  of 57426: (true, KeyDelete)
  else: (false, default(UiKey))

proc parseDecimal(value: string, defaultValue = 0): int =
  if value.len == 0:
    return defaultValue
  var parsed = 0
  for character in value:
    if character < '0' or character > '9':
      return defaultValue
    parsed = parsed * 10 + character.ord - '0'.ord
  return parsed

proc csiGroups(body: string): seq[seq[int]] =
  var parsedGroups: seq[seq[int]] = @[]
  var value = body
  while value.len > 0 and value[0] in {'?', '>', '<', '='}:
    value.delete(0 .. 0)
  for group in value.split(';'):
    var parts: seq[int] = @[]
    for part in group.split(':'):
      parts.add parseDecimal(part)
    parsedGroups.add parts
  if parsedGroups.len == 0:
    parsedGroups.add @[0]
  return parsedGroups

func groupValue(groups: seq[seq[int]], group, part: int, defaultValue = 0): int =
  if group >= 0 and group < groups.len and part >= 0 and part < groups[group].len:
    return groups[group][part]
  else:
    return defaultValue

proc addKey(result: var seq[TerminalInputEvent], key: UiKey,
    mods: UiModifiers = {}, action = InputPress) =
  result.add TerminalInputEvent(kind: TerminalKey, key: key, keyMods: mods, action: action)

proc parseCsi(sequence: string, result: var seq[TerminalInputEvent]) =
  if sequence.len < 3:
    return
  let command = sequence[^1]
  let body = sequence[2 ..< sequence.high]
  let leader = if body.len > 0 and body[0] in {'?', '>', '<', '='}: body[0] else: '\0'
  let groups = csiGroups(body)
  let first = groupValue(groups, 0, 0)
  let mods = modifierSet(groupValue(groups, 1, 0, 1))
  let action = case groupValue(groups, 1, 1, 1)
    of 2: InputRepeat
    of 3: InputRelease
    else: InputPress

  case command
  of 'A': result.addKey(KeyUp, mods, action)
  of 'B': result.addKey(KeyDown, mods, action)
  of 'C': result.addKey(KeyRight, mods, action)
  of 'D': result.addKey(KeyLeft, mods, action)
  of 'F': result.addKey(KeyEnd, mods, action)
  of 'H': result.addKey(KeyHome, mods, action)
  of 'P': result.addKey(KeyF1, mods, action)
  of 'Q': result.addKey(KeyF2, mods, action)
  of 'R': result.addKey(KeyF3, mods, action)
  of 'S': result.addKey(KeyF4, mods, action)
  of 'Z': result.addKey(KeyTab, mods + {ModShift}, action)
  of '~':
    let mapped = case first
      of 2: (true, KeyInsert)
      of 3: (true, KeyDelete)
      of 5: (true, KeyPageUp)
      of 6: (true, KeyPageDown)
      of 11..15: (true, UiKey(ord(KeyF1) + first - 11))
      of 17..21: (true, UiKey(ord(KeyF6) + first - 17))
      of 23..24: (true, UiKey(ord(KeyF11) + first - 23))
      else: (false, default(UiKey))
    if mapped[0]: result.addKey(mapped[1], mods, action)
  of 'u':
    if leader == '?':
      result.add TerminalInputEvent(kind: TerminalKittyFlags, kittyFlags: first)
    else:
      var associatedText = ""
      if groups.len > 2:
        for value in groups[2]:
          if value > 0 and value <= 0x10ffff:
            associatedText.add $Rune(value)
      let mapped = keyForKitty(first)
      if associatedText.len > 0 and first > 32 and first != 127 and action != InputRelease:
        result.add TerminalInputEvent(kind: TerminalText, text: associatedText, textMods: mods)
      elif mapped.found:
        result.addKey(mapped.key, mods, action)
  of 't':
    if groups.len >= 3:
      let height = groupValue(groups, 1, 0)
      let width = groupValue(groups, 2, 0)
      case first
      of 4, 6: result.add TerminalInputEvent(kind: TerminalPixelSize, width: width, height: height)
      of 5: result.add TerminalInputEvent(kind: TerminalCellPixelSize, width: width, height: height)
      of 8: result.add TerminalInputEvent(kind: TerminalGridSize, width: width, height: height)
      else: discard
  of 'm', 'M':
    if groups.len >= 3:
      let code = first
      let x = groupValue(groups, 1, 0) - 1
      let y = groupValue(groups, 2, 0) - 1
      let mouseMods = modifierSet(((code shr 2) and 7) + 1)
      if (code and 0x40) != 0:
        let delta = if (code and 1) == 0: 1 else: -1
        result.add TerminalInputEvent(kind: TerminalMouseWheel,
          wheelDelta: delta, wheelMods: mouseMods, wheelX: x, wheelY: y)
      elif (code and 0x20) != 0:
        let button = if (code and 3) == 3: -1 else: code and 3
        result.add TerminalInputEvent(kind: TerminalMouseMove,
          moveMods: mouseMods, moveX: x, moveY: y, dragButton: button)
      else:
        let button = case code and 3
          of 0: MouseLeft
          of 1: MouseMiddle
          else: MouseRight
        result.add TerminalInputEvent(kind: TerminalMouseButton, button: button,
          mouseAction: (if command == 'M': InputPress else: InputRelease),
          buttonMods: mouseMods, buttonX: x, buttonY: y)
  else:
    discard

proc parseAvailable(parser: var TerminalInputParser): seq[TerminalInputEvent] =
  result = @[]
  var consumed = 0
  while consumed < parser.pending.len:
    let value = parser.pending[consumed].uint8
    if value == 0x1b'u8:
      if consumed + 1 >= parser.pending.len:
        break
      let next = parser.pending[consumed + 1]
      if next == '[':
        var finish = consumed + 2
        while finish < parser.pending.len and parser.pending[finish].ord notin 0x40..0x7e:
          inc finish
        if finish >= parser.pending.len:
          break
        parseCsi(parser.pending[consumed .. finish], result)
        consumed = finish + 1
        continue
      if next == 'O':
        if consumed + 2 >= parser.pending.len:
          break
        case parser.pending[consumed + 2]
        of 'P': result.addKey(KeyF1)
        of 'Q': result.addKey(KeyF2)
        of 'R': result.addKey(KeyF3)
        of 'S': result.addKey(KeyF4)
        else: discard
        consumed += 3
        continue
      let runeBytes = utf8SequenceLength(next)
      if consumed + 1 + runeBytes > parser.pending.len:
        break
      let rune = parser.pending.runeAt(consumed + 1)
      let mapped = keyForAscii(rune.int)
      if mapped.found:
        result.addKey(mapped.key, {ModAlt})
      else:
        result.add TerminalInputEvent(kind: TerminalText, text: $rune, textMods: {ModAlt})
      consumed += 1 + runeBytes
      continue

    case value
    of 0x01'u8..0x07'u8, 0x0b'u8, 0x0c'u8, 0x0e'u8..0x1a'u8:
      let key = UiKey(ord(KeyA) + value.int - 1)
      result.addKey(key, {ModControl})
      inc consumed
    of 0x08'u8, 0x7f'u8:
      result.addKey(KeyBackspace)
      inc consumed
    of 0x09'u8:
      result.addKey(KeyTab)
      inc consumed
    of 0x0a'u8, 0x0d'u8:
      result.addKey(KeyEnter)
      inc consumed
    of 0x1c'u8..0x1f'u8:
      inc consumed
    else:
      let runeBytes = utf8SequenceLength(parser.pending[consumed])
      if consumed + runeBytes > parser.pending.len:
        break
      let rune = parser.pending.runeAt(consumed)
      let mapped = keyForAscii(rune.int)
      if mapped.found:
        result.addKey(mapped.key)
      result.add TerminalInputEvent(kind: TerminalText,
        text: parser.pending[consumed ..< consumed + runeBytes], textMods: {})
      consumed += runeBytes

  if consumed > 0:
    parser.pending.delete(0 .. consumed - 1)
  if parser.pending == "\e" and parser.escapeStartedAt == 0:
    parser.escapeStartedAt = getTicksNS()
  elif parser.pending != "\e":
    parser.escapeStartedAt = 0

proc parseInput*(parser: var TerminalInputParser, input: openArray[char]): seq[TerminalInputEvent] =
  if input.len > 0:
    for value in input:
      parser.pending.add value
  result = parser.parseAvailable()
  if parser.pending == "\e" and parser.escapeStartedAt > 0 and
      (getTicksNS() - parser.escapeStartedAt) div 1_000_000'u64 >= parser.escapeTimeoutMs.uint64:
    result.addKey(KeyEscape)
    parser.pending.setLen(0)
    parser.escapeStartedAt = 0
