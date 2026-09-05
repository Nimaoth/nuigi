import nuigi, nuigi/widgets/windows, nuigi/core/vecmath

{.passL: "-Lbuild".}

when defined(nimony):
  import std/assertions

proc require(cond: bool, msg: string) =
  when defined(nimony):
    assert cond, msg
  else:
    doAssert(cond, msg)

proc buildWindowFrame(b: var UiBuilder, input = default(UiInputSnapshot)) =
  discard b.beginUiFrame(800.0'f32, 600.0'f32, input)
  b.windowSpace()
  b.window("First", 0.0'f32, 0.0'f32, 200.0'f32, 200.0'f32):
    discard
  b.window("Second", 300.0'f32, 0.0'f32, 200.0'f32, 200.0'f32):
    discard
  b.endUiFrame(buildRenderCommands = false)

proc windowOrder(b: UiBuilder): seq[UiNodeId] =
  let windowSpaceIndex = b.currentNodeIndex(b.windows)
  if windowSpaceIndex < 0:
    return @[]
  result = @[]
  for childIndex in b.children(windowSpaceIndex):
    result.add b.frame.nodes[childIndex].id

proc windowSpaceStorage(b: var UiBuilder): nil WindowSpaceStorage =
  let windowSpaceIndex = b.currentNodeIndex(b.windows)
  if windowSpaceIndex < 0:
    return nil
  let stored = b.nodeStorageGet(b.frame.nodes[windowSpaceIndex].addr)
  if stored != nil and stored of WindowSpaceStorage:
    return cast[WindowSpaceStorage](stored)
  nil

proc windowStorage(b: var UiBuilder, windowId: UiNodeId): nil WindowStorage =
  let windowIndex = b.currentNodeIndex(windowId)
  if windowIndex < 0:
    return nil
  let stored = b.nodeStorageGet(b.frame.nodes[windowIndex].addr)
  if stored != nil and stored of WindowStorage:
    return cast[WindowStorage](stored)
  nil

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

proc testPressedWindowMovesToFront() =
  var b = newBuilder(fixedMeasureText)
  b.buildWindowFrame()

  let firstId = "First".hashChars.UiNodeId
  let secondId = "Second".hashChars.UiNodeId
  require(b.windowOrder() == @[firstId, secondId],
    "newer second window should initially be topmost")

  b.buildWindowFrame(UiInputSnapshot(
    frameIndex: 1,
    mouse: vec2(50.0'f32, 50.0'f32),
    mouseDown: {MouseLeft},
    mousePressed: {MouseLeft},
  ))

  require(b.windowOrder() == @[secondId, firstId],
    "pressing the first window should move it to the top")
  let storage = b.windowSpaceStorage()
  require(storage != nil, "window space should persist activation data in node storage")
  if storage != nil:
    require(storage.windows.len == 2, "window space should track both windows")
    require(storage.windows[0].lastActive > storage.windows[1].lastActive,
      "pressed window should have the newest activation value")

proc testTitleBarMatchesWindowTopCornerRadii() =
  var b = newBuilder(fixedMeasureText)
  b.buildWindowFrame()
  let firstIndex = b.currentNodeIndex("First".hashChars.UiNodeId)
  require(firstIndex >= 0, "first window should exist")
  let titleBarIndex = b.firstChildIndex(firstIndex)
  require(titleBarIndex >= 0, "window should have a title bar")

  let windowRadii = b.nodeStyle(firstIndex)[].resolvedCornerRadii
  let titleRadii = b.nodeStyle(titleBarIndex)[].resolvedCornerRadii
  require(titleRadii.topLeft == windowRadii.topLeft and
      titleRadii.topRight == windowRadii.topRight,
    "title bar top radii should match the window")
  require(titleRadii.bottomRight == 0.0'f32 and titleRadii.bottomLeft == 0.0'f32,
    "title bar bottom radii should remain square")

proc testWindowResizesFromBottomRightCorner() =
  var b = newBuilder(fixedMeasureText)
  b.buildWindowFrame()
  let firstId = "First".hashChars.UiNodeId

  b.buildWindowFrame(UiInputSnapshot(
    frameIndex: 1,
    mouse: vec2(199.0'f32, 199.0'f32),
    mouseDown: {MouseLeft},
    mousePressed: {MouseLeft},
  ))
  let storage = b.windowStorage(firstId)
  require(storage != nil, "first window should have persistent storage")
  if storage != nil:
    require(storage.resizeEdges == {ResizeRight, ResizeBottom},
    "pressing near the bottom-right corner should capture both edges")

  b.buildWindowFrame(UiInputSnapshot(
    frameIndex: 2,
    mouse: vec2(219.0'f32, 214.0'f32),
    mouseDelta: vec2(20.0'f32, 15.0'f32),
    mouseDown: {MouseLeft},
  ))

  if storage != nil:
    require(storage.pos == vec2(0.0'f32),
      "bottom-right resizing should not move the window origin")
    require(storage.size == vec2(220.0'f32, 215.0'f32),
      "bottom-right resizing should apply mouse delta to both dimensions")
  let firstIndex = b.currentNodeIndex(firstId)
  require(firstIndex >= 0, "first window should exist after resizing")
  let style = b.nodeStyle(firstIndex)
  let widths = style[].resolvedBorderWidths
  let colors = style[].resolvedBorderColors
  let highlightColor = rgba(1.0'f32, 0.86'f32, 0.16'f32, 1.0'f32)
  require(widths.right == 2.0'f32 and widths.bottom == 2.0'f32,
    "an active corner resize should thicken both highlighted borders")
  require(colors.right == highlightColor and colors.bottom == highlightColor,
    "an active corner resize should color both highlighted borders yellow")

when isMainModule:
  testPressedWindowMovesToFront()
  # testTitleBarMatchesWindowTopCornerRadii()
  # testWindowResizesFromBottomRightCorner()