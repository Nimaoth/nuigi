import nuigi
import profiler

type UiDynamicVirtualListItemProc* = proc(b: var UiBuilder, itemIndex: int, userData: int) {.nimcall.}

type UiDynamicVirtualListHeight* = object
  itemIndex*: int
  height*: float32

type UiDynamicVirtualListStorage* = ref object of UiNodeStorageData
  heights*: seq[UiDynamicVirtualListHeight]
  measuredHeightTotal*: float32
  itemCount: int
  heightHint: float32
  scrollOffsetY*: float32
  scrollVelocityY: float32
  buildItem: UiDynamicVirtualListItemProc
  buildItemUserData: int
  viewportHeight: float32
  scrollbarTrackIndex: int
  scrollbarThumbIndex: int

proc getOrCreateDynamicVirtualListStorage*(b: var UiBuilder, node: ptr UiNode): UiDynamicVirtualListStorage =
  let existing = b.nodeStorageGet(node)
  if existing != nil:
    return cast[UiDynamicVirtualListStorage](existing)
  var storage = UiDynamicVirtualListStorage()
  b.nodeStorage(node, storage)
  return storage

proc sampleIndex(storage: UiDynamicVirtualListStorage, itemIndex: int): int =
  var low = 0
  var high = storage.heights.len
  while low < high:
    let middle = (low + high) div 2
    if storage.heights[middle].itemIndex < itemIndex:
      low = middle + 1
    else:
      high = middle
  low

proc cacheHeight(storage: UiDynamicVirtualListStorage, itemIndex: int, height: float32): float32 =
  let index = storage.sampleIndex(itemIndex)
  if index < storage.heights.len and storage.heights[index].itemIndex == itemIndex:
    result = height - storage.heights[index].height
    storage.measuredHeightTotal += result
    storage.heights[index].height = height
    return

  let oldLen = storage.heights.len
  storage.heights.setLen(oldLen + 1)
  var moveIndex = oldLen
  while moveIndex > index:
    let h = storage.heights[moveIndex - 1]
    storage.heights[moveIndex] = h
    dec moveIndex
  storage.heights[index] = UiDynamicVirtualListHeight(itemIndex: itemIndex, height: height)
  storage.measuredHeightTotal += height
  result = height - storage.heightHint

proc trimHeights(storage: UiDynamicVirtualListStorage, itemCount: int) =
  while storage.heights.len > 0 and storage.heights[^1].itemIndex >= itemCount:
    storage.measuredHeightTotal -= storage.heights[^1].height
    storage.heights.setLen(storage.heights.len - 1)

proc estimatedItemHeight(storage: UiDynamicVirtualListStorage, itemIndex: int, heightHint: float32): float32 =
  let index = storage.sampleIndex(itemIndex)
  if index < storage.heights.len and storage.heights[index].itemIndex == itemIndex:
    return storage.heights[index].height
  heightHint

proc estimatedItemTop(storage: UiDynamicVirtualListStorage, itemIndex: int, heightHint: float32): float32 =
  result = itemIndex.float32 * heightHint
  for sample in storage.heights:
    if sample.itemIndex >= itemIndex:
      break
    result += sample.height - heightHint

proc updateMeasuredHeightTotal*(storage: UiDynamicVirtualListStorage) =
  storage.measuredHeightTotal = 0
  for h in storage.heights:
    storage.measuredHeightTotal += h.height

proc estimatedTotalHeight*(storage: UiDynamicVirtualListStorage, itemCount: int, heightHint: float32): float32 =
  let knownCount = min(storage.heights.len, max(0, itemCount))
  max(0.0'f32,
    storage.measuredHeightTotal + (max(0, itemCount) - knownCount).float32 * max(1.0'f32, heightHint))

proc centerItem*(storage: UiDynamicVirtualListStorage, itemIndex: int, viewportHeight: float32) =
  if storage == nil or storage.itemCount <= 0 or viewportHeight <= 0.0'f32:
    return
  let clampedItemIndex = clamp(itemIndex, 0, storage.itemCount - 1)
  let heightHint = max(1.0'f32, storage.heightHint)
  let itemTop = storage.estimatedItemTop(clampedItemIndex, heightHint)
  let itemHeight = storage.estimatedItemHeight(clampedItemIndex, heightHint)
  let maxScroll = max(0.0'f32,
    storage.estimatedTotalHeight(storage.itemCount, heightHint) - viewportHeight)
  storage.scrollOffsetY = clamp(
    itemTop + itemHeight * 0.5'f32 - viewportHeight * 0.5'f32,
    0.0'f32,
    maxScroll)
  storage.scrollVelocityY = 0.0'f32

proc centerItem*(storage: UiDynamicVirtualListStorage, itemIndex: int) =
  ## Centers an item using the viewport height measured during the previous frame.
  storage.centerItem(itemIndex, storage.viewportHeight)

proc firstVisibleItem(storage: UiDynamicVirtualListStorage, itemCount: int,
    heightHint, scrollOffset: float32): int =
  var low = 0
  var high = max(0, itemCount)
  while low < high:
    let middle = (low + high) div 2
    let itemBottom = storage.estimatedItemTop(middle, heightHint) +
      storage.estimatedItemHeight(middle, heightHint)
    if itemBottom <= scrollOffset:
      low = middle + 1
    else:
      high = middle
  low

proc dynamicVirtualListDeferredBuild(b: var UiBuilder, nodeIdx: int, rawData: int) =
  prof("dynamicVirtualListDeferredBuild")
  let _ = rawData
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let stored = b.nodeStorageGet(b.frame.nodes[nodeIdx].addr)
  if stored == nil or not (stored of UiDynamicVirtualListStorage):
    return
  let storage = cast[UiDynamicVirtualListStorage](stored)
  if storage.itemCount <= 0 or storage.buildItem == nil:
    return

  let viewport = b.frame.nodes[nodeIdx].addr
  let viewportStyle = b.nodeStyle(viewport)
  let viewportHeight = max(0.0'f32, viewport.size.y - viewportStyle.paddingY * 2.0'f32)
  let heightHint = max(1.0'f32, storage.heightHint)
  let totalHeight = storage.estimatedTotalHeight(storage.itemCount, heightHint)
  let scrollRange = max(0.0'f32, totalHeight - viewportHeight)

  let unclampedScrollOffset = storage.scrollOffsetY
  storage.scrollOffsetY = clamp(storage.scrollOffsetY, 0.0'f32, scrollRange)
  if storage.scrollOffsetY != unclampedScrollOffset:
    storage.scrollVelocityY = 0.0'f32
  storage.scrollOffsetY = (storage.scrollOffsetY + 0.5).int64.float32

  let thumbMinHeight = 20.0'f32
  if storage.scrollbarThumbIndex >= 0 and storage.scrollbarTrackIndex >= 0 and
      storage.scrollbarThumbIndex < b.frame.nodes.len and
      storage.scrollbarTrackIndex < b.frame.nodes.len and
      totalHeight > viewportHeight:
    let thumbHeight = max(thumbMinHeight, viewportHeight * (viewportHeight / totalHeight))
    let thumbTravel = max(0.0'f32, viewportHeight - thumbHeight)
    let thumbY = storage.scrollOffsetY / scrollRange * thumbTravel

    let thumbNode = b.frame.nodes[storage.scrollbarThumbIndex].addr
    thumbNode.size.y = thumbHeight
    thumbNode.pos.y = max(0.0'f32, thumbY)

  var visibleBottom = storage.scrollOffsetY + viewportHeight
  var itemIndex = storage.firstVisibleItem(storage.itemCount, heightHint, storage.scrollOffsetY)
  storage.viewportHeight = viewportHeight

  while itemIndex < storage.itemCount:
    let itemTop = storage.estimatedItemTop(itemIndex, heightHint)
    if itemTop >= visibleBottom:
      break
    let itemNodeIndex = b.nodes.len
    b.node(itemIndex.uint64):
      discard b.position(0.0'f32, itemTop - storage.scrollOffsetY).fillX()
      storage.buildItem(b, itemIndex, storage.buildItemUserData)
    discard b.postProcessChildren(itemNodeIndex)

    let measuredHeight = max(1.0'f32, b.nodes[itemNodeIndex].size.y)
    let heightDelta = storage.cacheHeight(itemIndex, measuredHeight)
    if itemTop < storage.scrollOffsetY and abs(heightDelta) > 0.0001'f32:
      storage.scrollOffsetY += heightDelta
      visibleBottom += heightDelta
      b.nodes[itemNodeIndex].pos.y -= heightDelta
    inc itemIndex

proc dynamicVirtualList*(b: var UiBuilder,
    inItemCount: int,
    inItemHeightHint: float32,
    inBuildItem: UiDynamicVirtualListItemProc,
  inItemUserData: int = 0): UiDynamicVirtualListStorage {.discardable.} =
  prof("dynamicVirtualList")
  let scrollSpeed = 20.0'f32
  let scrollDamping = 10.0'f32
  let maxScrollVelocity = 4000.0'f32
  let scrollbarWidth = 10.0'f32
  let thumbMinHeight = 20.0'f32
  let itemCount = max(0, inItemCount)
  let heightHint = max(1.0'f32, inItemHeightHint)

  b.node("dynamic-virtual-list"):
    discard b.fillX().sizeToParentY()
    b.nodeStorageParent()
    b.nodeStorageClearOldChildren(b.currentNode)

    var viewportIndex = -1
    var storage: UiDynamicVirtualListStorage
    b.node("dynamic-virtual-list-viewport"):
      viewportIndex = b.stack[^1]
      discard b.anchorsX(0, 1).offsetsX(0, -scrollbarWidth).finishAnchors().fillY()
      discard b.maskChildren()
      b.currentNode.flags.incl Scrollable
      storage = b.getOrCreateDynamicVirtualListStorage(b.currentNode)
      storage.trimHeights(itemCount)
      storage.itemCount = itemCount
      storage.heightHint = heightHint
      storage.buildItem = inBuildItem
      storage.buildItemUserData = inItemUserData

      let input = b.frameCtx.input
      let frameTime = min(0.1'f32, max(0.0'f32, b.frameCtx.animationTick))
      var wheelScrolled = false
      if b.previousOutput.scrolledId == b.currentNode.id and abs(input.wheel.y) > 0.0001'f32:
        let wheelDelta = -input.wheel.y * scrollSpeed
        storage.scrollOffsetY += wheelDelta
        let impulseTime = max(1.0'f32 / 240.0'f32, frameTime)
        storage.scrollVelocityY = clamp(
          storage.scrollVelocityY + wheelDelta / impulseTime,
          -maxScrollVelocity,
          maxScrollVelocity)
        wheelScrolled = true
        if storage.scrollVelocityY != 0:
          b.anythingAnimating = true

      let dragScroll = b.middleDragScroll.y
      if b.previousOutput.scrolledId == b.currentNode.id and abs(dragScroll) > 0.0001'f32:
        storage.scrollOffsetY += dragScroll
        storage.scrollVelocityY = 0.0'f32
        wheelScrolled = true

      if not wheelScrolled and abs(storage.scrollVelocityY) > 0.5'f32:
        storage.scrollOffsetY += storage.scrollVelocityY * frameTime

      storage.scrollVelocityY = storage.scrollVelocityY / (1.0'f32 + scrollDamping * frameTime)
      if abs(storage.scrollVelocityY) <= 1'f32:
        storage.scrollVelocityY = 0.0'f32
      if storage.scrollVelocityY != 0:
        b.anythingAnimating = true

      discard b.deferBuild(dynamicVirtualListDeferredBuild)

    b.node("dynamic-virtual-list-scrollbar"):
      let trackIndex = b.stack[^1]
      storage.scrollbarTrackIndex = trackIndex
      var thumbIndex = -1
      var thumbTravel = 0.0'f32
      var scrollRange = 0.0'f32
      var thumbHeight = thumbMinHeight

      discard b.anchorsX(1, 1).offsetsX(-scrollbarWidth, 0).finishAnchors().fillY()
      discard b.styleIndex(UiStyleIndexScrollBar)
      discard b.fillBackground()

      if viewportIndex >= 0 and viewportIndex < b.nodes.len:
        let viewportHeight = max(1.0'f32, b.nodes[viewportIndex].size.y)
        let totalHeight = storage.estimatedTotalHeight(itemCount, heightHint)
        if totalHeight > viewportHeight:
          scrollRange = max(1.0'f32, totalHeight - viewportHeight)
          thumbHeight = max(thumbMinHeight, viewportHeight * (viewportHeight / totalHeight))
          thumbTravel = max(0.0'f32, viewportHeight - thumbHeight)
          b.node("dynamic-virtual-list-scrollbar-thumb"):
            thumbIndex = b.stack[^1]
            storage.scrollbarThumbIndex = thumbIndex
            discard b.styleIndex(if b.wasHovered(thumbIndex, includeChildren = true):
              UiStyleIndexScrollBarHandleHover else: UiStyleIndexScrollBarHandle)
            discard b.position(1.0'f32, 0.0'f32)
            discard b.size(scrollbarWidth - 2.0'f32, thumbHeight)
            discard b.fillBackground()

      let input = b.frameCtx.input
      let draggingThumb = thumbIndex >= 0 and MouseLeft in input.mouseDown and
        b.wasHeld(thumbIndex, includeChildren = true)
      let draggingTrack = MouseLeft in input.mouseDown and b.wasHeld(trackIndex)
      if draggingThumb and thumbTravel > 0.0'f32:
        storage.scrollVelocityY = 0.0'f32
        let scrollDelta = input.mouseDelta.y / thumbTravel * scrollRange
        storage.scrollOffsetY = storage.scrollOffsetY + scrollDelta
      elif draggingTrack and thumbTravel > 0.0'f32:
        storage.scrollVelocityY = 0.0'f32
        let trackId = b.nodes[trackIndex].id
        let trackPos = b.absoluteNodePosPrev(trackId, trackIndex)
        let pointerNorm = clamp(
          (input.mouse.y - trackPos.y - thumbHeight * 0.5'f32) / thumbTravel,
          0.0'f32, 1.0'f32)
        storage.scrollOffsetY = pointerNorm * scrollRange

    result = storage
