import nuigi, dynamic_virtuallist, mymath

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

proc fixedMeasureText(text: openArray[char], fontId: int16, fontSize: float32, maxWidth: float32): UiTextArrangement {.gcsafe, raises: [].} =
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
    input = default(UiInputSnapshot), useCustomRowLayout = false) =
  context.builtIndices.setLen(0)
  discard b.beginUiFrame(200.0'f32, 100.0'f32, input)
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

proc dynamicListThumbId(b: UiBuilder): UiNodeId =
  let listIndex = b.firstChildIndex(0)
  if listIndex < 0:
    return noneNodeId()
  var scrollbarIndex = -1
  for childIndex in b.children(listIndex):
    scrollbarIndex = childIndex
  if scrollbarIndex < 0:
    return noneNodeId()
  let thumbIndex = b.firstChildIndex(scrollbarIndex)
  if thumbIndex < 0:
    return noneNodeId()
  b.frame.nodes[thumbIndex].id

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
  require(secondStorage.heights.len == 6, "newly visible item heights should extend the cache")

proc testWheelScrollContinuesWithMomentum() =
  var b = newBuilder(fixedMeasureText)
  var context = TestListContext(changedItemIndex: -1)
  b.buildFrame(context)

  let wheelInput = UiInputSnapshot(
    frameIndex: 1,
    mouse: vec2(10.0'f32, 10.0'f32),
    wheel: vec2(0.0'f32, -1.0'f32),
  )
  b.buildFrame(context, wheelInput)
  let storage = b.dynamicListStorage()
  let offsetAfterWheel = storage.scrollOffsetY
  require(offsetAfterWheel == 20.0, "wheel input should preserve the initial scroll distance")

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
  require(secondMomentumDelta > 0.0 and secondMomentumDelta < firstMomentumDelta,
    "scroll momentum should decay each frame")

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

proc runTests() =
  testOnlyVisibleItemsAreBuiltAndMeasured()
  testPostLayoutHeightUpdatesCacheAndScrollAnchor()
  testUpwardEntryHeightChangeAnchorsFollowingItem()
  testCachedHeightsSurviveAndGuideFollowingFrame()
  testWheelScrollContinuesWithMomentum()
  testThumbDragUsesMouseDelta()
  testPartiallyVisibleHeightChangeDoesNotAdjustScrollOffset()

when isMainModule:
  runTests()