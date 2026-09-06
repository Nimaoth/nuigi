
## Single-line text input with persistent cursor state.

import nuigi
import nuigi/debug/profiler

type TextFieldStorage* = ref object of UiNodeStorageData
  cursorPos*: int

proc getOrCreateTextFieldStorage*(b: var UiBuilder, node: ptr UiNode): TextFieldStorage =
  let existing = nodeStorageGet(b, node)
  if existing != nil:
    return cast[TextFieldStorage](existing)
  var storage: TextFieldStorage
  new(storage)
  nodeStorage(b, node, storage)
  return storage

proc textFieldInsertChar(text: var string, cursorPos: var int, ch: char) =
  var s = newString(text.len + 1)
  for i in 0..<cursorPos:
    s[i] = text[int(i)]
  s[int(cursorPos)] = ch
  for i in cursorPos..<text.len:
    s[int(i+1)] = text[int(i)]
  text = s
  inc cursorPos

proc textField*(b: var UiBuilder, text: var string, hint: string = "", state: nil TextFieldStorage = nil): bool =
  prof("textField")
  var submitted = false

  discard b.pushId(hint)
  b.node("textfield"):
    let nodeId = b.currentNode.id
    let nodePtr = b.currentNode
    discard b.focusable({FocusTabStop, FocusTextInput})
    if b.previousOutput.clickedId == nodeId:
      b.requestFocus()
    let isFocused = b.isFocused()
    let storage: TextFieldStorage = if state != nil:
      cast[TextFieldStorage](state)
    else:
      getOrCreateTextFieldStorage(b, nodePtr)
    storage.cursorPos = clamp(storage.cursorPos, 0, text.len)

    discard b.styleIndex(if isFocused: UiStyleIndexTextFieldFocused else: UiStyleIndexTextField)
    discard b.focusHighlight()
    discard b.fitX().fitY()
    discard b.fillBackground()

    let input = b.frameCtx.input

    if isFocused:
      for ch in input.textInput:
        text.textFieldInsertChar(storage.cursorPos, ch)

      for key in input.keysPressed:
        case key
        of KeyBackspace:
          if storage.cursorPos > 0:
            var s = newString(text.len - 1)
            for i in 0..<storage.cursorPos-1:
              s[i] = text[int(i)]
            for i in storage.cursorPos..<text.len:
              s[int(i-1)] = text[int(i)]
            text = s
            dec storage.cursorPos
        of KeyDelete:
          if storage.cursorPos < text.len:
            var s = newString(text.len - 1)
            for i in 0..<storage.cursorPos:
              s[i] = text[int(i)]
            for i in storage.cursorPos+1..<text.len:
              s[int(i-1)] = text[int(i)]
            text = s
        of KeyLeft: storage.cursorPos = max(0, storage.cursorPos - 1)
        of KeyRight: storage.cursorPos = min(text.len, storage.cursorPos + 1)
        of KeyHome: storage.cursorPos = 0
        of KeyEnd: storage.cursorPos = text.len
        of KeyEscape: b.clearFocus()
        of KeyEnter:
          b.clearFocus()
          submitted = true
        else: discard

      for key in input.keysRepeated:
        case key
        of KeyBackspace:
          if storage.cursorPos > 0:
            var s = newString(text.len - 1)
            for i in 0..<storage.cursorPos-1:
              s[i] = text[int(i)]
            for i in storage.cursorPos..<text.len:
              s[int(i-1)] = text[int(i)]
            text = s
            dec storage.cursorPos
        of KeyDelete:
          if storage.cursorPos < text.len:
            var s = newString(text.len - 1)
            for i in 0..<storage.cursorPos:
              s[i] = text[int(i)]
            for i in storage.cursorPos+1..<text.len:
              s[int(i-1)] = text[int(i)]
            text = s
        of KeyLeft: storage.cursorPos = max(0, storage.cursorPos - 1)
        of KeyRight: storage.cursorPos = min(text.len, storage.cursorPos + 1)
        of KeyHome: storage.cursorPos = 0
        of KeyEnd: storage.cursorPos = text.len
        of KeyEscape: b.clearFocus()
        of KeyEnter:
          b.clearFocus()
          submitted = true
        else: discard

    b.node("textfield-text"):
      discard b.styleIndex(if text.len > 0: UiStyleIndexDefault else: UiStyleIndexTextFieldHint)
      discard b.copyTextStyleIndex(if text.len > 0: UiStyleIndexTextFieldText else: UiStyleIndexTextFieldHintText)
      discard b.position(0, 0).fitX().fitY().anchorsY(0.5, 0.5).pivotY(0.5).finishAnchors().noHover()
      discard b.text(if text.len > 0: text else: hint)

    if isFocused:
      var ttext = newString(storage.cursorPos)
      for i in 0..<storage.cursorPos:
        ttext[i] = text[int(i)]
      var cursorText = UiNodeText(
        text: ttext.uiString,
        fontSize: b.nodeText(b.currentNode).fontSize,
      )
      let cursorW = b.measuredTextSize(cursorText.addr).x
      b.node("textfield-cursor"):
        discard b.styleIndex(UiStyleIndexTextCursor)
        discard b.position(cursorW, 1.0'f32)
        discard b.width(1.5).fillY()
        discard b.fillBackground()
  discard b.popId()

  submitted