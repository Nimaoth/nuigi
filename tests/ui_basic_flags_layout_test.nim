import std/os
when defined(nimony):
  import std/dirs
import nuigi, widgets, flex, grid, mymath, arena, array_view, widgets/tree_table, widgets/file_system_cursor

include compat2

{.passL: "-Lbuild".}

when defined(nimony):
  import std/assertions

proc approxEq(a, b: float32, eps = 0.001'f32): bool =
  abs(a - b) <= eps

proc require(cond: bool, msg: string) =
  when defined(nimony):
    assert cond, msg
  else:
    doAssert(cond, msg)

proc createTestDir(directory: string) =
  when defined(nimony):
    onRaiseQuit(createDir(path(directory)))
  else:
    createDir(directory)

proc removeTestDir(directory: string) =
  when defined(nimony):
    try:
      for kind, entryPath in walkDir(path(directory)):
        if kind == pcDir or kind == pcLinkToDir:
          removeTestDir($entryPath)
        else:
          removeFile(entryPath)
      removeDir(path(directory))
    except:
      quit "FAILURE: removeTestDir(" & directory & ")"
  else:
    removeDir(directory)

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

proc newTestBuilder(viewW = 200.0'f32, viewH = 120.0'f32): UiBuilder =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(viewW, viewH)
  b

var dragUiCallbackCalls = 0
var dragUiCallbackUserData: nil UiDragUserData = nil
var dragUiCallbackCanDrop = false

proc buildTestDragUi(b: var UiBuilder, userData: UiDragUserData, canDrop: bool) {.nimcall.} =
  inc dragUiCallbackCalls
  dragUiCallbackUserData = userData
  dragUiCallbackCanDrop = canDrop
  b.node:
    discard b.fit().text("drag")

# --- property editor test scaffolding ---------------------------------------

# A deterministic tree cursor: every non-leaf node has `childrenPerNode`
# children, down to `maxDepth` levels. Used to verify the property editor
# renders the expected property name labels for a known tree shape.
type
  TestTreeCursor* = ref object of TreeCursor
    maxDepth*: int
    childrenPerNode*: int

proc treeName(path: seq[int]): string =
  if path.len == 0:
    return "root"
  result = "n"
  for p in path:
    result.add("_")
    result.add($p)

method clone*(c: TestTreeCursor): TreeCursor =
  let r = TestTreeCursor()
  r.fieldName = c.fieldName
  r.index = c.index
  r.path = c.path
  r.maxDepth = c.maxDepth
  r.childrenPerNode = c.childrenPerNode
  return r

method childCount*(c: TestTreeCursor): int =
  if c.path.len < c.maxDepth:
    return c.childrenPerNode
  return 0

method enterChild*(c: TestTreeCursor): bool =
  if c.path.len >= c.maxDepth:
    return false
  c.path.add(0)
  c.index = 0
  c.fieldName = treeName(c.path)
  return true

method moveNext*(c: TestTreeCursor, count: int = 1): bool =
  if c.path.len == 0:
    return false
  # Advance among siblings: the parent's child count, not this node's own.
  let parentChildCount = if (c.path.len - 1) < c.maxDepth: c.childrenPerNode else: 0
  if c.index + count < parentChildCount:
    c.index += count
    c.path[c.path.high] = c.index
    c.fieldName = treeName(c.path)
    return true
  return false

method exitChild*(c: TestTreeCursor): bool =
  if c.path.len == 0:
    return false
  c.path.setLen(c.path.len - 1)
  c.index = if c.path.len > 0: c.path[^1] else: 0
  c.fieldName = treeName(c.path)
  return true

proc newTreeCursor*(maxDepth, childrenPerNode: int): TestTreeCursor =
  result = TestTreeCursor(maxDepth: maxDepth, childrenPerNode: childrenPerNode)
  result.path = @[]
  result.index = 0
  result.fieldName = treeName(result.path)

proc expectedTreeNamesRec(result: var seq[string], prefix: seq[int], depth, maxDepth, childrenPerNode: int) =
  if depth > maxDepth:
    return
  for i in 0 ..< childrenPerNode:
    var p = newSeqOfCap[int](prefix.len + 1)
    for value in prefix:
      p.add(value)
    p.add(i)
    var name = "n"
    for x in p:
      name.add("_")
      name.add($x)
    result.add(name)
    expectedTreeNamesRec(result, p, depth + 1, maxDepth, childrenPerNode)

proc expectedTreeNames(maxDepth, childrenPerNode: int): seq[string] =
  result = @[]
  result.add("root")
  expectedTreeNamesRec(result, @[], 1, maxDepth, childrenPerNode)

proc testFlagsAndMutators() =
  var b = newTestBuilder()

  discard b.text("abc")
  discard b.fillBackground()
  discard b.backgroundColor(rgba(0.2, 0.3, 0.4, 1.0))
  discard b.textColor(rgba(0.9, 0.8, 0.7, 1.0))

  let n = b.nodes[0]
  require(FillBackground in n.flags, "FillBackground flag missing")
  require(DrawText in n.flags, "DrawText flag missing")
  require(b.frame.texts[n.textIndex - 1].text.value == "abc", "text mutator mismatch")
  require(approxEq(b.frame.styles[n.styleIndex - 1].fillColor.r, 0.2'f32), "fillColor.r mismatch")
  require(approxEq(b.frame.texts[n.textIndex - 1].textColor.g, 0.8'f32), "textColor.g mismatch")

proc testTextWrappingUsesNodeWidthOnlyWhenEnabled() =
  var b = newTestBuilder()

  let unwrappedIdx = b.nodes.len
  b.node:
    discard b.width(30.0'f32).fitY().text("abcdefghij")

  let wrappedIdx = b.nodes.len
  b.node:
    discard b.width(30.0'f32).fitY().wrapText().text("abcdefghij")

  require(approxEq(b.nodes[unwrappedIdx].size.y, 20.0'f32), "unwrapped text should use an unlimited arrangement width")
  require(approxEq(b.nodes[wrappedIdx].size.y, 80.0'f32), "wrapped text should use the node content width")

proc testPositionAndSizeScalars() =
  var b = newTestBuilder()

  let idx = b.nodes.len
  b.node:
    discard b.position(12.0'f32, 34.0'f32)
    discard b.size(56.0'f32, 78.0'f32)
  discard b.postProcessChildren(0)

  let n = b.nodes[idx]
  require(approxEq(n.pos.x, 12.0), "position.x mismatch")
  require(approxEq(n.pos.y, 34.0), "position.y mismatch")
  require(approxEq(n.size.x, 56.0), "size.x mismatch")
  require(approxEq(n.size.y, 78.0), "size.y mismatch")

proc testVerticalLayoutTextSizing() =
  var b = newTestBuilder(200.0, 120.0)

  discard b.layout(LayoutVertical).padding(5.0).gap(3.0)

  let firstIdx = b.nodes.len
  b.node:
    discard b.fitX().fitY()
    discard b.text("abcd")

  let secondIdx = b.nodes.len
  b.node:
    discard b.size(10.0, 20.0)
    discard b.fillX()
  discard b.postProcessChildren(0)

  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]

  # fixedMeasureText: 4 chars => 40x20
  require(approxEq(first.size.x, 40.0), "vertical first size.x mismatch")
  require(approxEq(first.size.y, 20.0), "vertical first size.y mismatch")
  require(approxEq(first.pos.x, 0.0), "vertical first pos.x mismatch")
  require(approxEq(first.pos.y, 0.0), "vertical first pos.y mismatch")

  require(approxEq(second.size.x, 190.0), "vertical second size.x mismatch") # root width 200 - padding*2
  require(approxEq(second.size.y, 20.0), "vertical second size.y mismatch")
  require(approxEq(second.pos.x, 0.0), "vertical second pos.x mismatch")
  require(approxEq(second.pos.y, 23.0), "vertical second pos.y mismatch") # 20 + 3

proc testHorizontalLayoutTextSizing() =
  var b = newTestBuilder(300.0, 90.0)

  discard b.layout(LayoutHorizontal).padding(4.0).gap(2.0)

  let firstIdx = b.nodes.len
  b.node:
    discard b.size(30.0, 1.0)
    discard b.fillY()

  let secondIdx = b.nodes.len
  b.node:
    discard b.fitX().fitY()
    discard b.text("xy")
  discard b.postProcessChildren(0)

  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]

  require(approxEq(first.pos.x, 0.0), "horizontal first pos.x mismatch")
  require(approxEq(first.pos.y, 0.0), "horizontal first pos.y mismatch")
  require(approxEq(first.size.x, 30.0), "horizontal first size.x mismatch")
  require(approxEq(first.size.y, 82.0), "horizontal first size.y mismatch") # root height 90 - padding*2

  require(approxEq(second.pos.x, 32.0), "horizontal second pos.x mismatch") # 30 + 2
  require(approxEq(second.pos.y, 0.0), "horizontal second pos.y mismatch")
  require(approxEq(second.size.x, 20.0), "horizontal second size.x mismatch") # 2 chars * 10
  require(approxEq(second.size.y, 20.0), "horizontal second size.y mismatch")

proc testAlignCenterVerticalCrossAxis() =
  var b = newTestBuilder(200.0, 120.0)
  var idx = -1

  b.node:
    discard b.fillX().fillY()
    discard b.layout(LayoutVertical)

    idx = b.nodes.len
    b.node:
      discard b.alignCenter()
      discard b.size(40.0, 10.0)
  discard b.postProcessChildren(0)

  let n = b.nodes[idx]
  require(approxEq(n.pos.x, 80.0), "vertical AlignCenter should center child on X")
  require(approxEq(n.pos.y, 0.0), "vertical AlignCenter should not move child on Y")

proc testAlignCenterHorizontalCrossAxis() =
  var b = newTestBuilder(300.0, 90.0)
  var idx = -1

  b.node:
    discard b.fillX().fillY()
    discard b.layout(LayoutHorizontal)

    idx = b.nodes.len
    b.node:
      discard b.alignCenter()
      discard b.size(20.0, 10.0)
  discard b.postProcessChildren(0)

  let n = b.nodes[idx]
  require(approxEq(n.pos.x, 0.0), "horizontal AlignCenter should not move child on X")
  require(approxEq(n.pos.y, 40.0), "horizontal AlignCenter should center child on Y")

proc testAlignCenterWithoutLayout() =
  var b = newTestBuilder(200.0, 120.0)

  let idx = b.nodes.len
  b.node:
    discard b.alignCenter()
    discard b.size(40.0, 10.0)
  discard b.postProcessChildren(0)

  b.endUiFrame()

  let n = b.nodes[idx]
  require(approxEq(n.pos.x, 80.0), "layout-none AlignCenter should center child on X")
  require(approxEq(n.pos.y, 55.0), "layout-none AlignCenter should center child on Y")

proc testStandaloneFitOnEndNode() =
  var b = newTestBuilder(200.0, 120.0)

  let idx = b.nodes.len
  b.node:
    discard b.padding(3.0)
    discard b.fitX().fitY()
    discard b.text("abc")
  discard b.postProcessChildren(0)

  let n = b.nodes[idx]
  # fixedMeasureText: 3 chars => 30x20, plus padding 3 on each side.
  require(approxEq(n.size.x, 36.0), "standalone size-to-content width mismatch")
  require(approxEq(n.size.y, 26.0), "standalone size-to-content height mismatch")

proc testParentFitIncludesChildren() =
  var b = newTestBuilder(200.0, 120.0)

  let parentIdx = b.nodes.len
  b.node:
    discard b.padding(2.0)
    discard b.fitX().fitY()
    b.node:
      discard b.fitX().fitY()
      discard b.text("abcd")
      discard b.position(5.0, 7.0)
  discard b.postProcessChildren(0)

  let parent = b.nodes[parentIdx]
  # Child intrinsic is 40x20 (4 chars * 10 x 20), positioned at (5,7), plus parent leading/trailing padding.
  require(approxEq(parent.size.x, 49.0), "parent size-to-content width should include child extent")
  require(approxEq(parent.size.y, 31.0), "parent size-to-content height should include child extent")

proc testParentFitIgnoresFlaggedChildExtent() =
  var b = newTestBuilder(200.0, 120.0)

  let parentIdx = b.nodes.len
  var overlayIdx = -1
  b.node:
    discard b.fitX().fitY()
    b.node:
      discard b.size(20.0, 30.0)
    overlayIdx = b.nodes.len
    b.node:
      discard b.size(80.0, 90.0).ignoreInContentExtent()
      discard b.anchors(0.0, 0.0, 1.0, 0.0)
        .offsets(0.0, -10.0, 0.0, 10.0)
        .finishAnchors()
  discard b.postProcessChildren(0)

  require(IgnoreInContentExtent in b.nodes[overlayIdx].flags,
    "ignoreInContentExtent should set the node flag")
  require(approxEq(b.nodes[parentIdx].size.x, 20.0),
    "flagged overlay should not affect fitted parent width")
  require(approxEq(b.nodes[parentIdx].size.y, 30.0),
    "flagged overlay should not affect fitted parent height")

proc testParentFitIncludesChildren2() =
  var b = newTestBuilder(200.0, 120.0)

  let parentIdx = b.nodes.len
  b.node: # 1
    discard b.fillX().fitY()

    b.node: # 2
      discard b.padding(50).gap(6)
      discard b.fillX().fitY()
      discard b.layout(LayoutHorizontal)

      b.node: # 3
        discard b.fitX().fitY()
        discard b.text("abc")

      b.node: # 4
        discard b.size(80, 50)

      b.node: # 5
        discard b.fitX().fitY()
        discard b.text("abc")
  discard b.postProcessChildren(0)

  let parent = b.nodes[parentIdx]
  require(approxEq(parent.size.x, 200.0), "parent size-to-content width should include child extent")
  require(approxEq(parent.size.y, 50.0'f32 * 2.0'f32 + 50.0'f32), "parent size-to-content height should include child extent")

proc testHorizontalFitYWithNestedFillYPropagation() =
  var b = newTestBuilder(300.0, 160.0)

  var firstIdx = -1
  var firstChildIdx = -1
  var secondIdx = -1

  b.node:
    discard b.layout(LayoutHorizontal)
    discard b.fitY()
    discard b.gap(0.0)

    firstIdx = b.nodes.len
    b.node:
      discard b.fillY().fitX()

      firstChildIdx = b.nodes.len
      b.node:
        discard b.size(30.0, 0.0)
        discard b.fillY()

    secondIdx = b.nodes.len
    b.node:
      discard b.size(40.0, 50.0)
  discard b.postProcessChildren(0)

  let first = b.nodes[firstIdx]
  let firstChild = b.nodes[firstChildIdx]
  let second = b.nodes[secondIdx]

  require(approxEq(second.size.y, 50.0), "setup failed: second child fixed height mismatch")
  require(approxEq(first.size.y, second.size.y), "first child should match second child height after FitY post-process")
  require(approxEq(firstChild.size.y, second.size.y), "nested FillY child should recursively match propagated height")

proc testImmediateFillXAndFillY() =
  var b = newTestBuilder(220.0, 140.0)

  b.node:
    discard b.padding(10.0)
    discard b.size(100.0, 80.0)
    let childIdx = b.nodes.len
    b.node:
      discard b.size(1.0, 1.0)
      discard b.fillX().fillY()

    let child = b.nodes[childIdx]
    require(approxEq(child.size.x, 80.0), "fillX should resolve immediately from parent content width")
    require(approxEq(child.size.y, 60.0), "fillY should resolve immediately from parent content height")

proc testImmediateFillRespectsChildPosition() =
  var b = newTestBuilder(220.0, 140.0)

  b.node:
    discard b.size(100.0, 80.0)
    let childIdx = b.nodes.len
    b.node:
      discard b.size(1.0, 1.0)
      discard b.position(10.0, 15.0)
      discard b.fillX().fillY()

    let child = b.nodes[childIdx]
    require(approxEq(child.size.x, 90.0), "fillX should use remaining width after child x position")
    require(approxEq(child.size.y, 65.0), "fillY should use remaining height after child y position")

proc testPostProcessFillRespectsChildPosition() =
  var b = newTestBuilder(220.0, 140.0)

  b.node:
    discard b.size(100.0, 80.0)

    let fillChildIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 1.0)
      discard b.position(5.0, 12.0)
      discard b.fillY()

    # This sibling marks the parent for child post-processing.
    b.node:
      discard b.size(10.0, 10.0)
      discard b.alignCenter()

    let fillChild = b.nodes[fillChildIdx]
    require(approxEq(fillChild.size.y, 68.0), "post-process FillY should use remaining height after child y position")

proc testPostProcessFillPropagatesKnownParentAxes() =
  var b = newTestBuilder(220.0, 140.0)
  var parentIdx = -1
  var childIdx = -1

  b.node:
    parentIdx = b.nodes.len
    b.node:
      discard b.width(100.0'f32)
      childIdx = b.nodes.len
      b.node:
        discard b.fillX().fillY()

      b.node:
        discard b.alignCenter()

  discard b.postProcessChildren(parentIdx)
  let child = b.nodes[childIdx]
  require(SizeXKnown in child.flags, "post-process FillX should inherit a known parent width")
  require(SizeYKnown notin child.flags, "post-process FillY should remain unknown when the parent height is unknown")

proc testReverseVerticalFillXUsesContentWidth() =
  var b = newTestBuilder(220.0, 140.0)

  b.node:
    discard b.size(100.0, 80.0)
    discard b.layout(LayoutVertical)
    discard b.reverseLayout()

    let childIdx = b.nodes.len
    b.node:
      discard b.size(1.0, 10.0)
      discard b.fillX()

    let child = b.nodes[childIdx]
    require(approxEq(child.size.x, 100.0), "reverse vertical FillX should use full parent content width")

proc testMinMaxSizeClamping() =
  var b = newTestBuilder()

  let idx = b.nodes.len
  b.node:
    discard b.fitX().fitY()
    discard b.text("abcdefghij") # fixedMeasureText => 100 x 20
    discard b.minSize(120.0, 30.0)
    discard b.maxSize(90.0, 25.0)
  discard b.postProcessChildren(0)

  let n = b.nodes[idx]
  require(approxEq(n.size.x, 120.0), "width should clamp to effective min when max < min")
  require(approxEq(n.size.y, 30.0), "height should clamp to effective min when max < min")

proc testPaddingOffsetsChildWithoutLayout() =
  ## Parent padding should offset child placement during traversal/render command generation,
  ## while child.pos remains in parent content-space.
  var b = newTestBuilder(200.0, 120.0)

  var childIdx = -1
  b.node:
    discard b.padding(12.0)
    childIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 8.0)
      discard b.fillBackground()
      discard b.backgroundColor(rgba(0.4, 0.5, 0.6, 1.0))

  let child = b.nodes[childIdx]
  require(approxEq(child.pos.x, 0.0), "child pos.x should remain content-relative")
  require(approxEq(child.pos.y, 0.0), "child pos.y should remain content-relative")

  b.endUiFrame()
  var found = false
  for cmd in b.frameOutput.commands:
    if cmd.nodeIndex == childIdx and cmd.kind == CmdRectFill:
      found = true
      require(approxEq(cmd.pos.x, 12.0), "rendered child x should include parent padding")
      require(approxEq(cmd.pos.y, 12.0), "rendered child y should include parent padding")
  require(found, "expected a fill command for child node")

proc testCustomRenderCommandsInjection() =
  var b = newTestBuilder(220.0, 140.0)

  var custom = [
    UiRenderCommand(
      kind: CmdLine,
      nodeIndex: -1,
      pos: vec2(2.0'f32, 3.0'f32),
      size: vec2(11.0'f32, 7.0'f32),
      color: rgba(0.8, 0.2, 0.1, 1.0),
    ),
    UiRenderCommand(
      kind: CmdCircleFill,
      nodeIndex: 0,
      pos: vec2(9.0'f32, 5.0'f32),
      radius: 4.0'f32,
      color: rgba(0.2, 0.7, 0.4, 1.0),
    ),
  ]

  var customNodeIdx = -1
  b.node("custom-cmd-node"):
    customNodeIdx = b.stack[^1]
    discard b.customRenderCommands(custom)

  b.endUiFrame()

  var sawLine = false
  var sawCircle = false
  for cmd in b.frameOutput.commands:
    if cmd.kind == CmdLine:
      sawLine = true
      require(cmd.nodeIndex == customNodeIdx, "custom command without node index should inherit current node index")
      require(approxEq(cmd.pos.x, 2.0'f32), "custom line command x mismatch")
    if cmd.kind == CmdCircleFill:
      sawCircle = true
      require(cmd.nodeIndex == 0, "custom command with explicit node index should be preserved")

  require(sawLine, "expected custom line command in frame output")
  require(sawCircle, "expected custom circle command in frame output")

proc testCustomRenderCommandsSupportsTwoFrameLifetime() =
  var b = newBuilder(fixedMeasureText)
  var custom = [
    UiRenderCommand(
      kind: CmdLine,
      nodeIndex: -1,
      pos: vec2(1.0'f32, 1.0'f32),
      size: vec2(5.0'f32, 5.0'f32),
      color: rgba(0.1, 0.2, 0.3, 1.0),
    ),
  ]

  discard b.beginUiFrame(220.0, 140.0)
  b.node("persist-custom"):
    discard b.customRenderCommands(custom)
  b.endUiFrame()

  custom[0].pos = vec2(23.0'f32, 19.0'f32)

  discard b.beginUiFrame(220.0, 140.0)
  b.node("persist-custom"):
    discard b.customRenderCommands(custom)
  b.endUiFrame()

  var sawUpdated = false
  for cmd in b.frameOutput.commands:
    if cmd.kind == CmdLine:
      sawUpdated = true
      require(approxEq(cmd.pos.x, 23.0'f32), "second-frame custom command should read external storage")
      require(approxEq(cmd.pos.y, 19.0'f32), "second-frame custom command should read external storage")
      break

  require(sawUpdated, "expected custom line command in second frame output")

proc testArenaResizeArrayView() =
  var a = initArena(256)
  var cmds = a.allocEmptyArray(2, UiRenderCommand)

  cmds.add UiRenderCommand(kind: CmdRectFill, pos: vec2(1.0'f32, 2.0'f32), size: vec2(3.0'f32, 4.0'f32))
  require(cmds.len == 1, "setup failed: expected one command")
  require(cmds.cap == 2, "setup failed: expected initial capacity 2")

  a.resize(cmds, 4)
  require(cmds.cap == 4, "resize should grow capacity")
  require(cmds.len == 1, "resize should preserve logical length when growing")
  require(approxEq(cmds[0].pos.x, 1.0'f32), "resize should preserve existing command data")

  cmds.add UiRenderCommand(kind: CmdRectFill, pos: vec2(5.0'f32, 6.0'f32), size: vec2(1.0'f32, 1.0'f32))
  cmds.add UiRenderCommand(kind: CmdRectFill, pos: vec2(7.0'f32, 8.0'f32), size: vec2(1.0'f32, 1.0'f32))
  require(cmds.len == 3, "expected three commands after appends")

  a.resize(cmds, 2)
  require(cmds.cap == 2, "resize should shrink capacity")
  require(cmds.len == 2, "resize should clamp logical length when shrinking")
  require(approxEq(cmds[1].pos.x, 5.0'f32), "shrink should preserve prefix data")

proc testStableExplicitIdsAcrossFrames() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(200.0, 120.0)
  let a1Idx = b.nodes.len
  b.node("animated-A"):
    discard
  let idA1 = b.nodes[a1Idx].id

  let b1Idx = b.nodes.len
  b.node("animated-B"):
    discard
  let idB1 = b.nodes[b1Idx].id

  discard b.beginUiFrame(200.0, 120.0)
  # Insert an unrelated auto-id node before explicit IDs.
  b.node:
    discard

  let a2Idx = b.nodes.len
  b.node("animated-A"):
    discard
  let idA2 = b.nodes[a2Idx].id

  let b2Idx = b.nodes.len
  b.node("animated-B"):
    discard
  let idB2 = b.nodes[b2Idx].id

  require(idA1 == idA2, "explicit node id A must remain stable")
  require(idB1 == idB2, "explicit node id B must remain stable")
  require(not (idA1 == idB1), "different explicit keys must generate different ids")

proc testPushPopIdScopes() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(240.0, 120.0)
  discard b.pushId("left-column")
  let left1Idx = b.nodes.len
  b.node("button"):
    discard
  let left1 = b.nodes[left1Idx].id
  discard b.popId()

  discard b.pushId("right-column")
  let right1Idx = b.nodes.len
  b.node("button"):
    discard
  let right1 = b.nodes[right1Idx].id
  discard b.popId()

  discard b.beginUiFrame(240.0, 120.0)
  discard b.pushId("left-column")
  let left2Idx = b.nodes.len
  b.node("button"):
    discard
  let left2 = b.nodes[left2Idx].id
  discard b.popId()

  discard b.pushId("right-column")
  let right2Idx = b.nodes.len
  b.node("button"):
    discard
  let right2 = b.nodes[right2Idx].id
  discard b.popId()

  require(left1 == left2, "left scoped id must remain stable")
  require(right1 == right2, "right scoped id must remain stable")
  require(not (left1 == right1), "same node key in different scopes must not collide")

proc testButtonHoverAndPressed() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(260.0, 120.0)
  let firstIdx = b.nodes.len
  let firstPressed = b.button("Play")
  let firstFill = b.frame.styles[b.nodes[firstIdx].styleIndex - 1].fillColor

  require(not firstPressed, "button should not report pressed without prior click")
  require(approxEq(firstFill.r, 0.22'f32), "button default fill should be non-hover color")

  let pressInput = UiInputSnapshot(
    mouse: vec2(8.0'f32),
    mousePressed: {MouseLeft},
  )
  discard b.beginUiFrame(260.0, 120.0, input = pressInput)
  discard b.button("Play")

  let releaseInput = UiInputSnapshot(
    mouse: vec2(8.0'f32),
    mouseReleased: {MouseLeft},
  )
  discard b.beginUiFrame(260.0, 120.0, input = releaseInput)
  let secondIdx = b.nodes.len
  let secondPressed = b.button("Play")
  let secondFill = b.frame.styles[b.nodes[secondIdx].styleIndex - 1].fillColor

  require(secondPressed, "button should report pressed when previous frame clicked id matches")
  require(secondFill.r > firstFill.r, "button hover fill should animate toward hover color when previously hovered")
  require(secondFill.r < 0.96'f32 + 0.0001'f32, "button hover fill should remain below click highlight color")

proc testSliderClickUpdatesValue() =
  var b = newBuilder(fixedMeasureText)
  var value = 0.0'f32

  discard b.beginUiFrame(300.0, 120.0)
  let sliderIdx = b.nodes.len
  discard b.slider(value, 0.0'f32, 100.0'f32)

  require(b.childCount(sliderIdx) >= 2, "slider should create label and track children")
  let pressInput = UiInputSnapshot(
    mouse: vec2(84, 12),
    mousePressed: {MouseLeft},
  )
  discard b.beginUiFrame(300.0, 120.0, input = pressInput)
  discard b.slider(value, 0.0'f32, 100.0'f32)

  let releaseInput = UiInputSnapshot(
    mouse: vec2(84, 12),
    mouseReleased: {MouseLeft},
  )
  discard b.beginUiFrame(300.0, 120.0, input = releaseInput)
  let changed = b.slider(value, 0.0'f32, 100.0'f32)

  require(changed, "slider should report changed after click on track")
  require(approxEq(value, 50.0'f32), "slider click should map pointer x to range value")

proc testPreviousNodesAndIndicesDoubleBuffered() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(220.0, 120.0)
  let firstIdx = b.nodes.len
  b.node("persisted"):
    discard b.size(20.0, 10.0)
  let firstId = b.nodes[firstIdx].id

  let pressInput = UiInputSnapshot(
    mouse: vec2(5),
    mousePressed: {MouseLeft},
  )
  discard b.beginUiFrame(220.0, 120.0, input = pressInput)
  b.node("persisted"):
    discard b.size(20.0, 10.0)

  let releaseInput = UiInputSnapshot(
    mouse: vec2(5),
    mouseReleased: {MouseLeft},
  )
  discard b.beginUiFrame(220.0, 120.0, input = releaseInput)

  require(b.previousFrame.nodes.len > firstIdx, "previousFrame.nodes should retain prior frame tree after swap")
  require(b.previousOutput.hoveredIndex == firstIdx, "hoveredIndex should point into previousFrame.nodes")
  require(b.previousOutput.clickedIndex == firstIdx, "clickedIndex should point into previousFrame.nodes")
  require(b.previousFrame.nodes[b.previousOutput.hoveredIndex].id == firstId, "hoveredIndex should resolve to previous frame node id")
  require(b.previousFrame.nodes[b.previousOutput.clickedIndex].id == firstId, "clickedIndex should resolve to previous frame node id")

proc testDragUiCallbackAndDropState() =
  var b = newBuilder(fixedMeasureText)
  dragUiCallbackCalls = 0
  dragUiCallbackUserData = nil
  dragUiCallbackCanDrop = false
  let testUserData = UiDragUserData()

  discard b.beginUiFrame(220.0, 120.0, input = UiInputSnapshot(mouse: vec2(30.0'f32, 40.0'f32)))
  b.dragData.nodeId = b.nodes[0].id
  b.setDragData(testUserData)
  b.setDragUiCallback(buildTestDragUi)
  require(not b.endDrop(true), "accepted target should not drop before release")
  require(b.dragData.canDrop, "endDrop should store acceptance while the mouse remains down")
  b.endUiFrame(buildRenderCommands = false)

  require(dragUiCallbackCalls == 1, "endUiFrame should invoke the drag UI callback")
  require(dragUiCallbackUserData == testUserData, "drag UI callback user data mismatch")
  require(dragUiCallbackCanDrop, "drag UI callback should receive current target acceptance")
  require(b.nodes.len == 3, "drag tooltip and callback content should be added to the frame")
  require(b.dragData.nodeId != noneNodeId(), "drag should remain active before release")

  let releaseInput = UiInputSnapshot(
    mouse: vec2(30.0'f32, 40.0'f32),
    mouseReleased: {MouseLeft},
  )
  discard b.beginUiFrame(220.0, 120.0, input = releaseInput)
  require(not b.dragData.canDrop, "drop acceptance should reset at the start of each frame")
  require(not b.endDrop(false), "rejected target should not drop on release")
  b.endUiFrame(buildRenderCommands = false)

  require(dragUiCallbackCalls == 2, "drag UI callback should run on the release frame")
  require(not dragUiCallbackCanDrop, "release-frame callback should receive rejected target state")
  require(b.dragData.nodeId == noneNodeId(), "drag data should clear after release-frame UI is built")
  require(b.dragData.uiCallback == nil, "drag UI callback should clear with released drag data")

proc testFileSystemCursorDragAndDrop() =
  let root = getTempDir() / "nuigi-file-drag-test"
  if dirExists(root):
    removeTestDir(root)
  createTestDir(root)
  try:
    let sourceParentPath = root / "source"
    let sourceFolderPath = sourceParentPath / "folder"
    let sourceChildPath = sourceFolderPath / "child"
    let sourceFilePath = sourceParentPath / "item.txt"
    let targetPath = root / "target"
    let unrelatedPath = root / "unrelated"
    let cachedKindPath = root / "cached-kind"
    createTestDir(sourceParentPath)
    createTestDir(sourceFolderPath)
    createTestDir(sourceChildPath)
    createTestDir(targetPath)
    createTestDir(unrelatedPath)
    createTestDir(cachedKindPath)
    onRaiseQuit(writeFile(sourceFilePath, "drag"))

    let cache = newFileSystemCache()
    require(fileSystemCursor(cachedKindPath, cache).kind == Folder, "initial directory kind should be Folder")
    removeTestDir(cachedKindPath)
    require(fileSystemCursor(cachedKindPath, cache).kind == Folder, "shared cache should serve entry kind without rechecking the filesystem")
    let rootCursor = fileSystemCursor(root, cache)
    let sourceParent = fileSystemCursor(sourceParentPath, cache)
    let sourceFolder = fileSystemCursor(sourceFolderPath, cache)
    let sourceChild = fileSystemCursor(sourceChildPath, cache)
    let sourceFile = fileSystemCursor(sourceFilePath, cache)
    let target = fileSystemCursor(targetPath, cache)
    let unrelated = fileSystemCursor(unrelatedPath, cache)

    require(sourceFolder.kind == Folder, "directory cursor should have Folder kind")
    require(sourceFile.kind == File, "file cursor should have File kind")
    require(FileSystemCursor(sourceFolder.clone()).kind == Folder, "cloned cursor should preserve entry kind")
    require(not sourceFile.canDropOn(sourceFile), "file target should reject a drop")
    require(not sourceFolder.canDropOn(sourceFolder), "folder should not drop onto itself")
    require(not sourceFolder.canDropOn(sourceChild), "folder should not drop onto its child")
    require(not sourceFile.canDropOn(sourceParent), "entry should not drop onto its direct parent")
    require(sourceFolder.canDropOn(target), "sibling folder should accept the dragged folder")

    require(sourceParent.childCount() == 2, "source listing should be cached before the move")
    require(target.childCount() == 0, "target listing should be empty before the move")
    require(unrelated.childCount() == 0, "unrelated listing should be cached before the move")
    onRaiseQuit(writeFile(unrelatedPath / "late.txt", "cached"))

    var sourceNav = FileSystemCursor(rootCursor.clone())
    require(sourceNav.enterChild(), "source folder should be reachable from root")
    var sourceFolderNav = FileSystemCursor(sourceNav.clone())
    require(sourceFolderNav.enterChild(), "dragged folder should be reachable from source")
    let sourceFolderNavPath = sourceFolderNav.fullPath
    var sourceFolderParent = FileSystemCursor(sourceFolderNav.clone())
    require(sourceFolderParent.exitChild(), "cloned child cursor should restore its parent")
    require(sourceFolderParent.fullPath == sourceParentPath,
      "restored filesystem parent should retain its cached full path")
    require(sourceFolderNav.parentPath == sourceParentPath,
      "filesystem child should expose its parent location path")
    require(sourceFolderNav.rootPath == root,
      "filesystem child should derive its original root from its location chain")
    require(sourceFolderParent.fieldName == extractFilename(sourceParentPath),
      "restored filesystem parent should retain its cached name")
    require(sourceFolderNav.fullPath == sourceFolderNavPath,
      "ascending a clone should not mutate the original cursor")
    var targetNav = FileSystemCursor(rootCursor.clone())
    require(targetNav.enterChild() and targetNav.moveNext(), "target folder should be reachable from root")

    var tree = TreeTable(cursor: rootCursor)
    tree.toggleNode(rootCursor)
    tree.toggleNode(sourceNav)
    tree.toggleNode(sourceFolderNav)
    tree.toggleNode(targetNav)

    proc expandedIndex(tree: TreeTable, key: string): int =
      for i in 0 .. tree.nodes.high:
        if tree.nodes[i].cursor != nil and tree.nodes[i].cursor.cursorKey() == key:
          return i
      return -1

    let targetExpandedIndex = expandedIndex(tree, targetPath)
    require(targetExpandedIndex >= 0 and tree.nodes[targetExpandedIndex].childCount == 0,
      "target expansion should begin with a cached zero child count")

    require(sourceFolder.moveTo(target), "eligible folder move should succeed")
    require(dirExists(targetPath / "folder"), "moved folder should exist under target")
    require(not dirExists(sourceFolderPath), "moved folder should leave its source path")
    require(unrelated.childCount() == 0, "moving should not invalidate an unrelated listing")

    tree.refreshRenderedNode(sourceNav)
    require(expandedIndex(tree, sourceFolderPath) < 0, "rendered source should remove its missing expanded child")
    let sourceExpandedIndex = expandedIndex(tree, sourceParentPath)
    require(sourceExpandedIndex >= 0 and tree.nodes[sourceExpandedIndex].childCount == 1,
      "rendered source should refresh its cached child count")
    require(tree.nodes[expandedIndex(tree, targetPath)].childCount == 0,
      "non-rendered target should retain its cached child count")

    tree.refreshRenderedNode(targetNav)
    require(tree.nodes[expandedIndex(tree, targetPath)].childCount == 1,
      "rendered target should refresh its cached child count")

    require(sourceFile.moveTo(target), "eligible file move should succeed")
    require(fileExists(targetPath / "item.txt"), "moved file should exist under target")
    require(not fileExists(sourceFilePath), "moved file should leave its source path")
    require(sourceParent.childCount() == 0, "source cache should refresh after both moves")
    require(target.childCount() == 2, "target cache should refresh after both moves")
  finally:
    if dirExists(root):
      removeTestDir(root)

type
  ReverseChildMode = enum
    ReverseFixed, ReverseContent, ReverseFill

const
  reverseChildModes = [ReverseFixed, ReverseContent, ReverseFill]

proc configureReverseChild(b: var UiBuilder, mode: ReverseChildMode, horizontalAxis: bool, label: string) =
  case mode
  of ReverseFixed:
    if horizontalAxis:
      discard b.size(20.0, 10.0)
    else:
      discard b.size(10.0, 20.0)
  of ReverseContent:
    if horizontalAxis:
      discard b.fitX()
    else:
      discard b.fitY()
    discard b.text(label)
  of ReverseFill:
    if horizontalAxis:
      discard b.size(1.0, 10.0)
      discard b.fillX()
    else:
      discard b.size(10.0, 1.0)
      discard b.fillY()

proc reverseAxisExpectedSize(mode: ReverseChildMode, cursorAtBegin: float32): float32 =
  case mode
  of ReverseFixed, ReverseContent:
    20.0'f32
  of ReverseFill:
    max(0.0'f32, cursorAtBegin)

proc testReverseVerticalLayoutAllCombinations() =
  for firstMode in reverseChildModes:
    for secondMode in reverseChildModes:
      var b = newTestBuilder(240.0, 180.0)

      var firstIdx = -1
      var secondIdx = -1
      b.node:
        discard b.size(100.0, 100.0)
        discard b.layout(LayoutVertical)
        discard b.reverseLayout()

        firstIdx = b.nodes.len
        b.node:
          b.configureReverseChild(firstMode, false, "aa")

        secondIdx = b.nodes.len
        b.node:
          b.configureReverseChild(secondMode, false, "bb")

      discard b.postProcessChildren(firstIdx)

      let first = b.nodes[firstIdx]
      let second = b.nodes[secondIdx]
      let firstSize = reverseAxisExpectedSize(firstMode, 100.0'f32)
      let firstPos = max(0.0'f32, 100.0'f32 - firstSize)
      let secondSize = reverseAxisExpectedSize(secondMode, firstPos)
      let secondPos = max(0.0'f32, firstPos - secondSize)

      require(approxEq(first.size.y, firstSize), "reverse vertical first size.y mismatch")
      require(approxEq(first.pos.y, firstPos), "reverse vertical first pos.y mismatch")
      require(approxEq(second.size.y, secondSize), "reverse vertical second size.y mismatch")
      require(approxEq(second.pos.y, secondPos), "reverse vertical second pos.y mismatch")

proc testReverseHorizontalLayoutAllCombinations() =
  for firstMode in reverseChildModes:
    for secondMode in reverseChildModes:
      var b = newTestBuilder(260.0, 180.0)

      var firstIdx = -1
      var secondIdx = -1
      b.node:
        discard b.size(100.0, 100.0)
        discard b.layout(LayoutHorizontal)
        discard b.reverseLayout()

        firstIdx = b.nodes.len
        b.node:
          b.configureReverseChild(firstMode, true, "aa")

        secondIdx = b.nodes.len
        b.node:
          b.configureReverseChild(secondMode, true, "bb")

      discard b.postProcessChildren(firstIdx)

      let first = b.nodes[firstIdx]
      let second = b.nodes[secondIdx]
      let firstSize = reverseAxisExpectedSize(firstMode, 100.0'f32)
      let firstPos = max(0.0'f32, 100.0'f32 - firstSize)
      let secondSize = reverseAxisExpectedSize(secondMode, firstPos)
      let secondPos = max(0.0'f32, firstPos - secondSize)

      require(approxEq(first.size.x, firstSize), "reverse horizontal first size.x mismatch")
      require(approxEq(first.pos.x, firstPos), "reverse horizontal first pos.x mismatch")
      require(approxEq(second.size.x, secondSize), "reverse horizontal second size.x mismatch")
      require(approxEq(second.pos.x, secondPos), "reverse horizontal second pos.x mismatch")

proc testReverseVerticalParentFitRepositions() =
  var b = newTestBuilder(240.0, 180.0)
  var parentIdx = -1
  var firstIdx = -1
  var secondIdx = -1

  b.node:
    parentIdx = b.nodes.len
    b.node:
      discard b.layout(LayoutVertical)
      discard b.reverseLayout()
      discard b.fitY()

      firstIdx = b.nodes.len
      b.node:
        discard b.fitY()
        discard b.text("aa")

      secondIdx = b.nodes.len
      b.node:
        discard b.size(10.0, 20.0)
  discard b.postProcessChildren(0)
  let parent = b.nodes[parentIdx]
  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]
  require(approxEq(parent.size.y, 40.0), "reverse vertical size-to-content parent height mismatch")
  require(approxEq(first.pos.y, 20.0), "reverse vertical size-to-content first child position mismatch")
  require(approxEq(second.pos.y, 0.0), "reverse vertical size-to-content second child position mismatch")

proc testReverseHorizontalParentFitRepositions() =
  var b = newTestBuilder(260.0, 180.0)
  var parentIdx = -1
  var firstIdx = -1
  var secondIdx = -1

  b.node:
    parentIdx = b.nodes.len
    b.node:
      discard b.layout(LayoutHorizontal)
      discard b.reverseLayout()
      discard b.fitX()

      firstIdx = b.nodes.len
      b.node:
        discard b.fitX()
        discard b.text("aa")

      secondIdx = b.nodes.len
      b.node:
        discard b.size(20.0, 10.0)
  discard b.postProcessChildren(0)

  let parent = b.nodes[parentIdx]
  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]
  require(approxEq(parent.size.x, 40.0), "reverse horizontal size-to-content parent width mismatch")
  require(approxEq(first.pos.x, 20.0), "reverse horizontal size-to-content first child position mismatch")
  require(approxEq(second.pos.x, 0.0), "reverse horizontal size-to-content second child position mismatch")

proc testAnchoredLayoutPivotPositioning() =
  var b = newTestBuilder(200.0, 100.0)

  let childIdx = b.nodes.len
  b.node:
    discard b.size(40.0, 20.0)
    discard b.anchors(0.5, 0.5, 0.5, 0.5)
    discard b.offsets(10.0, -5.0, 10.0, -5.0)
    discard b.pivot(0.5, 0.5)

  b.endUiFrame()

  let child = b.nodes[childIdx]
  require(approxEq(child.size.x, 40.0), "point-anchored child should keep explicit width when anchors are equal")
  require(approxEq(child.size.y, 20.0), "point-anchored child should keep explicit height when anchors are equal")
  require(approxEq(child.pos.x, 90.0), "anchored layout should resolve expected x from anchor/pivot/offset")
  require(approxEq(child.pos.y, 35.0), "anchored layout should resolve expected y from anchor/pivot/offset")

proc testAnchoredLayoutStretchUsesAnchorOffsets() =
  var b = newTestBuilder(200.0, 100.0)

  let childIdx = b.nodes.len
  b.node:
    discard b.size(10.0, 12.0)
    discard b.minSize(0.0, 0.0)
    discard b.maxSize(10000.0, 10000.0)
    discard b.anchors(0.0, 0.0, 1.0, 1.0)
    discard b.offsets(5.0, 7.0, -9.0, -11.0)
    discard b.pivot(0.0, 0.0)

  b.endUiFrame()

  let child = b.nodes[childIdx]
  require(not approxEq(child.size.x, 10.0), "stretched anchored child should override explicit width when anchors differ")
  require(not approxEq(child.size.y, 12.0), "stretched anchored child should override explicit height when anchors differ")
  require(approxEq(child.pos.x, 5.0), "stretched anchored child x should include top-left offset")
  require(approxEq(child.pos.y, 7.0), "stretched anchored child y should include top-left offset")
  require(approxEq(child.size.x, 186.0), "stretched anchored child width should honor right offset")
  require(approxEq(child.size.y, 82.0), "stretched anchored child height should honor bottom offset")

proc testAnchoredLayoutTriggersParentPostProcessForFit() =
  var b = newTestBuilder(240.0, 140.0)

  let parentIdx = b.nodes.len
  b.node:
    discard b.fitX().fitY()

    b.node:
      discard b.size(20.0, 10.0)
      discard b.anchors(0.0, 0.0, 1.0, 1.0)
      discard b.pivot(0.5, 0.5)

  let parent = b.nodes[parentIdx]
  require(PostProcessChildren in parent.flags, "anchored child should mark size-to-content parent for post-processing")

proc testAnchoredLayoutAxisSpecificMutators() =
  var b = newTestBuilder(200.0, 100.0)

  let xOnlyIdx = b.nodes.len
  b.node:
    discard b.size(40.0, 20.0)
    discard b.anchorsX(0.5, 0.5)
    discard b.offsetsX(10.0, 10.0)
    discard b.pivotX(0.5)

  let yOnlyIdx = b.nodes.len
  b.node:
    discard b.size(30.0, 10.0)
    discard b.anchorsY(0.0, 1.0)
    discard b.offsetsY(3.0, -7.0)
    discard b.pivotY(0.0)

  b.endUiFrame()

  let xOnly = b.nodes[xOnlyIdx]
  require(AnchorX in xOnly.flags, "anchorsX should set AnchorX flag")
  require(not (AnchorY in xOnly.flags), "anchorsX should not set AnchorY flag")
  require(approxEq(xOnly.pos.x, 90.0), "x-only anchoring should resolve x")
  require(approxEq(xOnly.pos.y, 0.0), "x-only anchoring should not change y")
  require(approxEq(xOnly.size.x, 40.0), "x-only point anchors should keep explicit width")
  require(approxEq(xOnly.size.y, 20.0), "x-only anchoring should not change height")

  let yOnly = b.nodes[yOnlyIdx]
  require(AnchorY in yOnly.flags, "anchorsY should set AnchorY flag")
  require(not (AnchorX in yOnly.flags), "anchorsY should not set AnchorX flag")
  require(approxEq(yOnly.pos.x, 0.0), "y-only anchoring should not change x")
  require(approxEq(yOnly.pos.y, 3.0), "y-only anchoring should resolve y")
  require(approxEq(yOnly.size.x, 30.0), "y-only anchoring should not change width")
  require(approxEq(yOnly.size.y, 90.0), "y-only stretch anchors should override explicit height")

proc testFlexHorizontalGrowDistribution() =
  var b = newTestBuilder(260.0, 120.0)

  var firstIdx = -1
  var secondIdx = -1
  var thirdIdx = -1
  b.node:
    discard b.size(200.0, 80.0)
    discard b.layout(LayoutHorizontal)
    discard b.flexLayout()
    discard b.gap(10.0)

    firstIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 20.0)
      discard b.flex(1.0, 1.0, 50.0)

    secondIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 20.0)
      discard b.flex(1.0, 1.0, 50.0)

    thirdIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 20.0)
      discard b.flex(1.0, 1.0, 50.0)
  discard b.postProcessChildren(0)

  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]
  let third = b.nodes[thirdIdx]

  require(approxEq(first.size.x, 60.0), "flex grow should distribute extra main-axis space")
  require(approxEq(second.size.x, 60.0), "flex grow should distribute extra main-axis space equally")
  require(approxEq(third.size.x, 60.0), "flex grow should distribute extra main-axis space equally")
  require(approxEq(first.pos.x, 0.0), "first flex child x mismatch")
  require(approxEq(second.pos.x, 70.0), "second flex child x mismatch")
  require(approxEq(third.pos.x, 140.0), "third flex child x mismatch")

proc testFlexHorizontalShrinkDistribution() =
  var b = newTestBuilder(260.0, 120.0)

  var firstIdx = -1
  var secondIdx = -1
  b.node:
    discard b.size(120.0, 70.0)
    discard b.layout(LayoutHorizontal)
    discard b.flexLayout()
    discard b.gap(10.0)

    firstIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 20.0)
      discard b.flex(0.0, 1.0, 80.0)

    secondIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 20.0)
      discard b.flex(0.0, 1.0, 80.0)

  discard b.postProcessChildren(0)
  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]

  require(approxEq(first.size.x, 55.0), "flex shrink should reduce width proportionally")
  require(approxEq(second.size.x, 55.0), "flex shrink should reduce width proportionally")
  require(approxEq(first.pos.x, 0.0), "first shrink child x mismatch")
  require(approxEq(second.pos.x, 65.0), "second shrink child x mismatch")

proc testFlexAlignSelfAndStretch() =
  var b = newTestBuilder(260.0, 120.0)

  var startIdx = -1
  var centerIdx = -1
  var endIdx = -1
  var stretchIdx = -1
  var autoFillIdx = -1
  b.node:
    discard b.size(120.0, 60.0)
    discard b.layout(LayoutHorizontal)
    discard b.flexLayout()

    startIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 10.0)
      discard b.flexAlignSelf(FlexAlignStart)

    centerIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 20.0)
      discard b.flex(0.0, 1.0, 10.0)
      discard b.flexAlignSelf(FlexAlignCenter)

    endIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 15.0)
      discard b.flex(0.0, 1.0, 10.0)
      discard b.flexAlignSelf(FlexAlignEnd)

    stretchIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 5.0)
      discard b.flex(0.0, 1.0, 10.0)
      discard b.flexAlignSelf(FlexAlignStretch)

    autoFillIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 5.0)
      discard b.fillY()
      discard b.flex(0.0, 1.0, 10.0)

  discard b.postProcessChildren(0)
  let startNode = b.nodes[startIdx]
  let centerNode = b.nodes[centerIdx]
  let endNode = b.nodes[endIdx]
  let stretchNode = b.nodes[stretchIdx]
  let autoFillNode = b.nodes[autoFillIdx]

  require(approxEq(startNode.pos.y, 0.0), "flex align-self start should pin to top")
  require(approxEq(centerNode.pos.y, 20.0), "flex align-self center should center on cross-axis")
  require(approxEq(endNode.pos.y, 45.0), "flex align-self end should pin to bottom")
  require(approxEq(stretchNode.pos.y, 0.0), "flex align-self stretch should pin to top")
  require(approxEq(stretchNode.size.y, 60.0), "flex align-self stretch should expand cross-axis size")
  require(approxEq(autoFillNode.pos.y, 0.0), "flex auto align should place FillY child at cross start")
  require(approxEq(autoFillNode.size.y, 60.0), "flex auto align should expand FillY child on cross-axis")

proc testFlexReverseHorizontalPositions() =
  var b = newTestBuilder(260.0, 120.0)

  var firstIdx = -1
  var secondIdx = -1
  var thirdIdx = -1
  b.node:
    discard b.size(100.0, 50.0)
    discard b.layout(LayoutHorizontal)
    discard b.reverseLayout()
    discard b.flexLayout()
    discard b.gap(5.0)

    firstIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 20.0)

    secondIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 20.0)

    thirdIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 20.0)

  discard b.postProcessChildren(0)
  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]
  let third = b.nodes[thirdIdx]
  require(approxEq(first.pos.x, 80.0), "reverse flex first child x mismatch")
  require(approxEq(second.pos.x, 55.0), "reverse flex second child x mismatch")
  require(approxEq(third.pos.x, 30.0), "reverse flex third child x mismatch")

proc testFlexIgnoresAnchorLayoutOnChildren() =
  var b = newTestBuilder(260.0, 120.0)

  var firstIdx = -1
  var anchoredIdx = -1
  var thirdIdx = -1
  b.node:
    discard b.size(100.0, 50.0)
    discard b.layout(LayoutHorizontal)
    discard b.flexLayout()

    firstIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 30.0)

    anchoredIdx = b.nodes.len
    b.node:
      discard b.size(20.0, 10.0)
      discard b.anchorsX(0.5, 0.5)
      discard b.offsetsX(0.0, 0.0)
      discard b.pivotX(0.5)

    thirdIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 30.0)

  discard b.postProcessChildren(0)

  let first = b.nodes[firstIdx]
  let anchored = b.nodes[anchoredIdx]
  let third = b.nodes[thirdIdx]

  require(approxEq(first.pos.x, 0.0), "first flex item should start at x=0")
  require(approxEq(anchored.pos.x, 30.0), "anchored flags should be ignored under flex parent")
  require(approxEq(third.pos.x, 50.0), "third child should follow normal flex flow including anchored node")

proc testGridFixedTracksAndPlacement() =
  var b = newTestBuilder(320.0, 180.0)

  var aIdx = -1
  var bIdx = -1
  var cIdx = -1
  b.node:
    discard b.size(200.0, 120.0)
    discard b.gridLayout()
    discard b.gridTemplateColumns([gridPx(40.0), gridPx(50.0), gridPx(60.0)])
    discard b.gridTemplateRows([gridPx(20.0), gridPx(30.0)])
    discard b.gridGaps(5.0, 10.0)

    aIdx = b.nodes.len
    b.node:
      discard b.gridArea(1, 1)

    bIdx = b.nodes.len
    b.node:
      discard b.gridArea(2, 1, 2, 1)

    cIdx = b.nodes.len
    b.node:
      discard b.gridArea(1, 2)

  discard b.postProcessChildren(0)
  let a = b.nodes[aIdx]
  let bb = b.nodes[bIdx]
  let c = b.nodes[cIdx]

  require(approxEq(a.pos.x, 0.0), "grid fixed a pos.x mismatch")
  require(approxEq(a.pos.y, 0.0), "grid fixed a pos.y mismatch")
  require(approxEq(a.size.x, 40.0), "grid fixed a size.x mismatch")
  require(approxEq(a.size.y, 20.0), "grid fixed a size.y mismatch")

  require(approxEq(bb.pos.x, 50.0), "grid fixed b pos.x mismatch")
  require(approxEq(bb.pos.y, 0.0), "grid fixed b pos.y mismatch")
  require(approxEq(bb.size.x, 120.0), "grid fixed b size.x mismatch")
  require(approxEq(bb.size.y, 20.0), "grid fixed b size.y mismatch")

  require(approxEq(c.pos.x, 0.0), "grid fixed c pos.x mismatch")
  require(approxEq(c.pos.y, 25.0), "grid fixed c pos.y mismatch")
  require(approxEq(c.size.x, 40.0), "grid fixed c size.x mismatch")
  require(approxEq(c.size.y, 30.0), "grid fixed c size.y mismatch")

proc testGridFractionTracksAndAutoPlacement() =
  var b = newTestBuilder(320.0, 180.0)

  var firstIdx = -1
  var secondIdx = -1
  var thirdIdx = -1
  b.node:
    discard b.size(200.0, 100.0)
    discard b.gridLayout()
    discard b.gridTemplateColumns([gridFr(1.0), gridFr(2.0)])
    discard b.gridTemplateRows([gridPx(30.0), gridPx(30.0)])
    discard b.gridColumnGap(10.0)

    firstIdx = b.nodes.len
    b.node:
      discard

    secondIdx = b.nodes.len
    b.node:
      discard

    thirdIdx = b.nodes.len
    b.node:
      discard

  discard b.postProcessChildren(0)
  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]
  let third = b.nodes[thirdIdx]

  require(approxEq(first.pos.x, 0.0), "grid fr first pos.x mismatch")
  require(approxEq(first.pos.y, 0.0), "grid fr first pos.y mismatch")
  require(approxEq(first.size.x, 63.3333'f32, 0.01'f32), "grid fr first size.x mismatch")
  require(approxEq(first.size.y, 30.0), "grid fr first size.y mismatch")

  require(approxEq(second.pos.x, 73.3333'f32, 0.01'f32), "grid fr second pos.x mismatch")
  require(approxEq(second.pos.y, 0.0), "grid fr second pos.y mismatch")
  require(approxEq(second.size.x, 126.6667'f32, 0.01'f32), "grid fr second size.x mismatch")
  require(approxEq(second.size.y, 30.0), "grid fr second size.y mismatch")

  require(approxEq(third.pos.x, 0.0), "grid fr third pos.x mismatch")
  require(approxEq(third.pos.y, 30.0), "grid fr third pos.y mismatch")
  require(approxEq(third.size.x, 63.3333'f32, 0.01'f32), "grid fr third size.x mismatch")
  require(approxEq(third.size.y, 30.0), "grid fr third size.y mismatch")

proc testGridSelfAlignment() =
  var b = newTestBuilder(320.0, 180.0)

  var childIdx = -1
  b.node:
    discard b.size(120.0, 80.0)
    discard b.gridLayout()
    discard b.gridTemplateColumns([gridPx(40.0)])
    discard b.gridTemplateRows([gridPx(30.0)])

    childIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 8.0)
      discard b.gridArea(1, 1)
      discard b.gridJustifySelf(FlexAlignCenter)
      discard b.gridAlignSelf(FlexAlignEnd)

  discard b.postProcessChildren(0)
  let child = b.nodes[childIdx]
  require(approxEq(child.pos.x, 15.0), "grid self-alignment pos.x mismatch")
  require(approxEq(child.pos.y, 22.0), "grid self-alignment pos.y mismatch")
  require(approxEq(child.size.x, 10.0), "grid self-alignment size.x mismatch")
  require(approxEq(child.size.y, 8.0), "grid self-alignment size.y mismatch")

proc testGridFillStretchesWithinCell() =
  var b = newTestBuilder(320.0, 180.0)

  var childIdx = -1
  b.node:
    discard b.size(120.0, 80.0)
    discard b.gridLayout()
    discard b.gridTemplateColumns([gridPx(70.0)])
    discard b.gridTemplateRows([gridPx(35.0)])

    childIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 6.0)
      discard b.fillX().fillY()

  discard b.postProcessChildren(0)
  let child = b.nodes[childIdx]
  require(approxEq(child.pos.x, 0.0), "grid fill stretch pos.x mismatch")
  require(approxEq(child.pos.y, 0.0), "grid fill stretch pos.y mismatch")
  require(approxEq(child.size.x, 70.0), "grid fill stretch size.x mismatch")
  require(approxEq(child.size.y, 35.0), "grid fill stretch size.y mismatch")

proc testRenderTransformDoesNotAffectLayout() =
  var b = newTestBuilder(240.0, 120.0)

  let parentIdx = b.nodes.len
  b.node:
    discard b.layout(LayoutVertical)
    discard b.gap(5.0)
    discard b.size(100.0, 60.0)
    discard b.transformOffset(20.0, 10.0)
    discard b.transformRotation(0.8'f32)
    discard b.transformScale(1.5, 0.75)

    b.node:
      discard b.size(30.0, 10.0)

    b.node:
      discard b.size(30.0, 10.0)

  discard b.postProcessChildren(0)
  let parent = b.nodes[parentIdx]
  let firstChild = b.nodes[parentIdx + 1]
  let secondChild = b.nodes[parentIdx + 2]

  require(approxEq(parent.size.x, 100.0), "render transform should not change parent layout width")
  require(approxEq(parent.size.y, 60.0), "render transform should not change parent layout height")
  require(approxEq(firstChild.pos.x, 0.0), "render transform should not change child layout x")
  require(approxEq(firstChild.pos.y, 0.0), "render transform should not change first child layout y")
  require(approxEq(secondChild.pos.y, 15.0), "render transform should not change second child layout y")

proc testRenderTransformAppliesToSubtreeCommands() =
  var b = newTestBuilder(200.0, 120.0)

  var parentIdx = -1
  var childIdx = -1

  b.node:
    parentIdx = b.stack[^1]
    discard b.size(40.0, 24.0)
    discard b.padding(2.0)
    discard b.fillBackground()
    discard b.backgroundColor(rgba(0.30, 0.40, 0.50, 1.0))
    discard b.transformOffset(10.0, 5.0)

    b.node:
      childIdx = b.stack[^1]
      discard b.size(12.0, 8.0)
      discard b.fillBackground()
      discard b.backgroundColor(rgba(0.70, 0.30, 0.20, 1.0))

  b.endUiFrame()

  var parentFound = false
  var childFound = false
  for cmd in b.frameOutput.commands:
    if cmd.kind == CmdRectFill and cmd.nodeIndex == parentIdx:
      parentFound = true
      require(approxEq(cmd.pos.x, 0.0), "frame command positions should remain raw before render-time transform")
      require(approxEq(cmd.pos.y, 0.0), "frame command positions should remain raw before render-time transform")
    if cmd.kind == CmdRectFill and cmd.nodeIndex == childIdx:
      childFound = true
      require(approxEq(cmd.pos.x, 2.0), "child frame command x should stay in layout-space before render-time transform")
      require(approxEq(cmd.pos.y, 2.0), "child frame command y should stay in layout-space before render-time transform")

  require(parentFound, "expected transformed parent fill command")
  require(childFound, "expected transformed child fill command")

proc testRenderTransformIsAnimatable() =
  var b = newBuilder(fixedMeasureText)
  var nodeId = noneNodeId()

  discard b.beginUiFrame(200.0, 120.0)
  b.node("anim-transform"):
    nodeId = b.currentNode.id
    discard b.size(12.0, 10.0)
    discard b.fillBackground()
    discard b.backgroundColor(rgba(0.50, 0.40, 0.30, 1.0))
    b.animate:
      discard b.transformOffsetAnim(0.0, 0.0)
  b.endUiFrame()

  var firstOffsetX = 0.0'f32
  var firstFound = false
  for i in 0 ..< b.nodes.len:
    if b.nodes[i].id == nodeId:
      firstOffsetX = b.frame.transforms[b.nodes[i].transformIndex - 1].offset.x
      firstFound = true
      break
  require(firstFound, "expected first-frame transform state for animated node")

  discard b.beginUiFrame(200.0, 120.0)
  b.node("anim-transform"):
    discard b.size(12.0, 10.0)
    discard b.fillBackground()
    discard b.backgroundColor(rgba(0.50, 0.40, 0.30, 1.0))
    b.animate:
      discard b.transformOffsetAnim(20.0, 0.0)
  b.endUiFrame()

  var secondOffsetX = 0.0'f32
  var secondFound = false
  for i in 0 ..< b.nodes.len:
    if b.nodes[i].id == nodeId:
      secondOffsetX = b.frame.transforms[b.nodes[i].transformIndex - 1].offset.x
      secondFound = true
      break
  require(secondFound, "expected second-frame transform state for animated node")

  require(secondOffsetX > firstOffsetX, "animated transform offset should progress toward target")
  require(secondOffsetX < firstOffsetX + 20.0'f32, "animated transform offset should blend toward target")

proc testTreeTableTreeTexts() =
  # Build a 3-deep tree (levels 0..3) with 2 children per node => 15 nodes.
  let maxDepth = 3
  let branching = 2
  var b = newTestBuilder(800.0, 800.0)

  b.node:
    discard b.size(800.0, 800.0)
    var cursor = newTreeCursor(maxDepth, branching)
    # Pre-expand the whole tree by attaching an already-expanded editor storage.
    var storage = TreeTable()
    storage.cursor = cursor
    storage.initialized = true
    expandAll(storage)
    b.nodeStorage(b.currentNode, storage)
    proc renderRow(b: var UiBuilder, cursor: TreeCursor, index: int) {.canRaise, nimcall.} =
      b.label(cursor.fieldName & ":"):
        discard b.fitX().fitY()
      b.node:
        b.debugName("tree-table-row-overlay")
        discard b.anchors(0.0, 0.0, 1.0, 0.0)
          .offsets(0.0, -50.0, 0.0, 50.0)
          .finishAnchors()
          .ignoreInContentExtent()

    b.treeTable(cursor, renderRow)

  # The virtual list builds its rows in a deferred pass.
  b.flushDeferredNodes()

  # Collect every tree-name label (texts ending with ':').
  var foundNames: seq[string] = @[]
  for i in 0 ..< b.frame.texts.len:
    let t = b.frame.texts[i].text.value
    if t.len > 0 and t[^1] == ':':
      foundNames.add(t[0 .. ^2])

  let expected = expectedTreeNames(maxDepth, branching)
  require(foundNames.len == expected.len, "expected " & $expected.len & " tree names, got " & $foundNames.len)
  for e in expected:
    require(e in foundNames, "missing tree name: " & e)

  # The first row is the root: verify its children are laid out as columns
  # (left-to-right, strictly increasing x) and the row height fits the columns.
  var rowNodeIdx = -1
  for i in 0 ..< b.nodes.len:
    if b.nodes[i].nodeDebugName() == "tree-table-row":
      rowNodeIdx = i
      break
  if rowNodeIdx < 0:
    for i in 0 ..< b.nodes.len:
      let textIndex = b.nodes[i].textIndex.int
      if textIndex > 0 and b.frame.texts[textIndex - 1].text.value == "root:":
        rowNodeIdx = b.nodes[i].parent.int
        break
  require(rowNodeIdx >= 0, "expected at least one tree row node")

  var colXs: seq[float32]
  var colHeights: seq[float32]
  var overlayFound = false
  for childIdx in b.children(rowNodeIdx):
    let child = b.nodes[childIdx].addr
    if AnchorX in child.flags or AnchorY in child.flags:
      overlayFound = true
      require(IgnoreInContentExtent in child.flags,
        "tree-table overlay must be excluded from row content extent")
    else:
      colXs.add(child.pos.x)
      colHeights.add(child.size.y)
  require(overlayFound, "expected an anchored direct-row overlay")
  require(colXs.len == 2, "expected 2 columns per row (symbol, name), got " & $colXs.len)
  for i in 1 ..< colXs.len:
    require(colXs[i] > colXs[i - 1] - 0.5, "columns must be laid out left-to-right")
  let rowH = b.nodes[rowNodeIdx].size.y
  require(rowH < 100.0, "anchored overlay must not affect tree-table row fit")
  for h in colHeights:
    require(rowH >= h - 0.5, "row height should encompass its columns")

  # Cross-row alignment: every row's columns must start at the same x (table style),
  # so columns line up vertically regardless of row content.
  var firstRowCols: seq[float32]
  for i in 0 ..< b.nodes.len:
    if b.nodes[i].nodeDebugName() == "property-row":
      var xs: seq[float32]
      for childIdx in b.children(i):
        xs.add(b.nodes[childIdx].pos.x)
      if firstRowCols.len == 0:
        firstRowCols = xs
      else:
        require(xs.len == firstRowCols.len, "all rows must have the same number of columns")
        for k in 0 ..< xs.len:
          require(approxEq(xs[k], firstRowCols[k], 0.5), "column " & $k & " x must align across rows")

proc runTests() =
  testFlagsAndMutators()
  testTextWrappingUsesNodeWidthOnlyWhenEnabled()
  testPositionAndSizeScalars()
  testVerticalLayoutTextSizing()
  testHorizontalLayoutTextSizing()
  testAlignCenterVerticalCrossAxis()
  testAlignCenterHorizontalCrossAxis()
  testAlignCenterWithoutLayout()
  testStandaloneFitOnEndNode()
  testParentFitIncludesChildren()
  testParentFitIgnoresFlaggedChildExtent()
  testParentFitIncludesChildren2()
  testHorizontalFitYWithNestedFillYPropagation()
  testImmediateFillXAndFillY()
  testImmediateFillRespectsChildPosition()
  testPostProcessFillRespectsChildPosition()
  testPostProcessFillPropagatesKnownParentAxes()
  testReverseVerticalFillXUsesContentWidth()
  testMinMaxSizeClamping()
  testPaddingOffsetsChildWithoutLayout()
  testCustomRenderCommandsInjection()
  testCustomRenderCommandsSupportsTwoFrameLifetime()
  testArenaResizeArrayView()
  testStableExplicitIdsAcrossFrames()
  testPushPopIdScopes()
  # testButtonHoverAndPressed()
  # testSliderClickUpdatesValue()
  testPreviousNodesAndIndicesDoubleBuffered()
  testDragUiCallbackAndDropState()
  testFileSystemCursorDragAndDrop()
  testReverseVerticalLayoutAllCombinations()
  testReverseHorizontalLayoutAllCombinations()
  testReverseVerticalParentFitRepositions()
  testReverseHorizontalParentFitRepositions()
  testAnchoredLayoutPivotPositioning()
  testAnchoredLayoutStretchUsesAnchorOffsets()
  testAnchoredLayoutTriggersParentPostProcessForFit()
  testAnchoredLayoutAxisSpecificMutators()
  testFlexHorizontalGrowDistribution()
  testFlexHorizontalShrinkDistribution()
  testFlexAlignSelfAndStretch()
  testFlexReverseHorizontalPositions()
  testFlexIgnoresAnchorLayoutOnChildren()
  # testGridFixedTracksAndPlacement()
  # testGridFractionTracksAndAutoPlacement()
  # testGridSelfAlignment()
  # testGridFillStretchesWithinCell()
  testRenderTransformDoesNotAffectLayout()
  testRenderTransformAppliesToSubtreeCommands()
  testRenderTransformIsAnimatable()
  testTreeTableTreeTexts()

when isMainModule:
  runTests()

# Intentionally no endUiFrame/render calls here: tests validate flags/layout only,
# without generating render commands yet.
