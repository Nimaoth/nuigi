import std/sequtils
import nuigi
import mymath
import profiler
import flex, widgets

include compat2

type WindowResizeEdge* = enum
  ResizeLeft
  ResizeTop
  ResizeRight
  ResizeBottom

type WindowStorage* = ref object of UiNodeStorageData
  pos*: Vec2
  size*: Vec2
  resizeEdges*: set[WindowResizeEdge]
  collapsed*: bool

type WindowActivity* = object
  windowId*: UiNodeId
  lastActive*: uint64

type WindowSpaceStorage* = ref object of UiNodeStorageData
  windows*: seq[WindowActivity]
  activationCounter*: uint64

proc getOrCreateWindowStorage(b: var UiBuilder, node: ptr UiNode, defaultPos, defaultSize: Vec2): WindowStorage =
  let existing = nodeStorageGet(b, node)
  if existing != nil:
    return cast[WindowStorage](existing)
  var storage = WindowStorage(pos: defaultPos, size: defaultSize)
  nodeStorage(b, node, storage)
  return storage

proc getOrCreateWindowSpaceStorage*(b: var UiBuilder, node: ptr UiNode): WindowSpaceStorage =
  let existing = nodeStorageGet(b, node)
  if existing != nil:
    return cast[WindowSpaceStorage](existing)
  var storage = WindowSpaceStorage()
  nodeStorage(b, node, storage)
  return storage

proc markWindowActive(storage: WindowSpaceStorage, windowId: UiNodeId, active: bool) =
  var activityIndex = -1
  for i in 0 ..< storage.windows.len:
    if storage.windows[i].windowId == windowId:
      activityIndex = i
      break

  if activityIndex < 0:
    inc storage.activationCounter
    storage.windows.add WindowActivity(
      windowId: windowId,
      lastActive: storage.activationCounter,
    )
  elif active:
    inc storage.activationCounter
    storage.windows[activityIndex].lastActive = storage.activationCounter

proc windowLastActive(storage: WindowSpaceStorage, windowId: UiNodeId): uint64 =
  for activity in storage.windows:
    if activity.windowId == windowId:
      return activity.lastActive
  0'u64

proc windowSpaceDeferredBuild(b: var UiBuilder, nodeIdx: int, rawData: int) =
  prof("windowSpaceDeferredBuild")
  let _ = rawData
  if nodeIdx < 0 or nodeIdx >= b.nodes.len:
    return
  let stored = b.nodeStorageGet(b.nodes[nodeIdx].addr)
  if stored == nil or not (stored of WindowSpaceStorage):
    return
  let storage = cast[WindowSpaceStorage](stored)

  var orderedWindows: seq[int] = @[]
  for childIdx in b.children(nodeIdx):
    let childLastActive = storage.windowLastActive(b.nodes[childIdx].id)
    var insertAt = orderedWindows.len
    while insertAt > 0:
      let previousIdx = orderedWindows[insertAt - 1]
      let previousLastActive = storage.windowLastActive(b.nodes[previousIdx].id)
      if previousLastActive <= childLastActive:
        break
      dec insertAt
    orderedWindows.insert([childIdx], insertAt)

  if orderedWindows.len == 0:
    b.nodes[nodeIdx].lastChild = -1
    return
  for i in 0 ..< orderedWindows.len:
    let nextIndex = orderedWindows[(i + 1) mod orderedWindows.len]
    b.nodes[orderedWindows[i]].nextSibling = nextIndex.int32
  b.nodes[nodeIdx].lastChild = orderedWindows[^1].int32

proc windowSpace*(b: var UiBuilder) =
  b.node("windows"):
    discard b.fillX().fillY()
    b.windows = b.currentNode.id
    discard b.getOrCreateWindowSpaceStorage(b.currentNode)
    discard b.deferBuild(windowSpaceDeferredBuild)

proc configureWindowNode(b: var UiBuilder, storage: WindowStorage) =
  discard b.position(storage.pos)
  if storage.collapsed:
    discard b.width(storage.size.x).fitY()
  else:
    discard b.size(storage.size)
  discard b.copyStyleIndex(UiStyleIndexWindow)
  discard b.fillBackground()
  discard b.gap(0)

  let previousNodeIndex = b.previousNodeIndex(b.currentNode.id, b.currentNodeIndex)
  var previousScale = vec2(1.0'f32)
  if previousNodeIndex >= 0:
    let previousNode = b.previousFrame.nodes[previousNodeIndex].addr
    let transformSlot = int(previousNode.transformIndex)
    if transformSlot > 0 and transformSlot <= b.previousFrame.transforms.len:
      previousScale = b.previousFrame.transforms[transformSlot - 1].scale

  let closeScaleAnimation = @[
    UiFieldAnimation(
      currentValue: previousScale.x,
      targetValue: 0.0'f32,
      speed: 18.0'f32,
      fieldOffset: UiNodeFieldTransformScaleX,
    ),
    UiFieldAnimation(
      currentValue: previousScale.y,
      targetValue: 0.0'f32,
      speed: 18.0'f32,
      fieldOffset: UiNodeFieldTransformScaleY,
    ),
  ]
  discard b.virtualizeNode(closeScaleAnimation)
  b.animate:
    discard b.transformScaleAnim(1)
    if previousNodeIndex < 0:
      discard b.transformScale(0)

proc hoveredWindowResizeEdges(b: var UiBuilder, windowNodeIndex: int,
    edgeDistance: float32): set[WindowResizeEdge] =
  let windowId = b.nodes[windowNodeIndex].id
  let previousWindowIndex = b.previousNodeIndex(windowId, windowNodeIndex)
  if previousWindowIndex < 0 or not b.wasHovered(windowNodeIndex, includeChildren = true):
    return {}

  let previousPos = b.absoluteNodePosPrev(windowId, windowNodeIndex)
  let previousSize = b.previousFrame.nodes[previousWindowIndex].size
  let localMouse = b.frameCtx.input.mouse - previousPos
  result = {}
  if localMouse.y >= -edgeDistance and localMouse.y <= previousSize.y + edgeDistance:
    if abs(localMouse.x) <= edgeDistance:
      result.incl ResizeLeft
    if abs(localMouse.x - previousSize.x) <= edgeDistance:
      result.incl ResizeRight
  if localMouse.x >= -edgeDistance and localMouse.x <= previousSize.x + edgeDistance:
    if abs(localMouse.y) <= edgeDistance:
      result.incl ResizeTop
    if abs(localMouse.y - previousSize.y) <= edgeDistance:
      result.incl ResizeBottom

proc resizeWindow(storage: WindowStorage, mouseDelta: Vec2, minWindowW, minWindowH: float32) =
  let oldRight = storage.pos.x + storage.size.x
  let oldBottom = storage.pos.y + storage.size.y
  if ResizeLeft in storage.resizeEdges:
    storage.size.x = max(minWindowW, storage.size.x - mouseDelta.x)
    storage.pos.x = oldRight - storage.size.x
  elif ResizeRight in storage.resizeEdges:
    storage.size.x = max(minWindowW, storage.size.x + mouseDelta.x)
  if ResizeTop in storage.resizeEdges:
    storage.size.y = max(minWindowH, storage.size.y - mouseDelta.y)
    storage.pos.y = oldBottom - storage.size.y
  elif ResizeBottom in storage.resizeEdges:
    storage.size.y = max(minWindowH, storage.size.y + mouseDelta.y)

proc updateWindowInteraction(b: var UiBuilder, storage: WindowStorage,
    windowNodeIndex: int, titleBarId: UiNodeId, edgeDistance,
    minWindowW, minWindowH: float32): set[WindowResizeEdge] =
  let input = b.frameCtx.input
  let hoveredEdges = if storage.collapsed:
    default(set[WindowResizeEdge])
  else:
    b.hoveredWindowResizeEdges(windowNodeIndex, edgeDistance)
  if MouseLeft in input.mousePressed and hoveredEdges != {}:
    storage.resizeEdges = hoveredEdges
  elif MouseLeft notin input.mouseDown:
    storage.resizeEdges = {}

  let resizing = MouseLeft in input.mouseDown and storage.resizeEdges != {}
  let dragging = not resizing and MouseLeft in input.mouseDown and
    b.previousOutput.heldId == titleBarId
  if resizing:
    storage.resizeWindow(input.mouseDelta, minWindowW, minWindowH)
    discard b.position(storage.pos)
    discard b.size(storage.size)
  elif dragging:
    storage.pos += input.mouseDelta
    discard b.position(storage.pos)

  hoveredEdges + storage.resizeEdges

proc applyWindowResizeHighlight(b: var UiBuilder, edges: set[WindowResizeEdge]) =
  if edges == {}:
    return
  let style = b.currentNodeStyle()
  var widths = style[].resolvedBorderWidths
  var colors = style[].resolvedBorderColors
  let highlightColor = b.themeStyle(UiStyleIndexAccent).borderColor
  if ResizeLeft in edges:
    widths.left = 2.0'f32
    colors.left = highlightColor
  if ResizeTop in edges:
    widths.top = 2.0'f32
    colors.top = highlightColor
  if ResizeRight in edges:
    widths.right = 2.0'f32
    colors.right = highlightColor
  if ResizeBottom in edges:
    widths.bottom = 2.0'f32
    colors.bottom = highlightColor
  style.borderWidths = widths
  style.borderColors = colors

proc updateWindowSpaceActivity(b: var UiBuilder, windowNodeIndex: int) =
  let windowSpaceIndex = b.currentNodeIndex(b.windows)
  if windowSpaceIndex < 0 or windowSpaceIndex >= b.nodes.len:
    return
  let stored = b.nodeStorageGet(b.nodes[windowSpaceIndex].addr)
  if stored != nil and stored of WindowSpaceStorage:
    cast[WindowSpaceStorage](stored).markWindowActive(
      b.nodes[windowNodeIndex].id,
      b.wasPressed(windowNodeIndex, includeChildren = true))
  b.withParent(windowSpaceIndex):
    discard b.deferBuild(windowSpaceDeferredBuild)

template window*(b: var UiBuilder, title: string, inX, inY, width, height: float32, body: untyped): untyped =
  b.withParent(b.windows):
    prof("window")
    let minWindowW = 120.0'f32
    let minWindowH = 80.0'f32
    let resizeEdgeDistance = 4.0'f32

    b.nodeWithId(title.hashChars.UiNodeId):
      b.nodeStorageParent()
      let windowNodeIndex = b.stack[^1]
      let curNode = b.currentNode
      let windowStorage = getOrCreateWindowStorage(b, curNode,
        vec2(inX, inY),
        vec2(max(minWindowW, width), max(minWindowH, height)))
      b.configureWindowNode(windowStorage)

      var titleBarId = noneNodeId()
      let windowCornerRadii = b.currentNodeStyle()[].resolvedCornerRadii

      # if not windowStorage.collapsed:
      b.node("window-resize"):
        discard b.anchors(0, 0, 1, 1).offsets(-resizeEdgeDistance, -resizeEdgeDistance, resizeEdgeDistance, resizeEdgeDistance).finishAnchors()

      b.layoutVertical:
        if windowStorage.collapsed:
          discard b.fillX().fitY()
        else:
          discard b.fill()

        b.node("window-title-bar"):
          titleBarId = b.currentNode.id
          discard b.copyStyleIndex(UiStyleIndexWindowTitleBar)
          discard b.copyTextStyleIndex(UiStyleIndexWindowTitleBarText)
          let titleBarStyle = b.currentNodeStyle()
          titleBarStyle.cornerRadius = 0.0'f32
          titleBarStyle.cornerRadii = UiCornerRadii(
            topLeft: windowCornerRadii.topLeft,
            topRight: windowCornerRadii.topRight,
          )
          if windowStorage.collapsed:
            titleBarStyle.cornerRadii.bottomLeft = windowCornerRadii.bottomLeft
            titleBarStyle.cornerRadii.bottomRight = windowCornerRadii.bottomRight

          discard b.fillX().fitY().gap(4)
          discard b.flexLayout(true).flexFlow(FlexDirectionRow, FlexNoWrap)
          discard b.fillBackground()

          var textHeight: float32 = 0
          b.node("window-title-text"):
            discard b.flex(1, 0).fitY().noHover()
            discard b.copyTextStyleIndex(UiStyleIndexWindowTitleBarText)
            discard b.text(title)
            textHeight = b.currentNode.size.y

          var collapseBtnId = noneNodeId()
          b.node:
            discard b.size(textHeight, textHeight).noChildHover()
            if b.wasHovered():
              discard b.copyStyleIndex(UiStyleIndexWindowTitleBarCollapseHover).fillBackground()
            collapseBtnId = b.currentNode.id
            b.node("window-collapse-btn"):
              discard b.copyTextStyleIndex(UiStyleIndexWindowTitleBarText)
              discard b.fitX().fitY().alignCenter()
              discard b.text(if windowStorage.collapsed: "+" else: "-")

          if b.previousOutput.clickedId == collapseBtnId:
            windowStorage.collapsed = not windowStorage.collapsed

        if not windowStorage.collapsed:
          b.node("window-content"):
            discard b.styleIndex(UiStyleIndexWindowContent)
            discard b.fillX().fillY().maskChildren()
            body

      let highlightedEdges = b.updateWindowInteraction(
        windowStorage, windowNodeIndex, titleBarId, resizeEdgeDistance,
        minWindowW, minWindowH)
      b.applyWindowResizeHighlight(highlightedEdges)
      b.updateWindowSpaceActivity(windowNodeIndex)
