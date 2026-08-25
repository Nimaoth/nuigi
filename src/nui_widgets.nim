import nui
import mymath, arena
import array_view
import profiler

import nui_flex

include compat2

type UiVirtualListItemProc* = proc(b: var UiBuilder, itemIndex: int, userData: int) {.nimcall.}

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

proc virtualList*(b: var UiBuilder,
    scrollOffset: var float,
    inItemCount: int,
    inItemHeight: float32,
    inBuildItem: UiVirtualListItemProc,
    inItemUserData: int = 0)

template label*(b: var UiBuilder, inText: string, body: untyped): untyped =
  b.node:
    discard b.fitX().fitY()
    discard b.copyTextStyleIndex(UiStyleIndexLabel)
    body
    discard b.text(inText)

template labelWrapped*(b: var UiBuilder, inText: string, body: untyped): untyped =
  b.node:
    discard b.wrapText().fitY()
    discard b.copyTextStyleIndex(UiStyleIndexLabel)
    body
    discard b.text(inText)

proc label*(b: var UiBuilder, inText: string) =
  b.node:
    discard b.fitX().fitY()
    discard b.copyTextStyleIndex(UiStyleIndexLabel)
    discard b.text(inText)

template tooltip*(b: var UiBuilder, body: untyped): untyped =
  block:
    prof("tooltip")
    let input = b.frameCtx.input
    b.withParent(b.overlays):
      b.node("tooltip"):
        body
        discard b.offsets(input.mouse.x, input.mouse.y, 0, 0).pivot(0, 1).finishAnchors().noHover()

template tabBar*(b: var UiBuilder, tabs: openArray[string], activeTab: var int, body: untyped): untyped =
  block:
    prof("tabBar")
    if tabs.len <= 0:
      activeTab = 0
    else:
      activeTab = clamp(activeTab, 0, tabs.len - 1)

    b.layoutVertical("tab-bar"):
      discard b.sizeToParentX().sizeToParentY()

      b.node("tab-bar-header"):
        discard b.styleIndex(UiStyleIndexTabBarHeader)
        discard b.fillX().fitY().gap(4)
        discard b.flexLayout(true).flexFlow(FlexDirectionRow, FlexWrap)
        discard b.animateHeight().animateDelayed()
        discard b.fillBackground()

        for i in 0 ..< tabs.len:
          let isActive = i == activeTab
          let tabNodeIndex = b.nodes.len
          discard b.pushId(i.uint64)
          b.node("tab-bar-item"):
            discard b.styleIndex(if isActive: UiStyleIndexTabBarItemActive else: UiStyleIndexTabBarItem)
            discard b.copyTextStyleIndex(if isActive: UiStyleIndexTabBarItemActiveText else: UiStyleIndexTabBarItemText)
            discard b.fitX().fitY()
            discard b.fillBackground()
            discard b.text(tabs[i])
            discard b.animatePos().animateDelayed()
          discard b.popId()

          if b.wasClicked(tabNodeIndex, includeChildren = true):
            activeTab = i

      b.node("tab-bar-content"):
        discard b.styleIndex(UiStyleIndexTabBarContent)
        discard b.sizeToParentX().sizeToParentY()
        discard b.fillBackground()
        body

proc button*(b: var UiBuilder, text: string): bool =
  prof("button")
  let nodeIndex = b.nodes.len

  discard b.pushId(text)
  b.node("button"):
    discard b.copyStyleIndex(UiStyleIndexButton)
    discard b.copyTextStyleIndex(UiStyleIndexButtonText)
    discard b.fitX().fitY()
    discard b.text(text)
    let nodeId = b.currentNode.id
    let wasHovered = b.previousOutput.hoveredId == nodeId
    let hoverScale = if wasHovered: 1.15'f32 else: 1.0'f32
    discard b.fillBackground()
    b.animate(b.previousOutput.clickedId == nodeId or
        b.previousOutput.hoverBeganId == nodeId or
        b.previousOutput.hoverEndedId == nodeId):
      discard b.transformScaleAnim(hoverScale)
      discard b.backgroundColorAnim(if wasHovered:
        b.themeStyle(UiStyleIndexButtonHover)[].fillColor
      else:
        b.themeStyle(UiStyleIndexButton)[].fillColor)
      if b.previousOutput.clickedId == nodeId:
        b.ensureNodeStyle(b.currentNode).fillColor = b.themeTextStyle(UiStyleIndexButtonText)[].textColor
  discard b.popId()

  let id = b.nodes[nodeIndex].id
  b.previousOutput.clickedId == id

template menuItem*(b: var UiBuilder, inBody: untyped, inHovered: untyped, inClicked: untyped): untyped =
  block:
    prof("menuItem")
    b.layoutVertical:
      discard b.copyStyleIndex(UiStyleIndexMenuItem)
      discard b.fitX().fitY().fillX()
      inBody
      let wasHovered = b.wasHovered(b.stack[^1], includeChildren = true)
      discard b.fillBackground()
      discard b.backgroundColor(if wasHovered:
        b.themeStyle(UiStyleIndexMenuItemHover)[].fillColor
      else:
        b.themeStyle(UiStyleIndexMenuItem)[].fillColor)
      if wasHovered:
        b.ensureNodeText(b.currentNode).textColor = b.themeTextStyle(UiStyleIndexMenuItemHoverText)[].textColor
        inHovered
        discard
      else:
        b.ensureNodeText(b.currentNode).textColor = b.themeTextStyle(UiStyleIndexMenuItemText)[].textColor
      if b.wasClicked(includeChildren = true):
        inClicked
        discard

template menuItem*(b: var UiBuilder, inBody: untyped): untyped =
  menuItem(b, inBody):
    discard
  do:
    discard

template menuBarItem*(b: var UiBuilder, inOpen: var bool, inBody: untyped, inHovered: untyped, inClicked: untyped, onOpen: untyped): untyped =
  block:
    prof("menuBarItem")
    b.node:
      discard b.copyStyleIndex(UiStyleIndexMenuItem)
      discard b.fitX().fitY().padding(4)
      inBody
      let wasHovered = b.wasHovered(b.stack[^1], includeChildren = true)
      discard b.fillBackground()
      discard b.backgroundColor(if wasHovered:
        b.themeStyle(UiStyleIndexMenuItemHover)[].fillColor
      else:
        b.themeStyle(UiStyleIndexMenuItem)[].fillColor)
      if wasHovered:
        b.ensureNodeText(b.currentNode).textColor = b.themeTextStyle(UiStyleIndexMenuItemHoverText)[].textColor
        inHovered
        discard
      else:
        b.ensureNodeText(b.currentNode).textColor = b.themeTextStyle(UiStyleIndexMenuItemText)[].textColor
      if b.wasPressed(includeChildren = true):
        inOpen = not inOpen
        inClicked
        discard

    if inOpen:
      onOpen

template menuBar*(b: var UiBuilder, inBody: untyped): untyped =
  block:
    prof("menuBar")
    b.node("menu-bar"):
      discard b.fillX().fitY().padding(4).gap(4)
      discard b.flexLayout(true).flexFlow(FlexDirectionRow, FlexWrap)
      discard b.fillBackground().backgroundColor(rgba(0.11, 0.13, 0.18, 1.0))
      inBody

template menu*(b: var UiBuilder, inOpen: var bool, inAnchorX, inAnchorY: float32, inBody: untyped, inMinWidth: float32 = 160.0): untyped =
  block:
    prof("menu")
    if inOpen:
      var popupIdx = -1
      let input = b.frameCtx.input
      var previousNodeIndex = -1

      b.withParent(b.overlays):
        b.node("menu-popup"):
          popupIdx = b.stack[^1]
          discard b.deferPostProcess()
          discard b.position(inAnchorX, inAnchorY)
          discard b.layout(LayoutVertical)
          discard b.minWidth(inMinWidth)
          discard b.fitX().fitY()
          discard b.styleIndex(UiStyleIndexMenu)
          discard b.fillBackground()
          # When the window is removed from the live tree it is promoted to a virtual node;
          # animate its transform scale from 1 down to 0 so it shrinks away, then gets dropped.
          previousNodeIndex = b.previousNodeIndex(b.currentNode.id, b.currentNodeIndex)
          var previousScale = vec2(1.0'f32)
          if previousNodeIndex != -1:
            let n = b.previousFrame.nodes[previousNodeIndex]
            let transformSlot = int(n.transformIndex)
            if transformSlot > 0 and transformSlot <= b.previousFrame.transforms.len:
              previousScale = b.previousFrame.transforms[transformSlot - 1].scale
          let closeScaleAnim = @[
            UiFieldAnimation(
              currentValue: previousScale.x,
              targetValue: 0.0'f32,
              speed: 18.0'f32,
              fieldOffset: UiNodeTransformScaleXFieldOffset,
            ),
            UiFieldAnimation(
              currentValue: previousScale.y,
              targetValue: 0.0'f32,
              speed: 18.0'f32,
              fieldOffset: UiNodeTransformScaleYFieldOffset,
            ),
          ]
          discard b.virtualizeNode(closeScaleAnim)
          discard b.transformPivot(0, 0)
          b.animate:
            discard b.transformScaleAnim(1)
            if b.previousNodeIndex(b.currentNode.id, b.currentNodeIndex) == -1:
              discard b.transformScale(0)
          inBody

      if KeyEscape in input.keysPressed:
        inOpen = false

      if previousNodeIndex != -1 and VirtualNode notin b.previousFrame.nodes[previousNodeIndex].flags:
        if MouseLeft in input.mousePressed and popupIdx >= 0 and not b.wasHovered(popupIdx, includeChildren = true):
          inOpen = false

proc checkbox*(b: var UiBuilder, label: string, value: var bool, fillXInVertical = true): bool =
  prof("checkbox")
  var boxNodeId = noneNodeId()
  var previousBoxNodeIndex = -1
  var boxNodeIdx = -1

  discard b.pushId(label)
  b.layoutHorizontalReverse("checkbox"):
    discard b.fitX().fitY()
    discard b.gap(6)

    let parent = b.currentParent
    if fillXInVertical and parent != nil and LayoutVertical in parent.flags:
      discard b.fillX()

    b.node("checkbox-box"):
      discard b.styleIndex(UiStyleIndexCheckbox)
      discard b.size(14, 14)
      discard b.fillBackground()
      discard b.alignCenter()
      boxNodeIdx = b.nodes.high
      boxNodeId = b.currentNode.id

      b.node("checkbox-mark"):
        discard b.styleIndex(UiStyleIndexCheckboxMark)
        discard b.alignCenter()
        b.animate(b.wasClicked(boxNodeIdx, includeChildren = true)):
          if value:
            discard b.sizeAnim(8, 8)
          else:
            discard b.sizeAnim(0, 0)
        discard b.fillBackground()

      let boxIsHovered = b.wasHovered(boxNodeIdx, includeChildren = true)
      discard b.styleIndex(if boxIsHovered: UiStyleIndexCheckboxHover else: UiStyleIndexCheckbox)

    b.node("checkbox-label"):
      # discard b.padding(4)
      discard b.copyTextStyleIndex(UiStyleIndexLabel)
      discard b.fillX().fitX().fitY().alignCenter()
      discard b.text(label)
  discard b.popId()

  previousBoxNodeIndex = b.previousNodeIndex(boxNodeId, boxNodeIdx)
  let clicked =
    if previousBoxNodeIndex < 0:
      false
    else:
      b.wasClicked(boxNodeIdx, includeChildren = true)
  if clicked:
    value = not value
  clicked

proc slider*(b: var UiBuilder, label: string, value: var float32, minValue = 0.0'f32, maxValue = 1.0'f32, defaultValue = 0.5'f32): bool =
  prof("slider")
  let trackWidth = 160.0'f32
  let trackHeight = 18.0'f32
  let thumbWidth = 10.0'f32
  let low = min(minValue, maxValue)
  let high = max(minValue, maxValue)
  let span = max(0.0001'f32, high - low)
  value = clamp(value, low, high)

  var trackNodeId = noneNodeId()
  var trackNodeIdx = -1
  var previousTrackIndex = -1
  var normalized = clamp((value - low) / span, 0.0'f32, 1.0'f32)
  var thumbX = normalized * max(0.0'f32, trackWidth - thumbWidth)
  var fillWidth = max(thumbWidth, normalized * trackWidth)

  discard b.pushId(label)
  b.layoutVertical("slider"):
    discard b.padding(4)
    discard b.fitX().fitY()
    discard b.gap(4)

    b.node("slider-label"):
      discard b.styleIndex(UiStyleIndexSlider)
      discard b.copyTextStyleIndex(UiStyleIndexSliderText)
      discard b.fitX().fitY()
      discard b.text(label & ": " & fmt2(value))

    b.node("slider-track"):
      discard b.styleIndex(UiStyleIndexSliderTrack)
      discard b.size(trackWidth, trackHeight)
      discard b.fillBackground()

      trackNodeId = b.currentNode.id
      trackNodeIdx = b.stack[^1]
      previousTrackIndex = b.previousNodeIndex(trackNodeId, trackNodeIdx)
      let trackHovered = b.wasHovered(trackNodeIdx, includeChildren = true)
      discard b.styleIndex(if trackHovered: UiStyleIndexSliderTrackHover else: UiStyleIndexSliderTrack)

      b.node("slider-fill"):
        discard b.styleIndex(UiStyleIndexSliderFill)
        discard b.size(fillWidth, trackHeight)
        discard b.fillBackground()

      b.node("slider-thumb"):
        discard b.styleIndex(UiStyleIndexSliderHandle)
        discard b.position(thumbX, 1)
        discard b.size(thumbWidth, trackHeight - 2.0'f32)
        discard b.fillBackground()
  discard b.popId()

  let input = b.frameCtx.input
  previousTrackIndex = b.previousNodeIndex(trackNodeId, trackNodeIdx)
  let dragging =
    previousTrackIndex >= 0 and
    MouseLeft in input.mouseDown and
    b.wasHeld(trackNodeIdx, includeChildren = true)
  let clicked =
    previousTrackIndex >= 0 and
    b.wasClicked(trackNodeIdx, includeChildren = true)

  let rightClicked =
    previousTrackIndex >= 0 and
    b.wasRightClicked(trackNodeIdx, includeChildren = true)

  if rightClicked and trackNodeIdx >= 0 and trackNodeIdx < b.nodes.len:
    value = defaultValue

  if (dragging or clicked) and trackNodeIdx >= 0 and trackNodeIdx < b.nodes.len:
    let track = b.nodes[trackNodeIdx].addr
    let trackPos = b.absoluteNodePosPrev(b.nodes[trackNodeIdx].id, trackNodeIdx)
    let pointerT =
      if track.size.x <= 0.0'f32:
        0.0'f32
      else:
        clamp((input.mouse.x - trackPos.x) / track.size.x, 0.0'f32, 1.0'f32)
    let newValue = low + pointerT * span
    let changed = abs(newValue - value) > 0.0001'f32
    value = newValue
    return changed

  false

proc colorPicker*(b: var UiBuilder, value: var UiColor): bool =
  prof("colorPicker")
  var changed = false

  var swatchIdx = -1
  var swatchId = noneNodeId()
  var pickerIdx = -1
  b.node:
    b.debugName("color-picker")
    pickerIdx = b.stack[^1]
    discard b.size(38, 18)

    swatchIdx = b.stack[^1]
    swatchId = b.currentNode.id
    let swatchHovered = b.wasHovered(b.stack[^1], includeChildren = true)
    let swatchOpen = b.focusedNode == swatchId
    discard b.fillBackground()
    discard b.backgroundColor(value)
    discard b.borderWidth(if swatchOpen or swatchHovered: 2.0'f32 else: 1.0'f32)
    discard b.borderColor(if swatchOpen or swatchHovered: rgba(0.95, 0.86, 0.40, 1.0) else: rgba(0.64, 0.28, 0.34, 1.0))

  if b.previousOutput.clickedId == swatchId:
    if b.focusedNode == swatchId:
      b.focusedNode = noneNodeId()
    else:
      b.focusedNode = swatchId

  let pickerOpen = b.focusedNode == swatchId
  var popupIdx = -1
  if pickerOpen:
    if swatchIdx >= 0 and swatchIdx < b.nodes.len:
      let swatchAbsPos = b.absoluteNodePosPrev(swatchId, swatchIdx)
      let swatchNode = b.nodes[swatchIdx].addr

      b.withParent(b.overlays):
        b.node("color-picker-popup"):
          popupIdx = b.stack[^1]
          discard b.position(swatchAbsPos.x, swatchAbsPos.y + swatchNode.size.y + 4.0'f32)
          discard b.layout(LayoutVertical)
          discard b.fitX().fitY()
          discard b.padding(6)
          discard b.gap(4)
          discard b.fillBackground()
          discard b.backgroundColor(rgba(0.10, 0.12, 0.16, 0.98))
          discard b.borderWidth(1)
          discard b.borderColor(rgba(0.34, 0.40, 0.50, 1.0))
          discard b.cornerRadius(4)

          var rValue = value.r
          var gValue = value.g
          var bValue = value.b
          var aValue = value.a
          if b.slider("R", rValue, 0.0'f32, 1.0'f32, value.r):
            changed = true
          if b.slider("G", gValue, 0.0'f32, 1.0'f32, value.g):
            changed = true
          if b.slider("B", bValue, 0.0'f32, 1.0'f32, value.b):
            changed = true
          if b.slider("A", aValue, 0.0'f32, 1.0'f32, value.a):
            changed = true
          value.r = rValue
          value.g = gValue
          value.b = bValue
          value.a = aValue

  if pickerOpen and KeyEscape in b.frameCtx.input.keysPressed:
    b.focusedNode = noneNodeId()

  if pickerOpen and MouseLeft in b.frameCtx.input.mousePressed:
    let swatchHovered = swatchIdx >= 0 and b.wasHovered(swatchIdx, includeChildren = true)
    let popupHovered = popupIdx >= 0 and b.wasHovered(popupIdx, includeChildren = true)
    if not swatchHovered and not popupHovered and not b.wasHovered(pickerIdx, includeChildren = true):
      b.focusedNode = noneNodeId()

  changed

type DropdownStorage = ref object of UiNodeStorageData
  open: bool
  btnAbsPos: Vec2
  btnHeight: float32
  overlaySize: Vec2

proc getOrCreateDropdownStorage(b: var UiBuilder, node: ptr UiNode): DropdownStorage =
  let existing = nodeStorageGet(b, node)
  if existing != nil:
    return cast[DropdownStorage](existing)
  var storage = DropdownStorage()
  nodeStorage(b, node, storage)
  return storage

proc dropdownPopupReposition(b: var UiBuilder, nodeIdx: int, rawData: int) {.nimcall.} =
  if rawData == 0:
    return
  let ownerId = UiNodeId(uint64(rawData))
  let ownerIdx = b.currentNodeIndex(ownerId)
  if ownerIdx < 0 or ownerIdx >= b.frame.nodes.len:
    return
  let storage = cast[DropdownStorage](nodeStorageGet(b, b.frame.nodes[ownerIdx].addr))
  if storage == nil:
    return
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let popup = b.frame.nodes[nodeIdx].addr
  let popupW = popup.size.x
  let popupH = popup.size.y

  var popupX = storage.btnAbsPos.x
  var popupY = storage.btnAbsPos.y + storage.btnHeight + 2.0'f32
  if popupY + popupH > storage.overlaySize.y:
    let aboveY = storage.btnAbsPos.y - 2.0'f32 - popupH
    popupY = if aboveY >= 0: aboveY else: max(0.0'f32, storage.overlaySize.y - popupH)
  if popupY < 0.0'f32:
    popupY = 0.0'f32
  if popupX + popupW > storage.overlaySize.x:
    popupX = max(0.0'f32, storage.overlaySize.x - popupW)
  if popupX < 0.0'f32:
    popupX = 0.0'f32

  popup.pos.x = popupX
  popup.pos.y = popupY

proc dropdown*(b: var UiBuilder, options: openArray[string], selected: var int, hint: string = "Select"): bool =
  prof("dropdown")
  var changed = false

  b.node("dropdown"):
    discard b.fitX().fitY()
    let dropdownNode = b.currentNode
    let storage = getOrCreateDropdownStorage(b, dropdownNode)

    if options.len > 0:
      selected = clamp(selected, 0, options.len - 1)

    var btnIdx = -1
    var btnId = noneNodeId()
    discard b.pushId("dropdown-toggle")
    b.node("dropdown-button"):
      btnIdx = b.stack[^1]
      btnId = b.currentNode.id
      discard b.fitX().fitY().padding(4).gap(6)
      discard b.copyStyleIndex(UiStyleIndexButton)
      discard b.fillBackground().noChildHover()

      b.layoutHorizontal("dropdown-button-row"):
        discard b.fit().gap(6)
        b.node("dropdown-button-label"):
          discard b.fit()
          discard b.copyTextStyleIndex(UiStyleIndexButtonText)
          let label = if options.len > 0 and selected >= 0 and selected < options.len: options[selected] else: hint
          discard b.text(label)
        b.node("dropdown-button-arrow"):
          discard b.fitX().fitY().alignCenter()
          discard b.copyTextStyleIndex(UiStyleIndexButtonText)
          discard b.text(if storage.open: "^" else: "v")
    discard b.popId()

    if b.previousOutput.clickedId == btnId:
      storage.open = not storage.open

    if storage.open and btnIdx >= 0 and btnIdx < b.nodes.len:
      let btnAbsPos = b.absoluteNodePosPrev(btnId, btnIdx)
      let btnNode = b.nodes[btnIdx].addr
      let input = b.frameCtx.input
      var popupIdx = -1

      let overlayIdx = b.currentNodeIndex(b.overlays)
      storage.btnAbsPos = btnAbsPos
      storage.btnHeight = btnNode.size.y
      storage.overlaySize = if overlayIdx >= 0 and overlayIdx < b.nodes.len:
        b.nodes[overlayIdx].size
      else:
        vec2(100000.0'f32, 100000.0'f32)

      b.withParent(b.overlays):
        b.node("dropdown-popup"):
          popupIdx = b.stack[^1]
          discard b.deferPostProcess()
          discard b.deferBuild(dropdownPopupReposition, cast[int](dropdownNode.id))
          discard b.position(btnAbsPos.x, btnAbsPos.y + btnNode.size.y + 2.0'f32)
          discard b.layout(LayoutVertical)
          discard b.minWidth(btnNode.size.x)
          discard b.fitX().fitY()
          discard b.styleIndex(UiStyleIndexMenu)
          discard b.fillBackground()

          for i in 0 ..< options.len:
            let optIdx = i
            discard b.pushId(i.uint64)
            b.layoutVertical("dropdown-option"):
              discard b.copyStyleIndex(UiStyleIndexMenuItem)
              discard b.fitX().fitY().fillX()
              discard b.text(options[i])
              let wasHovered = b.wasHovered(b.stack[^1], includeChildren = true)
              discard b.fillBackground()
              discard b.backgroundColor(if wasHovered:
                b.themeStyle(UiStyleIndexMenuItemHover)[].fillColor
              else:
                b.themeStyle(UiStyleIndexMenuItem)[].fillColor)
              if wasHovered:
                b.ensureNodeText(b.currentNode).textColor = b.themeTextStyle(UiStyleIndexMenuItemHoverText)[].textColor
              else:
                b.ensureNodeText(b.currentNode).textColor = b.themeTextStyle(UiStyleIndexMenuItemText)[].textColor
              if b.wasClicked(includeChildren = true):
                if selected != optIdx:
                  selected = optIdx
                  changed = true
                storage.open = false
            discard b.popId()

      if KeyEscape in input.keysPressed:
        storage.open = false

      if MouseLeft in input.mousePressed:
        let popupHovered = popupIdx >= 0 and b.wasHovered(popupIdx, includeChildren = true)
        let btnHovered = b.wasHovered(btnIdx, includeChildren = true)
        if not popupHovered and not btnHovered:
          storage.open = false

  changed

proc scrollBoxDeferred(b: var UiBuilder, nodeIdx: int, rawData: int) =
  prof("scrollBoxDeferred")
  if rawData == 0:
    return

  let scrollOffset = cast[ptr float](rawData)

  let scrollSpeed = 28.0'f32
  let scrollbarWidth = 10.0'f32
  let thumbMinHeight = 24.0'f32
  var viewportIdx = -1
  var contentIdx = -1
  var trackIdx = -1
  var thumbIdx = -1

  viewportIdx = nodeIdx
  contentIdx = b.firstChildIndex(viewportIdx)

  if viewportIdx >= 0 and contentIdx >= 0 and
      viewportIdx < b.nodes.len and contentIdx < b.nodes.len:
    let viewportNode = b.nodes[viewportIdx].addr
    let contentNode = b.nodes[contentIdx].addr
    let viewportHeight = max(0.0'f32, viewportNode.size.y)
    let contentHeight = max(contentNode.size.y, contentNode.contentExtent.y)
    let scrollRange = max(0.0'f32, contentHeight - viewportHeight)

    if scrollRange > 0.0'f32:
      let viewportHovered = b.previousOutput.scrolledId == b.nodes[nodeIdx].id
      let dragScroll = b.middleDragScroll.y
      if viewportHovered and (abs(b.frameCtx.input.wheel.y) > 0.0001'f32 or dragScroll != 0.0'f32):
        scrollOffset[] += (b.frameCtx.input.wheel.y * scrollSpeed - dragScroll).float

    let minOffset = -scrollRange
    scrollOffset[] = clamp(scrollOffset[].floor, minOffset.float, 0.0)
    contentNode.pos.y = scrollOffset[].float32

    if scrollRange > 0.0'f32 and viewportHeight > 0.0'f32:
      let trackX = max(0.0'f32, viewportNode.size.x - scrollbarWidth)
      let thumbHeight = max(thumbMinHeight, viewportHeight * (viewportHeight / contentHeight))
      let travel = max(0.0'f32, viewportHeight - thumbHeight)
      let normalized = clamp((-scrollOffset[].float32) / scrollRange, 0.0'f32, 1.0'f32)
      let thumbY = travel * normalized

      b.node("scrollbar-track"):
        trackIdx = b.stack[^1]
        discard b.styleIndex(UiStyleIndexScrollBar)
        discard b.position(trackX, 0)
        discard b.size(scrollbarWidth, viewportHeight)
        discard b.fillBackground()

        b.node("scrollbar-thumb"):
          thumbIdx = b.stack[^1]
          discard b.styleIndex(if b.wasHovered(thumbIdx, includeChildren = true): UiStyleIndexScrollBarHandleHover else: UiStyleIndexScrollBarHandle)
          discard b.position(1, thumbY)
          discard b.size(max(2.0'f32, scrollbarWidth - 2.0'f32), thumbHeight)
          discard b.fillBackground()

      let draggingThumb =
        thumbIdx >= 0 and
        MouseLeft in b.frameCtx.input.mouseDown and
        b.wasHeld(thumbIdx, includeChildren = true)
      let clickedTrack =
        trackIdx >= 0 and
        b.wasHeld(trackIdx, includeChildren = true)

      if draggingThumb or clickedTrack:
        let viewportId = b.nodes[viewportIdx].id
        let viewportPos = b.absoluteNodePosPrev(viewportId, viewportIdx)
        let pointerNorm =
          if travel <= 0.0'f32:
            0.0'f32
          else:
            clamp((b.frameCtx.input.mouse.y - viewportPos.y - thumbHeight * 0.5'f32) / travel, 0.0'f32, 1.0'f32)
        scrollOffset[] = (-pointerNorm * scrollRange).float.floor
        contentNode.pos.y = scrollOffset[].float32

type ScrollStorage = ref object of UiNodeStorageData
  scrollOffset: float

proc getOrCreateScrollStorage(b: var UiBuilder, node: ptr UiNode): ScrollStorage =
  let existing = nodeStorageGet(b, node)
  if existing != nil:
    return cast[ScrollStorage](existing)
  var storage = ScrollStorage()
  nodeStorage(b, node, storage)
  return storage

template scrollBox*(b: var UiBuilder, body: untyped): untyped =
  block:
    prof("scrollBox")
    var viewportIdx = -1
    var contentIdx = -1

    b.node("scroll-box"):
      viewportIdx = b.previousNodeIndex(b.currentNode.id)
      discard b.sizeToParent()
      discard b.maskChildren()
      b.currentNode.flags.incl Scrollable
      let storage = b.getOrCreateScrollStorage(b.currentNode)

      b.node("scroll-content"):
        contentIdx = b.stack[^1]
        discard b.position(0, storage.scrollOffset.float32)
        body

      discard b.deferBuild(scrollBoxDeferred, cast[int](storage.scrollOffset.addr))

      # if viewportIdx >= 0 and contentIdx >= 0 and
      #     viewportIdx < b.previousFrame.nodes.len and contentIdx < b.nodes.len:
      #   let viewportNode = b.previousFrame.nodes[viewportIdx].addr
      #   let contentNode = b.nodes[contentIdx].addr
      #   let viewportHeight = max(0.0'f32, viewportNode.size.y)
      #   let contentHeight = max(contentNode.size.y, contentNode.contentExtent.y)
      #   let scrollRange = max(0.0'f32, contentHeight - viewportHeight)

      #   if scrollRange > 0.0'f32:
      #     let viewportHovered = b.wasHovered(viewportNode, includeChildren = true, viewportIdx)
      #     if viewportHovered and abs(b.frameCtx.input.wheel.y) > 0.0001'f32:
      #       scrollOffset += (b.frameCtx.input.wheel.y * scrollSpeed).float
      #       b.frameCtx.input.wheel.y = 0

      #   let minOffset = -scrollRange
      #   scrollOffset = clamp(scrollOffset, minOffset.float, 0.0)
      #   contentNode.pos.y = scrollOffset.float32

      #   if scrollRange > 0.0'f32 and viewportHeight > 0.0'f32:
      #     let trackX = max(0.0'f32, viewportNode.size.x - scrollbarWidth)
      #     let thumbHeight = max(thumbMinHeight, viewportHeight * (viewportHeight / contentHeight))
      #     let travel = max(0.0'f32, viewportHeight - thumbHeight)
      #     let normalized = clamp((-scrollOffset.float32) / scrollRange, 0.0'f32, 1.0'f32)
      #     let thumbY = travel * normalized

      #     b.node("scrollbar-track"):
      #       trackIdx = b.stack[^1]
      #       discard b.styleIndex(UiStyleIndexScrollBar)
      #       discard b.position(trackX, 0)
      #       discard b.size(scrollbarWidth, viewportHeight)
      #       discard b.fillBackground()

      #       b.node("scrollbar-thumb"):
      #         thumbIdx = b.stack[^1]
      #         discard b.styleIndex(if b.wasHovered(thumbIdx, includeChildren = true): UiStyleIndexScrollBarHandleHover else: UiStyleIndexScrollBarHandle)
      #         discard b.position(1, thumbY)
      #         discard b.size(max(2.0'f32, scrollbarWidth - 2.0'f32), thumbHeight)
      #         discard b.fillBackground()

      #     let draggingThumb =
      #       thumbIdx >= 0 and
      #       MouseLeft in b.frameCtx.input.mouseDown and
      #       b.wasHeld(thumbIdx, includeChildren = true)
      #     let clickedTrack =
      #       trackIdx >= 0 and
      #       b.wasClicked(trackIdx, includeChildren = true)

      #     if draggingThumb or clickedTrack:
      #       let viewportId = b.previousFrame.nodes[viewportIdx].id
      #       let viewportPos = b.absoluteNodePosPrev(viewportId, viewportIdx)
      #       let pointerNorm =
      #         if travel <= 0.0'f32:
      #           0.0'f32
      #         else:
      #           clamp((b.frameCtx.input.mouse.y - viewportPos.y - thumbHeight * 0.5'f32) / travel, 0.0'f32, 1.0'f32)
      #       scrollOffset = (-pointerNorm * scrollRange).float
      #       contentNode.pos.y = scrollOffset.float32

type
  TableColumnWidthKind* = enum
    TableColumnFixed
    TableColumnFit
    TableColumnFill
    TableColumnProportional

  TableColumn* = object
    kind*: TableColumnWidthKind
    fixedWidth*: float32
    proportional*: float32

  UiTableLayout* = object
    columnGap*: float32
    rowGap*: float32
    columnCount*: int
    columns*: ptr UncheckedArray[TableColumn]

proc tableColumnFixed*(width: float32): TableColumn =
  TableColumn(kind: TableColumnFixed, fixedWidth: width)

proc tableColumnFit*(): TableColumn =
  TableColumn(kind: TableColumnFit)

proc tableColumnFill*(): TableColumn =
  TableColumn(kind: TableColumnFill)

proc tableColumnProportional*(weight: float32): TableColumn =
  TableColumn(kind: TableColumnProportional, proportional: weight)

proc tableColumnsFill*(count: int): seq[TableColumn] =
  result = newSeq[TableColumn](count)
  for i in 0 ..< count:
    result[i] = tableColumnFill()

proc tableCustomLayout(b: var UiBuilder, nodeIdx: int, userData: int) {.raises: [].} =
  prof("tableCustomLayout")
  if userData == 0:
    return
  let data = cast[ptr UiTableLayout](userData)
  let cols = max(1, data.columnCount)
  let colGap = max(0.0'f32, data.columnGap)
  let rowGap = max(0.0'f32, data.rowGap)

  let n = b.frame.nodes[nodeIdx].addr
  let nodeStyle = b.nodeStyle(n)
  let contentW = max(0.0'f32, n.size.x - nodeStyle.paddingX * 2)
  let totalColGap = colGap * max(0, cols - 1).float32

  let childCount = b.childCount(nodeIdx)
  if childCount == 0:
    return
  let rowCount = (childCount + cols - 1) div cols

  var colWidths = b.frame.arena[].allocArray(cols, float32)
  var colWeights = b.frame.arena[].allocArray(cols, float32)
  var anyFit = false
  for c in 0 ..< cols:
    let col = data.columns[c]
    case col.kind
    of TableColumnFixed:
      colWidths[c] = max(0.0'f32, col.fixedWidth)
      colWeights[c] = 0.0'f32
    of TableColumnFit:
      colWidths[c] = 0.0'f32
      colWeights[c] = 0.0'f32
      anyFit = true
    of TableColumnFill:
      colWidths[c] = 0.0'f32
      colWeights[c] = 1.0'f32
    of TableColumnProportional:
      let w = max(0.0001'f32, col.proportional)
      colWidths[c] = 0.0'f32
      colWeights[c] = w

  # Resolve size-to-content column widths from the children's natural widths,
  # which were already measured during the normal size-to-content passes.
  if anyFit:
    var i = 0
    for childIdx in b.children(nodeIdx):
      let child = b.frame.nodes[childIdx].addr
      let c = i mod cols
      if colWeights[c] == 0.0'f32 and data.columns[c].kind == TableColumnFit:
        colWidths[c] = max(colWidths[c], child.size.x)
      inc i

  var usedByBase = 0.0'f32
  var totalWeight = 0.0'f32
  for c in 0 ..< cols:
    if colWeights[c] == 0.0'f32:
      usedByBase += colWidths[c]
    else:
      totalWeight += colWeights[c]

  let freeSpace = contentW - totalColGap - usedByBase
  if totalWeight > 0.0'f32 and freeSpace > 0.0'f32:
    for c in 0 ..< cols:
      if colWeights[c] > 0.0'f32:
        colWidths[c] = max(0.0'f32, freeSpace * (colWeights[c] / totalWeight))

  let layoutCheckpoint = b.frame.arena[].checkpoint()
  var rowHeights = b.frame.arena[].allocArray(rowCount, float32)
  for r in 0 ..< rowCount:
    rowHeights[r] = 0.0'f32

  var i = 0
  for childIdx in b.children(nodeIdx):
    let child = b.frame.nodes[childIdx].addr
    let col = i mod cols
    let row = i div cols
    child.size.x = colWidths[col]
    child.flags.incl {SizeXKnown, SizeDirty}
    rowHeights[row] = max(rowHeights[row], child.size.y)
    inc i

  var rowStartY = b.frame.arena[].allocArray(rowCount, float32)
  rowStartY[0] = 0.0'f32
  for row in 1 ..< rowCount:
    rowStartY[row] = rowStartY[row - 1] + rowHeights[row - 1] + rowGap

  i = 0
  for childIdx in b.children(nodeIdx):
    let child = b.frame.nodes[childIdx].addr
    let col = i mod cols
    let row = i div cols
    child.pos.x = 0.0'f32
    for c in 0 ..< col:
      child.pos.x += colWidths[c] + colGap
    child.pos.y = rowStartY[row]
    inc i

  let totalH = rowStartY[rowCount - 1] + rowHeights[rowCount - 1]
  n.contentExtent.y = totalH
  if FitY in n.flags:
    n.size.y = max(0.0'f32, totalH + nodeStyle.paddingY * 2)

  b.frame.arena[].restoreCheckpoint(layoutCheckpoint)

template tableLayout*(b: var UiBuilder, inColumns: openArray[TableColumn], inColumnGap, inRowGap: float32, body: untyped): untyped =
  block:
    prof("tableLayout")
    var colArr = b.frame.arena[].allocArray(inColumns.len, TableColumn)
    for ci in 0 ..< inColumns.len:
      colArr[ci] = inColumns[ci]
    var tableDataArr = b.frame.arena[].allocArray(1, UiTableLayout)
    tableDataArr[0] = UiTableLayout(
      columnGap: inColumnGap,
      rowGap: inRowGap,
      columnCount: inColumns.len,
      columns: colArr.data())
    b.node:
      discard b.customLayout(tableCustomLayout, cast[int](tableDataArr.data()))
      body

type UiVirtualListData* = object
  itemCount*: int
  itemHeight*: float32
  scrollOffsetY*: float32
  buildItem*: UiVirtualListItemProc
  buildItemUserData*: int

proc virtualListDeferredBuild(b: var UiBuilder, nodeIdx: int, rawData: int) =
  prof("virtualListDeferredBuild")
  if rawData == 0:
    return
  let data = cast[ptr UiVirtualListData](rawData)
  if data.itemCount <= 0 or data.buildItem == nil:
    return

  let n = b.frame.nodes[nodeIdx].addr
  let nodeStyle = b.nodeStyle(n)
  let contentH = max(0.0'f32, n.size.y - nodeStyle.paddingY * 2)

  let itemH = max(1.0'f32, data.itemHeight)
  let scrollY = max(0.0'f32, data.scrollOffsetY)

  let firstVisible = int(scrollY / itemH)
  let lastVisible = min(data.itemCount - 1, firstVisible + int(contentH / itemH) + 2)

  for i in firstVisible .. lastVisible:
    let itemY = i.float32 * itemH - scrollY
    b.node(i.uint64):
      discard b.position(0.0'f32, itemY).fillX().height(itemH)
      data.buildItem(b, i, data.buildItemUserData)

proc virtualList*(b: var UiBuilder,
    scrollOffset: var float,
    inItemCount: int,
    inItemHeight: float32,
    inBuildItem: UiVirtualListItemProc,
    inItemUserData: int = 0) =
  block:
    prof("virtualList")
    let vListScrollSpeed = 40.0'f32
    let vListScrollbarW = 10.0'f32
    let vListThumbMinH = 20.0'f32
    let vListTotalH = inItemCount.float32 * inItemHeight

    var vlDataArr = b.frame.arena[].allocEmptyArray(1, UiVirtualListData)
    vlDataArr.add(UiVirtualListData())
    let vlRaw = vlDataArr.data()
    vlRaw[0].itemCount = inItemCount
    vlRaw[0].itemHeight = inItemHeight
    vlRaw[0].buildItem = inBuildItem
    vlRaw[0].buildItemUserData = inItemUserData

    b.node("virtual-list"):
      discard b.fillX().sizeToParentY()

      var vlViewportIdx = -1

      b.node("virtual-list-viewport"):
        vlViewportIdx = b.stack[^1]
        discard b.anchorsX(0, 1).offsetsX(0, -10).finishAnchors().fillY()
        discard b.maskChildren()
        b.currentNode.flags.incl Scrollable

        let input = b.frameCtx.input
        let dragScroll = b.middleDragScroll.y
        if b.previousOutput.scrolledId == b.currentNode.id and (abs(b.frameCtx.input.wheel.y) > 0.0001'f32 or dragScroll != 0.0'f32):
          scrollOffset -= (input.wheel.y * vListScrollSpeed - dragScroll).float

        let vlViewportH = max(1.0'f32, b.frame.nodes[vlViewportIdx].size.y)
        let vlMaxScroll = max(0.0'f32, vListTotalH - vlViewportH)
        scrollOffset = clamp(scrollOffset, 0.0, vlMaxScroll.float)

        vlRaw[0].scrollOffsetY = scrollOffset.float32

        discard b.deferBuild(virtualListDeferredBuild, cast[int](vlRaw))

      b.node("virtual-list-scrollbar"):
        let vlTrackIdx = b.stack[^1]
        var vlThumbIdx = -1
        var vlSbTravel = 0.0'f32
        var vlSbRange = 0.0'f32
        var vlSbThumbH = vListThumbMinH

        discard b.anchorsX(1, 1).offsetsX(-vListScrollbarW, 0).finishAnchors().fillY()
        discard b.styleIndex(UiStyleIndexScrollBar)
        discard b.fillBackground()

        if vlViewportIdx >= 0 and vlViewportIdx < b.nodes.len:
          let vlVH = max(1.0'f32, b.nodes[vlViewportIdx].size.y)
          if vListTotalH > vlVH:
            vlSbRange = max(1.0'f32, vListTotalH - vlVH)
            let thumbRatio = vlVH / vListTotalH
            vlSbThumbH = max(vListThumbMinH, thumbRatio * vlVH)
            vlSbTravel = max(0.0'f32, vlVH - vlSbThumbH)
            let thumbY = scrollOffset.float32 / vlSbRange * vlSbTravel
            b.node("virtual-list-scrollbar-thumb"):
              vlThumbIdx = b.stack[^1]
              discard b.styleIndex(if b.wasHovered(vlThumbIdx, includeChildren = true): UiStyleIndexScrollBarHandleHover else: UiStyleIndexScrollBarHandle)
              discard b.position(1.0'f32, max(0.0'f32, thumbY))
              discard b.size(vListScrollbarW - 2.0'f32, vlSbThumbH)
              discard b.fillBackground()

        let sbInput = b.frameCtx.input
        let draggingThumb = vlThumbIdx >= 0 and MouseLeft in sbInput.mouseDown and b.wasHeld(vlThumbIdx, includeChildren = true)
        let clickedTrack = b.wasHeld(vlTrackIdx, includeChildren = true)

        if (draggingThumb or clickedTrack) and vlSbTravel > 0.0'f32:
          let vlTrackId = b.nodes[vlTrackIdx].id
          let sbAbsPos = b.absoluteNodePosPrev(vlTrackId, vlTrackIdx)
          let pointerNorm = clamp(
            (sbInput.mouse.y - sbAbsPos.y - vlSbThumbH * 0.5'f32) / vlSbTravel,
            0.0'f32, 1.0'f32)
          scrollOffset = (pointerNorm * vlSbRange).float
          vlRaw[0].scrollOffsetY = scrollOffset.float32

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
    let isFocused = b.focusedNode == nodeId
    let storage: TextFieldStorage = if state != nil:
      cast[TextFieldStorage](state)
    else:
      getOrCreateTextFieldStorage(b, nodePtr)
    storage.cursorPos = clamp(storage.cursorPos, 0, text.len)

    discard b.styleIndex(if isFocused: UiStyleIndexTextFieldFocused else: UiStyleIndexTextField)
    discard b.fitX().fitY()
    discard b.fillBackground()

    let input = b.frameCtx.input

    if b.previousOutput.clickedId == nodeId:
      b.focusedNode = nodeId

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
        of KeyEscape: b.focusedNode = noneNodeId()
        of KeyEnter:
          b.focusedNode = noneNodeId()
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
        of KeyEscape: b.focusedNode = noneNodeId()
        of KeyEnter:
          b.focusedNode = noneNodeId()
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
