## Draggable, resizable, collapsible windows and their containing window space.
##
## Per-window geometry lives in node storage. The window space separately
## tracks a monotonic activation order and performs deferred construction so
## active windows render on top without making callers reorder their code.
##
## A window space can optionally be given a `DockSpace`. The dock space owns a
## serializable `DockLayout` that decides whether each window is floating or
## docked into a tree of resizable splits and tab groups. Windows are still
## declared with the same `window` template; dragging a floating window over a
## docked one previews and performs docking, and dragging a tab undocks it.

import std/[math, sequtils, assertions]
import nuigi
import nuigi/core/vecmath
import nuigi/debug/profiler
import nuigi/layout/flex
import nuigi/widgets/dock_layout

export dock_layout

include nuigi/util/compat2

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
  docked*: bool
    ## Whether the window was placed in the dock layout this frame.

type WindowActivity* = object
  windowId*: UiNodeId
  lastActive*: uint64

type
  DockRect = object
    pos: Vec2
    size: Vec2
    visible: bool

  DockDropTarget = object
    valid: bool
    target: string
      ## A window in the target tab group, or empty for the whole dock space.
    side: DockSide
    ratio: float32
    previewPos: Vec2
    previewSize: Vec2

  DockSpace* = ref object
    ## Docking state of a window space. `layout` is the persistent part and can
    ## be saved with `serialize` and restored with `parseDockLayout`; the rest
    ## is per-frame interaction state.
    layout*: DockLayout
    rects: seq[DockRect]
    origin: Vec2
    bounds: Vec2
    initialized: bool
    visibleWindows: seq[string]
      ## Windows submitted during the previous frame.
    submitted: seq[string]
    dragWindow: string
      ## Floating window currently being moved and possibly docked.
    dragStart: Vec2
    dragMoved: bool
    tabPressTitle: string
    tabPressPos: Vec2
    tabPressOffset: Vec2
    dropTarget: DockDropTarget


type WindowSpaceStorage* = ref object of UiNodeStorageData
  windows*: seq[WindowActivity]
  activationCounter*: uint64
  dock*: DockSpace
  dockChromeId: UiNodeId
  dockAreasId*: UiNodeId
  dockPreviewId: UiNodeId

type WindowPlacement = enum
  WindowFloating
  WindowDocked
  WindowHidden
    ## Docked in an inactive tab or a tab group that is not visible.

type WindowMetrics = object
  minSize: Vec2
  edgeDistance: float32

const
  dockTabDragThreshold = 6.0'f32
  dockMinPaneSize = 60.0'f32

proc newDockSpace*(layout = initDockLayout()): DockSpace =
  ## Create a dock space to pass to `windowSpace`. Windows that are not part of
  ## `layout` start floating at the position given to `window`.
  DockSpace(layout: layout)

proc isDragging*(dock: DockSpace): bool =
  ## Whether a floating window is currently being dragged for docking.
  dock != nil and dock.dragWindow.len > 0 and dock.dragMoved

proc dockTabId*(title: string): UiNodeId =
  ## Node ID of the tab representing a docked window.
  hashChars("dock-tab:" & title).UiNodeId

proc dockSplitterId*(nodeIndex: int): UiNodeId =
  ## Node ID of the splitter of the split node at `nodeIndex`.
  hashChars("dock-splitter:" & $nodeIndex).UiNodeId

proc windowMetrics(b: UiBuilder): WindowMetrics =
  if b.backendType == UiBackendType.Terminal:
    WindowMetrics(minSize: vec2(20.0'f32, 5.0'f32), edgeDistance: 1.0'f32)
  else:
    WindowMetrics(minSize: vec2(120.0'f32, 80.0'f32), edgeDistance: 4.0'f32)

proc getOrCreateWindowStorage(b: var UiBuilder, node: ptr UiNode, defaultPos, defaultSize: vecmath.Vec2): WindowStorage =
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
  for index in 0 ..< storage.windows.len:
    let activity = storage.windows[index]
    if activity.windowId == windowId:
      return activity.lastActive
  0'u64

proc windowSpaceStorageAt(b: var UiBuilder, nodeIdx: int): WindowSpaceStorage =
  if nodeIdx < 0 or nodeIdx >= b.nodes.len:
    return nil
  let stored = b.nodeStorageGet(b.nodes[nodeIdx].addr)
  if stored == nil or not (stored of WindowSpaceStorage):
    return nil
  cast[WindowSpaceStorage](stored)

proc currentDockSpace(b: var UiBuilder): DockSpace =
  let storage = b.windowSpaceStorageAt(b.currentNodeIndex(b.windows))
  if storage == nil:
    return nil
  return storage.dock

proc sameTitles(a, b: seq[string]): bool =
  if a.len != b.len:
    return false
  for title in a:
    if title notin b:
      return false
  true

proc windowSpaceChildRank(b: var UiBuilder, storage: WindowSpaceStorage, childIdx: int): int =
  ## Paint order group: other children, docked windows, dock splitters,
  ## floating windows, drop areas, dock preview.
  let dock = storage.dock
  if dock == nil:
    return 0
  let id = b.nodes[childIdx].id
  if id == storage.dockChromeId:
    return 2
  if id == storage.dockPreviewId:
    return 5
  if id == storage.dockAreasId:
    return 4
  let stored = b.nodeStorageGet(b.nodes[childIdx].addr)
  if stored != nil and stored of WindowStorage:
    return if cast[WindowStorage](stored).docked: 1 else: 3
  0

proc windowSpaceDeferredBuild(b: var UiBuilder, nodeIdx: int, rawData: int) =
  prof("windowSpaceDeferredBuild")
  let _ = rawData
  let storage = b.windowSpaceStorageAt(nodeIdx)
  if storage == nil:
    return

  var orderedWindows: seq[int] = @[]
  var orderKeys: seq[(int, uint64)] = @[]
  for childIdx in b.children(nodeIdx):
    let childKey = (b.windowSpaceChildRank(storage, childIdx),
      storage.windowLastActive(b.nodes[childIdx].id))
    var insertAt = orderedWindows.len
    while insertAt > 0:
      let previousKey = orderKeys[insertAt - 1]
      if previousKey[0] < childKey[0] or
          (previousKey[0] == childKey[0] and previousKey[1] <= childKey[1]):
        break
      dec insertAt
    if insertAt >= 0:
      orderedWindows.insert([childIdx], insertAt)
      orderKeys.insert([childKey], insertAt)
    else:
      assert false, "window insertion index must not be negative"

  let dock = storage.dock
  if dock != nil and not sameTitles(dock.submitted, dock.visibleWindows):
    # The set of windows changed; build another frame so the dock layout
    # reflects it.
    b.anythingAnimating = true

  if orderedWindows.len == 0:
    b.nodes[nodeIdx].lastChild = -1
    return
  for i in 0 ..< orderedWindows.len:
    let nextIndex = orderedWindows[(i + 1) mod orderedWindows.len]
    b.nodes[orderedWindows[i]].nextSibling = nextIndex.int32
  b.nodes[nodeIdx].lastChild = orderedWindows[^1].int32

# Dock layout geometry

proc dockGap(b: UiBuilder): float32 =
  if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 4.0'f32

proc isVisibleDockNode(dock: DockSpace, index: int): bool =
  if index < 0 or index >= dock.layout.nodes.len:
    return false
  let node = dock.layout.nodes[index]
  case node.kind
  of DockNodeTabs:
    for title in node.windows:
      if title in dock.visibleWindows:
        return true
    false
  of DockNodeSplit:
    dock.isVisibleDockNode(node.children[0]) or dock.isVisibleDockNode(node.children[1])
  of DockNodeFree:
    false

proc visibleActiveWindow(dock: DockSpace, tabs: int): string =
  ## The window shown by a tab group: its active tab, or the first visible tab
  ## when the active one was not submitted.
  let node = dock.layout.nodes[tabs]
  if node.activeTab >= 0 and node.activeTab < node.windows.len and
      node.windows[node.activeTab] in dock.visibleWindows:
    return node.windows[node.activeTab]
  for title in node.windows:
    if title in dock.visibleWindows:
      return title
  ""

proc layoutDockNode(dock: DockSpace, index: int, pos, size: Vec2, gap: float32) =
  dock.rects[index] = DockRect(pos: pos, size: size, visible: true)
  let node = dock.layout.nodes[index]
  if node.kind != DockNodeSplit:
    return
  let first = node.children[0]
  let second = node.children[1]
  let firstVisible = dock.isVisibleDockNode(first)
  let secondVisible = dock.isVisibleDockNode(second)
  if firstVisible and secondVisible:
    if node.axis == DockAxisX:
      let available = max(0.0'f32, size.x - gap)
      let firstWidth = floor(available * node.ratio + 0.5'f32)
      dock.layoutDockNode(first, pos, vec2(firstWidth, size.y), gap)
      dock.layoutDockNode(second, pos + vec2(firstWidth + gap, 0.0'f32),
        vec2(available - firstWidth, size.y), gap)
    else:
      let available = max(0.0'f32, size.y - gap)
      let firstHeight = floor(available * node.ratio + 0.5'f32)
      dock.layoutDockNode(first, pos, vec2(size.x, firstHeight), gap)
      dock.layoutDockNode(second, pos + vec2(0.0'f32, firstHeight + gap),
        vec2(size.x, available - firstHeight), gap)
  elif firstVisible:
    dock.layoutDockNode(first, pos, size, gap)
  elif secondVisible:
    dock.layoutDockNode(second, pos, size, gap)

proc computeDockRects(dock: DockSpace, gap: float32) =
  dock.rects = newSeq[DockRect](dock.layout.nodes.len)
  if dock.isVisibleDockNode(dock.layout.root):
    dock.layoutDockNode(dock.layout.root, vec2(0.0'f32), dock.bounds, gap)

proc dockSideRect(pos, size: Vec2, side: DockSide, ratio: float32): (Vec2, Vec2) =
  case side
  of DockCenter: (pos, size)
  of DockLeft: (pos, vec2(size.x * ratio, size.y))
  of DockRight: (pos + vec2(size.x * (1.0'f32 - ratio), 0.0'f32), vec2(size.x * ratio, size.y))
  of DockTop: (pos, vec2(size.x, size.y * ratio))
  of DockBottom: (pos + vec2(0.0'f32, size.y * (1.0'f32 - ratio)), vec2(size.x, size.y * ratio))

proc makeDropTarget(target: string, side: DockSide, ratio: float32,
    pos, size: Vec2): DockDropTarget =
  let (previewPos, previewSize) = dockSideRect(pos, size, side, ratio)
  DockDropTarget(valid: true, target: target, side: side, ratio: ratio,
    previewPos: previewPos, previewSize: previewSize)

proc dockCenterSize(size: Vec2, terminal: bool): float32 =
  let extent = min(size.x, size.y)
  min(if terminal: 4.0'f32 else: 100.0'f32, extent / 3.0'f32)

proc dockEdgeSize(size: Vec2, terminal: bool): float32 =
  # Cap edge bands so even small panes retain a floating gap around the center.
  min(if terminal: 10.0'f32 else: 100.0'f32, min(size.x, size.y) * 0.25'f32)

proc isCenterDrop(local, size: Vec2, terminal: bool): bool =
  let square = dockCenterSize(size, terminal)
  let offset = local - size * 0.5'f32
  square > 0 and abs(offset.x) <= square * 0.5'f32 and
    abs(offset.y) <= square * 0.5'f32

proc relativeDropSide(local, size: Vec2, terminal: bool, side: var DockSide): bool =
  if isCenterDrop(local, size, terminal):
    side = DockCenter
    return true
  let edge = dockEdgeSize(size, terminal)
  let distances = [local.x, size.x - local.x, local.y, size.y - local.y]
  var nearest = distances[0]
  for i in 1 ..< distances.len:
    nearest = min(nearest, distances[i])
  if nearest >= edge:
    return false
  if nearest == distances[0]:
    side = DockLeft
  elif nearest == distances[1]:
    side = DockRight
  elif nearest == distances[2]:
    side = DockTop
  else:
    side = DockBottom
  true

proc computeDropTarget(dock: DockSpace, mouse: Vec2, terminal: bool): DockDropTarget =
  ## Drop target for `dock.dragWindow` at `mouse` (window space coordinates).
  result = DockDropTarget()
  if mouse.x < 0 or mouse.y < 0 or mouse.x >= dock.bounds.x or mouse.y >= dock.bounds.y:
    return
  if not dock.isVisibleDockNode(dock.layout.root):
    if isCenterDrop(mouse, dock.bounds, terminal):
      return makeDropTarget("", DockCenter, 1.0'f32, vec2(0.0'f32), dock.bounds)
    return

  let edge = min(if terminal: 2.0'f32 else: 32.0'f32,
    min(dock.bounds.x, dock.bounds.y) * 0.125'f32)
  let rootRatio = 0.25'f32
  if mouse.x < edge:
    return makeDropTarget("", DockLeft, rootRatio, vec2(0.0'f32), dock.bounds)
  if mouse.x >= dock.bounds.x - edge:
    return makeDropTarget("", DockRight, rootRatio, vec2(0.0'f32), dock.bounds)
  if mouse.y < edge:
    return makeDropTarget("", DockTop, rootRatio, vec2(0.0'f32), dock.bounds)
  if mouse.y >= dock.bounds.y - edge:
    return makeDropTarget("", DockBottom, rootRatio, vec2(0.0'f32), dock.bounds)

  for index in 0 ..< dock.layout.nodes.len:
    let node = dock.layout.nodes[index].addr
    if node.kind != DockNodeTabs or index >= dock.rects.len or not dock.rects[index].visible:
      continue
    let rect = dock.rects[index]
    let local = mouse - rect.pos
    if local.x < 0 or local.y < 0 or local.x >= rect.size.x or local.y >= rect.size.y:
      continue
    let target = dock.visibleActiveWindow(index)
    if target.len == 0:
      continue
    var side = DockCenter
    if relativeDropSide(local, rect.size, terminal, side):
      return makeDropTarget(target, side, 0.5'f32, rect.pos, rect.size)
    return

# Dock interaction, run at the start of the frame before windows are built

proc clampFloatingSize(b: UiBuilder, dock: DockSpace, size: Vec2): Vec2 =
  let minSize = b.windowMetrics().minSize
  let maxSize = vec2(max(minSize.x, dock.bounds.x * 0.6'f32), max(minSize.y, dock.bounds.y * 0.6'f32))
  vec2(clamp(size.x, minSize.x, maxSize.x), clamp(size.y, minSize.y, maxSize.y))

proc distance(a, b: Vec2): float32 =
  let d = a - b
  sqrt(d.x * d.x + d.y * d.y)

proc updateDockTabs(b: var UiBuilder, dock: DockSpace, storage: WindowSpaceStorage, mouse: Vec2) =
  let input = b.frameCtx.input
  var pressedTab = ""
  var heldTab = ""
  for title in dock.layout.dockedWindows:
    let id = dockTabId(title)
    if b.previousOutput.pressedId == id:
      pressedTab = title
    if b.previousOutput.heldId == id:
      heldTab = title

  if pressedTab.len > 0:
    dock.layout.activateTab(pressedTab)
    dock.tabPressTitle = pressedTab
    dock.tabPressPos = mouse
    let tabs = dock.layout.findTabs(pressedTab)
    dock.tabPressOffset =
      if tabs < dock.rects.len: mouse - dock.rects[tabs].pos
      else: vec2(0.0'f32)
  elif MouseLeft notin input.mouseDown:
    dock.tabPressTitle = ""

  if heldTab.len == 0 or heldTab != dock.tabPressTitle or MouseLeft notin input.mouseDown:
    return
  if distance(mouse, dock.tabPressPos) <= dockTabDragThreshold:
    return

  # Dragging a tab out of its group undocks the window.
  let tabs = dock.layout.findTabs(heldTab)
  let leafSize =
    if tabs >= 0 and tabs < dock.rects.len: dock.rects[tabs].size
    else: vec2(400.0'f32, 300.0'f32)
  let size = b.clampFloatingSize(dock, leafSize)
  let grab = vec2(min(dock.tabPressOffset.x, size.x * 0.5'f32), min(dock.tabPressOffset.y, 8.0'f32))
  dock.layout.floatWindow(heldTab, mouse - grab, size)
  dock.dragWindow = heldTab
  dock.dragStart = dock.tabPressPos
  dock.dragMoved = true
  dock.tabPressTitle = ""
  storage.markWindowActive(heldTab.hashChars.UiNodeId, true)

proc updateDockSplitters(b: var UiBuilder, dock: DockSpace, mouse: Vec2, gap: float32) =
  if MouseLeft notin b.frameCtx.input.mouseDown:
    return
  for index in 0 ..< min(dock.layout.nodes.len, dock.rects.len):
    let node = dock.layout.nodes[index]
    if node.kind != DockNodeSplit or not dock.rects[index].visible:
      continue
    if b.previousOutput.heldId != dockSplitterId(index):
      continue
    let rect = dock.rects[index]
    let (extent, offset) =
      if node.axis == DockAxisX: (rect.size.x, mouse.x - rect.pos.x)
      else: (rect.size.y, mouse.y - rect.pos.y)
    let available = extent - gap
    if available <= 0:
      continue
    let minFraction = min(0.5'f32, dockMinPaneSize / available)
    dock.layout.nodes[index].ratio = clamp((offset - gap * 0.5'f32) / available,
      minFraction, 1.0'f32 - minFraction)

proc updateDockDrag(b: var UiBuilder, dock: DockSpace, mouse: Vec2) =
  let input = b.frameCtx.input
  dock.dropTarget = DockDropTarget()
  if dock.dragWindow.len == 0:
    return
  if dock.layout.findFloating(dock.dragWindow) < 0:
    dock.dragWindow = ""
    return
  if distance(mouse, dock.dragStart) > dockTabDragThreshold:
    dock.dragMoved = true
  # Holding shift moves a floating window without docking it.
  let docking = dock.dragMoved and ModShift notin input.modsDown
  let target =
    if docking: dock.computeDropTarget(mouse, b.backendType == UiBackendType.Terminal)
    else: DockDropTarget()
  if MouseLeft in input.mouseDown:
    dock.dropTarget = target
    b.anythingAnimating = true
    return
  if target.valid:
    dock.layout.dockWindow(dock.dragWindow, target.target, target.side, target.ratio)
  dock.dragWindow = ""
  dock.dragMoved = false

proc buildDockChrome(b: var UiBuilder, dock: DockSpace, storage: WindowSpaceStorage, gap: float32) =
  let accent = b.themeStyle(UiStyleIndexAccent)[].borderColor
  let terminal = b.backendType == UiBackendType.Terminal
  b.node("dock-chrome"):
    storage.dockChromeId = b.currentNode.id
    discard b.fill().noHover()
    for index in 0 ..< min(dock.layout.nodes.len, dock.rects.len):
      let node = dock.layout.nodes[index]
      if node.kind != DockNodeSplit or not dock.rects[index].visible:
        continue
      let first = node.children[0]
      let second = node.children[1]
      if not (dock.rects[first].visible and dock.rects[second].visible):
        continue
      let rect = dock.rects[index]
      let grow = if terminal: 0.0'f32 else: 1.0'f32
      let (pos, size) =
        if node.axis == DockAxisX:
          let x = dock.rects[first].pos.x + dock.rects[first].size.x
          (vec2(x - grow, rect.pos.y), vec2(gap + grow * 2.0'f32, rect.size.y))
        else:
          let y = dock.rects[first].pos.y + dock.rects[first].size.y
          (vec2(rect.pos.x, y - grow), vec2(rect.size.x, gap + grow * 2.0'f32))
      b.nodeWithId(dockSplitterId(index)):
        discard b.position(pos).size(size)
        if b.wasHovered() or b.previousOutput.heldId == b.currentNode.id:
          discard b.backgroundColor(accent).fillBackground()

proc buildDockAreas(b: var UiBuilder, dock: DockSpace, storage: WindowSpaceStorage) =
  let input = b.frameCtx.input
  if not dock.isDragging or MouseLeft notin input.mouseDown or ModShift in input.modsDown:
    return
  let mouse = input.mouse - dock.origin
  if mouse.x < 0 or mouse.y < 0 or mouse.x >= dock.bounds.x or mouse.y >= dock.bounds.y:
    return
  var hovered = DockRect()
  let empty = not dock.isVisibleDockNode(dock.layout.root)
  if empty:
    hovered = DockRect(size: dock.bounds, visible: true)
  else:
    for index in 0 ..< dock.layout.nodes.len:
      let node = dock.layout.nodes[index].addr
      if node.kind != DockNodeTabs or index >= dock.rects.len or not dock.rects[index].visible:
        continue
      let rect = dock.rects[index]
      let local = mouse - rect.pos
      if local.x >= 0 and local.y >= 0 and local.x < rect.size.x and local.y < rect.size.y:
        hovered = rect
        break
  if not hovered.visible:
    return
  let terminal = b.backendType == UiBackendType.Terminal
  let accent = b.themeStyle(UiStyleIndexAccent)[].borderColor
  let dark = UiColor(r: accent.r * 0.5'f32, g: accent.g * 0.5'f32,
    b: accent.b * 0.5'f32, a: accent.a)
  let square = dockCenterSize(hovered.size, terminal)
  let edge = dockEdgeSize(hovered.size, terminal)
  b.node("dock-drop-areas"):
    storage.dockAreasId = b.currentNode.id
    discard b.fill().noHover().noChildHover()
    for side in [DockCenter, DockLeft, DockRight, DockTop, DockBottom]:
      if empty and side != DockCenter:
        continue
      let (pos, size) =
        case side
        of DockCenter:
          (hovered.pos + (hovered.size - vec2(square)) * 0.5'f32, vec2(square))
        of DockLeft:
          (hovered.pos, vec2(edge, hovered.size.y))
        of DockRight:
          (hovered.pos + vec2(hovered.size.x - edge, 0.0'f32), vec2(edge, hovered.size.y))
        of DockTop:
          (hovered.pos + vec2(edge, 0.0'f32), vec2(hovered.size.x - edge * 2, edge))
        of DockBottom:
          (hovered.pos + vec2(edge, hovered.size.y - edge), vec2(hovered.size.x - edge * 2, edge))
      b.node:
        discard b.position(pos).size(size).noHover().noChildHover()
        discard b.backgroundColor(UiColor(r: dark.r, g: dark.g, b: dark.b, a: dark.a * 0.3'f32))
        discard b.fillBackground().borderColor(dark).borderWidth(if terminal: 1.0'f32 else: 2.0'f32)

proc buildDockPreview(b: var UiBuilder, dock: DockSpace, storage: WindowSpaceStorage) =
  if not dock.dropTarget.valid:
    return
  let accent = b.themeStyle(UiStyleIndexAccent)[].borderColor
  b.node("dock-preview"):
    storage.dockPreviewId = b.currentNode.id
    discard b.position(dock.dropTarget.previewPos).size(dock.dropTarget.previewSize)
    discard b.noHover().noChildHover()
    discard b.backgroundColor(UiColor(r: accent.r, g: accent.g, b: accent.b, a: accent.a * 0.3'f32))
    discard b.fillBackground()
    discard b.borderColor(accent).borderWidth(if b.backendType == UiBackendType.Terminal: 1.0'f32 else: 2.0'f32)

proc updateDockSpace(b: var UiBuilder, dock: DockSpace, storage: WindowSpaceStorage, spaceIdx: int) =
  prof("updateDockSpace")
  dock.origin = b.absoluteNodePos(spaceIdx)
  dock.bounds = b.nodes[spaceIdx].size
  if dock.initialized:
    dock.visibleWindows = dock.submitted
  else:
    dock.visibleWindows = toSeq(dock.layout.dockedWindows)
    dock.initialized = true
  dock.submitted = @[]

  let gap = b.dockGap()
  let mouse = b.frameCtx.input.mouse - dock.origin
  # Interaction uses the geometry that was on screen last frame.
  b.updateDockTabs(dock, storage, mouse)
  b.updateDockSplitters(dock, mouse, gap)
  dock.computeDockRects(gap)
  b.updateDockDrag(dock, mouse)
  dock.computeDockRects(gap)

  b.buildDockChrome(dock, storage, gap)
  b.buildDockAreas(dock, storage)
  b.buildDockPreview(dock, storage)

proc windowSpace*(b: var UiBuilder, dock: DockSpace = nil) =
  ## Create the window space that hosts `window`s. When `dock` is given, its
  ## layout decides which windows are docked and which are floating.
  let dockSpace = dock
  b.node("windows"):
    discard b.fillX().fillY().noHover()
    b.windows = b.currentNode.id
    let storage = b.getOrCreateWindowSpaceStorage(b.currentNode)
    storage.dock = dockSpace
    storage.dockChromeId = noneNodeId()
    storage.dockAreasId = noneNodeId()
    storage.dockPreviewId = noneNodeId()
    if dockSpace != nil:
      b.updateDockSpace(dockSpace, storage, b.stack[^1])
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
    if previousNodeIndex < 0 and not storage.docked:
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
    titleBarId != noneNodeId() and b.previousOutput.heldId == titleBarId
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

proc resolveWindowPlacement(b: var UiBuilder, dock: DockSpace, title: string,
    storage: WindowStorage, metrics: WindowMetrics): WindowPlacement =
  ## Decide where the window goes this frame. In a dock space the layout is
  ## the source of truth, including the geometry of floating windows.
  storage.docked = false
  if dock == nil:
    return WindowFloating

  let tabs = dock.layout.findTabs(title)
  if tabs < 0:
    let floating = dock.layout.findFloating(title)
    if floating < 0:
      dock.layout.floating.add DockFloatingWindow(title: title,
        pos: storage.pos, size: storage.size, collapsed: storage.collapsed)
    else:
      let state = dock.layout.floating[floating]
      storage.pos = state.pos
      storage.size = vec2(max(metrics.minSize.x, state.size.x), max(metrics.minSize.y, state.size.y))
      storage.collapsed = state.collapsed
    return WindowFloating

  storage.docked = true
  storage.collapsed = false
  storage.resizeEdges = {}
  if tabs < dock.rects.len and dock.rects[tabs].visible and
      dock.visibleActiveWindow(tabs) == title:
    storage.pos = dock.rects[tabs].pos
    storage.size = dock.rects[tabs].size
    return WindowDocked
  if title notin dock.visibleWindows:
    # Newly submitted; the layout makes room for it next frame.
    b.anythingAnimating = true
  WindowHidden

proc configureHiddenWindowNode(b: var UiBuilder) =
  discard b.position(vec2(0.0'f32)).size(0.0'f32, 0.0'f32)
  discard b.noHover().noChildHover()

proc buildWindowTitleBar(b: var UiBuilder, title: string, storage: WindowStorage,
    windowCornerRadii: UiCornerRadii): UiNodeId =
  b.node("window-title-bar"):
    result = b.currentNode.id
    discard b.copyStyleIndex(UiStyleIndexWindowTitleBar)
    discard b.copyTextStyleIndex(UiStyleIndexWindowTitleBarText)
    let titleBarStyle = b.currentNodeStyle()
    titleBarStyle.cornerRadius = 0.0'f32
    titleBarStyle.cornerRadii = UiCornerRadii(
      topLeft: windowCornerRadii.topLeft,
      topRight: windowCornerRadii.topRight,
    )
    if storage.collapsed:
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
        discard b.text(if storage.collapsed: "+" else: "-")

    if b.previousOutput.clickedId == collapseBtnId:
      storage.collapsed = not storage.collapsed

proc buildDockTabBar(b: var UiBuilder, dock: DockSpace, title: string) =
  ## Tab bar shown instead of the title bar of a docked window. It lists the
  ## visible windows of the tab group; dragging a tab undocks its window.
  let terminal = b.backendType == UiBackendType.Terminal
  b.node("dock-tab-bar"):
    discard b.styleIndex(UiStyleIndexTabBarHeader)
    let style = b.currentNodeStyle()
    style.cornerRadius = 0.0'f32
    style.cornerRadii = default(UiCornerRadii)
    if terminal:
      discard b.padding(0).gap(1)
    else:
      discard b.gap(4)
    discard b.fillX().fitY()
    discard b.flexLayout(true).flexFlow(FlexDirectionRow, FlexNoWrap)
    discard b.fillBackground().maskChildren()
    let tabs = dock.layout.findTabs(title)
    let tabTitles = if tabs >= 0: dock.layout.nodes[tabs].windows else: @[title]
    for tabTitle in tabTitles:
      if tabTitle != title and tabTitle notin dock.visibleWindows:
        continue
      let active = tabTitle == title
      b.nodeWithId(dockTabId(tabTitle)):
        discard b.styleIndex(if active: UiStyleIndexTabBarItemActive else: UiStyleIndexTabBarItem)
        discard b.copyTextStyleIndex(if active: UiStyleIndexTabBarItemActiveText else: UiStyleIndexTabBarItemText)
        if terminal:
          discard b.padding(0).borderWidth(0)
        discard b.fitX().fitY().fillBackground()
        discard b.text(tabTitle)

proc finishWindow(b: var UiBuilder, dock: DockSpace, title: string,
    storage: WindowStorage, placement: WindowPlacement, windowNodeIndex: int,
    titleBarId: UiNodeId, metrics: WindowMetrics) =
  if placement == WindowFloating:
    var dragTitleBarId = titleBarId
    if dock != nil:
      # Dock spaces track title bar drags themselves so a drag can continue
      # after undocking a tab and end by docking the window.
      dragTitleBarId = noneNodeId()
      let input = b.frameCtx.input
      if titleBarId != noneNodeId() and b.previousOutput.pressedId == titleBarId:
        dock.dragWindow = title
        dock.dragStart = input.mouse - dock.origin
        dock.dragMoved = false
      if dock.dragWindow == title and MouseLeft in input.mouseDown:
        storage.pos += input.mouseDelta
        discard b.position(storage.pos)

    let highlightedEdges = b.updateWindowInteraction(
      storage, windowNodeIndex, dragTitleBarId, metrics.edgeDistance,
      metrics.minSize.x, metrics.minSize.y)
    b.applyWindowResizeHighlight(highlightedEdges)

    if dock != nil:
      let floating = dock.layout.findFloating(title)
      if floating >= 0:
        dock.layout.floating[floating].pos = storage.pos
        dock.layout.floating[floating].size = storage.size
        dock.layout.floating[floating].collapsed = storage.collapsed

  if dock != nil:
    if title notin dock.submitted:
      dock.submitted.add title
  b.updateWindowSpaceActivity(windowNodeIndex)

template window*(b: var UiBuilder, title: string, inX, inY, width, height: float32, body: untyped): untyped =
  ## A window inside the current window space. Without a dock space it floats
  ## at its stored geometry, initialized from `inX`, `inY`, `width` and
  ## `height`. With a dock space, the dock layout decides whether it is
  ## floating, docked, or hidden behind another tab; the body is only built
  ## when the window is shown.
  b.withParent(b.windows):
    prof("window")
    let windowMetrics = b.windowMetrics()

    b.nodeWithId(title.hashChars.UiNodeId):
      b.nodeStorageParent()
      let windowNodeIndex = b.stack[^1]
      let windowStorage = getOrCreateWindowStorage(b, b.currentNode,
        vecmath.vec2(inX, inY),
        vecmath.vec2(max(windowMetrics.minSize.x, width), max(windowMetrics.minSize.y, height)))
      let windowDock = b.currentDockSpace()
      let placement = b.resolveWindowPlacement(windowDock, title, windowStorage, windowMetrics)
      var titleBarId = noneNodeId()

      if placement == WindowHidden:
        b.configureHiddenWindowNode()
      else:
        b.configureWindowNode(windowStorage)
        if placement == WindowDocked:
          let windowStyle = b.currentNodeStyle()
          windowStyle.cornerRadius = 0.0'f32
          windowStyle.cornerRadii = default(UiCornerRadii)
        if b.backendType == UiBackendType.Terminal:
          discard b.padding(1)

        let windowCornerRadii = b.currentNodeStyle()[].resolvedCornerRadii
        let resizeEdgeDistance = windowMetrics.edgeDistance

        b.node("window-resize"):
          if placement == WindowFloating:
            discard b.anchors(0, 0, 1, 1).offsets(-resizeEdgeDistance, -resizeEdgeDistance, resizeEdgeDistance, resizeEdgeDistance).finishAnchors()
          else:
            discard b.noHover()

        b.layoutVertical:
          if windowStorage.collapsed:
            discard b.fillX().fitY()
          else:
            discard b.fill()

          if placement == WindowDocked:
            if windowDock == nil:
              quit "docked placement requires a dock space"
            b.buildDockTabBar(windowDock, title)
          else:
            titleBarId = b.buildWindowTitleBar(title, windowStorage, windowCornerRadii)

          if not windowStorage.collapsed:
            b.node("window-content"):
              discard b.styleIndex(UiStyleIndexWindowContent)
              discard b.fillX().fillY().maskChildren()
              body

      b.finishWindow(windowDock, title, windowStorage, placement,
        windowNodeIndex, titleBarId, windowMetrics)
