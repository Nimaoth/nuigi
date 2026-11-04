when defined(nimony):
  {.feature: "lenientnils".}

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

proc windowSpaceStorage(b: var UiBuilder): WindowSpaceStorage =
  let windowSpaceIndex = b.currentNodeIndex(b.windows)
  if windowSpaceIndex < 0:
    return nil
  let stored = b.nodeStorageGet(b.frame.nodes[windowSpaceIndex].addr)
  if stored != nil and stored of WindowSpaceStorage:
    return cast[WindowSpaceStorage](stored)
  nil

proc requiredWindowSpaceStorage(b: var UiBuilder): WindowSpaceStorage =
  let stored = b.windowSpaceStorage()
  if stored == nil:
    assert false, "window space storage is unavailable"
  return stored

proc windowStorage(b: var UiBuilder, windowId: UiNodeId): WindowStorage =
  let windowIndex = b.currentNodeIndex(windowId)
  if windowIndex < 0:
    return nil
  let stored = b.nodeStorageGet(b.frame.nodes[windowIndex].addr)
  if stored != nil and stored of WindowStorage:
    return cast[WindowStorage](stored)
  nil

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

proc testTerminalWindowFitsViewport() =
  var b = newBuilder(fixedMeasureText, textHeight = 1.0'f32,
    backendType = UiBackendType.Terminal)
  b.themeStyle(UiStyleIndexWindowContent).paddingX = 3.0'f32
  b.themeStyle(UiStyleIndexWindowContent).paddingY = 3.0'f32
  discard b.beginUiFrame(80.0'f32, 24.0'f32)
  b.windowSpace()
  var contentIndex = -1
  b.window("Terminal", 0.0'f32, 0.0'f32, 80.0'f32, 24.0'f32):
    contentIndex = b.stack[^1]

  let storage = b.windowStorage("Terminal".hashChars.UiNodeId)
  require(storage != nil, "terminal window should have persistent storage")
  if storage != nil:
    require(storage.size == vec2(80.0'f32, 24.0'f32),
      "terminal window should retain viewport-sized dimensions")

  var foundTitleBar = false
  for index in 0 ..< b.nodes.len:
    let textIndex = b.nodes[index].textIndex.int - 1
    if textIndex >= 0 and textIndex < b.frame.texts.len and
        b.frame.texts[textIndex].text.value == "Terminal":
      let titleBarIndex = b.nodes[index].parent.int
      foundTitleBar = true
  require(foundTitleBar, "terminal window should contain a title bar")
  require(contentIndex >= 0, "terminal window should contain a content node")

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

proc buildDockFrame(b: var UiBuilder, dock: DockSpace, input = default(UiInputSnapshot),
    viewport = vec2(800.0'f32, 600.0'f32)) =
  discard b.beginUiFrame(viewport.x, viewport.y, input, animationTick = 1.0'f32)
  b.windowSpace(dock)
  for title in ["A", "B", "C"]:
    b.window(title, 100.0'f32, 100.0'f32, 200.0'f32, 150.0'f32):
      discard
  b.endUiFrame(buildRenderCommands = false)

proc nodeRect(b: UiBuilder, id: UiNodeId): (Vec2, Vec2) =
  let index = b.currentNodeIndex(id)
  if index < 0:
    return (vec2(-1.0'f32), vec2(-1.0'f32))
  (b.absoluteNodePos(index), b.frame.nodes[index].size)

proc windowRect(b: UiBuilder, title: string): (Vec2, Vec2) =
  b.nodeRect(title.hashChars.UiNodeId)

proc pressAt(frame: uint64, pos: Vec2): UiInputSnapshot =
  UiInputSnapshot(frameIndex: frame, mouse: pos, mouseDown: {MouseLeft}, mousePressed: {MouseLeft})

proc holdAt(frame: uint64, pos, delta: Vec2): UiInputSnapshot =
  UiInputSnapshot(frameIndex: frame, mouse: pos, mouseDelta: delta, mouseDown: {MouseLeft})

proc releaseAt(frame: uint64, pos: Vec2): UiInputSnapshot =
  UiInputSnapshot(frameIndex: frame, mouse: pos, mouseReleased: {MouseLeft})

proc sideBySideDock(): DockSpace =
  var layout = initDockLayout()
  layout.dockWindow("A")
  layout.dockWindow("B", "A", DockRight, 0.5'f32)
  newDockSpace(layout)

proc testDockLayoutSerializationRoundTrip() =
  var layout = initDockLayout()
  layout.dockWindow("Session")
  layout.dockWindow("Sessions list", "", DockLeft, 0.25'f32)
  layout.dockWindow("Overview", "Session", DockBottom, 0.75'f32)
  layout.dockWindow("Tags", "Overview", DockCenter)
  layout.floatWindow("Tool window", vec2(10.0'f32, 20.0'f32), vec2(300.0'f32, 200.0'f32), collapsed = true)
  require(layout.isDocked("Tags") and layout.findTabs("Tags") == layout.findTabs("Overview"),
    "center docking should add a tab to the target group")

  let text = layout.serialize()
  var parsed = initDockLayout()
  require(parseDockLayout(text, parsed), "serialized layout should parse")
  require(parsed.serialize() == text, "layout should survive a serialization round trip")
  require(parsed.findFloating("Tool window") >= 0 and
      parsed.floating[parsed.findFloating("Tool window")].collapsed,
    "floating windows should keep their state")

  var untouched = initDockLayout()
  require(not parseDockLayout("garbage", untouched) and untouched.isEmpty,
    "malformed text should be rejected")
  for malformed in [
      "nuigi-dock-layout 1\nsplit x invalid\nempty\nempty\n",
      "nuigi-dock-layout 1\ntabs 0 invalid\nwindow A\n",
      "nuigi-dock-layout 1\nempty\nfloating invalid 0 1 1 0 Tool\n"]:
    require(not parseDockLayout(malformed, untouched) and untouched.isEmpty,
      "malformed numeric values should be rejected without modifying the layout")

  parsed.removeWindow("Sessions list")
  require(not parsed.isDocked("Sessions list") and parsed.isDocked("Session"),
    "removing a window should collapse its split")
  parsed.removeWindow("Tags")
  parsed.removeWindow("Overview")
  parsed.removeWindow("Session")
  require(parsed.isEmpty, "removing all docked windows should empty the tree")

proc testDockedWindowsFillLeaves() =
  var b = newBuilder(fixedMeasureText)
  let dock = sideBySideDock()
  b.buildDockFrame(dock)
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 1))

  require(b.windowRect("A") == (vec2(0.0'f32), vec2(398.0'f32, 600.0'f32)),
    "first docked window should fill the left half")
  require(b.windowRect("B") == (vec2(402.0'f32, 0.0'f32), vec2(398.0'f32, 600.0'f32)),
    "second docked window should fill the right half")
  require(b.windowRect("C") == (vec2(100.0'f32), vec2(200.0'f32, 150.0'f32)),
    "a window outside the layout should float at its default geometry")
  require(dock.layout.findFloating("C") >= 0, "floating windows should be recorded in the layout")

  let order = b.windowOrder()
  require(order[^1] == "C".hashChars.UiNodeId, "floating windows should render above docked windows")

proc testDockTabsSwitchActiveWindow() =
  var b = newBuilder(fixedMeasureText)
  let dock = sideBySideDock()
  dock.layout.dockWindow("C", "A", DockCenter)
  b.buildDockFrame(dock)
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 1))

  require(b.windowRect("C")[1] == vec2(398.0'f32, 600.0'f32), "new tab should be active")
  require(b.windowRect("A")[1] == vec2(0.0'f32), "inactive tab should be hidden")

  let (tabPos, tabSize) = b.nodeRect(dockTabId("A"))
  require(tabSize.x > 0.0'f32, "tab bar should list the inactive window")
  b.buildDockFrame(dock, pressAt(2, tabPos + tabSize * 0.5'f32))
  require(b.windowRect("A")[1] == vec2(398.0'f32, 600.0'f32), "clicking a tab should activate it")
  require(b.windowRect("C")[1] == vec2(0.0'f32), "previously active tab should be hidden")

proc testDockSplitterResizesPanes() =
  var b = newBuilder(fixedMeasureText)
  let dock = sideBySideDock()
  b.buildDockFrame(dock)
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 1))

  let split = dock.layout.root
  let (splitterPos, splitterSize) = b.nodeRect(dockSplitterId(split))
  require(splitterSize.x > 0.0'f32, "split should have a splitter")
  let grab = splitterPos + splitterSize * 0.5'f32
  b.buildDockFrame(dock, pressAt(2, grab))
  b.buildDockFrame(dock, holdAt(3, vec2(202.0'f32, grab.y), vec2(202.0'f32 - grab.x, 0.0'f32)))
  require(abs(dock.layout.nodes[split].ratio - 200.0'f32 / 796.0'f32) < 0.001'f32,
    "dragging the splitter should update the split ratio")
  require(b.windowRect("A")[1].x == 200.0'f32, "left pane should follow the splitter")

proc testDraggingFloatingWindowDocksIt() =
  var b = newBuilder(fixedMeasureText)
  let dock = sideBySideDock()
  b.buildDockFrame(dock)
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 1))

  let titlePos = vec2(110.0'f32, 105.0'f32)
  b.buildDockFrame(dock, pressAt(2, titlePos))
  let target = vec2(600.0'f32, 560.0'f32)
  b.buildDockFrame(dock, holdAt(3, target, target - titlePos))
  require(dock.isDragging, "moving the title bar should start a dock drag")
  let order = b.windowOrder()
  require(order[^1] != "C".hashChars.UiNodeId, "the dock preview should render above the dragged window")
  b.buildDockFrame(dock, releaseAt(4, target))

  let cTabs = dock.layout.findTabs("C")
  require(cTabs >= 0, "dropping on the bottom of a window should dock it")
  let parent = dock.layout.nodes[cTabs].parent
  require(parent >= 0 and dock.layout.nodes[parent].axis == DockAxisY and
      dock.layout.nodes[parent].children[1] == cTabs and
      dock.layout.nodes[dock.layout.nodes[parent].children[0]].windows == @["B"],
    "dropping on the bottom half should split the target vertically")

  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 5))
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 6))
  require(b.windowRect("C") == (vec2(402.0'f32, 302.0'f32), vec2(398.0'f32, 298.0'f32)),
    "docked window should take the bottom half of the target")

proc testShiftDragKeepsWindowFloating() =
  var b = newBuilder(fixedMeasureText)
  let dock = sideBySideDock()
  b.buildDockFrame(dock)
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 1))

  let titlePos = vec2(110.0'f32, 105.0'f32)
  b.buildDockFrame(dock, pressAt(2, titlePos))
  let target = vec2(600.0'f32, 560.0'f32)
  var input = holdAt(3, target, target - titlePos)
  input.modsDown = {ModShift}
  b.buildDockFrame(dock, input)
  require(b.requiredWindowSpaceStorage().dockAreasId == noneNodeId(), "Shift should hide drop guides")
  var release = releaseAt(4, target)
  release.modsDown = {ModShift}
  b.buildDockFrame(dock, release)
  require(not dock.layout.isDocked("C"), "shift should disable docking")
  let floating = dock.layout.findFloating("C")
  require(floating >= 0 and dock.layout.floating[floating].pos == vec2(100.0'f32) + target - titlePos,
    "the window should have moved with the mouse")

proc checkDockDrop(target: Vec2, docks: bool, side = DockCenter,
    viewport = vec2(800.0'f32, 600.0'f32), terminal = false, empty = false) =
  var b = newBuilder(fixedMeasureText,
    backendType = if terminal: UiBackendType.Terminal else: UiBackendType.Graphical)
  let dock = newDockSpace()
  if not empty:
    dock.layout.dockWindow("A")
  let start = vec2(min(100.0'f32, viewport.x * 0.25'f32),
    min(100.0'f32, viewport.y * 0.25'f32))
  let size = vec2(200.0'f32, 150.0'f32)
  dock.layout.floatWindow("C", start, size)
  b.buildDockFrame(dock, viewport = viewport)
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 1), viewport)
  require(b.requiredWindowSpaceStorage().dockAreasId == noneNodeId(), "idle windows should not show drop guides")
  let grab = start + vec2(10.0'f32, 5.0'f32)
  b.buildDockFrame(dock, pressAt(2, grab), viewport)
  b.buildDockFrame(dock, holdAt(3, target, target - grab), viewport)
  require(dock.isDragging, "drop test should start a window drag")
  let areasId = b.requiredWindowSpaceStorage().dockAreasId
  require(areasId != noneNodeId(), "hovering a pane should show the available drop areas")
  require((b.windowOrder()[^1] != areasId) == docks,
    "only valid drop areas should show a bright result preview at " & $target)
  let areasIndex = b.currentNodeIndex(areasId)
  let square = min(if terminal: 4.0'f32 else: 100.0'f32, min(viewport.x, viewport.y) / 3.0'f32)
  var areaCount = 0
  let accent = b.themeStyle(UiStyleIndexAccent)[].borderColor
  for index in b.children(areasIndex):
    if areaCount == 0:
      require(b.nodes[index].size == vec2(square), "tab guide should match the center hit area")
      require(b.absoluteNodePos(index) == (viewport - vec2(square)) * 0.5'f32,
        "tab guide should be centered in the pane")
    let color = b.nodeStyle(index)[].borderColor
    require(color.r == accent.r * 0.5'f32 and color.g == accent.g * 0.5'f32 and
        color.b == accent.b * 0.5'f32, "drop guides should use a darker accent")
    inc areaCount
  require(areaCount == (if empty: 1 else: 5), "show only the available drop areas")
  b.buildDockFrame(dock, releaseAt(4, target), viewport)
  require(b.requiredWindowSpaceStorage().dockAreasId == noneNodeId(), "release should hide the drop guides")
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 5), viewport)
  require(dock.layout.isDocked("C") == docks,
    "drop result should match the preview at " & $target)
  if not docks:
    let floating = dock.layout.findFloating("C")
    require(floating >= 0 and dock.layout.floating[floating].pos == start + target - grab,
      "a drop in the gap should preserve the floating position")
  elif empty:
    require(dock.layout.nodes[dock.layout.root].windows == @["C"],
      "center drop should fill an empty dock space")
  elif side == DockCenter:
    require(dock.layout.findTabs("C") == dock.layout.findTabs("A"),
      "center square should share the target's tabs")
  else:
    let tabs = dock.layout.findTabs("C")
    let parent = dock.layout.nodes[tabs].parent
    require(parent >= 0, "edge drop should create a split")
    require(dock.layout.nodes[parent].axis == (if side in {DockLeft, DockRight}: DockAxisX else: DockAxisY),
      "edge drop should split along the selected axis")
    require(dock.layout.nodes[parent].children[if side in {DockLeft, DockTop}: 0 else: 1] == tabs,
      "edge drop should place the new pane on the selected side")

proc testDockDropZones() =
  for target in [vec2(400.0'f32, 300.0'f32), vec2(350.0'f32, 250.0'f32),
      vec2(450.0'f32, 350.0'f32)]:
    checkDockDrop(target, true)
  for (target, side) in [
      (vec2(99.0'f32, 300.0'f32), DockLeft),
      (vec2(701.0'f32, 300.0'f32), DockRight),
      (vec2(400.0'f32, 99.0'f32), DockTop),
      (vec2(400.0'f32, 501.0'f32), DockBottom)]:
    checkDockDrop(target, true, side)
  for target in [vec2(100.0'f32, 300.0'f32), vec2(700.0'f32, 300.0'f32),
      vec2(400.0'f32, 100.0'f32), vec2(400.0'f32, 500.0'f32),
      vec2(349.0'f32, 300.0'f32), vec2(451.0'f32, 300.0'f32),
      vec2(400.0'f32, 249.0'f32), vec2(400.0'f32, 351.0'f32),
      vec2(349.0'f32, 249.0'f32)]:
    checkDockDrop(target, false)
  for (target, side) in [
      (vec2(1.0'f32, 300.0'f32), DockLeft),
      (vec2(799.0'f32, 300.0'f32), DockRight),
      (vec2(400.0'f32, 1.0'f32), DockTop),
      (vec2(400.0'f32, 599.0'f32), DockBottom)]:
    checkDockDrop(target, true, side)

  let small = vec2(240.0'f32, 180.0'f32)
  checkDockDrop(vec2(120.0'f32, 90.0'f32), true, viewport = small)
  checkDockDrop(vec2(40.0'f32, 90.0'f32), true, DockLeft, small)
  checkDockDrop(vec2(80.0'f32, 90.0'f32), false, viewport = small)
  let tiny = vec2(80.0'f32, 60.0'f32)
  checkDockDrop(vec2(40.0'f32, 30.0'f32), true, viewport = tiny)
  checkDockDrop(vec2(26.0'f32, 30.0'f32), false, viewport = tiny)
  checkDockDrop(vec2(400.0'f32, 300.0'f32), true, terminal = true)
  checkDockDrop(vec2(5.0'f32, 300.0'f32), true, DockLeft, terminal = true)
  checkDockDrop(vec2(396.0'f32, 300.0'f32), false, terminal = true)
  checkDockDrop(vec2(400.0'f32, 300.0'f32), true, empty = true)
  checkDockDrop(vec2(300.0'f32, 300.0'f32), false, empty = true)
  checkDockDrop(vec2(50.0'f32, 300.0'f32), false, empty = true)

proc testReleaseInGapClearsDockPreview() =
  var b = newBuilder(fixedMeasureText)
  let dock = sideBySideDock()
  b.buildDockFrame(dock)
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 1))
  let grab = vec2(110.0'f32, 105.0'f32)
  let center = vec2(600.0'f32, 300.0'f32)
  b.buildDockFrame(dock, pressAt(2, grab))
  b.buildDockFrame(dock, holdAt(3, center, center - grab))
  require(b.windowOrder()[^1] != "C".hashChars.UiNodeId, "center should show a preview")
  b.buildDockFrame(dock, releaseAt(4, vec2(600.0'f32, 200.0'f32)))
  require(not dock.layout.isDocked("C"), "release in the gap must not use the previous preview")
  require(b.windowOrder()[^1] == "C".hashChars.UiNodeId, "gap release should remove the preview")

proc testDraggingTabIntoGapKeepsItFloating() =
  var b = newBuilder(fixedMeasureText)
  let dock = sideBySideDock()
  b.buildDockFrame(dock)
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 1))
  let (tabPos, tabSize) = b.nodeRect(dockTabId("B"))
  let grab = tabPos + tabSize * 0.5'f32
  let gap = vec2(300.0'f32, 300.0'f32)
  b.buildDockFrame(dock, pressAt(2, grab))
  b.buildDockFrame(dock, holdAt(3, gap, gap - grab))
  require(dock.isDragging and not dock.layout.isDocked("B"), "tab should undock during the drag")
  require(b.windowOrder()[^1] == b.requiredWindowSpaceStorage().dockAreasId,
    "floating gap should show drop guides but no bright result preview")
  b.buildDockFrame(dock, releaseAt(4, gap))
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 5))
  require(not dock.layout.isDocked("B") and dock.layout.findFloating("B") >= 0,
    "releasing an undocked tab in the gap should leave it floating without Shift")
  require(b.windowRect("A") == (vec2(0.0'f32), vec2(800.0'f32, 600.0'f32)),
    "remaining pane should fill the dock space")

proc testDraggingTabUndocksWindow() =
  var b = newBuilder(fixedMeasureText)
  let dock = sideBySideDock()
  b.buildDockFrame(dock)
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 1))

  let (tabPos, tabSize) = b.nodeRect(dockTabId("B"))
  let grab = tabPos + tabSize * 0.5'f32
  b.buildDockFrame(dock, pressAt(2, grab))
  b.buildDockFrame(dock, holdAt(3, grab + vec2(-30.0'f32, 40.0'f32), vec2(-30.0'f32, 40.0'f32)))
  require(not dock.layout.isDocked("B") and dock.layout.findFloating("B") >= 0,
    "dragging a tab should undock its window")
  require(dock.layout.root >= 0 and dock.layout.nodes[dock.layout.root].windows == @["A"],
    "the remaining window should take the whole dock space")
  b.buildDockFrame(dock, releaseAt(4, vec2(-10.0'f32)))
  require(b.requiredWindowSpaceStorage().dockAreasId == noneNodeId(), "outside release should hide drop guides")
  b.buildDockFrame(dock, UiInputSnapshot(frameIndex: 5))
  require(b.windowRect("A") == (vec2(0.0'f32), vec2(800.0'f32, 600.0'f32)),
    "remaining docked window should fill the dock space")
  require(b.windowRect("B")[1].x > 0.0'f32 and not dock.layout.isDocked("B"),
    "released outside the dock space, the window should stay floating")

when isMainModule:
  testPressedWindowMovesToFront()
  testTerminalWindowFitsViewport()
  # testTitleBarMatchesWindowTopCornerRadii()
  # testWindowResizesFromBottomRightCorner()
  testDockLayoutSerializationRoundTrip()
  testDockedWindowsFillLeaves()
  testDockTabsSwitchActiveWindow()
  testDockSplitterResizesPanes()
  testDraggingFloatingWindowDocksIt()
  testShiftDragKeepsWindowFloating()
  testDockDropZones()
  testReleaseInGapClearsDockPreview()
  testDraggingTabIntoGapKeepsItFloating()
  testDraggingTabUndocksWindow()