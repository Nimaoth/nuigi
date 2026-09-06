
## Single-line text input with persistent cursor state.

import std/[math, unicode]
import nuigi
import nuigi/debug/profiler
import nuigi/text/graphemes

type TextFieldStorage* = ref object of UiNodeStorageData
  cursorPos*: int
  selectionAnchor*: int
  selectionActive*: bool
  scrollOffsetX*: float32
  dragAnchor: int
  draggingSelection: bool
  textNodeIndex: int
  selectionNodeIndex: int
  cursorNodeIndex: int
  textWidth: float32
  cursorX: float32
  selectionX: float32
  selectionWidth: float32

proc getOrCreateTextFieldStorage*(b: var UiBuilder, node: ptr UiNode): TextFieldStorage =
  let existing = nodeStorageGet(b, node)
  if existing != nil:
    return cast[TextFieldStorage](existing)
  var storage = TextFieldStorage(
    textNodeIndex: -1, selectionNodeIndex: -1, cursorNodeIndex: -1)
  nodeStorage(b, node, storage)
  return storage

proc isWhitespaceAt(text: string, position: int): bool =
  position >= 0 and position < text.len and text.runeAt(position).isWhiteSpace

proc previousWordBoundary(text: string, position: int): int =
  result = text.graphemeBoundaryAtOrBefore(position)
  while result > 0:
    let previous = text.previousGraphemeBoundary(result)
    if not text.isWhitespaceAt(previous):
      break
    result = previous
  while result > 0:
    let previous = text.previousGraphemeBoundary(result)
    if text.isWhitespaceAt(previous):
      break
    result = previous

proc nextWordBoundary(text: string, position: int): int =
  result = text.graphemeBoundaryAtOrBefore(position)
  while result < text.len and not text.isWhitespaceAt(result):
    result = text.nextGraphemeBoundary(result)
  while result < text.len and text.isWhitespaceAt(result):
    result = text.nextGraphemeBoundary(result)

type TextFieldCharacterClass = enum
  CharacterWhitespace
  CharacterWord
  CharacterOther

proc characterClassAt(text: string, position: int): TextFieldCharacterClass =
  let rune = text.runeAt(position)
  if rune.isWhiteSpace:
    CharacterWhitespace
  elif rune.isAlpha or (rune.int >= ord('0') and rune.int <= ord('9')) or
      rune.int == ord('_'):
    CharacterWord
  else:
    CharacterOther

proc selectWordAt(text: string, storage: TextFieldStorage, position: int) =
  if text.len == 0:
    storage.cursorPos = 0
    storage.selectionActive = false
    return

  var first = text.graphemeBoundaryAtOrBefore(position)
  if first == text.len:
    first = text.previousGraphemeBoundary(first)
  let characterClass = text.characterClassAt(first)
  var last = text.nextGraphemeBoundary(first)

  if characterClass != CharacterOther:
    while first > 0:
      let previous = text.previousGraphemeBoundary(first)
      if text.characterClassAt(previous) != characterClass:
        break
      first = previous
    while last < text.len and text.characterClassAt(last) == characterClass:
      last = text.nextGraphemeBoundary(last)

  storage.selectionAnchor = first
  storage.cursorPos = last
  storage.selectionActive = first != last

proc hasSelection(storage: TextFieldStorage): bool {.inline.} =
  storage.selectionActive and storage.selectionAnchor != storage.cursorPos

proc selectionRange(storage: TextFieldStorage): tuple[first, last: int] =
  (min(storage.selectionAnchor, storage.cursorPos),
    max(storage.selectionAnchor, storage.cursorPos))

proc replaceRange(text: var string, first, last: int, replacement: string) =
  var updated = newStringOfCap(text.len - (last - first) + replacement.len)
  if first > 0:
    updated.add(text[0 ..< first])
  updated.add(replacement)
  if last < text.len:
    updated.add(text[last .. text.high])
  text = updated

proc deleteSelection(text: var string, storage: TextFieldStorage): bool =
  if not storage.hasSelection:
    return false
  let selected = storage.selectionRange
  text.replaceRange(selected.first, selected.last, "")
  storage.cursorPos = selected.first
  storage.selectionActive = false
  true

proc sanitizedSingleLine(text: string): string =
  result = newStringOfCap(text.len)
  for rune in text.runes:
    if rune != Rune(0x0a) and rune != Rune(0x0d):
      result.add($rune)

proc insertText(text: var string, storage: TextFieldStorage, insertedText: string) =
  let inserted = insertedText.sanitizedSingleLine
  discard text.deleteSelection(storage)
  if inserted.len == 0:
    return
  text.replaceRange(storage.cursorPos, storage.cursorPos, inserted)
  storage.cursorPos += inserted.len
  storage.selectionActive = false

proc moveCursor(storage: TextFieldStorage, target: int, selecting: bool) =
  if selecting:
    if not storage.selectionActive:
      storage.selectionAnchor = storage.cursorPos
      storage.selectionActive = true
  else:
    storage.selectionActive = false
  storage.cursorPos = target
  if storage.selectionAnchor == storage.cursorPos:
    storage.selectionActive = false

proc measuredPrefixWidth(b: var UiBuilder, text: string, byteCount: int,
    textStyle: UiNodeText): float32 =
  if byteCount <= 0:
    return 0.0'f32
  var prefixStyle = textStyle
  prefixStyle.text = text[0 ..< byteCount].uiString
  b.measuredTextSize(prefixStyle.addr).x

proc cursorPositionAtX(b: var UiBuilder, text: string, pointerX: float32,
    textStyle: UiNodeText): int =
  if pointerX <= 0.0'f32 or text.len == 0:
    return 0
  var previousPosition = 0
  var position = text.nextGraphemeBoundary(0)
  while position <= text.len:
    let previousX = b.measuredPrefixWidth(text, previousPosition, textStyle)
    let currentX = b.measuredPrefixWidth(text, position, textStyle)
    if pointerX < (previousX + currentX) * 0.5'f32:
      return previousPosition
    if position == text.len:
      return text.len
    previousPosition = position
    position = text.nextGraphemeBoundary(position)
  text.len

proc textFieldDeferred(b: var UiBuilder, nodeIdx: int, rawData: int) {.nimcall.} =
  if rawData == 0 or nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let storage = cast[TextFieldStorage](rawData)
  let node = b.frame.nodes[nodeIdx].addr
  let style = b.nodeStyle(nodeIdx)
  let contentWidth = max(0.0'f32, node.size.x - style.paddingX * 2.0'f32)
  let cursorWidth = if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 2.0'f32
  let cursorAllowance =
    if storage.textWidth > contentWidth: cursorWidth
    else: 0.0'f32

  if storage.cursorX < storage.scrollOffsetX:
    storage.scrollOffsetX = storage.cursorX
  elif storage.cursorX + cursorAllowance > storage.scrollOffsetX + contentWidth:
    storage.scrollOffsetX = storage.cursorX + cursorAllowance - contentWidth
  storage.scrollOffsetX = clamp(storage.scrollOffsetX,
    0.0'f32, max(0.0'f32, storage.textWidth + cursorAllowance - contentWidth))

  if storage.textNodeIndex >= 0:
    b.frame.nodes[storage.textNodeIndex].pos.x = -storage.scrollOffsetX
  if storage.selectionNodeIndex >= 0:
    b.frame.nodes[storage.selectionNodeIndex].pos.x =
      storage.selectionX - storage.scrollOffsetX
  if storage.cursorNodeIndex >= 0:
    b.frame.nodes[storage.cursorNodeIndex].pos.x =
      (storage.cursorX - storage.scrollOffsetX).round()

  if b.focusedNode == node.id:
    let absolutePos = b.absoluteNodePos(nodeIdx)
    b.textInputRequest = UiTextInputRequest(
      active: true,
      rectPos: absolutePos,
      rectSize: node.size,
      cursorOffset: style.paddingX + storage.cursorX - storage.scrollOffsetX)

proc textField*(b: var UiBuilder, text: var string, hint: string = "",
  state: nil TextFieldStorage = nil, maxWidth = 0.0'f32,
  minWidth = 0.0'f32): bool =
  prof("textField")
  var submitted = false

  discard b.pushId(hint)
  b.node("textfield"):
    let nodeId = b.currentNode.id
    let nodePtr = b.currentNode
    let nodeIndex = b.currentNodeIndex
    discard b.focusable({FocusTabStop, FocusTextInput})
    let storage: TextFieldStorage = if state != nil:
      cast[TextFieldStorage](state)
    else:
      getOrCreateTextFieldStorage(b, nodePtr)
    storage.cursorPos = text.graphemeBoundaryAtOrBefore(storage.cursorPos)
    if storage.selectionActive:
      storage.selectionAnchor = text.graphemeBoundaryAtOrBefore(storage.selectionAnchor)

    let textStyle = b.themeTextStyle(UiStyleIndexTextFieldText)[]
    if b.wasPressed(nodeId, includeChildren = true, indexHint = nodeIndex):
      b.requestFocus()
      let previousPos = b.absoluteNodePosPrev(nodeId, nodeIndex)
      let style = b.themeStyle(UiStyleIndexTextField)[]
      let pointerX = b.frameCtx.input.mouse.x - previousPos.x - style.paddingX +
        storage.scrollOffsetX
      storage.cursorPos = b.cursorPositionAtX(text, pointerX, textStyle)
      case b.frameCtx.input.mouseClickCount
      of 2:
        text.selectWordAt(storage, storage.cursorPos)
        storage.draggingSelection = false
      of 3..uint8.high:
        storage.selectionAnchor = 0
        storage.cursorPos = text.len
        storage.selectionActive = text.len > 0
        storage.draggingSelection = false
      else:
        storage.selectionActive = false
        storage.dragAnchor = storage.cursorPos
        storage.draggingSelection = true
    elif b.isFocused() and MouseLeft in b.frameCtx.input.mouseDown and
        storage.draggingSelection and
        b.wasHeld(nodeId, includeChildren = true, indexHint = nodeIndex):
      let previousPos = b.absoluteNodePosPrev(nodeId, nodeIndex)
      let style = b.themeStyle(UiStyleIndexTextFieldFocused)[]
      let pointerX = b.frameCtx.input.mouse.x - previousPos.x - style.paddingX +
        storage.scrollOffsetX
      storage.selectionAnchor = storage.dragAnchor
      storage.selectionActive = true
      storage.cursorPos = b.cursorPositionAtX(text, pointerX, textStyle)
      if storage.selectionAnchor == storage.cursorPos:
        storage.selectionActive = false
    elif MouseLeft notin b.frameCtx.input.mouseDown:
      storage.draggingSelection = false

    let isFocused = b.isFocused()

    discard b.styleIndex(if isFocused: UiStyleIndexTextFieldFocused else: UiStyleIndexTextField)
    discard b.focusHighlight()
    discard b.fitX().fitY()
    discard b.fillBackground()

    let input = b.frameCtx.input

    if isFocused:
      let primaryModifier = ModControl in input.modsDown or ModSuper in input.modsDown
      let selecting = ModShift in input.modsDown

      if primaryModifier and KeyA in input.keysPressed:
        storage.selectionAnchor = 0
        storage.selectionActive = true
        storage.cursorPos = text.len
      if primaryModifier and KeyC in input.keysPressed and storage.hasSelection and
          b.writeClipboardFn != nil:
        let selected = storage.selectionRange
        discard b.writeClipboardFn(text[selected.first ..< selected.last])
      if primaryModifier and KeyX in input.keysPressed and storage.hasSelection and
          b.writeClipboardFn != nil:
        let selected = storage.selectionRange
        if b.writeClipboardFn(text[selected.first ..< selected.last]):
          discard text.deleteSelection(storage)
      if primaryModifier and KeyV in input.keysPressed and b.readClipboardFn != nil:
        text.insertText(storage, b.readClipboardFn())

      if KeyLeft in input.keysPressed or KeyLeft in input.keysRepeated:
        if not selecting and storage.hasSelection:
          let selected = storage.selectionRange
          storage.moveCursor(selected.first, false)
        else:
          let target = if primaryModifier:
            text.previousWordBoundary(storage.cursorPos)
          else:
            text.previousGraphemeBoundary(storage.cursorPos)
          storage.moveCursor(target, selecting)
      if KeyRight in input.keysPressed or KeyRight in input.keysRepeated:
        if not selecting and storage.hasSelection:
          let selected = storage.selectionRange
          storage.moveCursor(selected.last, false)
        else:
          let target = if primaryModifier:
            text.nextWordBoundary(storage.cursorPos)
          else:
            text.nextGraphemeBoundary(storage.cursorPos)
          storage.moveCursor(target, selecting)
      if KeyHome in input.keysPressed or KeyHome in input.keysRepeated:
        storage.moveCursor(0, selecting)
      if KeyEnd in input.keysPressed or KeyEnd in input.keysRepeated:
        storage.moveCursor(text.len, selecting)

      if KeyBackspace in input.keysPressed or KeyBackspace in input.keysRepeated:
        if not text.deleteSelection(storage) and storage.cursorPos > 0:
          let first = if primaryModifier:
            text.previousWordBoundary(storage.cursorPos)
          else:
            text.previousGraphemeBoundary(storage.cursorPos)
          text.replaceRange(first, storage.cursorPos, "")
          storage.cursorPos = first
      if KeyDelete in input.keysPressed or KeyDelete in input.keysRepeated:
        if not text.deleteSelection(storage) and storage.cursorPos < text.len:
          let last = if primaryModifier:
            text.nextWordBoundary(storage.cursorPos)
          else:
            text.nextGraphemeBoundary(storage.cursorPos)
          text.replaceRange(storage.cursorPos, last, "")

      if input.textInput.len > 0:
        text.insertText(storage, input.textInput)

      if KeyEscape in input.keysPressed:
        storage.selectionActive = false
        b.clearFocus()
      if KeyEnter in input.keysPressed:
        storage.selectionActive = false
        b.clearFocus()
        submitted = true

    storage.textWidth = b.measuredPrefixWidth(text, text.len, textStyle)
    storage.cursorX = b.measuredPrefixWidth(text, storage.cursorPos, textStyle)
    storage.selectionNodeIndex = -1
    storage.cursorNodeIndex = -1

    b.node:
      b.debugName("textfield-text-container")
      discard b.maskChildren()
      discard b.fitX().fitY()
      if minWidth > 0.0'f32:
        discard b.minWidth(minWidth)
      if maxWidth > 0.0'f32:
        discard b.maxWidth(maxWidth)

      if isFocused and storage.hasSelection:
        let selected = storage.selectionRange
        storage.selectionX = b.measuredPrefixWidth(text, selected.first, textStyle)
        let selectionEndX = b.measuredPrefixWidth(text, selected.last, textStyle)
        storage.selectionWidth = selectionEndX - storage.selectionX
        b.node("textfield-selection"):
          storage.selectionNodeIndex = b.currentNodeIndex
          discard b.styleIndex(UiStyleIndexAccent)
          discard b.position(storage.selectionX, 0.0'f32)
          discard b.width(storage.selectionWidth).fillY()
          discard b.fillBackground().ignoreInContentExtent().noHover()

      b.node:
        b.debugName("textfield-text")
        storage.textNodeIndex = b.currentNodeIndex
        discard b.styleIndex(if text.len > 0: UiStyleIndexDefault else: UiStyleIndexTextFieldHint)
        discard b.copyTextStyleIndex(if text.len > 0: UiStyleIndexTextFieldText else: UiStyleIndexTextFieldHintText)
        discard b.position(0, 0).fitX().fitY().anchorsY(0.5, 0.5).pivotY(0.5).finishAnchors().noHover()
        discard b.text(if text.len > 0: text else: hint)

    let fieldStyle = b.nodeStyle(b.currentNode)
    let cursorWidth = if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 2.0'f32
    let naturalWidth = b.currentNode.contentExtent.x + fieldStyle.paddingX * 2.0'f32 + cursorWidth
    b.currentNode.contentExtent.x =
      ceil(naturalWidth - fieldStyle.paddingX * 2.0'f32)

    if isFocused and not storage.hasSelection:
      b.node("textfield-cursor"):
        storage.cursorNodeIndex = b.currentNodeIndex
        discard b.styleIndex(UiStyleIndexTextCursor)
        discard b.position(storage.cursorX, 0.0'f32)
        discard b.width(if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 2.0'f32).fillY()
        discard b.fillBackground().ignoreInContentExtent().noHover()

    discard b.deferBuild(textFieldDeferred, cast[int](storage))
  discard b.popId()

  submitted