import nuigi, nuigi/widgets, nuigi/widgets/[dynamic_virtuallist, list_table],
  nuigi/core/vecmath

{.passL: "-Lbuild".}

when defined(nimony):
  import std/assertions

type TestListContext = object
  builtIndices: seq[int]
  changedItemIndex: int
  changedItemHeight: float32
  postLayoutChangedItemIndex: int
  postLayoutChangedItemHeight: float32
  itemThreeId: UiNodeId
  wideItemIndex: int
  wideItemWidth: float32

proc fixedMeasureText(text: openArray[char], fontId: int16, fontSize: float32, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.gcsafe, raises: [].} =
  let _ = fontId
  let naturalWidth = text.len.float32 * 10.0'f32
  let lineCount =
    if maxWidth > 0.0'f32 and naturalWidth > maxWidth:
      int((naturalWidth + maxWidth - 1.0'f32) / maxWidth)
    else:
      1
  result = UiTextArrangement()
  result.fontSize = fontSize
  result.size = vec2(if maxWidth >= 0.0'f32: min(naturalWidth, maxWidth) else: naturalWidth, lineCount.float32 * 20.0'f32)

proc require(cond: bool, msg: string) =
  when defined(nimony):
    assert cond, msg
  else:
    doAssert(cond, msg)

proc buildVariableHeightItem(b: var UiBuilder, itemIndex: int, userData: int) =
  let context = cast[ptr TestListContext](userData)
  context.builtIndices.add(itemIndex)
  if itemIndex == 3:
    context.itemThreeId = b.currentNode.id
  let itemHeight =
    if itemIndex == context.changedItemIndex:
      context.changedItemHeight
    elif itemIndex mod 2 == 0:
      20.0'f32
    else:
      50.0'f32
  discard b.height(itemHeight)

proc buildTableRow(b: var UiBuilder, itemIndex: int, userData: int) =
  discard itemIndex
  discard userData
  b.node:
    discard b.size(10.0'f32, 20.0'f32)
  b.node:
    discard b.size(60.0'f32, 30.0'f32)
  b.node:
    discard b.size(20.0'f32, 10.0'f32)

proc postLayoutVariableHeightItems(
    b: var UiBuilder, nodeIdx: int, userData: int) {.raises: [].} =
  let context = cast[ptr TestListContext](userData)
  var renderedListIndex = 0
  for itemNodeIdx in b.children(nodeIdx):
    if renderedListIndex >= context.builtIndices.len:
      break
    if context.postLayoutChangedItemIndex >= 0 and
      context.postLayoutChangedItemHeight > 0.0'f32 and
      context.builtIndices[renderedListIndex] == context.postLayoutChangedItemIndex:
      b.frame.nodes[itemNodeIdx].size.y = context.postLayoutChangedItemHeight
    inc renderedListIndex

proc buildFrame(b: var UiBuilder, context: var TestListContext,
    input = default(UiInputSnapshot), useCustomRowLayout = false,
    animationTick = 1.0'f32 / 60.0'f32) =
  context.builtIndices.setLen(0)
  discard b.beginUiFrame(200.0'f32, 100.0'f32, input, animationTick)
  if useCustomRowLayout:
    discard b.dynamicVirtualList(100, 30.0'f32,
      buildVariableHeightItem, cast[int](context.addr),
      postLayoutVariableHeightItems, cast[int](context.addr))
  else:
    discard b.dynamicVirtualList(100, 30.0'f32,
      buildVariableHeightItem, cast[int](context.addr))
  b.endUiFrame(buildRenderCommands = false)

proc dynamicListStorage(b: var UiBuilder): UiDynamicVirtualListStorage =
  for i in 0 ..< b.frame.nodes.len:
    let storage = b.nodeStorageGet(b.frame.nodes[i].addr)
    if storage != nil and storage of UiDynamicVirtualListStorage:
      return cast[UiDynamicVirtualListStorage](storage)
  return nil

proc dynamicListStorageNodeIndex(b: var UiBuilder): int =
  for i in 0 ..< b.frame.nodes.len:
    let storage = b.nodeStorageGet(b.frame.nodes[i].addr)
    if storage != nil and storage of UiDynamicVirtualListStorage:
      return i
  return -1

proc dynamicListThumbId(b: var UiBuilder): UiNodeId =
  let storage = b.dynamicListStorage()
  if storage == nil or storage.scrollbarThumbIndex < 0:
    return noneNodeId()
  b.frame.nodes[storage.scrollbarThumbIndex].id

proc testOnlyVisibleItemsAreBuiltAndMeasured() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(changedItemIndex: -1)
  b.buildFrame(context)

  require(context.builtIndices == @[0, 1, 2, 3], "dynamic list should only build intersecting items")
  let storage = b.dynamicListStorage()
  require(storage != nil, "dynamic list should persist its cache in node storage")
  require(storage.heights.len == 4, "dynamic list should cache every rendered item height")
  require(storage.heights[0].height == 20.0'f32, "first measured height mismatch")
  require(storage.heights[1].height == 50.0'f32, "second measured height mismatch")
  require(storage.estimatedTotalHeight(100, 30.0'f32) == 3020.0'f32,
    "total height estimate should combine hints with measured heights")

proc testCachedHeightsSurviveAndGuideFollowingFrame() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(changedItemIndex: -1)
  b.buildFrame(context)
  let firstStorage = b.dynamicListStorage()

  firstStorage.scrollOffsetY = 70.0'f32
  b.buildFrame(context)
  let secondStorage = b.dynamicListStorage()

  require(secondStorage == firstStorage, "dynamic list storage should survive across frames")
  require(context.builtIndices == @[2, 3, 4, 5],
    "cached heights should determine the visible range after scrolling")
  let visibleRange = secondStorage.visibleItemRange()
  require(visibleRange.first == 2 and visibleRange.last == 5,
    "visible range should include the last measured row intersecting the viewport")
  require(secondStorage.heights.len == 6, "newly visible item heights should extend the cache")

proc testWheelScrollContinuesWithMomentum() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(changedItemIndex: -1)
  b.buildFrame(context)
  let storage = b.dynamicListStorage()
  storage.scrollSpeed = 20.0'f32
  storage.scrollFrequency = 50.0'f32

  let wheelInput = UiInputSnapshot(
    frameIndex: 1,
    mouse: vec2(10.0'f32, 10.0'f32),
    wheel: vec2(0.0'f32, -1.0'f32),
  )
  b.buildFrame(context, wheelInput)
  let offsetAfterWheel = storage.scrollOffsetY
  require(offsetAfterWheel > 0.0'f32 and offsetAfterWheel < 20.0'f32,
    "wheel distance should be animated rather than applied as a one-frame jump")
  require(b.anythingAnimating, "wheel animation should keep render-on-demand active")

  let idleInput = UiInputSnapshot(
    frameIndex: 2,
    mouse: vec2(10.0'f32, 10.0'f32),
  )
  b.buildFrame(context, idleInput)
  let firstMomentumDelta = storage.scrollOffsetY - offsetAfterWheel
  require(firstMomentumDelta > 0.0, "scrolling should continue after wheel input ends")

  b.buildFrame(context, UiInputSnapshot(
    frameIndex: 3,
    mouse: vec2(10.0'f32, 10.0'f32),
  ))
  let secondMomentumDelta = storage.scrollOffsetY - offsetAfterWheel - firstMomentumDelta
  require(secondMomentumDelta > 0.0,
    "scrolling should continue smoothly across event-free frames")
  for frame in 4 .. 64:
    b.buildFrame(context, UiInputSnapshot(frameIndex: frame.uint64))
  require(abs(storage.scrollOffsetY - 20.0'f32) < 0.001'f32,
    "wheel animation should settle at the requested distance without extra drift")
  require(not b.anythingAnimating, "settled scrolling should stop requesting frames")

proc buildScrollItem(b: var UiBuilder, itemIndex: int, userData: int) =
  discard itemIndex
  discard userData
  discard b.height(20.0'f32)

proc buildScrollFrame(b: var UiBuilder, wheelY: float32 = 0.0'f32,
    animationTick = 1.0'f32 / 60.0'f32) =
  let input = UiInputSnapshot(
    mouse: vec2(10.0'f32, 10.0'f32),
    wheel: vec2(0.0'f32, wheelY))
  discard b.beginUiFrame(200.0'f32, 100.0'f32, input, animationTick)
  discard b.dynamicVirtualList(1000, 20.0'f32, buildScrollItem)
  b.endUiFrame(buildRenderCommands = false)

proc testScrollFrequencyIsConfigurable() =
  var slow = newBuilder(fixedMeasureText)
  var fast = newBuilder(fixedMeasureText)
  slow.buildScrollFrame()
  fast.buildScrollFrame()
  let slowStorage = slow.dynamicListStorage()
  let fastStorage = fast.dynamicListStorage()
  slowStorage.scrollSpeed = 20.0'f32
  fastStorage.scrollSpeed = 20.0'f32
  fastStorage.scrollFrequency = 50.0'f32
  slowStorage.scrollFrequency = 30.0'f32
  slow.buildScrollFrame(-1.0'f32)
  fast.buildScrollFrame(-1.0'f32)
  require(fastStorage.scrollOffsetY > slowStorage.scrollOffsetY,
    "higher storage frequency should reach the wheel target faster")
  require(slowStorage.scrollFrequency == 30.0'f32,
    "rebuilding the list must preserve its configured frequency")
  require(slowStorage.scrollSpeed == 20.0'f32 and fastStorage.scrollSpeed == 20.0'f32,
    "rebuilding the list must preserve its configured wheel distance")
  for frame in 0 ..< 120:
    slow.buildScrollFrame()
    fast.buildScrollFrame()
  require(abs(slowStorage.scrollOffsetY - 20.0'f32) < 0.001'f32 and
    abs(fastStorage.scrollOffsetY - 20.0'f32) < 0.001'f32,
    "frequency should change response time, not total scroll distance")

proc testIrregularWheelEventsAreFrameRateIndependent() =
  var reference: seq[float32] = @[]
  for frameRate in [30, 60, 120, 240]:
    var b = newBuilder(fixedMeasureText)
    b.buildScrollFrame()
    let storage = b.dynamicListStorage()
    storage.scrollSpeed = 20.0'f32
    storage.scrollFrequency = 50.0'f32
    let frameTime = 1.0'f32 / frameRate.float32
    let eventStride = frameRate div 10
    let amounts = [-1.0'f32, -3.0'f32, -0.5'f32, -2.0'f32, -1.25'f32]
    var previousOffset = 0.0'f32
    var sampleIndex = 0
    for frame in 0 ..< frameRate:
      let eventIndex = frame div eventStride
      let wheel =
        if frame mod eventStride == 0 and eventIndex < amounts.len:
          amounts[eventIndex]
        else: 0.0'f32
      b.buildScrollFrame(wheel, frameTime)
      require(storage.scrollOffsetY >= previousOffset and
        storage.scrollOffsetY <= 155.001'f32,
        "uneven wheel events must move monotonically without overshooting their total")
      if frameRate == 240 and frame < 120:
        require(storage.scrollOffsetY > previousOffset,
          "subpixel animation must continue between sparse wheel events")
      previousOffset = storage.scrollOffsetY
      if (frame + 1) mod (frameRate div 30) == 0:
        if frameRate == 30:
          reference.add(storage.scrollOffsetY)
        else:
          require(abs(storage.scrollOffsetY - reference[sampleIndex]) < 0.002'f32,
            "the same wheel sequence must follow the same curve at every frame rate")
        inc sampleIndex
    require(abs(storage.scrollOffsetY - 155.0'f32) < 0.001'f32,
      "irregular wheel deltas should settle at their sum, regardless of frame rate")
    require(not b.anythingAnimating, "the wheel sequence should finish animating")

proc testWheelTimingAndDirectionChanges() =
  var b = newBuilder(fixedMeasureText)
  b.buildScrollFrame()
  let storage = b.dynamicListStorage()
  storage.scrollSpeed = 20.0'f32
  storage.scrollFrequency = 50.0'f32
  b.buildScrollFrame(-0.25'f32, 0.0'f32)
  require(storage.scrollOffsetY == 0.0'f32 and b.anythingAnimating,
    "a zero-time input frame should queue distance without an impulse or division by zero")
  b.buildScrollFrame(animationTick = 1.0'f32)
  require(abs(storage.scrollOffsetY - 5.0'f32) < 0.001'f32 and not b.anythingAnimating,
    "a long frame should settle the animation without clamping elapsed time")

  storage.scrollOffsetY = 100.0'f32
  b.buildScrollFrame(-3.0'f32)
  let beforeReverse = storage.scrollOffsetY
  b.buildScrollFrame(1.0'f32)
  require(storage.scrollOffsetY < beforeReverse,
    "reversing wheel direction should cancel the old pending motion immediately")
  for frame in 0 ..< 60:
    b.buildScrollFrame()
  require(abs(storage.scrollOffsetY - (beforeReverse - 20.0'f32)) < 0.001'f32,
    "reversed scrolling should not resume the previous direction")

proc testDirectScrollingCancelsWheelAnimation() =
  for action in 0 .. 5:
    var b = newBuilder(fixedMeasureText)
    b.buildScrollFrame()
    let storage = b.dynamicListStorage()
    storage.scrollSpeed = 20.0'f32
    storage.scrollFrequency = 50.0'f32
    storage.scrollOffsetY = 100.0'f32
    b.buildScrollFrame(-3.0'f32)
    case action
    of 0: storage.scrollByY(10.0'f32)
    of 1: storage.centerItem(30)
    of 2: discard storage.scrollToItemAtOffset(30, 10.0'f32)
    of 3: discard storage.ensureItemVisible(30, 100.0'f32, 0.0'f32)
    of 4: storage.scrollOffsetY = 500.0'f32
    else: discard storage.scrollToItem(30, 100.0'f32, 0.0'f32, true, false)
    let offset = storage.scrollOffsetY
    for frame in 0 ..< 30:
      b.buildScrollFrame()
    require(abs(storage.scrollOffsetY - offset) < 0.001'f32,
      "direct navigation must clear both velocity and remaining wheel distance")
    require(not b.anythingAnimating, "cancelled wheel animation must stop rendering")

proc testWheelStopsAtScrollBoundaries() =
  var b = newBuilder(fixedMeasureText)
  b.buildScrollFrame()
  let storage = b.dynamicListStorage()
  storage.scrollSpeed = 20.0'f32
  storage.scrollFrequency = 50.0'f32
  storage.scrollOffsetY = 19895.0'f32
  b.buildScrollFrame(-10.0'f32)
  for frame in 0 ..< 60:
    b.buildScrollFrame()
  require(abs(storage.scrollOffsetY - 19900.0'f32) < 0.001'f32 and not b.anythingAnimating,
    "the wheel target should stop at the bottom boundary without hidden overscroll")
  b.buildScrollFrame(1.0'f32)
  require(storage.scrollOffsetY < 19900.0'f32,
    "scrolling away from a boundary should respond on the first event")
  storage.scrollOffsetY = 5.0'f32
  b.buildScrollFrame(10.0'f32)
  for frame in 0 ..< 60:
    b.buildScrollFrame()
  require(abs(storage.scrollOffsetY) < 0.001'f32 and not b.anythingAnimating,
    "the wheel target should stop at the top boundary")

proc testTerminalWheelScrollsOneRow() =
  var b = newBuilder(fixedMeasureText, backendType = UiBackendType.Terminal)
  var context = TestListContext(changedItemIndex: -1)
  b.buildFrame(context)
  b.dynamicListStorage().scrollSpeed = 1.0'f32

  b.buildFrame(context, UiInputSnapshot(
    frameIndex: 1,
    mouse: vec2(10.0'f32, 10.0'f32),
    wheel: vec2(0.0'f32, -1.0'f32),
  ))
  require(b.dynamicListStorage().scrollOffsetY == 1.0'f32,
    "terminal wheel input should scroll one row")
  for frame in 2 .. 10:
    b.buildFrame(context, UiInputSnapshot(frameIndex: frame.uint64))
  require(b.dynamicListStorage().scrollOffsetY == 1.0'f32 and not b.anythingAnimating,
    "terminal wheel input must not cause delayed fractional-row momentum")

proc testThumbDragUsesMouseDelta() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(changedItemIndex: -1)
  b.buildFrame(context)

  let thumbId = b.dynamicListThumbId()
  require(thumbId != noneNodeId(), "dynamic list should build a scrollbar thumb")
  let thumbIndex = b.currentNodeIndex(thumbId)
  require(thumbIndex >= 0, "expected the scrollbar thumb in the current frame")
  let thumbPos = b.absoluteNodePos(thumbIndex)
  let thumbSize = b.frame.nodes[thumbIndex].size
  let pressPos = thumbPos + thumbSize * 0.5'f32
  b.buildFrame(context, UiInputSnapshot(
    frameIndex: 1,
    mouse: pressPos,
    mouseDown: {MouseLeft},
    mousePressed: {MouseLeft},
  ))
  require(b.previousOutput.heldId == thumbId,
    "pressing the scrollbar thumb should capture it")
  let storage = b.dynamicListStorage()
  storage.scrollOffsetY = 100.0'f32

  b.buildFrame(context, UiInputSnapshot(
    frameIndex: 2,
    mouse: pressPos + vec2(0.0'f32, 4.0'f32),
    mouseDelta: vec2(0.0'f32, 4.0'f32),
    mouseDown: {MouseLeft},
  ))

  # Estimated range is 2920 and thumb travel is 80, so 4 px moves 146 list
  # pixels. Measuring the partially clipped first item must not alter that.
  require(abs(storage.scrollOffsetY - 246.0'f32) < 0.001,
    "thumb dragging must not be offset by measuring the first visible item; got " &
      $storage.scrollOffsetY)

proc testPartiallyVisibleHeightChangeDoesNotAdjustScrollOffset() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(changedItemIndex: -1)
  b.buildFrame(context)

  let storage = b.dynamicListStorage()
  storage.scrollOffsetY = 80.0'f32
  b.buildFrame(context)
  context.changedItemIndex = 2
  context.changedItemHeight = 40.0'f32
  b.buildFrame(context)

  require(abs(storage.scrollOffsetY - 80.0'f32) < 0.001,
    "resizing the partially visible first item must not move the scroll offset")
  let itemThreeIndex = b.currentNodeIndex(context.itemThreeId)
  require(itemThreeIndex >= 0, "expected the item after the resized row to be rendered")
  require(abs(b.frame.nodes[itemThreeIndex].pos.y - 30.0'f32) < 0.001,
    "content after a resized partially visible item should move by its height delta")

proc testPostLayoutHeightUpdatesCacheAndScrollAnchor() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(
    changedItemIndex: -1,
    postLayoutChangedItemIndex: -1)
  b.buildFrame(context, useCustomRowLayout = true)

  let storage = b.dynamicListStorage()
  storage.scrollOffsetY = 10.0'f32
  context.postLayoutChangedItemIndex = 0
  context.postLayoutChangedItemHeight = 40.0'f32
  b.buildFrame(context, useCustomRowLayout = true)

  require(storage.heights[0].height == 40.0'f32,
    "post-layout measurement should replace the rendered item's cached height")
  require(abs(storage.scrollOffsetY - 10.0'f32) < 0.001,
    "post-layout resizing of the partially visible first item must not move the scroll offset")
  let firstItemNodeIndex = b.firstChildIndex(b.dynamicListStorageNodeIndex())
  require(firstItemNodeIndex >= 0, "expected a rendered dynamic-list item")
  require(abs(b.frame.nodes[firstItemNodeIndex].pos.y + 10.0'f32) < 0.001,
    "post-layout resizing must preserve the partially visible item's position")

  storage.scrollOffsetY = 90.0'f32
  b.buildFrame(context, useCustomRowLayout = true)
  require(context.builtIndices[0] == 2,
    "scrolling should use heights changed by post-layout measurement")
  let firstVisibleNodeIndex = b.firstChildIndex(b.dynamicListStorageNodeIndex())
  require(firstVisibleNodeIndex >= 0, "expected a rendered item after scrolling")
  require(abs(b.frame.nodes[firstVisibleNodeIndex].pos.y) < 0.001,
    "the first visible item should use the post-layout height when positioned")

proc testUpwardEntryHeightChangeAnchorsFollowingItem() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(
    changedItemIndex: -1,
    postLayoutChangedItemIndex: -1)
  b.buildFrame(context, useCustomRowLayout = true)
  let storage = b.dynamicListStorage()

  storage.scrollOffsetY = 110.0'f32
  b.buildFrame(context, useCustomRowLayout = true)
  require(context.builtIndices[0] == 3,
    "expected item 3 to be first before scrolling upward")

  storage.scrollOffsetY = 80.0'f32
  context.postLayoutChangedItemIndex = 2
  context.postLayoutChangedItemHeight = 40.0'f32
  b.buildFrame(context, useCustomRowLayout = true)

  require(context.builtIndices[0] == 2,
    "scrolling upward should reveal item 2 above the previous first item")
  require(abs(storage.scrollOffsetY - 100.0'f32) < 0.001,
    "a taller item entering from above should compensate the scroll offset")
  let viewportIndex = b.dynamicListStorageNodeIndex()
  let firstItemIndex = b.firstChildIndex(viewportIndex)
  require(firstItemIndex >= 0, "expected the newly revealed first item")
  let secondItemIndex = b.frame.nodes[firstItemIndex].nextSibling
  require(secondItemIndex >= 0, "expected the previously visible following item")
  require(abs(b.frame.nodes[firstItemIndex].pos.y + 30.0'f32) < 0.001,
    "the taller first item should extend upward by its height delta")
  require(abs(b.frame.nodes[secondItemIndex].pos.y - 10.0'f32) < 0.001,
    "the previously visible following item should remain at the same position")

proc testListTableAlignsRenderedColumns() =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(300.0'f32, 100.0'f32)
  discard b.listTable(10, 30.0'f32, [
    tableColumnFixed(40.0'f32),
    tableColumnFit(),
    tableColumnFill(),
  ], buildTableRow, columnGap = 5.0'f32)
  b.endUiFrame(buildRenderCommands = false)

  let viewportIndex = b.dynamicListStorageNodeIndex()
  let rowIndex = b.firstChildIndex(viewportIndex)
  require(rowIndex >= 0, "list table should build a visible row")
  let firstCell = b.firstChildIndex(rowIndex)
  let secondCell = b.frame.nodes[firstCell].nextSibling
  let thirdCell = b.frame.nodes[secondCell].nextSibling
  require(b.frame.nodes[firstCell].size.x == 40.0'f32,
    "fixed list-table column width mismatch")
  require(b.frame.nodes[secondCell].size.x == 60.0'f32,
    "fit list-table column should use the widest rendered cell")
  require(b.frame.nodes[thirdCell].size.x == 180.0'f32,
    "fill list-table column should consume remaining viewport width")
  require(b.frame.nodes[secondCell].pos.x == 45.0'f32 and
      b.frame.nodes[thirdCell].pos.x == 110.0'f32,
    "list-table cells should share aligned column positions")
  require(b.frame.nodes[rowIndex].size.y == 30.0'f32,
    "list-table row should fit its tallest cell")
  require(b.frame.nodes[firstCell].pos.y == 5.0'f32 and
      b.frame.nodes[thirdCell].pos.y == 10.0'f32,
    "list-table cells should be vertically centered")

proc buildFitFrame(b: var UiBuilder, context: var TestListContext,
    input = default(UiInputSnapshot), useMaxHeight = false, maxH = 0.0'f32) =
  context.builtIndices.setLen(0)
  discard b.beginUiFrame(200.0'f32, 400.0'f32, input)
  b.node:
    discard b.fillX().fitY()
    if useMaxHeight:
      discard b.maxHeight(maxH)
    discard b.dynamicVirtualList(4, 30.0'f32,
      buildVariableHeightItem, cast[int](context.addr))
  b.endUiFrame(buildRenderCommands = false)

proc fitListRootIndex(b: var UiBuilder): int =
  let viewportIndex = b.dynamicListStorageNodeIndex()
  if viewportIndex < 0:
    return -1
  int(b.frame.nodes[viewportIndex].parent)

proc fitListThumbIndex(b: var UiBuilder): int =
  let storage = b.dynamicListStorage()
  if storage == nil:
    return -1
  let thumbIdx = storage.scrollbarThumbIndex
  let trackIdx = storage.scrollbarTrackIndex
  if thumbIdx < 0 or thumbIdx >= b.frame.nodes.len:
    return -1
  if trackIdx < 0 or trackIdx >= b.frame.nodes.len:
    return -1
  if b.frame.nodes[thumbIdx].parent != trackIdx.int32:
    return -1
  thumbIdx

proc testFitParentSizesImmediately() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(changedItemIndex: -1)
  context.builtIndices.setLen(0)
  discard b.beginUiFrame(200.0'f32, 400.0'f32, default(UiInputSnapshot))
  b.node:
    discard b.fillX().fitY()
    discard b.dynamicVirtualList(4, 30.0'f32,
      buildVariableHeightItem, cast[int](context.addr))
    # No endUiFrame yet and no deferred build: rows and sizes must already
    # be resolved by the dynamicVirtualList call itself.
    let storage = b.dynamicListStorage()
    require(storage != nil, "fit list should persist its cache in node storage")
    require(context.builtIndices == @[0, 1, 2, 3],
      "fit list should build rows immediately, without waiting for flush")
    require(abs(storage.viewportHeight - 140.0'f32) < 0.001,
      "fit list viewport should size to the rows immediately; got " & $storage.viewportHeight)
    let listIndex = b.fitListRootIndex()
    require(listIndex >= 0, "expected the dynamic list root node")
    require(abs(b.frame.nodes[listIndex].size.y - 140.0'f32) < 0.001,
      "fit list root should size to the rows immediately; got " & $b.frame.nodes[listIndex].size.y)
    let wrapperIndex = int(b.frame.nodes[listIndex].parent)
    require(abs(b.frame.nodes[wrapperIndex].size.y - 140.0'f32) < 0.001,
      "fit parent should wrap the rows immediately; got " & $b.frame.nodes[wrapperIndex].size.y)
  b.endUiFrame(buildRenderCommands = false)

proc testFitParentSizesToRowsWithoutScrollbar() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(changedItemIndex: -1)
  b.buildFitFrame(context)

  let storage = b.dynamicListStorage()
  require(storage != nil, "fit list should persist its cache in node storage")
  require(context.builtIndices == @[0, 1, 2, 3],
    "fit list should build all rows when they fit")
  require(abs(storage.viewportHeight - 140.0'f32) < 0.001,
    "fit list viewport should size to the rows height; got " & $storage.viewportHeight)
  let listIndex = b.fitListRootIndex()
  require(listIndex >= 0, "expected the dynamic list root node")
  require(abs(b.frame.nodes[listIndex].size.y - 140.0'f32) < 0.001,
    "fit list root should size to the rows height; got " & $b.frame.nodes[listIndex].size.y)
  let wrapperIndex = int(b.frame.nodes[listIndex].parent)
  require(abs(b.frame.nodes[wrapperIndex].size.y - 140.0'f32) < 0.001,
    "fit parent should wrap the rows height; got " & $b.frame.nodes[wrapperIndex].size.y)
  let trackIndex = storage.scrollbarTrackIndex
  require(trackIndex >= 0 and trackIndex < b.frame.nodes.len,
    "expected the scrollbar track node")
  require(abs(b.frame.nodes[trackIndex].size.x) < 0.001,
    "fit list should hide the scrollbar when rows fit; got " & $b.frame.nodes[trackIndex].size.x)

  # A second frame converges row positions to the measured heights.
  b.buildFitFrame(context)
  let expectedTops = @[0.0'f32, 20.0'f32, 70.0'f32, 90.0'f32]
  var rowPos = 0
  for rowIdx in b.children(b.dynamicListStorageNodeIndex()):
    require(rowPos < expectedTops.len, "fit list built more rows than expected")
    require(abs(b.frame.nodes[rowIdx].pos.y - expectedTops[rowPos]) < 0.001,
      "fit list row position mismatch at " & $rowPos & "; got " & $b.frame.nodes[rowIdx].pos.y)
    inc rowPos
  require(rowPos == expectedTops.len, "fit list should build every row")

proc testFitParentCapsAtMaxHeightWithScrollbar() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(changedItemIndex: -1)
  b.buildFitFrame(context, useMaxHeight = true, maxH = 60.0'f32)

  let storage = b.dynamicListStorage()
  require(storage != nil, "capped fit list should persist its cache in node storage")
  require(context.builtIndices == @[0, 1],
    "capped fit list should only build rows visible in the capped viewport")
  require(abs(storage.viewportHeight - 60.0'f32) < 0.001,
    "capped fit list viewport should clamp to the maximum height; got " & $storage.viewportHeight)
  let listIndex = b.fitListRootIndex()
  require(listIndex >= 0, "expected the dynamic list root node")
  require(abs(b.frame.nodes[listIndex].size.y - 60.0'f32) < 0.001,
    "capped fit list root should clamp to the maximum height; got " & $b.frame.nodes[listIndex].size.y)
  let wrapperIndex = int(b.frame.nodes[listIndex].parent)
  require(abs(b.frame.nodes[wrapperIndex].size.y - 60.0'f32) < 0.001,
    "capped fit parent should clamp to the maximum height; got " & $b.frame.nodes[wrapperIndex].size.y)
  let trackIndex = storage.scrollbarTrackIndex
  require(trackIndex >= 0 and trackIndex < b.frame.nodes.len,
    "expected the scrollbar track node")
  require(abs(b.frame.nodes[trackIndex].size.x - 10.0'f32) < 0.001,
    "capped fit list should show the scrollbar; got " & $b.frame.nodes[trackIndex].size.x)
  let thumbIndex = b.fitListThumbIndex()
  require(thumbIndex >= 0, "capped fit list should build a scrollbar thumb")
  require(b.frame.nodes[thumbIndex].size.y > 0.0'f32,
    "capped fit list scrollbar thumb should be visible")

proc buildHorizontalItem(b: var UiBuilder, itemIndex: int, userData: int) =
  let context = cast[ptr TestListContext](userData)
  context.builtIndices.add itemIndex
  discard b.height(20.0'f32)
  b.layoutHorizontal:
    discard b.fillX().fitY()
    b.node:
      discard b.size(if itemIndex == context.wideItemIndex:
        context.wideItemWidth else: 50.0'f32, 20.0'f32)

proc buildHorizontalFrame(b: var UiBuilder, context: var TestListContext,
    input = default(UiInputSnapshot), enabled = true, width = 200.0'f32,
    fitParent = false, capped = false) =
  context.builtIndices.setLen(0)
  discard b.beginUiFrame(width, 100.0'f32, input)
  if fitParent:
    b.node:
      discard b.fillX().fitY()
      if capped:
        discard b.maxHeight(60.0'f32)
      discard b.dynamicVirtualList(4, 20.0'f32, buildHorizontalItem,
        cast[int](context.addr), horizontalScroll = enabled)
  else:
    discard b.dynamicVirtualList(100, 20.0'f32, buildHorizontalItem,
      cast[int](context.addr), horizontalScroll = enabled)
  b.endUiFrame(buildRenderCommands = false)

proc testHorizontalWidthPersistsUntilReset() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(wideItemIndex: 0, wideItemWidth: 600.0'f32)
  b.buildHorizontalFrame(context)
  let storage = b.dynamicListStorage()
  require(storage.maxItemWidth == 600.0'f32, "measure overflowing descendants, not just fillX row width")
  require(storage.viewportWidth == 190.0'f32, "horizontal range should exclude vertical track")
  require(storage.viewportHeight == 90.0'f32, "horizontal track should reserve viewport height immediately")
  let thumbWidth = b.nodes[storage.horizontalScrollbarThumbIndex].size.x
  require(abs(thumbWidth - 190.0'f32 * 190.0'f32 / 600.0'f32) < 0.001'f32,
    "horizontal thumb should reflect widest known row")
  storage.scrollOffsetY = 200.0'f32
  storage.scrollByX(100.0'f32)
  b.buildHorizontalFrame(context)
  require(0 notin context.builtIndices, "wide row must be offscreen for retention test")
  require(storage.maxItemWidth == 600.0'f32, "scrolling away must retain widest row")
  require(b.nodes[storage.horizontalScrollbarThumbIndex].size.x == thumbWidth,
    "horizontal thumb must not shrink or grow when wide row leaves view")
  for rowIdx in b.children(b.dynamicListStorageNodeIndex()):
    require(b.nodes[rowIdx].pos.x == -100.0'f32, "entire rows must use horizontal offset")
  b.buildHorizontalFrame(context, width = 800.0'f32)
  require(storage.scrollOffsetX == 0.0'f32, "viewport expansion must clamp horizontal offset")
  require(storage.maxItemWidth == 600.0'f32, "resizing must not change measured content widths")
  context.wideItemWidth = 50.0'f32
  storage.clearMeasuredWidths()
  b.buildHorizontalFrame(context)
  require(storage.maxItemWidth == 50.0'f32, "explicit reset must permit width to shrink")
  require(b.nodes[storage.horizontalScrollbarTrackIndex].size.y == 0.0'f32,
    "short content must hide horizontal track")
  require(storage.viewportHeight == 100.0'f32, "hidden track must return viewport height")

proc testHorizontalInputAndDisable() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(wideItemIndex: 0, wideItemWidth: 600.0'f32)
  b.buildHorizontalFrame(context)
  let storage = b.dynamicListStorage()
  storage.scrollSpeed = 80.0'f32
  b.buildHorizontalFrame(context, UiInputSnapshot(frameIndex: 1,
    mouse: vec2(10.0'f32, 10.0'f32), wheel: vec2(-1.0'f32, 0.0'f32)))
  require(storage.scrollOffsetX == 80.0'f32, "horizontal wheel should move horizontal offset")
  require(storage.scrollOffsetY == 0.0'f32, "horizontal wheel must not move vertical offset")
  b.buildHorizontalFrame(context, UiInputSnapshot(frameIndex: 2,
    mouse: vec2(10.0'f32, 10.0'f32), wheel: vec2(0.0'f32, -1.0'f32),
    modsDown: {ModShift}))
  require(storage.scrollOffsetX == 160.0'f32, "Shift-wheel should scroll horizontally")
  require(storage.scrollOffsetY == 0.0'f32, "Shift-wheel must not scroll vertically")
  let thumb = b.nodes[storage.horizontalScrollbarThumbIndex]
  let trackPos = b.absoluteNodePos(storage.horizontalScrollbarTrackIndex)
  let mouse = vec2(trackPos.x + thumb.pos.x + 2.0'f32, trackPos.y + 2.0'f32)
  b.buildHorizontalFrame(context, UiInputSnapshot(frameIndex: 3, mouse: mouse,
    mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
  let beforeDrag = storage.scrollOffsetX
  b.buildHorizontalFrame(context, UiInputSnapshot(frameIndex: 4,
    mouse: mouse + vec2(10.0'f32, 0.0'f32), mouseDelta: vec2(10.0'f32, 0.0'f32),
    mouseDown: {MouseLeft}))
  require(storage.scrollOffsetX > beforeDrag, "horizontal thumb drag must scroll")
  storage.scrollByX(10000.0'f32)
  b.buildHorizontalFrame(context)
  require(storage.scrollOffsetX == 410.0'f32, "horizontal offset must clamp to known content width")
  b.buildHorizontalFrame(context, enabled = false)
  require(storage.scrollOffsetX == 0.0'f32, "wrapped/disabled mode must reset horizontal offset")
  require(storage.horizontalScrollbarTrackIndex == -1, "disabled mode must not create horizontal scrollbar")
  require(storage.viewportHeight == 100.0'f32, "disabled mode must preserve full viewport height")
  for rowIdx in b.children(b.dynamicListStorageNodeIndex()):
    require(b.nodes[rowIdx].pos.x == 0.0'f32, "disabled mode must not offset rows")

proc testHorizontalFitAndTerminal() =
  var context = TestListContext(wideItemIndex: 0, wideItemWidth: 600.0'f32)
  var b = newBuilder(fixedMeasureText)
  b.buildHorizontalFrame(context, fitParent = true)
  let storage = b.dynamicListStorage()
  require(storage.viewportHeight == 80.0'f32, "fit list should retain all rows")
  require(b.nodes[int(b.nodes[b.dynamicListStorageNodeIndex()].parent)].size.y == 90.0'f32,
    "fit list height must include horizontal scrollbar")
  b.buildHorizontalFrame(context, fitParent = true, capped = true)
  require(storage.viewportHeight == 50.0'f32, "capped fit viewport must reserve horizontal scrollbar")
  require(b.nodes[int(b.nodes[b.dynamicListStorageNodeIndex()].parent)].size.y == 60.0'f32,
    "horizontal scrollbar must not exceed fit maximum height")
  var terminal = newBuilder(fixedMeasureText)
  terminal.backendType = UiBackendType.Terminal
  terminal.buildHorizontalFrame(context)
  let terminalStorage = terminal.dynamicListStorage()
  require(terminal.nodes[terminalStorage.horizontalScrollbarTrackIndex].size.y == 1.0'f32,
    "terminal horizontal scrollbar should occupy one row")
  terminalStorage.scrollByX(3.5'f32)
  terminal.buildHorizontalFrame(context)
  require(terminalStorage.scrollOffsetX == 3.0'f32, "terminal horizontal offsets must align to cells")

proc buildLongHorizontalItem(b: var UiBuilder, itemIndex, userData: int) =
  b.layoutHorizontal:
    discard b.fillX().fitY()
    for i in 0 ..< 1200:
      b.node:
        discard b.fit().text("x")

proc testHorizontalLongRowsSurviveNodeGrowth() =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(200, 100)
  let storage = b.dynamicVirtualList(1, 20, buildLongHorizontalItem,
    horizontalScroll = true)
  b.endUiFrame(buildRenderCommands = false)
  require(storage.maxItemWidth == 12000, "measure entire long rows after node storage reallocates")
  require(storage.viewportHeight == 90, "long rows must still reserve horizontal scrollbar height")
  require(b.nodes[storage.horizontalScrollbarThumbIndex].size.x == 20,
    "long-row scrollbar thumb should respect minimum width")

proc testHorizontalRangeVisibilityRequests() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(wideItemIndex: 0, wideItemWidth: 600)
  b.buildHorizontalFrame(context)
  let storage = b.dynamicListStorage()
  storage.requestHorizontalRangeVisible(400, 410)
  b.buildHorizontalFrame(context)
  require(storage.scrollOffsetX == 220, "scroll minimally to show right edge of requested range")
  for rowIdx in b.children(b.dynamicListStorageNodeIndex()):
    require(b.nodes[rowIdx].pos.x == -220, "range requests must move rows in the same frame")
  storage.requestHorizontalRangeVisible(300, 310)
  b.buildHorizontalFrame(context)
  require(storage.scrollOffsetX == 220, "already visible ranges must leave offset unchanged")
  storage.requestHorizontalRangeVisible(10, 20)
  b.buildHorizontalFrame(context)
  require(storage.scrollOffsetX == 10, "scroll minimally to show left edge of requested range")
  storage.requestHorizontalRangeVisible(600, 610)
  b.buildHorizontalFrame(context)
  require(storage.maxItemWidth == 610 and storage.scrollOffsetX == 420,
    "line-end ranges must extend content enough to show the caret")
  storage.requestHorizontalRangeVisible(0, 10)
  storage.scrollByX(-20)
  b.buildHorizontalFrame(context)
  require(storage.scrollOffsetX == 400, "manual scrolling must cancel pending navigation")
  storage.requestHorizontalRangeVisible(10, 20)
  b.buildHorizontalFrame(context, enabled = false)
  b.buildHorizontalFrame(context)
  require(storage.scrollOffsetX == 0, "disabled mode must discard pending horizontal navigation")
  var terminal = newBuilder(fixedMeasureText)
  terminal.backendType = UiBackendType.Terminal
  terminal.buildHorizontalFrame(context)
  let terminalStorage = terminal.dynamicListStorage()
  terminalStorage.requestHorizontalRangeVisible(600.2'f32, 610.2'f32)
  terminal.buildHorizontalFrame(context)
  require(terminalStorage.maxItemWidth == 611 and terminalStorage.scrollOffsetX == 412,
    "terminal range visibility must round outward to keep the entire range visible")

proc testAnchorSurvivesHeightCacheInvalidation() =
  for customLayout in [false, true]:
    var b = newBuilder(fixedMeasureText)
    var context = TestListContext(changedItemIndex: -1,
      postLayoutChangedItemIndex: 2, postLayoutChangedItemHeight: 55)
    b.buildFrame(context, useCustomRowLayout = customLayout)
    let storage = b.dynamicListStorage()
    let pixelOffset = 20.0'f32
    for edit in 0 ..< 5:
      storage.clearMeasuredHeights()
      storage.shiftScrollOffset(storage.itemTop(3) - pixelOffset - storage.scrollOffsetY)
      storage.preserveItemAnchorAfterMeasurement(3)
      b.buildFrame(context, useCustomRowLayout = customLayout)
      require(storage.itemTop(3) - storage.scrollOffsetY == pixelOffset,
        "cache invalidation must not move the anchored row after measurement")
      var renderedIndex = 0
      for rowIdx in b.children(b.dynamicListStorageNodeIndex()):
        require(b.nodes[rowIdx].pos.y ==
          storage.itemTop(context.builtIndices[renderedIndex]) - storage.scrollOffsetY,
          "row geometry must agree with corrected measured offsets")
        inc renderedIndex

proc buildSlightHeightItem(b: var UiBuilder, itemIndex, userData: int) =
  discard b.height(if itemIndex mod 2 == 0: 29.5'f32 else: 30.5'f32)

proc buildTransientHeightItem(b: var UiBuilder, itemIndex, userData: int) =
  let context = cast[ptr TestListContext](userData)
  context.builtIndices.add(itemIndex)
  discard b.height(context.changedItemHeight)

proc layoutTransientHeightItems(b: var UiBuilder, nodeIdx, userData: int) {.raises: [].} =
  let context = cast[ptr TestListContext](userData)
  for rowIdx in b.children(nodeIdx):
    b.frame.nodes[rowIdx].size.y = context.changedItemHeight

proc testTransientHeightsFillViewport() =
  for mode in 0..<4:
    let customLayout = mode mod 2 == 1
    let invalidateCache = mode >= 2
    var b = newBuilder(fixedMeasureText)
    var context = TestListContext(changedItemHeight: 40,
      postLayoutChangedItemIndex: -1)
    var storage: UiDynamicVirtualListStorage
    for frame in 0..<6:
      context.builtIndices.setLen(0)
      context.changedItemHeight = if frame mod 2 == 0: 40 else: 10
      discard b.beginUiFrame(200, 100)
      storage = b.dynamicVirtualList(100, 30, buildTransientHeightItem,
        cast[int](context.addr),
        if customLayout: layoutTransientHeightItems else: nil,
        cast[int](context.addr))
      if frame == 1:
        storage.scrollOffsetY = storage.itemTop(2) - 20
      if frame > 0:
        let pixelOffset = storage.itemTop(2) - storage.scrollOffsetY
        if invalidateCache:
          storage.clearMeasuredHeights()
          storage.shiftScrollOffset(storage.itemTop(2) - pixelOffset - storage.scrollOffsetY)
        storage.preserveItemAnchorAfterMeasurement(2)
      b.endUiFrame(buildRenderCommands = false)
      let visible = storage.visibleItemRange()
      require(context.builtIndices[^1] >= visible.last,
        "every measured-visible row must be built on the shrink/grow frame")
      let last = context.builtIndices[^1]
      require(storage.itemTop(last) + storage.itemHeight(last) -
        storage.scrollOffsetY >= storage.viewportHeight,
        "rendered rows must reach the viewport bottom on the same frame")
      for i in 1..<context.builtIndices.len:
        require(context.builtIndices[i] == context.builtIndices[i - 1] + 1,
          "completion must append consecutive rows without rebuilding them")
      var rendered = 0
      for rowIdx in b.children(b.dynamicListStorageNodeIndex()):
        require(abs(b.nodes[rowIdx].pos.y -
          (storage.itemTop(context.builtIndices[rendered]) - storage.scrollOffsetY)) < 0.001,
          "completed rows must use final anchored positions")
        inc rendered

proc testMeasuredCursorVisibilityAfterInvalidation() =
  var b = newBuilder(fixedMeasureText)
  var storage: UiDynamicVirtualListStorage
  for edit in 0 ..< 8:
    discard b.beginUiFrame(200, 100)
    storage = b.dynamicVirtualList(100, 30, buildSlightHeightItem)
    storage.clearMeasuredHeights()
    storage.shiftScrollOffset(storage.itemTop(8) - 63 - storage.scrollOffsetY)
    storage.preserveItemAnchorAfterMeasurement(8)
    discard storage.scrollToItem(8, 100, 7.5, false, false)
    b.endUiFrame(buildRenderCommands = false)
    require(abs(storage.itemTop(8) - storage.scrollOffsetY - 63) < 0.001,
      "small height differences must not trigger cursor-margin scroll after invalidation")
  discard b.beginUiFrame(200, 100)
  storage = b.dynamicVirtualList(100, 30, buildSlightHeightItem)
  storage.clearMeasuredHeights()
  storage.shiftScrollOffset(storage.itemTop(8) - 70 - storage.scrollOffsetY)
  storage.preserveItemAnchorAfterMeasurement(8)
  discard storage.scrollToItem(8, 100, 7.5, false, false)
  b.endUiFrame(buildRenderCommands = false)
  require(abs(storage.itemTop(8) - storage.scrollOffsetY - 63) < 0.001,
    "cursor rows outside the margin must still scroll using their measured height")
  discard b.beginUiFrame(200, 100)
  storage = b.dynamicVirtualList(100, 30, buildSlightHeightItem)
  storage.clearMeasuredHeights()
  storage.shiftScrollOffset(storage.itemTop(8) - 63 - storage.scrollOffsetY)
  storage.preserveItemAnchorAfterMeasurement(8)
  discard storage.scrollToItem(8, 100, 7.5, true, false)
  b.endUiFrame(buildRenderCommands = false)
  require(abs(storage.itemTop(8) - storage.scrollOffsetY - 35.25) < 0.001,
    "explicit centering must use measured height after invalidation")
  for target in [40, 2]:
    discard b.beginUiFrame(200, 100)
    storage = b.dynamicVirtualList(100, 30, buildSlightHeightItem)
    storage.clearMeasuredHeights()
    storage.shiftScrollOffset(storage.itemTop(8) - 63 - storage.scrollOffsetY)
    storage.preserveItemAnchorAfterMeasurement(8)
    discard storage.scrollToItem(target, 100, 7.5, false, target == 2)
    b.endUiFrame(buildRenderCommands = false)
    let pixelOffset = storage.itemTop(target) - storage.scrollOffsetY
    require(pixelOffset >= 7.499 and pixelOffset <= 63.001,
      "navigation to another row must take precedence over the old measurement anchor")
    if target == 2:
      require(abs(pixelOffset - 35.25) < 0.001,
        "offscreen centering of another row must use its measured height")

proc buildSynchronizedItem(b: var UiBuilder, itemIndex, userData: int) =
  let context = cast[ptr TestListContext](userData)
  context.builtIndices.add(itemIndex)
  b.node:
    discard b.size(context.wideItemWidth,
      if itemIndex == context.changedItemIndex: context.changedItemHeight else: 20.0'f32)
  discard b.fillX().fitY()

proc testSynchronizedLists() =
  var b = newBuilder(fixedMeasureText)
  var leader: UiDynamicVirtualListStorage
  var follower: UiDynamicVirtualListStorage
  var leaderViewport, followerViewport: int
  var current = TestListContext(wideItemWidth: 600, changedItemIndex: 1,
    changedItemHeight: 50)
  var old = TestListContext(wideItemWidth: 50, changedItemIndex: 2,
    changedItemHeight: 40)
  template frame(input: UiInputSnapshot = default(UiInputSnapshot), fit: bool = false) =
    current.builtIndices.setLen(0)
    old.builtIndices.setLen(0)
    discard b.beginUiFrame(200, 100, input)
    b.node("pair"):
      discard b.fillX()
      if fit: discard b.fitY()
      else: discard b.fillY()
      b.node("current"):
        discard b.anchorsX(0.5, 1).finishAnchors()
        if fit: discard b.fitY()
        else: discard b.fillY()
        let root = b.nodes.len
        leader = b.dynamicVirtualList(if fit: 4 else: 100, 20,
          buildSynchronizedItem, cast[int](current.addr),
          horizontalScroll = true, synchronized = true)
        leaderViewport = b.firstChildIndex(root)
      b.node("old"):
        discard b.anchorsX(0, 0.5).finishAnchors()
        if fit: discard b.fitY()
        else: discard b.fillY()
        let root = b.nodes.len
        follower = b.dynamicVirtualList(if fit: 4 else: 100, 20,
          buildSynchronizedItem, cast[int](old.addr),
          horizontalScroll = true, synchronizeWith = leader)
        followerViewport = b.firstChildIndex(root)
    b.endUiFrame(buildRenderCommands = false)
    require(leader != follower, "panes must have separate storage")
    require(current.builtIndices == old.builtIndices, "both panes must build the same visible rows")
    require(leader.heights == follower.heights, "measured paired-row heights must match")
    require(leader.scrollOffsetX == follower.scrollOffsetX and
      leader.scrollOffsetY == follower.scrollOffsetY, "both scroll offsets must match")
    require(leader.viewportHeight == follower.viewportHeight, "viewport heights must match")
    var leaderRows: seq[int] = @[]
    var followerRows: seq[int] = @[]
    for row in b.children(leaderViewport): leaderRows.add row
    for row in b.children(followerViewport): followerRows.add row
    for i in 0..<leaderRows.len:
      require(b.nodes[leaderRows[i]].pos == b.nodes[followerRows[i]].pos and
        b.nodes[leaderRows[i]].size.y == b.nodes[followerRows[i]].size.y,
        "paired rows must be aligned after measurement")
  frame()
  require(leader.itemHeight(1) == 50 and leader.itemHeight(2) == 40,
    "each paired height must be the maximum of both panes")
  require(follower.maxItemWidth == 600, "shorter pane must follow the wider pane")
  for x in [25.0'f32, 125.0'f32]:
    frame(UiInputSnapshot(mouse: vec2(x, 10)))
    let beforeX = leader.scrollOffsetX
    frame(UiInputSnapshot(mouse: vec2(x, 10), wheel: vec2(-1, 0)))
    require(leader.scrollOffsetX > beforeX, "horizontal wheel on either pane must scroll both")
    let beforeY = leader.scrollOffsetY
    frame(UiInputSnapshot(mouse: vec2(x, 10), wheel: vec2(0, -1)))
    require(leader.scrollOffsetY > beforeY, "vertical wheel on either pane must scroll both immediately")
    for tick in 0..<30: frame()
  current.changedItemHeight = 20
  old.changedItemHeight = 20
  discard leader.scrollToItemAtOffset(0, 0, 90)
  frame()
  require(leader.itemHeight(1) == 20 and leader.itemHeight(2) == 20,
    "paired measurements must shrink when content shrinks")
  frame(fit = true)
  require(leader.viewportHeight == 80, "fit pairs must resolve their measured content height")
  require(b.nodes[int(b.nodes[leaderViewport].parent)].size.y == 90,
    "fit pairs must reserve the shared horizontal scrollbar")

proc runTests() =
  testSynchronizedLists()
  testTransientHeightsFillViewport()
  testMeasuredCursorVisibilityAfterInvalidation()
  testAnchorSurvivesHeightCacheInvalidation()
  testHorizontalWidthPersistsUntilReset()
  testHorizontalInputAndDisable()
  testHorizontalFitAndTerminal()
  testHorizontalLongRowsSurviveNodeGrowth()
  testHorizontalRangeVisibilityRequests()
  testOnlyVisibleItemsAreBuiltAndMeasured()
  testPostLayoutHeightUpdatesCacheAndScrollAnchor()
  testUpwardEntryHeightChangeAnchorsFollowingItem()
  testListTableAlignsRenderedColumns()
  testCachedHeightsSurviveAndGuideFollowingFrame()
  testWheelScrollContinuesWithMomentum()
  testScrollFrequencyIsConfigurable()
  testIrregularWheelEventsAreFrameRateIndependent()
  testWheelTimingAndDirectionChanges()
  testDirectScrollingCancelsWheelAnimation()
  testWheelStopsAtScrollBoundaries()
  testTerminalWheelScrollsOneRow()
  testThumbDragUsesMouseDelta()
  testPartiallyVisibleHeightChangeDoesNotAdjustScrollOffset()
  testFitParentSizesImmediately()
  testFitParentSizesToRowsWithoutScrollbar()
  testFitParentCapsAtMaxHeightWithScrollbar()

when isMainModule:
  when defined(nuiHorizontalScrollTests):
    testSynchronizedLists()
    testTransientHeightsFillViewport()
    testMeasuredCursorVisibilityAfterInvalidation()
    testAnchorSurvivesHeightCacheInvalidation()
    testHorizontalWidthPersistsUntilReset()
    testHorizontalInputAndDisable()
    testHorizontalFitAndTerminal()
    testHorizontalLongRowsSurviveNodeGrowth()
    testHorizontalRangeVisibilityRequests()
    testOnlyVisibleItemsAreBuiltAndMeasured()
    testPostLayoutHeightUpdatesCacheAndScrollAnchor()
    testUpwardEntryHeightChangeAnchorsFollowingItem()
    testListTableAlignsRenderedColumns()
    testCachedHeightsSurviveAndGuideFollowingFrame()
    testPartiallyVisibleHeightChangeDoesNotAdjustScrollOffset()
    testFitParentSizesImmediately()
    testFitParentSizesToRowsWithoutScrollbar()
    testFitParentCapsAtMaxHeightWithScrollbar()
  elif defined(nuiScrollTests):
    testWheelScrollContinuesWithMomentum()
    testScrollFrequencyIsConfigurable()
    testIrregularWheelEventsAreFrameRateIndependent()
    testWheelTimingAndDirectionChanges()
    testDirectScrollingCancelsWheelAnimation()
    testWheelStopsAtScrollBoundaries()
    testTerminalWheelScrollsOneRow()
  else:
    runTests()