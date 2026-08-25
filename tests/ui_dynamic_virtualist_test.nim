import nui, nui_dynamic_virtualist, mymath

{.passL: "-Lbuild".}

when defined(nimony):
  import std/assertions

type TestListContext = object
  builtIndices: seq[int]
  changedItemIndex: int
  changedItemHeight: float32
  itemThreeId: UiNodeId

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

proc buildFrame(b: var UiBuilder, context: var TestListContext,
    input = default(UiInputSnapshot)) =
  context.builtIndices.setLen(0)
  discard b.beginUiFrame(200.0'f32, 100.0'f32, input)
  b.dynamicVirtualList(100, 30.0'f32,
    buildVariableHeightItem, cast[int](context.addr))
  b.endUiFrame(buildRenderCommands = false)

proc dynamicListStorage(b: var UiBuilder): UiDynamicVirtualListStorage =
  for i in 0 ..< b.nodes.len:
    let storage = b.nodeStorageGet(b.nodes[i].addr)
    if storage != nil and storage of UiDynamicVirtualListStorage:
      return cast[UiDynamicVirtualListStorage](storage)
  return nil

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
  b.nodes[thumbIndex].id

proc testOnlyVisibleItemsAreBuiltAndMeasured() =
  var b = newBuilder()
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
  var b = newBuilder()
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
  var b = newBuilder()
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
  require(offsetAfterWheel == 10.0, "wheel input should preserve the initial scroll distance")

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
  var b = newBuilder()
  var context = TestListContext(changedItemIndex: -1)
  b.buildFrame(context)

  let thumbId = b.dynamicListThumbId()
  require(thumbId != noneNodeId(), "dynamic list should build a scrollbar thumb")
  b.previousOutput.heldId = thumbId
  let storage = b.dynamicListStorage()
  storage.scrollOffsetY = 100.0'f32

  b.buildFrame(context, UiInputSnapshot(
    frameIndex: 1,
    mouse: vec2(199.0'f32, 90.0'f32),
    mouseDelta: vec2(0.0'f32, 4.0'f32),
    mouseDown: {MouseLeft},
  ))

  # Estimated range is 2920 and thumb travel is 80, so 4 px moves 146 list pixels.
  require(abs(storage.scrollOffsetY - 246.0'f32) < 0.001,
    "thumb dragging should apply mouse delta without jumping to the pointer position")

proc testHeightChangeAboveViewportAdjustsScrollOffset() =
  var b = newBuilder()
  var context = TestListContext(changedItemIndex: -1)
  b.buildFrame(context)

  let storage = b.dynamicListStorage()
  storage.scrollOffsetY = 80.0'f32
  b.buildFrame(context)
  context.changedItemIndex = 2
  context.changedItemHeight = 40.0'f32
  b.buildFrame(context)

  require(abs(storage.scrollOffsetY - 100.0'f32) < 0.001,
    "height changes above the viewport should adjust the stored scroll offset")
  let itemThreeIndex = b.currentNodeIndex(context.itemThreeId)
  require(itemThreeIndex >= 0, "expected the item after the resized row to be rendered")
  require(abs(b.nodes[itemThreeIndex].pos.y - 10.0'f32) < 0.001,
    "the item after a resized row should remain at the same screen position")

proc runTests() =
  testOnlyVisibleItemsAreBuiltAndMeasured()
  testCachedHeightsSurviveAndGuideFollowingFrame()
  testWheelScrollContinuesWithMomentum()
  testThumbDragUsesMouseDelta()
  testHeightChangeAboveViewportAdjustsScrollOffset()

when isMainModule:
  runTests()