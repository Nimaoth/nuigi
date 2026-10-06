## Virtualized scrolling list for rows with variable, initially unknown heights.
##
## The list samples rendered row heights, estimates unmeasured content, and
## builds only the visible range through a deferred callback. Its persistent
## storage also adjusts scroll offsets when measurements change so the visible
## anchor remains stable; a custom row layout can handle width-dependent rows.
## Inside a `fitY` parent the rows are built immediately instead, so the list
## height (rows height up to the list's maximum height) is already resolved
## when the call returns and sizes propagate through normal layout flow.

import std/math
import nuigi
import nuigi/debug/profiler

type UiDynamicVirtualListItemProc* = proc(b: var UiBuilder, itemIndex: int, userData: int) {.nimcall, gcsafe, raises: [].}

type UiDynamicVirtualListHeight* = object
  itemIndex*: int
  height*: float32

type UiScrollbarMarker* = object
  ## Change/location marker drawn as a colored rect inside the scrollbar track
  ## background. Positions are fractions (0..1) of the total content height, so
  ## callers can pass display-row fractions (yFrac = displayLine / totalLines)
  ## assuming uniform row heights.
  yFrac*: float32
  hFrac*: float32
  color*: UiColor

type UiDynamicVirtualListStorage* = ref object of UiNodeStorageData
  heights*: seq[UiDynamicVirtualListHeight]
  renderedItemIndexes: seq[int]
  measuredHeightTotal*: float32
  itemCount: int
  heightHint: float32
  scrollOffsetY*: float32
  scrollOffsetX*: float32
  maxItemWidth*: float32
  viewportWidth*: float32
  horizontalScroll: bool
  horizontalScrollbarTrackIndex*: int
  horizontalScrollbarThumbIndex*: int
  pendingHorizontalRange: bool
  horizontalRangeStart: float32
  horizontalRangeEnd: float32
  scrollFrequency*: float32 ## Positive spring response rate; higher values settle faster.
  scrollVelocityY: float32
  scrollRemainingY: float32
  scrollAnimationOffsetY: float32
  buildItem: UiDynamicVirtualListItemProc
  buildItemUserData: int
  customRowLayout: UiCustomLayoutProc
  customRowLayoutUserData: int
  previousFirstVisibleItem: int
  pendingMeasurementAnchor: bool
  measurementAnchorItem: int
  measurementAnchorTop: float32
  pendingMeasuredScrollTo: bool
  measuredScrollItem: int
  measuredScrollMargin: float32
  measuredScrollCenter: bool
  measuredScrollCenterOffscreen: bool
  viewportHeight*: float32
  scrollbarTrackIndex*: int
  scrollbarThumbIndex*: int
  scrollbarMarkers*: seq[UiScrollbarMarker]
  scrollbarMarkerCommands: seq[UiRenderCommand]

proc cancelScrollAnimation(storage: UiDynamicVirtualListStorage) =
  storage.scrollVelocityY = 0.0'f32
  storage.scrollRemainingY = 0.0'f32

proc animateScroll(storage: UiDynamicVirtualListStorage, frameTime: float32) =
  # Exact critically damped spring integration keeps event gaps and frame rate
  # from changing the distance travelled. The remaining distance follows anchors.
  let frequency = storage.scrollFrequency
  let decay = exp(-frequency * frameTime)
  let transition = frequency * storage.scrollRemainingY - storage.scrollVelocityY
  let remaining = (storage.scrollRemainingY + transition * frameTime) * decay
  storage.scrollVelocityY =
    (storage.scrollVelocityY + frequency * transition * frameTime) * decay
  storage.scrollOffsetY += storage.scrollRemainingY - remaining
  storage.scrollRemainingY = remaining
  if abs(remaining) < 0.01'f32 and abs(storage.scrollVelocityY) < 0.5'f32:
    storage.scrollOffsetY += remaining
    storage.cancelScrollAnimation()

proc getOrCreateDynamicVirtualListStorage*(b: var UiBuilder, node: ptr UiNode): UiDynamicVirtualListStorage =
  let existing = b.nodeStorageGet(node)
  if existing != nil:
    return cast[UiDynamicVirtualListStorage](existing)
  var storage = UiDynamicVirtualListStorage(
    previousFirstVisibleItem: -1, scrollFrequency: 40.0'f32,
    horizontalScrollbarTrackIndex: -1, horizontalScrollbarThumbIndex: -1)
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

proc itemTop*(storage: UiDynamicVirtualListStorage, itemIndex: int): float32 =
  ## Estimated content-space top of `itemIndex` (measured heights where known,
  ## height hint elsewhere).
  if storage == nil:
    return 0.0'f32
  storage.estimatedItemTop(max(0, itemIndex), max(1.0'f32, storage.heightHint))

proc itemHeight*(storage: UiDynamicVirtualListStorage, itemIndex: int): float32 =
  if storage == nil:
    return 0.0'f32
  storage.estimatedItemHeight(itemIndex, max(1.0'f32, storage.heightHint))

proc shiftScrollOffset*(storage: UiDynamicVirtualListStorage, deltaY: float32) =
  ## Moves the scroll offset without cancelling an in-flight smooth scroll, for
  ## compensating content changes above the viewport. The deferred build clamps
  ## the result into range.
  if storage == nil or deltaY == 0.0'f32:
    return
  storage.scrollOffsetY += deltaY
  storage.scrollAnimationOffsetY += deltaY

proc clearMeasuredHeights*(storage: UiDynamicVirtualListStorage) =
  ## Drops all cached row measurements, e.g. after rows were renumbered. Rows
  ## are re-measured when they are built again.
  if storage == nil:
    return
  storage.heights.setLen(0)
  storage.measuredHeightTotal = 0.0'f32
  storage.previousFirstVisibleItem = -1
  storage.pendingMeasurementAnchor = false
  storage.pendingMeasuredScrollTo = false

proc preserveItemAnchorAfterMeasurement*(storage: UiDynamicVirtualListStorage,
    itemIndex: int) =
  ## Preserve the viewport position of an estimated row while the next build
  ## replaces height hints with measurements (e.g. after cache invalidation).
  if storage == nil:
    return
  storage.measurementAnchorItem = max(0, itemIndex)
  storage.measurementAnchorTop = storage.itemTop(storage.measurementAnchorItem)
  storage.pendingMeasurementAnchor = true

proc clearMeasuredWidths*(storage: UiDynamicVirtualListStorage) =
  ## Forget the widest rendered row after content changes. Scrolling and
  ## viewport resizing deliberately retain this measurement.
  if storage != nil:
    storage.maxItemWidth = 0.0'f32

proc scrollByX*(storage: UiDynamicVirtualListStorage, deltaX: float32) =
  if storage != nil and storage.horizontalScroll and deltaX != 0.0'f32:
    storage.pendingHorizontalRange = false
    storage.scrollOffsetX += deltaX

proc requestHorizontalRangeVisible*(storage: UiDynamicVirtualListStorage,
    firstX, lastX: float32) =
  ## Content-space bounds, resolved after row measurement with the final
  ## viewport width. Include the caret width to keep line-end cursors visible.
  if storage == nil or not storage.horizontalScroll:
    return
  storage.horizontalRangeStart = max(0.0'f32, firstX)
  storage.horizontalRangeEnd = max(storage.horizontalRangeStart, lastX)
  storage.maxItemWidth = max(storage.maxItemWidth, storage.horizontalRangeEnd)
  storage.pendingHorizontalRange = true

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
  storage.cancelScrollAnimation()

proc centerItem*(storage: UiDynamicVirtualListStorage, itemIndex: int) =
  ## Centers an item using the viewport height measured during the previous frame.
  storage.centerItem(itemIndex, storage.viewportHeight)

proc scrollByY*(storage: UiDynamicVirtualListStorage, deltaY: float32) =
  ## Relative pixel scroll (e.g. wheel / scrollLines equivalents). The deferred
  ## build clamps the result into range.
  if storage == nil:
    return
  storage.scrollOffsetY += deltaY
  storage.cancelScrollAnimation()

proc scrollToItemAtOffset*(storage: UiDynamicVirtualListStorage, itemIndex: int,
    yOffset: float32, viewportHeight: float32 = 0.0'f32): bool =
  ## Places `itemIndex` at `yOffset` px from the top of the viewport
  ## (mirrors `ScrollBox.scrollToY`). Returns false when the viewport height is
  ## not known yet so the caller can keep the request pending.
  if storage == nil or storage.itemCount <= 0:
    return false
  let heightHint = max(1.0'f32, storage.heightHint)
  let vp = if viewportHeight > 0.0'f32: viewportHeight else: storage.viewportHeight
  if vp <= 0.0'f32:
    return false
  let clampedItemIndex = clamp(itemIndex, 0, storage.itemCount - 1)
  let itemTop = storage.estimatedItemTop(clampedItemIndex, heightHint)
  let maxScroll = max(0.0'f32,
    storage.estimatedTotalHeight(storage.itemCount, heightHint) - vp)
  storage.scrollOffsetY = clamp(itemTop - yOffset, 0.0'f32, maxScroll)
  storage.cancelScrollAnimation()
  true

proc ensureItemVisible*(storage: UiDynamicVirtualListStorage, itemIndex: int,
    viewportHeight: float32, margin: float32): bool =
  ## Minimal scroll to bring `itemIndex` into view with `margin` px from the
  ## top/bottom edges (mirrors the non-center branch of `ScrollBox.scrollTo`).
  ## Returns false when the viewport height is not known yet.
  if storage == nil or storage.itemCount <= 0:
    return false
  let vp = if viewportHeight > 0.0'f32: viewportHeight else: storage.viewportHeight
  if vp <= 0.0'f32:
    return false
  let heightHint = max(1.0'f32, storage.heightHint)
  let clampedItemIndex = clamp(itemIndex, 0, storage.itemCount - 1)
  let itemTop = storage.estimatedItemTop(clampedItemIndex, heightHint)
  let itemHeight = storage.estimatedItemHeight(clampedItemIndex, heightHint)
  let itemBottom = itemTop + itemHeight
  let maxScroll = max(0.0'f32,
    storage.estimatedTotalHeight(storage.itemCount, heightHint) - vp)
  let m = clamp(margin, 0.0'f32, max(0.0'f32, vp * 0.5'f32 - itemHeight * 0.5'f32))
  if itemTop < storage.scrollOffsetY + m:
    storage.scrollOffsetY = clamp(itemTop - m, 0.0'f32, maxScroll)
    storage.cancelScrollAnimation()
  elif itemBottom > storage.scrollOffsetY + vp - m:
    var targetY = vp - m - itemHeight
    targetY = max(targetY, m)
    # Match ScrollBox: place item top at targetY.
    storage.scrollOffsetY = clamp(itemTop - targetY, 0.0'f32, maxScroll)
    storage.cancelScrollAnimation()
  true

proc scrollToItem*(storage: UiDynamicVirtualListStorage, itemIndex: int,
    viewportHeight: float32, margin: float32, center: bool,
    centerOffscreen: bool): bool =
  ## Mirrors `ScrollBox.scrollTo(index, center, centerOffscreen)` for the
  ## deferred list: centered scroll when `center`, centered only when offscreen
  ## when `centerOffscreen`, otherwise minimal `ensureItemVisible` scroll.
  ## Returns false when the viewport height is not known yet.
  if storage == nil or storage.itemCount <= 0:
    return false
  let vp = if viewportHeight > 0.0'f32: viewportHeight else: storage.viewportHeight
  if vp <= 0.0'f32:
    return false
  if storage.pendingMeasurementAnchor:
    storage.pendingMeasuredScrollTo = true
    storage.measuredScrollItem = clamp(itemIndex, 0, storage.itemCount - 1)
    storage.measuredScrollMargin = margin
    storage.measuredScrollCenter = center
    storage.measuredScrollCenterOffscreen = centerOffscreen
    # The restored anchor already places this row in the viewport. Do not
    # move it based on a height hint before its actual height is available.
    if storage.measuredScrollItem == storage.measurementAnchorItem:
      return true
  if center:
    storage.centerItem(itemIndex, vp)
    return true
  let heightHint = max(1.0'f32, storage.heightHint)
  let clampedItemIndex = clamp(itemIndex, 0, storage.itemCount - 1)
  let itemTop = storage.estimatedItemTop(clampedItemIndex, heightHint)
  let itemHeight = storage.estimatedItemHeight(clampedItemIndex, heightHint)
  let itemBottom = itemTop + itemHeight
  let m = clamp(margin, 0.0'f32, max(0.0'f32, vp * 0.5'f32 - itemHeight * 0.5'f32))
  let visible = itemTop >= storage.scrollOffsetY + m and
    itemBottom <= storage.scrollOffsetY + vp - m
  if centerOffscreen and not visible:
    if storage.pendingMeasuredScrollTo:
      storage.measuredScrollCenter = true
    storage.centerItem(clampedItemIndex, vp)
    return true
  if centerOffscreen and visible:
    return true
  return storage.ensureItemVisible(clampedItemIndex, vp, m)

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

proc visibleItemRange*(storage: UiDynamicVirtualListStorage): tuple[first, last: int] =
  ## Inclusive item range intersecting the measured viewport. An empty range
  ## has `last < first`.
  result = (0, -1)
  if storage == nil or storage.itemCount <= 0 or storage.viewportHeight <= 0.0'f32:
    return
  let heightHint = max(1.0'f32, storage.heightHint)
  let visibleTop = storage.scrollOffsetY
  let visibleBottom = visibleTop + storage.viewportHeight
  let first = storage.firstVisibleItem(storage.itemCount, heightHint, visibleTop)
  if first >= storage.itemCount:
    return
  var itemTop = storage.estimatedItemTop(first, heightHint)
  if itemTop >= visibleBottom:
    return
  var itemIndex = first
  while itemIndex + 1 < storage.itemCount:
    let nextItemTop = itemTop + storage.estimatedItemHeight(itemIndex, heightHint)
    if nextItemTop >= visibleBottom:
      break
    inc itemIndex
    itemTop = nextItemTop
  result = (first, itemIndex)

proc applyFitListSizes(b: var UiBuilder, viewportIdx, listRootIdx, trackIdx: int,
    rowsH, viewportPadY, listPadY, listContentW, scrollbarWidth: float32,
    needsScroll: bool, horizontalScrollbarHeight: float32 = 0.0'f32) {.gcsafe, raises: [].} =
  ## Resize a fitY-parented list (root, viewport, scrollbar track) to `rowsH`
  ## content pixels. When no scrollbar is needed the viewport takes the full
  ## width and the track collapses to zero width so nothing is rendered.
  let viewport = b.frame.nodes[viewportIdx].addr
  let listRoot = b.frame.nodes[listRootIdx].addr
  let viewportW =
    if needsScroll: max(0.0'f32, listContentW - scrollbarWidth)
    else: listContentW
  b.ensureNodeAnchor(viewport).bottomRightOffset.x =
    if needsScroll: -scrollbarWidth else: 0.0'f32
  viewport.size.x = viewportW
  viewport.size.y = rowsH + viewportPadY
  b.clampNodeSize(viewport)
  listRoot.size.y = rowsH + viewportPadY + listPadY + horizontalScrollbarHeight
  b.clampNodeSize(listRoot)
  if trackIdx >= 0 and trackIdx < b.frame.nodes.len:
    let track = b.frame.nodes[trackIdx].addr
    if needsScroll:
      b.ensureNodeAnchor(track).topLeftOffset.x = -scrollbarWidth
      b.ensureNodeAnchor(track).bottomRightOffset.x = 0.0'f32
      track.size.x = scrollbarWidth
    else:
      b.ensureNodeAnchor(track).topLeftOffset.x = 0.0'f32
      b.ensureNodeAnchor(track).bottomRightOffset.x = 0.0'f32
      track.size.x = 0.0'f32
    track.size.y = rowsH + viewportPadY
    b.clampNodeSize(track)

proc renderedRowWidth(b: var UiBuilder, nodeIdx: int): float32 =
  let node = b.frame.nodes[nodeIdx].addr
  # Viewport-filling containers and spacers are not content measurements.
  result = if FillX in node.flags or AnchorX in node.flags: 0.0'f32 else: node.size.x
  for childIdx in b.children(nodeIdx):
    result = max(result, b.frame.nodes[childIdx].pos.x + b.renderedRowWidth(childIdx))

proc horizontalScrollbarHeight(b: UiBuilder,
    storage: UiDynamicVirtualListStorage, viewportWidth: float32): float32 =
  if storage.horizontalScroll and storage.maxItemWidth > viewportWidth:
    if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 10.0'f32
  else:
    0.0'f32

proc updateHorizontalScrollbar(b: var UiBuilder, viewportIdx: int,
    storage: UiDynamicVirtualListStorage, resolveRange = false) =
  let viewport = b.frame.nodes[viewportIdx].addr
  let style = b.nodeStyle(viewport)
  storage.viewportWidth = max(0.0'f32, viewport.size.x - style.paddingX * 2.0'f32)
  if b.backendType == UiBackendType.Terminal and storage.pendingHorizontalRange:
    storage.maxItemWidth = ceil(storage.maxItemWidth)
  let rangeX = max(0.0'f32, storage.maxItemWidth - storage.viewportWidth)
  if resolveRange and storage.pendingHorizontalRange and storage.horizontalScroll and
      storage.viewportWidth > 0.0'f32:
    let firstX = storage.horizontalRangeStart
    let lastX = storage.horizontalRangeEnd
    if firstX < storage.scrollOffsetX or lastX - firstX > storage.viewportWidth:
      storage.scrollOffsetX = firstX
    elif lastX > storage.scrollOffsetX + storage.viewportWidth:
      storage.scrollOffsetX = lastX - storage.viewportWidth
      if b.backendType == UiBackendType.Terminal:
        storage.scrollOffsetX = ceil(storage.scrollOffsetX)
    storage.pendingHorizontalRange = false
  storage.scrollOffsetX =
    if storage.horizontalScroll: clamp(storage.scrollOffsetX, 0.0'f32, rangeX)
    else: 0.0'f32
  if b.backendType == UiBackendType.Terminal:
    storage.scrollOffsetX = floor(storage.scrollOffsetX)
  for rowIdx in b.children(viewportIdx):
    b.frame.nodes[rowIdx].pos.x = -storage.scrollOffsetX
  let trackIdx = storage.horizontalScrollbarTrackIndex
  let thumbIdx = storage.horizontalScrollbarThumbIndex
  if trackIdx < 0 or thumbIdx < 0:
    return
  let height = b.horizontalScrollbarHeight(storage, storage.viewportWidth)
  let track = b.frame.nodes[trackIdx].addr
  track.size.x = viewport.size.x
  track.size.y = height
  track.pos.y = viewport.pos.y + viewport.size.y
  let thumb = b.frame.nodes[thumbIdx].addr
  let inset = if b.backendType == UiBackendType.Terminal: 0.0'f32 else: 1.0'f32
  let minWidth = if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 20.0'f32
  let thumbWidth =
    if height > 0.0'f32:
      min(track.size.x, max(minWidth,
        track.size.x * storage.viewportWidth / storage.maxItemWidth))
    else: 0.0'f32
  thumb.size.x = thumbWidth
  thumb.size.y = max(0.0'f32, height - inset * 2.0'f32)
  thumb.pos.x = if rangeX > 0.0'f32:
      storage.scrollOffsetX / rangeX * max(0.0'f32, track.size.x - thumbWidth)
    else: 0.0'f32
  thumb.pos.y = inset

proc dynamicVirtualListBuild(b: var UiBuilder, nodeIdx: int, propagateFitSizes: bool) {.gcsafe, raises: [].} =
  prof("dynamicVirtualListBuild")
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let stored = b.nodeStorageGet(b.frame.nodes[nodeIdx].addr)
  if stored == nil or not (stored of UiDynamicVirtualListStorage):
    return
  let storage = cast[UiDynamicVirtualListStorage](stored)
  if storage.itemCount <= 0 or storage.buildItem == nil:
    return

  var viewport = b.frame.nodes[nodeIdx].addr
  let viewportStyle = b.nodeStyle(viewport)
  let viewportPaddingY = viewportStyle.paddingY * 2.0'f32
  var viewportHeight = max(0.0'f32, viewport.size.y - viewportPaddingY)
  let heightHint = max(1.0'f32, storage.heightHint)
  var totalHeight = storage.estimatedTotalHeight(storage.itemCount, heightHint)
  var scrollRange = max(0.0'f32, totalHeight - viewportHeight)

  # When the list root sizes to its content (fitY parent), the viewport
  # collapses to zero during the main layout pass. Size it here from the
  # estimated rows instead: rows height up to the list's maximum height so
  # scrolling only kicks in when the rows exceed it.
  var fitParentY = false
  var fitListRootIdx = -1
  var fitTrackIdx = -1
  var fitHasMax = false
  var fitMaxRowsH = 0.0'f32
  var fitViewportPadY = 0.0'f32
  var fitListPadY = 0.0'f32
  var fitListContentW = 0.0'f32
  var fitScrollbarWidth = 0.0'f32
  var fitNeedsScrollPre = false
  let listRootIdx = int(viewport.parent)
  if listRootIdx >= 0 and listRootIdx < b.frame.nodes.len:
    let listRoot = b.frame.nodes[listRootIdx].addr
    if FitY in listRoot.flags:
      fitParentY = true
      fitListRootIdx = listRootIdx
      fitScrollbarWidth =
        if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 10.0'f32
      let listStyle = b.nodeStyle(listRoot)
      fitListPadY = listStyle.paddingY * 2.0'f32
      fitViewportPadY = viewportStyle.paddingY * 2.0'f32
      fitListContentW = max(0.0'f32,
        listRoot.size.x - listStyle.paddingX * 2.0'f32)
      let maxAllowedH = listRoot.maxSize.y
      fitHasMax = maxAllowedH < 1.0e8'f32
      fitMaxRowsH =
        if fitHasMax: max(0.0'f32, maxAllowedH - fitListPadY - fitViewportPadY -
          b.horizontalScrollbarHeight(storage, viewport.size.x))
        else: 1.0e9'f32
      let preRowsH = min(totalHeight, fitMaxRowsH)
      fitNeedsScrollPre = totalHeight > preRowsH + 0.001'f32
      if not fitNeedsScrollPre:
        storage.scrollOffsetY = 0.0'f32
        storage.cancelScrollAnimation()
      viewportHeight = preRowsH
      scrollRange = max(0.0'f32, totalHeight - preRowsH)
      fitTrackIdx = storage.scrollbarTrackIndex
      b.applyFitListSizes(nodeIdx, fitListRootIdx, fitTrackIdx, preRowsH,
        fitViewportPadY, fitListPadY, fitListContentW, fitScrollbarWidth,
        fitNeedsScrollPre)

  let unclampedScrollOffset = storage.scrollOffsetY
  storage.scrollOffsetY = clamp(storage.scrollOffsetY, 0.0'f32, scrollRange)
  if storage.scrollOffsetY != unclampedScrollOffset:
    storage.cancelScrollAnimation()
  if b.backendType == UiBackendType.Terminal:
    storage.scrollOffsetY = (storage.scrollOffsetY + 0.5).int64.float32

  let thumbMinHeight =
    if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 20.0'f32
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
  let firstRenderedItem = itemIndex
  let firstItemEnteredFromAbove = storage.previousFirstVisibleItem >= 0 and
    firstRenderedItem < storage.previousFirstVisibleItem
  storage.viewportHeight = viewportHeight
  storage.renderedItemIndexes.setLen(0)
  let resolvedMeasurementAnchor = storage.pendingMeasurementAnchor
  var measurementAnchorTop = storage.measurementAnchorTop
  var resolveMeasuredScrollTo = storage.pendingMeasuredScrollTo

  while true:
    var measurementScrollAdjustment = 0.0'f32
    while itemIndex < storage.itemCount:
      let itemTop = storage.estimatedItemTop(itemIndex, heightHint)
      let isLookaheadItem = itemTop >= visibleBottom
      if isLookaheadItem and storage.customRowLayout == nil:
        break
      let itemNodeIndex = b.nodes.len
      storage.renderedItemIndexes.add(itemIndex)
      b.node(itemIndex.uint64):
        discard b.position(0.0'f32, itemTop - storage.scrollOffsetY).fillX()
        storage.buildItem(b, itemIndex, storage.buildItemUserData)
      discard b.postProcessChildren(itemNodeIndex)
      if storage.customRowLayout == nil:
        let previousHeight = storage.estimatedItemHeight(itemIndex, heightHint)
        let measuredHeight = max(1.0'f32, b.nodes[itemNodeIndex].size.y)
        let heightDelta = storage.cacheHeight(itemIndex, measuredHeight)
        let preserveFollowingRows = itemIndex == firstRenderedItem and
          firstItemEnteredFromAbove
        if (itemTop + previousHeight <= storage.scrollOffsetY or
            preserveFollowingRows) and abs(heightDelta) > 0.0001'f32:
          storage.scrollOffsetY += heightDelta
          measurementScrollAdjustment += heightDelta
          visibleBottom += heightDelta
          b.nodes[itemNodeIndex].pos.y -= heightDelta
      inc itemIndex
      if isLookaheadItem:
        break

    if storage.customRowLayout != nil:
      storage.customRowLayout(b, nodeIdx, storage.customRowLayoutUserData)
      var renderedListIndex = 0
      for itemNodeIdx in b.children(nodeIdx):
        if renderedListIndex >= storage.renderedItemIndexes.len:
          break
        let renderedItemIndex = storage.renderedItemIndexes[renderedListIndex]
        let oldItemTop = storage.estimatedItemTop(renderedItemIndex, heightHint)
        let previousHeight = storage.estimatedItemHeight(renderedItemIndex, heightHint)
        let measuredHeight = max(1.0'f32, b.nodes[itemNodeIdx].size.y)
        let heightDelta = storage.cacheHeight(renderedItemIndex, measuredHeight)
        let preserveFollowingRows = renderedListIndex == 0 and
          firstItemEnteredFromAbove
        if (oldItemTop + previousHeight <= storage.scrollOffsetY or
            preserveFollowingRows) and abs(heightDelta) > 0.0001'f32:
          storage.scrollOffsetY += heightDelta
          measurementScrollAdjustment += heightDelta
        let correctedItemTop = storage.estimatedItemTop(renderedItemIndex, heightHint)
        b.nodes[itemNodeIdx].pos.y = correctedItemTop - storage.scrollOffsetY
        inc renderedListIndex
    if resolvedMeasurementAnchor:
      let anchorTop = storage.itemTop(storage.measurementAnchorItem)
      let delta = anchorTop - measurementAnchorTop - measurementScrollAdjustment
      storage.shiftScrollOffset(delta)
      for rowIdx in b.children(nodeIdx):
        b.frame.nodes[rowIdx].pos.y -= delta
      measurementAnchorTop = anchorTop
      storage.pendingMeasurementAnchor = false
    viewport = b.frame.nodes[nodeIdx].addr
    if storage.horizontalScroll:
      for rowIdx in b.children(nodeIdx):
        storage.maxItemWidth = max(storage.maxItemWidth, b.renderedRowWidth(rowIdx))

    if fitParentY:
      # Reconcile with the measured rows: shrink to the exact rows height when
      # everything fits (hints may have overestimated), hide the scrollbar, and
      # propagate the resolved sizes up through fitY ancestors.
      let finalTotal = storage.estimatedTotalHeight(storage.itemCount, heightHint)
      totalHeight = finalTotal
      let horizontalHeight = b.horizontalScrollbarHeight(storage, viewport.size.x)
      if fitHasMax:
        fitMaxRowsH = max(0.0'f32, b.frame.nodes[fitListRootIdx].maxSize.y -
          fitListPadY - fitViewportPadY - horizontalHeight)
      let desiredRowsH =
        if fitHasMax: min(finalTotal, fitMaxRowsH) else: finalTotal
      let needsScrollFinal = finalTotal > desiredRowsH + 0.001'f32
      scrollRange = max(0.0'f32, finalTotal - desiredRowsH)
      let oldOffset = storage.scrollOffsetY
      storage.scrollOffsetY = clamp(storage.scrollOffsetY, 0.0'f32, scrollRange)
      if storage.scrollOffsetY != oldOffset:
        storage.cancelScrollAnimation()
        let offsetDelta = storage.scrollOffsetY - oldOffset
        for rowIdx in b.children(nodeIdx):
          b.frame.nodes[rowIdx].pos.y -= offsetDelta
      if storage.horizontalScroll or abs(desiredRowsH - viewportHeight) > 0.001'f32 or
          needsScrollFinal != fitNeedsScrollPre:
        b.applyFitListSizes(nodeIdx, fitListRootIdx, fitTrackIdx, desiredRowsH,
          fitViewportPadY, fitListPadY, fitListContentW, fitScrollbarWidth,
          needsScrollFinal, horizontalHeight)
        viewportHeight = desiredRowsH
      let thumbIdx = storage.scrollbarThumbIndex
      let trackIdx = storage.scrollbarTrackIndex
      let thumbValid = thumbIdx >= 0 and thumbIdx < b.frame.nodes.len and
        trackIdx >= 0 and trackIdx < b.frame.nodes.len and
        b.frame.nodes[thumbIdx].parent == trackIdx.int32
      if needsScrollFinal:
        if thumbValid and totalHeight > viewportHeight:
          let thumbHeight = max(thumbMinHeight, viewportHeight * (viewportHeight / totalHeight))
          let thumbTravel = max(0.0'f32, viewportHeight - thumbHeight)
          let thumbY =
            if scrollRange > 0.0'f32: storage.scrollOffsetY / scrollRange * thumbTravel
            else: 0.0'f32
          let thumbNode = b.frame.nodes[thumbIdx].addr
          thumbNode.size.y = thumbHeight
          thumbNode.pos.y = max(0.0'f32, thumbY)
      elif thumbValid:
        let thumbNode = b.frame.nodes[thumbIdx].addr
        thumbNode.size.x = 0.0'f32
        thumbNode.size.y = 0.0'f32
      storage.viewportHeight = viewportHeight
      if propagateFitSizes:
        var propagateIdx = fitListRootIdx
        var propagateGuard = 0
        while propagateIdx >= 0 and propagateGuard < 32:
          discard b.postProcessChildren(propagateIdx)
          let parentIdx = int(b.frame.nodes[propagateIdx].parent)
          if parentIdx < 0 or parentIdx >= b.frame.nodes.len:
            break
          if FitY notin b.frame.nodes[parentIdx].flags:
            break
          propagateIdx = parentIdx
          inc propagateGuard
    elif storage.horizontalScroll:
      let root = b.frame.nodes[listRootIdx].addr
      let rootStyle = b.nodeStyle(root)
      let horizontalHeight = b.horizontalScrollbarHeight(storage, viewport.size.x)
      b.ensureNodeAnchor(viewport).bottomRightOffset.y = -horizontalHeight
      viewport.size.y = max(0.0'f32,
        root.size.y - rootStyle.paddingY * 2.0'f32 - horizontalHeight)
      storage.viewportHeight = max(0.0'f32, viewport.size.y - viewportPaddingY)
      if storage.scrollbarTrackIndex >= 0:
        let track = b.frame.nodes[storage.scrollbarTrackIndex].addr
        b.ensureNodeAnchor(track).bottomRightOffset.y = -horizontalHeight
        track.size.y = viewport.size.y
      let finalRangeY = max(0.0'f32,
        storage.estimatedTotalHeight(storage.itemCount, heightHint) - storage.viewportHeight)
      let oldOffsetY = storage.scrollOffsetY
      storage.scrollOffsetY = clamp(oldOffsetY, 0.0'f32, finalRangeY)
      if storage.scrollOffsetY != oldOffsetY:
        storage.cancelScrollAnimation()
        for rowIdx in b.children(nodeIdx):
          b.frame.nodes[rowIdx].pos.y += oldOffsetY - storage.scrollOffsetY
    if resolvedMeasurementAnchor:
      let finalRangeY = max(0.0'f32,
        storage.estimatedTotalHeight(storage.itemCount, heightHint) - storage.viewportHeight)
      let oldOffsetY = storage.scrollOffsetY
      let targetY = clamp(oldOffsetY, 0.0'f32, finalRangeY)
      storage.shiftScrollOffset(targetY - oldOffsetY)
      for rowIdx in b.children(nodeIdx):
        b.frame.nodes[rowIdx].pos.y += oldOffsetY - targetY
    resolveMeasuredScrollTo = resolveMeasuredScrollTo or storage.pendingMeasuredScrollTo
    if resolveMeasuredScrollTo:
      storage.pendingMeasuredScrollTo = false
      let oldOffsetY = storage.scrollOffsetY
      discard storage.scrollToItem(storage.measuredScrollItem, storage.viewportHeight,
        storage.measuredScrollMargin, storage.measuredScrollCenter,
        storage.measuredScrollCenterOffscreen)
      for rowIdx in b.children(nodeIdx):
        b.frame.nodes[rowIdx].pos.y += oldOffsetY - storage.scrollOffsetY
    b.updateHorizontalScrollbar(nodeIdx, storage, resolveRange = true)
    if (storage.horizontalScroll or resolvedMeasurementAnchor or resolveMeasuredScrollTo) and
        storage.scrollbarThumbIndex >= 0:
      let finalTotal = storage.estimatedTotalHeight(storage.itemCount, heightHint)
      let finalRange = max(0.0'f32, finalTotal - storage.viewportHeight)
      let thumb = b.frame.nodes[storage.scrollbarThumbIndex].addr
      thumb.size.y = min(storage.viewportHeight, max(thumbMinHeight,
        storage.viewportHeight * storage.viewportHeight / max(finalTotal, 1.0'f32)))
      thumb.pos.y = if finalRange > 0.0'f32:
          storage.scrollOffsetY / finalRange * max(0.0'f32, storage.viewportHeight - thumb.size.y)
        else: 0.0'f32
    visibleBottom = storage.scrollOffsetY + storage.viewportHeight
    # Measurements, anchor restoration and final sizing can expose more rows
    # than the cached range. Append them now, rather than leaving a frame gap.
    if itemIndex >= storage.itemCount or
        storage.itemTop(itemIndex) >= visibleBottom:
      break
    viewportHeight = storage.viewportHeight
  storage.previousFirstVisibleItem = firstRenderedItem
  storage.scrollAnimationOffsetY = storage.scrollOffsetY

proc dynamicVirtualListDeferredBuild(b: var UiBuilder, nodeIdx: int, rawData: int) {.gcsafe, raises: [].} =
  prof("dynamicVirtualListDeferredBuild")
  let _ = rawData
  b.dynamicVirtualListBuild(nodeIdx, true)

proc dynamicVirtualListScrollbarMarkersBuild(b: var UiBuilder, nodeIdx: int, rawData: int) {.gcsafe, raises: [].} =
  ## Emit scrollbar marker rects inside the scrollbar-background node (nodeIdx).
  ## Runs deferred so the track size is resolved; rects are node-local, like the
  ## highlight layer's CmdRectFill commands. Markers live on the viewport's list
  ## storage (bg -> track -> list root -> first child viewport).
  {.cast(gcsafe).}:
    prof("dynamicVirtualListScrollbarMarkersBuild")
    try:
      let _ = rawData
      if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
        return
      let trackIdx = int(b.frame.nodes[nodeIdx].parent)
      if trackIdx < 0 or trackIdx >= b.frame.nodes.len:
        return
      let rootIdx = int(b.frame.nodes[trackIdx].parent)
      if rootIdx < 0 or rootIdx >= b.frame.nodes.len:
        return
      var viewportIdx = -1
      for childIdx in b.children(rootIdx):
        viewportIdx = childIdx
        break
      if viewportIdx < 0:
        return
      let data = b.nodeStorageGet(b.frame.nodes[viewportIdx].addr)
      if data == nil:
        return
      let storage = cast[UiDynamicVirtualListStorage](data)
      if storage.scrollbarMarkers.len == 0:
        return
      let w = b.frame.nodes[nodeIdx].size.x
      let h = b.frame.nodes[nodeIdx].size.y
      if w <= 0.0'f32 or h <= 0.0'f32:
        return
      storage.scrollbarMarkerCommands.setLen(0)
      for m in storage.scrollbarMarkers:
        var cmd = UiRenderCommand(kind: CmdRectFill, color: m.color)
        cmd.pos.x = 0.0'f32
        cmd.pos.y = clamp(m.yFrac, 0.0'f32, 1.0'f32) * h
        cmd.size.x = w
        cmd.size.y = max(m.hFrac * h, 2.0'f32)
        if cmd.pos.y + cmd.size.y > h:
          cmd.size.y = max(h - cmd.pos.y, 0.0'f32)
        if cmd.size.y <= 0.0'f32:
          continue
        storage.scrollbarMarkerCommands.add cmd
      if storage.scrollbarMarkerCommands.len > 0:
        discard b.customRenderCommands(storage.scrollbarMarkerCommands)
    except:
      discard

proc dynamicVirtualList*(b: var UiBuilder,
    inItemCount: int,
    inItemHeightHint: float32,
    inBuildItem: UiDynamicVirtualListItemProc,
  inItemUserData: int = 0,
  inCustomRowLayout: nil UiCustomLayoutProc = nil,
  inCustomRowLayoutUserData: int = 0,
  horizontalScroll: bool = false): UiDynamicVirtualListStorage {.discardable.} =
  prof("dynamicVirtualList")
  let scrollSpeed =
    if b.backendType == UiBackendType.Terminal: 2.0'f32 else: 80.0'f32
  let scrollbarWidth =
    if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 10.0'f32
  let thumbMinHeight =
    if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 20.0'f32
  let thumbInset =
    if b.backendType == UiBackendType.Terminal: 0.0'f32 else: 1.0'f32
  let itemCount = max(0, inItemCount)
  let heightHint = max(1.0'f32, inItemHeightHint)
  # When the parent sizes to its content, rows are built immediately so the
  # list height is resolved during this call and propagates to fitY parents
  # through the normal endNode layout flow (no deferred build needed).
  let fitSizing = FitY in b.currentNode.flags

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
      storage.customRowLayout = inCustomRowLayout
      storage.customRowLayoutUserData = inCustomRowLayoutUserData
      storage.horizontalScroll = horizontalScroll
      storage.scrollbarThumbIndex = -1
      storage.horizontalScrollbarTrackIndex = -1
      storage.horizontalScrollbarThumbIndex = -1
      if not horizontalScroll:
        storage.scrollOffsetX = 0.0'f32
        storage.pendingHorizontalRange = false
      if horizontalScroll:
        let horizontalHeight = b.horizontalScrollbarHeight(storage, b.currentNode.size.x)
        discard b.anchorsY(0, 1).offsetsY(0, -horizontalHeight).finishAnchors()

      let input = b.frameCtx.input
      let frameTime = max(0.0'f32, b.frameCtx.animationTick)
      if storage.scrollOffsetY != storage.scrollAnimationOffsetY:
        storage.cancelScrollAnimation()
      let shiftWheel = horizontalScroll and ModShift in input.modsDown
      let wheelY = if shiftWheel: 0.0'f32 else: input.wheel.y
      if b.previousOutput.scrolledId == b.currentNode.id and abs(wheelY) > 0.0001'f32:
        let wheelDelta = -wheelY * scrollSpeed
        if b.backendType == UiBackendType.Terminal:
          storage.scrollOffsetY += wheelDelta
          storage.cancelScrollAnimation()
        else:
          if wheelDelta * storage.scrollRemainingY < 0.0'f32:
            storage.cancelScrollAnimation()
          storage.scrollRemainingY += wheelDelta

      let dragScroll = b.middleDragScroll.y
      if b.previousOutput.scrolledId == b.currentNode.id and abs(dragScroll) > 0.0001'f32:
        storage.scrollOffsetY += dragScroll
        storage.cancelScrollAnimation()
      if horizontalScroll and b.previousOutput.scrolledId == b.currentNode.id:
        let wheelX = input.wheel.x + (if shiftWheel: input.wheel.y else: 0.0'f32)
        storage.scrollByX(-wheelX * scrollSpeed + b.middleDragScroll.x)

      if storage.viewportHeight > 0.0'f32:
        let scrollRange = max(0.0'f32,
          storage.estimatedTotalHeight(itemCount, heightHint) - storage.viewportHeight)
        storage.scrollRemainingY = clamp(
          storage.scrollOffsetY + storage.scrollRemainingY, 0.0'f32, scrollRange) -
          storage.scrollOffsetY
      storage.animateScroll(frameTime)
      if storage.scrollRemainingY != 0.0'f32 or storage.scrollVelocityY != 0.0'f32:
        b.anythingAnimating = true

      if fitSizing:
        # The scrollbar track does not exist yet; the build skips it and the
        # scrollbar block below sizes it from the resolved rows instead.
        storage.scrollbarTrackIndex = -1
        storage.scrollbarThumbIndex = -1
        b.dynamicVirtualListBuild(viewportIndex, false)
      else:
        discard b.deferBuild(dynamicVirtualListDeferredBuild)

    b.node("dynamic-virtual-list-scrollbar"):
      let trackIndex = b.stack[^1]
      storage.scrollbarTrackIndex = trackIndex
      var thumbIndex = -1
      var thumbTravel = 0.0'f32
      var scrollRange = 0.0'f32
      var thumbHeight = thumbMinHeight

      discard b.anchorsX(1, 1).offsetsX(-scrollbarWidth, 0).finishAnchors().fillY()
      if horizontalScroll:
        let horizontalHeight = b.horizontalScrollbarHeight(storage, storage.viewportWidth)
        discard b.anchorsY(0, 1).offsetsY(0, -horizontalHeight).finishAnchors()
      discard b.styleIndex(UiStyleIndexScrollBar)
      discard b.fillBackground()
      b.node("dynamic-virtual-list-scrollbar-background"):
        discard b.fill().noHover()
        discard b.deferBuild(dynamicVirtualListScrollbarMarkersBuild)

      if viewportIndex >= 0 and viewportIndex < b.nodes.len:
        let currentViewportHeight = b.nodes[viewportIndex].size.y
        let viewportHeight = max(1.0'f32,
          if storage.viewportHeight > 0.0'f32:
            storage.viewportHeight
          else:
            currentViewportHeight)
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
            discard b.position(thumbInset, 0.0'f32)
            discard b.size(scrollbarWidth - thumbInset * 2.0'f32, thumbHeight)
            discard b.fillBackground()

      let input = b.frameCtx.input
      let draggingThumb = thumbIndex >= 0 and MouseLeft in input.mouseDown and
        b.wasHeld(thumbIndex, includeChildren = true)
      let draggingTrack = MouseLeft in input.mouseDown and b.wasHeld(trackIndex)
      if draggingThumb and thumbTravel > 0.0'f32:
        storage.cancelScrollAnimation()
        let scrollDelta = input.mouseDelta.y / thumbTravel * scrollRange
        storage.scrollOffsetY = storage.scrollOffsetY + scrollDelta
      elif draggingTrack and thumbTravel > 0.0'f32:
        storage.cancelScrollAnimation()
        let trackId = b.nodes[trackIndex].id
        let trackPos = b.absoluteNodePosPrev(trackId, trackIndex)
        let pointerNorm = clamp(
          (input.mouse.y - trackPos.y - thumbHeight * 0.5'f32) / thumbTravel,
          0.0'f32, 1.0'f32)
        storage.scrollOffsetY = pointerNorm * scrollRange

    if fitSizing and viewportIndex >= 0 and viewportIndex < b.nodes.len:
      # Rows were built above, so the scrollbar nodes created by the previous
      # block can be sized from the resolved rows right away: collapse the
      # track when everything fits, otherwise keep the capped height.
      let listRootIdx = int(b.frame.nodes[viewportIndex].parent)
      if listRootIdx >= 0 and listRootIdx < b.frame.nodes.len:
        let listRoot = b.frame.nodes[listRootIdx].addr
        let viewport = b.frame.nodes[viewportIndex].addr
        let listStyle = b.nodeStyle(listRoot)
        let viewportStyle = b.nodeStyle(viewport)
        let rowsH = storage.viewportHeight
        let totalH = storage.estimatedTotalHeight(itemCount, heightHint)
        let needScroll = totalH > rowsH + 0.001'f32
        b.applyFitListSizes(viewportIndex, listRootIdx, storage.scrollbarTrackIndex,
          rowsH, viewportStyle.paddingY * 2.0'f32, listStyle.paddingY * 2.0'f32,
          max(0.0'f32, listRoot.size.x - listStyle.paddingX * 2.0'f32),
          scrollbarWidth, needScroll,
          b.horizontalScrollbarHeight(storage, viewport.size.x))
        let fitThumbIdx = storage.scrollbarThumbIndex
        let fitTrackIdx = storage.scrollbarTrackIndex
        let thumbValid = fitThumbIdx >= 0 and fitThumbIdx < b.frame.nodes.len and
          fitTrackIdx >= 0 and fitTrackIdx < b.frame.nodes.len and
          b.frame.nodes[fitThumbIdx].parent == fitTrackIdx.int32
        if needScroll:
          if thumbValid and totalH > rowsH:
            let fitThumbHeight = max(thumbMinHeight, rowsH * (rowsH / totalH))
            let fitThumbTravel = max(0.0'f32, rowsH - fitThumbHeight)
            let fitScrollRange = max(0.0'f32, totalH - rowsH)
            let fitThumbNode = b.frame.nodes[fitThumbIdx].addr
            fitThumbNode.size.y = fitThumbHeight
            fitThumbNode.pos.y =
              if fitScrollRange > 0.0'f32:
                max(0.0'f32, storage.scrollOffsetY / fitScrollRange * fitThumbTravel)
              else:
                0.0'f32
        elif thumbValid:
          let fitThumbNode = b.frame.nodes[fitThumbIdx].addr
          fitThumbNode.size.x = 0.0'f32
          fitThumbNode.size.y = 0.0'f32

    if horizontalScroll:
      b.node("dynamic-virtual-list-horizontal-scrollbar"):
        let trackIdx = b.currentNodeIndex
        storage.horizontalScrollbarTrackIndex = trackIdx
        let horizontalHeight = b.horizontalScrollbarHeight(storage, storage.viewportWidth)
        discard b.anchors(0, 1, 1, 1).offsets(0, -horizontalHeight, -scrollbarWidth, 0)
          .finishAnchors().styleIndex(UiStyleIndexScrollBar).fillBackground()
        b.node("dynamic-virtual-list-horizontal-scrollbar-thumb"):
          let thumbIdx = b.currentNodeIndex
          storage.horizontalScrollbarThumbIndex = thumbIdx
          discard b.styleIndex(if b.wasHovered(thumbIdx, includeChildren = true):
            UiStyleIndexScrollBarHandleHover else: UiStyleIndexScrollBarHandle)
          discard b.size(0.0'f32, 0.0'f32).fillBackground()
        b.updateHorizontalScrollbar(viewportIndex, storage)
        let thumbIdx = storage.horizontalScrollbarThumbIndex
        let travel = max(0.0'f32, b.nodes[trackIdx].size.x - b.nodes[thumbIdx].size.x)
        let rangeX = max(0.0'f32, storage.maxItemWidth - storage.viewportWidth)
        let input = b.frameCtx.input
        if MouseLeft in input.mouseDown and travel > 0.0'f32:
          if b.wasHeld(thumbIdx, includeChildren = true):
            storage.scrollByX(input.mouseDelta.x / travel * rangeX)
          elif b.wasHeld(trackIdx):
            storage.pendingHorizontalRange = false
            let trackPos = b.absoluteNodePosPrev(b.nodes[trackIdx].id, trackIdx)
            storage.scrollOffsetX = clamp(
              (input.mouse.x - trackPos.x - b.nodes[thumbIdx].size.x * 0.5'f32) / travel,
              0.0'f32, 1.0'f32) * rangeX
        if fitSizing:
          b.updateHorizontalScrollbar(viewportIndex, storage)

    storage.scrollAnimationOffsetY = storage.scrollOffsetY
    result = storage
