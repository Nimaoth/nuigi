## Serializable docking layout used by docking window spaces.
##
## The layout is plain data keyed by window title so it can be saved and
## restored independently of node IDs. Docked windows live in a binary tree of
## split nodes whose leaves are tab groups; floating windows keep their own
## geometry. Nodes are stored in a flat array and reference each other by
## index; removed nodes become `DockNodeFree` and are reused.

import std/[parseutils, strutils]
import nuigi/core/vecmath

type
  DockAxis* = enum
    DockAxisX ## Children are placed side by side.
    DockAxisY ## Children are stacked vertically.

  DockSide* = enum
    DockCenter ## Add as a tab to the target.
    DockLeft
    DockRight
    DockTop
    DockBottom

  DockNodeKind* = enum
    DockNodeFree
    DockNodeSplit
    DockNodeTabs

  DockNode* = object
    kind*: DockNodeKind
    parent*: int
    axis*: DockAxis
    ratio*: float32
      ## Fraction of a split's extent given to `children[0]`.
    children*: array[2, int]
    windows*: seq[string]
      ## Window titles of a tab group, in tab order.
    activeTab*: int

  DockFloatingWindow* = object
    title*: string
    pos*: Vec2
    size*: Vec2
    collapsed*: bool

  DockLayout* = object
    nodes*: seq[DockNode]
    root*: int = -1
    floating*: seq[DockFloatingWindow]

const dockLayoutHeader = "nuigi-dock-layout 1"

proc parseDockInt(value: string, parsed: var int): bool =
  if value.len == 0:
    return false
  var number: BiggestInt = 0
  let consumed = parseutils.parseBiggestInt(value.toOpenArray(0, value.high), number)
  if consumed != value.len or number < BiggestInt(low(int)) or
      number > BiggestInt(high(int)):
    return false
  parsed = int(number)
  true

proc parseDockFloat(value: string, parsed: var float32): bool =
  if value.len == 0:
    return false
  var number: BiggestFloat = 0.0
  let consumed = parseutils.parseBiggestFloat(value.toOpenArray(0, value.high), number)
  if consumed != value.len:
    return false
  parsed = float32(number)
  true

proc initDockLayout*(): DockLayout =
  DockLayout(root: -1)

proc isEmpty*(layout: DockLayout): bool =
  layout.root < 0

proc findTabs*(layout: DockLayout, title: string): int =
  ## Index of the tab group containing `title`, or -1.
  for index, node in layout.nodes:
    if node.kind == DockNodeTabs and title in node.windows:
      return index
  -1

proc findFloating*(layout: DockLayout, title: string): int =
  ## Index into `floating` for `title`, or -1.
  for index, window in layout.floating:
    if window.title == title:
      return index
  -1

proc isDocked*(layout: DockLayout, title: string): bool =
  layout.findTabs(title) >= 0

proc contains*(layout: DockLayout, title: string): bool =
  layout.findTabs(title) >= 0 or layout.findFloating(title) >= 0

iterator dockedWindows*(layout: DockLayout): string =
  for node in layout.nodes:
    if node.kind == DockNodeTabs:
      for title in node.windows:
        yield title

proc firstLeaf*(layout: DockLayout, index: int): int =
  ## First tab group below `index` following `children[0]`.
  var current = index
  while current >= 0 and layout.nodes[current].kind == DockNodeSplit:
    current = layout.nodes[current].children[0]
  current

proc addNode(layout: var DockLayout, node: DockNode): int =
  for index in 0 ..< layout.nodes.len:
    if layout.nodes[index].kind == DockNodeFree:
      layout.nodes[index] = node
      return index
  layout.nodes.add node
  layout.nodes.high

proc freeNode(layout: var DockLayout, index: int) =
  layout.nodes[index] = DockNode(kind: DockNodeFree, parent: -1,
    children: [-1, -1])

proc replaceChild(layout: var DockLayout, parent, oldChild, newChild: int) =
  if parent < 0:
    layout.root = newChild
  else:
    for slot in 0 .. 1:
      if layout.nodes[parent].children[slot] == oldChild:
        layout.nodes[parent].children[slot] = newChild
  if newChild >= 0:
    layout.nodes[newChild].parent = parent

proc removeTabs(layout: var DockLayout, index: int) =
  ## Remove an empty tab group and collapse its parent split.
  let parent = layout.nodes[index].parent
  layout.freeNode(index)
  if parent < 0:
    layout.root = -1
    return
  let split = layout.nodes[parent]
  let sibling =
    if split.children[0] == index: split.children[1]
    else: split.children[0]
  layout.replaceChild(split.parent, parent, sibling)
  layout.freeNode(parent)

proc removeWindow*(layout: var DockLayout, title: string) =
  ## Remove a window from the dock tree and the floating list.
  let tabs = layout.findTabs(title)
  if tabs >= 0:
    let position = layout.nodes[tabs].windows.find(title)
    layout.nodes[tabs].windows.delete(position)
    if layout.nodes[tabs].windows.len == 0:
      layout.removeTabs(tabs)
    elif layout.nodes[tabs].activeTab >= position:
      layout.nodes[tabs].activeTab = max(0, layout.nodes[tabs].activeTab - 1)
  let floating = layout.findFloating(title)
  if floating >= 0:
    layout.floating.delete(floating)

proc activateTab*(layout: var DockLayout, title: string) =
  let tabs = layout.findTabs(title)
  if tabs >= 0:
    layout.nodes[tabs].activeTab = layout.nodes[tabs].windows.find(title)

proc dockWindow*(layout: var DockLayout, title: string, target = "",
    side = DockCenter, ratio = 0.5'f32) =
  ## Dock `title` relative to the tab group containing `target`, or relative
  ## to the whole dock space when `target` is empty or not docked. `ratio` is
  ## the fraction of the target's extent given to the new window for side
  ## docking. A window that is already part of the layout is moved.
  if title.len == 0 or title == target:
    return
  layout.removeWindow(title)
  if layout.root < 0:
    layout.root = layout.addNode(DockNode(kind: DockNodeTabs, parent: -1,
      windows: @[title], children: [-1, -1]))
    return

  var targetIndex = if target.len > 0: layout.findTabs(target) else: -1
  if side == DockCenter:
    if targetIndex < 0:
      targetIndex = layout.firstLeaf(layout.root)
    layout.nodes[targetIndex].windows.add title
    layout.nodes[targetIndex].activeTab = layout.nodes[targetIndex].windows.high
    return

  if targetIndex < 0:
    targetIndex = layout.root
  let newTabs = layout.addNode(DockNode(kind: DockNodeTabs,
    windows: @[title], children: [-1, -1]))
  let newFirst = side in {DockLeft, DockTop}
  let fraction = clamp(ratio, 0.05'f32, 0.95'f32)
  let parent = layout.nodes[targetIndex].parent
  let split = layout.addNode(DockNode(kind: DockNodeSplit,
    axis: if side in {DockLeft, DockRight}: DockAxisX else: DockAxisY,
    ratio: if newFirst: fraction else: 1.0'f32 - fraction,
    children: if newFirst: [newTabs, targetIndex] else: [targetIndex, newTabs]))
  layout.replaceChild(parent, targetIndex, split)
  layout.nodes[targetIndex].parent = split
  layout.nodes[newTabs].parent = split

proc floatWindow*(layout: var DockLayout, title: string, pos, size: Vec2,
    collapsed = false) =
  ## Make `title` a floating window with the given geometry.
  layout.removeWindow(title)
  layout.floating.add DockFloatingWindow(title: title, pos: pos, size: size,
    collapsed: collapsed)

# Serialization: one record per line. The tree is written in pre-order, every
# split followed by its two children; window titles occupy the rest of a line.

proc serializeNode(layout: DockLayout, index: int, output: var string) =
  if index < 0:
    output.add "empty\n"
    return
  let node = layout.nodes[index]
  case node.kind
  of DockNodeSplit:
    output.add "split " & (if node.axis == DockAxisX: "x" else: "y") & " " &
      $node.ratio & "\n"
    layout.serializeNode(node.children[0], output)
    layout.serializeNode(node.children[1], output)
  of DockNodeTabs:
    output.add "tabs " & $node.activeTab & " " & $node.windows.len & "\n"
    for title in node.windows:
      output.add "window " & title & "\n"
  of DockNodeFree:
    output.add "empty\n"

proc serialize*(layout: DockLayout): string =
  ## Serialize the layout to a line-based text format readable by
  ## `parseDockLayout`.
  result = dockLayoutHeader & "\n"
  layout.serializeNode(layout.root, result)
  for window in layout.floating:
    result.add "floating " & $window.pos.x & " " & $window.pos.y & " " &
      $window.size.x & " " & $window.size.y & " " &
      (if window.collapsed: "1" else: "0") & " " & window.title & "\n"

proc parseNode(layout: var DockLayout, lines: seq[string], line: var int,
    parent: int): tuple[ok: bool, index: int] =
  if line >= lines.len:
    return (false, -1)
  let parts = lines[line].split(' ', maxsplit = 3)
  inc line
  case parts[0]
  of "empty":
    return (true, -1)
  of "split":
    if parts.len < 3 or parts[1] notin ["x", "y"]:
      return (false, -1)
    var ratio = 0.0'f32
    if not parseDockFloat(parts[2], ratio):
      return (false, -1)
    let index = layout.addNode(DockNode(kind: DockNodeSplit, parent: parent,
      axis: if parts[1] == "x": DockAxisX else: DockAxisY,
      ratio: clamp(ratio, 0.0'f32, 1.0'f32),
      children: [-1, -1]))
    for slot in 0 .. 1:
      let child = layout.parseNode(lines, line, index)
      if not child.ok or child.index < 0:
        return (false, -1)
      layout.nodes[index].children[slot] = child.index
    return (true, index)
  of "tabs":
    if parts.len < 3:
      return (false, -1)
    var count = 0
    var activeTab = 0
    if not parseDockInt(parts[1], activeTab) or not parseDockInt(parts[2], count):
      return (false, -1)
    var node = DockNode(kind: DockNodeTabs, parent: parent,
      activeTab: activeTab, children: [-1, -1])
    for _ in 0 ..< count:
      if line >= lines.len or not lines[line].startsWith("window "):
        return (false, -1)
      node.windows.add lines[line]["window ".len .. ^1]
      inc line
    if node.windows.len == 0:
      return (false, -1)
    node.activeTab = clamp(node.activeTab, 0, node.windows.high)
    return (true, layout.addNode(node))
  else:
    return (false, -1)

proc parseDockLayout*(text: string, layout: var DockLayout): bool =
  ## Parse a layout produced by `serialize`. Returns false and leaves
  ## `layout` untouched when the text is malformed.
  var lines: seq[string] = @[]
  for line in text.splitLines():
    if line.len > 0:
      lines.add line
  if lines.len < 2 or lines[0] != dockLayoutHeader:
    return false
  var parsed = initDockLayout()
  var line = 1
  let root = parsed.parseNode(lines, line, -1)
  if not root.ok:
    return false
  parsed.root = root.index
  while line < lines.len:
    let parts = lines[line].split(' ', maxsplit = 6)
    inc line
    if parts.len < 7 or parts[0] != "floating":
      return false
    var x, y, width, height = 0.0'f32
    if not parseDockFloat(parts[1], x) or not parseDockFloat(parts[2], y) or
        not parseDockFloat(parts[3], width) or not parseDockFloat(parts[4], height):
      return false
    parsed.floating.add DockFloatingWindow(title: parts[6],
      pos: vec2(x, y), size: vec2(width, height),
      collapsed: parts[5] == "1")
  layout = parsed
  true
