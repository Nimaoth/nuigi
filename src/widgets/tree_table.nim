import nuigi
import mymath
import mesh
import arena, array_view

import widgets
import dynamic_virtuallist, profiler

include compat2

# A cursor identifies a node within a value tree and can be navigated with the
# moveNext/enterChild/exitChild/movePrev methods. Concrete types subclass it.
type
  TreeCursor* = ref object of RootRef
    fieldName*: string
    index*: int
    path*: seq[int]

  # A cached expanded node. Only expanded nodes live in `TreeTable.nodes`;
  # each serves as an anchor from which any visible row can be reached by seeking
  # forward through the cursor.
  ExpandedNode* = object
    cursor*: TreeCursor
    childIndex*: int
    depth*: int
    childCount*: int
    totalChildren*: int

  # Per-instance state for one tree table, kept in the builder's node storage.
  TreeTable* = ref object of UiNodeStorageData
    cursor*: TreeCursor
    nodes*: seq[ExpandedNode]
    initialized*: bool
    pendingToggleCursor*: TreeCursor
    walkCursor*: TreeCursor
    walkIndex*: int
    walkNode*: int # Index into TreeTable.nodes which is the walkCursors ExpandedNode or the parents ExpandedNode
    nodesIndex: int # Index into nodes where we currently are while rendering items
    searchFilter*: string
    scrollOffset*: Vec2
    rowRenderer: TreeTableRowRenderer

  TreeTableRowRenderer* = proc(b: var UiBuilder, cursor: TreeCursor, index: int) {.canRaise, nimcall.}

  TreeTableOptions* = object
    ## Options for `treeTable`. All fields have sensible defaults; use
    ## `defaultTreeTableOptions()` or a struct literal and override what you need.
    columns*: seq[TableColumn]
      ## Per-logical-column sizing (logical 0 = combined indent+name, logical N>=1 = physical N+1).
      ## Same semantics as `widgets.tableColumn*` – Fixed/Fit/Fill/Proportional.
    columnGap*: float32
      ## Gap between logical columns (also the gap between indent and name inside logical 0).
    showColumnLines*: bool
      ## When true, vertical separator lines are drawn between logical columns.
    columnLineThickness*: float32
      ## Thickness of the vertical lines (px). Clamped to >= 1.
    columnLineColor*: UiColor
      ## Color of the vertical lines. When `hasCustomLineColor` is false the theme's
      ## border color (`UiStyleIndexPanel` / `grayBorder`) is used.
    hasCustomLineColor*: bool
    showIndentationLines*: bool
      ## When true, one vertical line per indentation level (depth) is drawn inside
      ## the indent area. Lines span the full row height and thus connect across
      ## neighboring rows that share the same depth level.
    indentationLineThickness*: float32
      ## Thickness of indentation lines (px).
    indentationLineColor*: UiColor
      ## Color of indentation lines. Falls back to theme border color when not custom.
    hasCustomIndentationLineColor*: bool
    indentationStep*: float32
      ## Horizontal distance per depth level (default 20). The indent spacer is
      ## `depth * indentationStep` wide; each guide is drawn centered in its step.

  TreeTableLayout* = object
    ## Internal layout payload passed as `userData` to `treeTableColumnLayout`.
    ## Mirrors `TreeTableOptions` but stores columns as an arena pointer for the layout pass.
    columnGap*: float32
    columnCount*: int
    columns*: ptr UncheckedArray[TableColumn]
    showColumnLines*: bool
    columnLineThickness*: float32
    columnLineColor*: UiColor
    hasCustomLineColor*: bool
    showIndentationLines*: bool
    indentationLineThickness*: float32
    indentationLineColor*: UiColor
    hasCustomIndentationLineColor*: bool
    indentationStep*: float32

func depth*(c: TreeCursor): int = c.path.len

proc defaultTreeTableOptions*(): TreeTableOptions =
  result = TreeTableOptions(
    columns: @[],
    columnGap: 4.0'f32,
    showColumnLines: false,
    columnLineThickness: 1.0'f32,
    columnLineColor: UiColor(r: 0, g: 0, b: 0, a: 0),
    hasCustomLineColor: false,
    showIndentationLines: false,
    indentationLineThickness: 1.0'f32,
    indentationLineColor: UiColor(r: 0, g: 0, b: 0, a: 0),
    hasCustomIndentationLineColor: false,
    indentationStep: 20.0'f32,
  )

proc initTreeTableOptions*(
    columns: openArray[TableColumn],
    columnGap: float32 = 4.0'f32,
    showColumnLines: bool = false,
    columnLineThickness: float32 = 1.0'f32,
    columnLineColor: UiColor = UiColor(r: 0, g: 0, b: 0, a: 0),
    hasCustomLineColor: bool = false,
    showIndentationLines: bool = false,
    indentationLineThickness: float32 = 1.0'f32,
    indentationLineColor: UiColor = UiColor(r: 0, g: 0, b: 0, a: 0),
    hasCustomIndentationLineColor: bool = false,
    indentationStep: float32 = 20.0'f32): TreeTableOptions =
  result.columns = @columns
  result.columnGap = columnGap
  result.showColumnLines = showColumnLines
  result.columnLineThickness = columnLineThickness
  result.columnLineColor = columnLineColor
  result.hasCustomLineColor = hasCustomLineColor or columnLineColor.a > 0.001'f32
  result.showIndentationLines = showIndentationLines
  result.indentationLineThickness = indentationLineThickness
  result.indentationLineColor = indentationLineColor
  result.hasCustomIndentationLineColor = hasCustomIndentationLineColor or indentationLineColor.a > 0.001'f32
  result.indentationStep = if indentationStep > 0.001'f32: indentationStep else: 20.0'f32

# Returns the editor state attached to `node`, creating it on first use.
proc getOrCreateStorage(b: var UiBuilder, node: ptr UiNode): TreeTable =
  let existing = nodeStorageGet(b, node)
  if existing != nil:
    return cast[TreeTable](existing)
  var storage = TreeTable()
  nodeStorage(b, node, storage)
  return storage

method clone*(c: TreeCursor): TreeCursor {.base.} =
  result = TreeCursor()
  result.fieldName = c.fieldName
  result.index = c.index
  result.path = c.path

# Unique identity of a node, used to match expansion state. Subtypes override
# this (e.g. a file system cursor returns its full path).
method cursorKey*(c: TreeCursor): string {.base.} =
  result = ""
  for i in c.path:
    result.add($i)
    result.add("/")

method moveNext*(c: TreeCursor, count: int = 1): bool {.base.} =
  false

method movePrev*(c: TreeCursor, count: int = 1): bool {.base.} =
  false

method childCount*(c: TreeCursor): int {.base.} =
  0

method enterChild*(c: TreeCursor): bool {.base.} =
  false

method exitChild*(c: TreeCursor): bool {.base.} =
  false

# True if the node under `c` is currently expanded (present in `nodes`).
proc nodeIsExpanded(e: TreeTable, c: TreeCursor, startIndex: int): bool =
  prof("nodeIsExpanded")
  let key = cursorKey(c)
  for i in startIndex..e.nodes.high:
    if cursorKey(e.nodes[i].cursor) == key:
      return true
  return false

# Advances `c` to the next visible row in preorder, descending into a node only
# when it is expanded.
proc stepForward(c: var TreeCursor, e: TreeTable, startIndex: int): bool =
  prof("stepForward")
  if nodeIsExpanded(e, c, startIndex) and c.enterChild():
    return true
  while true:
    if c.moveNext():
      return true
    if not c.exitChild():
      return false
    if c.moveNext():
      return true

iterator expandedChildren*(e: TreeTable, nodeIndex: int): (int, ptr ExpandedNode) =
  if nodeIndex < e.nodes.len:
    let parent {.cursor.} = e.nodes[nodeIndex]
    var i = nodeIndex + 1
    while i < e.nodes.len:
      let n = e.nodes[i].addr
      if n.depth <= parent.depth:
        break
      if n.depth == parent.depth + 1:
        yield (i, n)
      inc i

proc seek*(e: TreeTable, targetRow: int): bool =
  prof("seek")
  assert e.walkIndex == 0

  e.walkCursor = e.cursor.clone()
  e.walkIndex = 0
  e.walkNode = 0
  var targetChild = 0
  if targetRow > 0:
    var done = false
    while not done:
      done = true
      var totalChildrenBefore = 0
      var hasChildren = false
      for (i, n) in e.expandedChildren(e.walkNode):
        hasChildren = true
        let childOffset = n.childIndex + 1 + totalChildrenBefore
        if targetRow < e.walkIndex + childOffset:
          done = true
          targetChild = targetRow - (e.walkIndex + totalChildrenBefore + 1)
          break
        elif targetRow <= e.walkIndex + childOffset + n.totalChildren:
          e.walkCursor = n.cursor.clone()
          e.walkNode = i
          e.walkIndex += childOffset
          done = e.walkIndex == targetRow
          targetChild = targetRow - e.walkIndex - 1
          break
        else:
          totalChildrenBefore += n.totalChildren
          targetChild = targetRow - (e.walkIndex + childOffset + n.totalChildren) + n.childIndex

      if not hasChildren:
        targetChild = targetRow - e.walkIndex - 1

    # Step the remaining (usually short) distance from the anchor to the target.
    if e.walkIndex < targetRow:
      prof("slow step")
      if not e.walkCursor.enterChild():
        echo "failed to enter child ", e.walkIndex, " < ", targetRow, ", ", targetChild, ", ", e.walkCursor.path
        e.walkIndex = targetRow
        return false
      inc e.walkIndex
      if targetChild > 0:
        if not e.walkCursor.moveNext(targetChild):
          return false
  e.walkIndex = targetRow
  return true

# True if `a`'s path is a strict prefix of `b`'s path (i.e. `a` is an ancestor of `b`).
func isAncestorPath*(a, b: seq[int]): bool =
  if a.len >= b.len:
    return false
  for i in 0 ..< a.len:
    if a[i] != b[i]:
      return false
  return true

# True if `a` comes before `b` in a preorder traversal of the tree.
func preorderLess*(a, b: TreeCursor): bool =
  let n = min(a.path.len, b.path.len)
  for i in 0 ..< n:
    if a.path[i] != b.path[i]:
      return a.path[i] < b.path[i]
  return a.path.len < b.path.len

# Toggles the expansion state of the node under `cursor`. Expanding inserts the
# node into `nodes` at its preorder position; collapsing removes it and every
# descendant. `nodes` always stays sorted in preorder and downward-closed.
proc toggleNode*(e: var TreeTable, cursor: TreeCursor) =
  let key = cursorKey(cursor)
  var idx = -1
  for i in 0 .. e.nodes.high:
    if cursorKey(e.nodes[i].cursor) == key:
      idx = i
      break
  if idx >= 0:
    let collapseTotal = e.nodes[idx].totalChildren
    var depth = cursor.depth
    for i in 0..<idx:
      let parentIndex = idx - i - 1
      if e.nodes[parentIndex].cursor.depth == depth - 1:
        e.nodes[parentIndex].totalChildren -= collapseTotal
        dec depth
    var i = idx
    while i < e.nodes.len:
      let k = cursorKey(e.nodes[i].cursor)
      if k == key or isAncestorPath(cursor.path, e.nodes[i].cursor.path):
        e.nodes.delete(i)
      else:
        i += 1
  else:
    var ins = e.nodes.len
    for i in 0 .. e.nodes.high:
      if not preorderLess(e.nodes[i].cursor, cursor):
        ins = i
        break
    let childCount = cursor.childCount()
    e.nodes.insert(ExpandedNode(
      cursor: cursor.clone(),
      depth: cursor.path.len,
      childIndex: cursor.index,
      childCount: childCount,
      totalChildren: childCount), ins)
    var depth = cursor.depth
    for i in 0..<ins:
      let parentIndex = ins - i - 1
      if e.nodes[parentIndex].cursor.depth == depth - 1:
        e.nodes[parentIndex].totalChildren += childCount
        dec depth

# Seeds `nodes` with just the root on first use.
proc ensureNodes(e: var TreeTable) =
  if e.initialized:
    return
  e.initialized = true
  var root = e.cursor.clone()
  let childCount = root.childCount()
  e.nodes.add(ExpandedNode(
    cursor: root,
    depth: 0,
    childCount: childCount,
    totalChildren: childCount))

# Collapses the whole tree back to just the root, keeping it initialized.
proc collapseAll*(e: var TreeTable) =
  e.nodes.setLen(0)
  var root = e.cursor.clone()
  let childCount = root.childCount()
  e.nodes.add(ExpandedNode(
    cursor: root,
    depth: 0,
    childCount: childCount,
    totalChildren: childCount))

# Total number of visible rows: the root plus every child of each expanded node.
proc countVisible(e: TreeTable): int =
  var count = 1
  for i in 0 ..< e.nodes.len:
    var c = e.nodes[i].cursor.clone()
    count += c.childCount()
  return count

# Expands every node that has children by adding them all to `nodes` in preorder.
proc expandAll*(e: TreeTable) =
  e.nodes.setLen(0)
  var stack: seq[(TreeCursor, int)]
  stack.add((e.cursor.clone(), 0))
  while stack.len > 0:
    let (cursor, depth) = stack.pop()
    let childCount = cursor.childCount()
    if childCount > 0:
      e.nodes.add(ExpandedNode(
        cursor: cursor.clone(),
        depth: depth,
        childIndex: cursor.index,
        childCount: childCount,
        totalChildren: childCount))
    if childCount > 0:
      var child = cursor.clone()
      if child.enterChild():
        var children: seq[TreeCursor]
        while true:
          children.add(child.clone())
          if not child.moveNext():
            break
        for i in countdown(children.len - 1, 0):
          stack.add((children[i], depth + 1))
  # bottom-up totalChildren = childCount + sum of direct expanded children totalChildren
  for i in countdown(e.nodes.high, 0):
    var sum = 0
    let parentDepth = e.nodes[i].depth
    var j = i + 1
    while j <= e.nodes.high:
      if e.nodes[j].depth <= parentDepth:
        break
      if e.nodes[j].depth == parentDepth + 1 and isAncestorPath(e.nodes[i].cursor.path, e.nodes[j].cursor.path):
        sum += e.nodes[j].totalChildren
      inc j
    e.nodes[i].totalChildren = e.nodes[i].childCount + sum

proc buildChevronDeferred(b: var UiBuilder, nodeIdx: int, userData: int) =
  ## Deferred builder for the expand/collapse chevron icon.
  ## userData == 1 => expanded (down), 0 => collapsed (right)
  let arena = b.frame.arena
  if arena == nil:
    return
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let n = b.frame.nodes[nodeIdx].addr
  let origin = b.absoluteNodePos(nodeIdx)
  let size = n.size
  if size.x <= 0.0'f32 or size.y <= 0.0'f32:
    return
  let inset = 2.0'f32
  let innerPos = origin + vec2(inset, inset)
  let innerSize = vec2(max(0.0'f32, size.x - inset * 2.0'f32), max(0.0'f32, size.y - inset * 2.0'f32))
  if innerSize.x <= 0.0'f32 or innerSize.y <= 0.0'f32:
    return
  let dir = if userData == 1: vec2(0.0'f32, 1.0'f32) else: vec2(1.0'f32, 0.0'f32)
  let color = b.themeTextStyle(UiStyleIndexDefaultText)[].textColor
  let (data, count) = buildChevronVertices(arena, innerPos, innerSize, dir, color)
  if data == nil or count == 0:
    return
  var cmds = arena[].allocEmptyArray(1, UiRenderCommand)
  if cmds.data == nil:
    return
  cmds.add UiRenderCommand(
    kind: CmdRawVertices,
    vertexData: data,
    vertexCount: count.int32,
    color: color,
  )
  b.withParent(nodeIdx):
    discard b.customRenderCommands(cmds)

# Renders a single row for the node under `cursor`. A leading chevron mesh
# indicates whether the node has children and its expanded/collapsed state.
# Collapsed points right (1,0), expanded points down (0,1).
proc treeTableField*(b: var UiBuilder; e: var TreeTable, index: int) =
  prof("treeTableField")
  let hasChildren = e.walkCursor.childCount() > 0
  let isExpanded = hasChildren and nodeIsExpanded(e, e.walkCursor, 0)

  let hovered = b.wasHovered(includeChildren = true)
  if hovered:
    discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexRowAlt)[].fillColor)

  # current node is table row, each node created here is one column

  b.debugName("tree-table-row")
  discard b.fitY().gap(4).paddingY(2)

  b.layoutHorizontal:
    discard b.fit().gap(2)
    b.node:
      discard b.size(e.walkCursor.depth.float32 * 20, 1)
    if hasChildren:
      b.node:
        b.debugName("symbol")
        discard b.size(14, 14).alignCenter()
        if b.wasClicked(includeChildren = true):
          e.pendingToggleCursor = e.walkCursor.clone()
        # chevron mesh via custom render command (right when collapsed, down when expanded)
        discard b.deferBuild(buildChevronDeferred, if isExpanded: 1 else: 0)

  e.rowRenderer(b, e.walkCursor, index)

# Custom layout for the virtual list viewport: lays out every row's children as
# columns, table-style. First pass measures the maximum width of each column index
# across all visible rows; the second pass positions each row's columns using those
# shared widths so columns line up vertically. Each column is fit-sized; the row
# height follows the tallest column in that row.
#
# Columns 0 and 1 (indent/chevron container + first renderer column) are treated as
# a single logical column 0, so the second column lives right next to the indent
# instead of being vertically aligned across rows. Logical column 0's width is the
# combined width of those two physical children (including the gap between them);
# logical column N (N>=1) maps to physical child N+1. Only starting at the third
# physical column (logical 1) are columns vertically aligned.
#
# When a column spec is supplied via userData (ptr TreeTableLayout, same shape as
# widgets.tableLayout), each logical column can be Fixed, Fit, Fill or
# Proportional (see widgets.nim). Fixed/Fill/Proportional work for logical 0 as
# well – the indent width is subtracted so the name column (physical 1) fills the
# remainder of the allocated logical width.
#
# `TreeTableLayout.showColumnLines` draws vertical separator lines between
# logical columns (inside the inter-column gap, centered).
proc treeTableColumnLayout(b: var UiBuilder, nodeIdx: int, userData: int) {.raises: [].} =
  prof "treeTableColumnLayout"
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let n = b.frame.nodes[nodeIdx].addr
  let baseGap = b.nodeGap(n)
  let nodeStyle = b.nodeStyle(n)
  let contentW = max(0.0'f32, n.size.x - nodeStyle.paddingX * 2.0'f32)

  # -------------------------------------------------------------------------
  # No spec – legacy Fit-only path (backwards compatible)
  # -------------------------------------------------------------------------
  if userData == 0:
    let gap = baseGap
    var colWidths: seq[float32] = @[0]
    for rowIdx in b.children(nodeIdx):
      var k = 0
      var firstTwoColumns: float32 = 0.0
      for childIdx in b.children(rowIdx):
        let w = b.frame.nodes[childIdx].addr.size.x
        if k == 0:
          firstTwoColumns += w
        elif k == 1:
          firstTwoColumns += w
          colWidths[0] = max(firstTwoColumns, colWidths[0])
        elif k - 1 >= colWidths.len:
          colWidths.add(w)
        elif w > colWidths[k - 1]:
          colWidths[k - 1] = w
        k += 1

    for rowIdx in b.children(nodeIdx):
      let row = b.frame.nodes[rowIdx].addr
      let rowGap = b.nodeGap(row)
      var cursor = 0.0'f32
      var k = 0
      var rowHeight = 0.0'f32
      for childIdx in b.children(rowIdx):
        let child = b.frame.nodes[childIdx].addr
        let cw = if k == 0:
          child.size.x
        elif k == 1:
          rowGap + colWidths[0] - cursor
        elif k - 1 < colWidths.len:
          colWidths[k - 1]
        else: child.size.x

        child.pos.x = cursor
        child.pos.y = 0.0'f32
        if k > 1 and k - 1 < colWidths.len:
          let oldSize = child.size.x
          child.size.x = colWidths[k - 1]
          child.flags.incl SizeXKnown
          if child.size.x != oldSize:
            b.postProcessChildren(childIdx)
        rowHeight = max(rowHeight, child.size.y)
        cursor += cw + rowGap
        row.contentExtent.x = max(row.contentExtent.x, child.pos.x + child.size.x)
        row.contentExtent.y = max(row.contentExtent.y, child.pos.y + child.size.y)
        k += 1
      for childIdx in b.children(rowIdx):
        let child = b.frame.nodes[childIdx].addr
        child.pos.y = ((rowHeight - child.size.y) * 0.5).floor
      b.updateNodeFit(row)
    return

  # -------------------------------------------------------------------------
  # Spec path – Fixed / Fit / Fill / Proportional per logical column + lines
  # -------------------------------------------------------------------------
  let data = cast[ptr TreeTableLayout](userData)
  let logicalCount = max(0, data.columnCount)
  let colGap = if data.columnGap > 0.0'f32: data.columnGap else: baseGap
  # If no column spec but lines requested (columns empty), we still compute
  # fitted widths dynamically so lines know where to go.
  let useDynamicFit = logicalCount == 0

  var colWidths: seq[float32]
  var colWeights: seq[float32]
  var anyFit = false
  if not useDynamicFit:
    colWidths = newSeq[float32](logicalCount)
    colWeights = newSeq[float32](logicalCount)
    for c in 0 ..< logicalCount:
      let col = data.columns[c]
      case col.kind
      of TableColumnFixed:
        colWidths[c] = max(0.0'f32, col.fixedWidth.round())
        colWeights[c] = 0.0'f32
      of TableColumnFit:
        colWidths[c] = 0.0'f32
        colWeights[c] = 0.0'f32
        anyFit = true
      of TableColumnFill:
        colWidths[c] = 0.0'f32
        colWeights[c] = 1.0'f32
      of TableColumnProportional:
        let w = max(0.0001'f32, col.proportional)
        colWidths[c] = 0.0'f32
        colWeights[c] = w
    if anyFit:
      for rowIdx in b.children(nodeIdx):
        var k = 0
        var indentW: float32 = 0.0'f32
        for childIdx in b.children(rowIdx):
          let w = b.frame.nodes[childIdx].addr.size.x
          if k == 0:
            indentW = w
          elif k == 1:
            if colWeights[0] == 0.0'f32 and data.columns[0].kind == TableColumnFit:
              let combined = indentW + colGap + w
              colWidths[0] = max(colWidths[0], combined)
          elif k - 1 < logicalCount:
            let logical = k - 1
            if colWeights[logical] == 0.0'f32 and data.columns[logical].kind == TableColumnFit:
              colWidths[logical] = max(colWidths[logical], w)
          k += 1
    var usedByBase = 0.0'f32
    var totalWeight = 0.0'f32
    for c in 0 ..< logicalCount:
      if colWeights[c] == 0.0'f32:
        usedByBase += colWidths[c]
      else:
        totalWeight += colWeights[c]
    let totalColGap = colGap * max(0, logicalCount - 1).float32
    let freeSpace = contentW - totalColGap - usedByBase
    if totalWeight > 0.0'f32 and freeSpace > 0.0'f32:
      for c in 0 ..< logicalCount:
        if colWeights[c] > 0.0'f32:
          colWidths[c] = max(0.0'f32, freeSpace * (colWeights[c] / totalWeight)).round()
  else:
    # Dynamic fit fallback – mirrors the legacy path but we keep widths for line drawing.
    colWidths = @[0.0'f32]
    for rowIdx in b.children(nodeIdx):
      var k = 0
      var firstTwo: float32 = 0.0'f32
      for childIdx in b.children(rowIdx):
        let w = b.frame.nodes[childIdx].addr.size.x
        if k == 0:
          firstTwo += w
        elif k == 1:
          firstTwo += w
          colWidths[0] = max(firstTwo, colWidths[0])
        elif k - 1 >= colWidths.len:
          colWidths.add(w)
        elif w > colWidths[k - 1]:
          colWidths[k - 1] = w
        k += 1

  # Resolve helper for line drawing
  let showLines = data.showColumnLines
  let lineThickness = max(1.0'f32, data.columnLineThickness)
  let lineColor: UiColor = if data.hasCustomLineColor:
    data.columnLineColor
  else:
    b.themeStyle(UiStyleIndexPanel)[].borderColor

  # Position each row.
  for rowIdx in b.children(nodeIdx):
    let row = b.frame.nodes[rowIdx].addr
    # Use the spec gap for inter-logical-column spacing; intra-logical-0 gap is colGap as well.
    let gap = colGap
    var cursor = 0.0'f32
    var k = 0
    var indentW: float32 = 0.0'f32
    var rowHeight = 0.0'f32
    if not useDynamicFit:
      for childIdx in b.children(rowIdx):
        let child = b.frame.nodes[childIdx].addr
        if k == 0:
          child.pos.x = cursor
          child.pos.y = 0.0'f32
          indentW = child.size.x
          rowHeight = max(rowHeight, child.size.y)
          cursor += child.size.x + gap
          row.contentExtent.x = max(row.contentExtent.x, child.pos.x + child.size.x)
          row.contentExtent.y = max(row.contentExtent.y, child.pos.y + child.size.y)
        elif k == 1:
          let logical0W = colWidths[0]
          var nameW = max(0.0'f32, logical0W - indentW - gap)
          let oldW = child.size.x
          child.size.x = nameW
          child.flags.incl SizeXKnown
          if nameW != oldW:
            b.postProcessChildren(childIdx)
          child.pos.x = cursor
          child.pos.y = 0.0'f32
          rowHeight = max(rowHeight, child.size.y)
          cursor += nameW + gap
          row.contentExtent.x = max(row.contentExtent.x, child.pos.x + child.size.x)
          row.contentExtent.y = max(row.contentExtent.y, child.pos.y + child.size.y)
        elif k - 1 < logicalCount:
          let logical = k - 1
          let cw = colWidths[logical]
          let oldW = child.size.x
          child.size.x = cw
          child.flags.incl SizeXKnown
          if cw != oldW:
            b.postProcessChildren(childIdx)
          child.pos.x = cursor
          child.pos.y = 0.0'f32
          rowHeight = max(rowHeight, child.size.y)
          cursor += cw + gap
          row.contentExtent.x = max(row.contentExtent.x, child.pos.x + child.size.x)
          row.contentExtent.y = max(row.contentExtent.y, child.pos.y + child.size.y)
        else:
          child.pos.x = cursor
          child.pos.y = 0.0'f32
          rowHeight = max(rowHeight, child.size.y)
          cursor += child.size.x + gap
          row.contentExtent.x = max(row.contentExtent.x, child.pos.x + child.size.x)
          row.contentExtent.y = max(row.contentExtent.y, child.pos.y + child.size.y)
        k += 1
    else:
      # Dynamic fit positioning (same as legacy but we already computed colWidths)
      for childIdx in b.children(rowIdx):
        let child = b.frame.nodes[childIdx].addr
        let cw = if k == 0: child.size.x
          elif k == 1: gap + colWidths[0] - cursor
          elif k - 1 < colWidths.len: colWidths[k - 1]
          else: child.size.x
        child.pos.x = cursor
        child.pos.y = 0.0'f32
        if k > 1 and k - 1 < colWidths.len:
          let oldSize = child.size.x
          child.size.x = colWidths[k - 1]
          child.flags.incl SizeXKnown
          if child.size.x != oldSize:
            b.postProcessChildren(childIdx)
        rowHeight = max(rowHeight, child.size.y)
        cursor += cw + gap
        row.contentExtent.x = max(row.contentExtent.x, child.pos.x + child.size.x)
        row.contentExtent.y = max(row.contentExtent.y, child.pos.y + child.size.y)
        k += 1
    for childIdx in b.children(rowIdx):
      let child = b.frame.nodes[childIdx].addr
      child.pos.y = ((rowHeight - child.size.y) * 0.5).floor
    b.updateNodeFit(row)

    # -------------------------------------------------------------------
    # Vertical lines between logical columns (inside inter-column gap).
    # -------------------------------------------------------------------
    if showLines:
      let logicalForLines = if useDynamicFit: colWidths.len else: logicalCount
      if logicalForLines > 1:
        let rowStyle = b.nodeStyle(row)
        let padY = rowStyle.paddingY
        # Count how many separators actually have both sides present in this row.
        var sepCount = 0
        let childCount = b.childCount(rowIdx)
        for i in 0 ..< logicalForLines - 1:
          let leftK = if i == 0: 1 else: i + 1
          let rightK = leftK + 1
          if rightK < childCount:
            inc sepCount
        if sepCount > 0:
          var avail = b.frame.arena[].allocEmptyArray(sepCount, UiRenderCommand)
          for i in 0 ..< logicalForLines - 1:
            let leftK = if i == 0: 1 else: i + 1
            let rightK = leftK + 1
            let childCount = b.childCount(rowIdx)
            if rightK >= childCount: continue
            var leftIdx = -1
            var rightIdx = -1
            var kk = 0
            for childIdx in b.children(rowIdx):
              if kk == leftK: leftIdx = childIdx
              if kk == rightK: rightIdx = childIdx
              inc kk
            if leftIdx < 0 or rightIdx < 0: continue
            let left = b.frame.nodes[leftIdx].addr
            let right = b.frame.nodes[rightIdx].addr
            let leftEnd = left.pos.x + left.size.x
            let rightStart = right.pos.x
            let gapW = rightStart - leftEnd
            let centerX = if gapW > 0.001'f32: (leftEnd + rightStart) * 0.5'f32 else: leftEnd + gapW * 0.5'f32
            let x = centerX - lineThickness * 0.5'f32
            avail.add UiRenderCommand(
              kind: CmdRectFill,
              color: lineColor,
              pos: vec2(x, -padY),
              size: vec2(lineThickness, row.size.y),
              radius: 0.0'f32,
            )
          if avail.len > 0:
            var existing = b.ensureNodeCustomCommands(row)
            if existing.len > 0:
              # Merge with any pre-existing custom commands on the row.
              let total = existing.len + avail.len
              var combined = b.frame.arena[].allocEmptyArray(total, UiRenderCommand)
              for j in 0 ..< existing.len: combined.add existing[j]
              for j in 0 ..< avail.len: combined.add avail[j]
              b.ensureNodeCustomCommands(row) = combined
            else:
              b.ensureNodeCustomCommands(row) = avail

    # -------------------------------------------------------------------
    # Indentation guides – one vertical line per depth level, centered in
    # each  `indentationStep` slot. Lines span the full row height so
    # neighboring rows that share the same depth level appear connected.
    # -------------------------------------------------------------------
    if data.showIndentationLines:
      let indentThickness = max(1.0'f32, data.indentationLineThickness)
      let indentColor: UiColor = if data.hasCustomIndentationLineColor:
        data.indentationLineColor
      else:
        b.themeStyle(UiStyleIndexPanel)[].borderColor
      let step = if data.indentationStep > 0.001'f32: data.indentationStep else: 20.0'f32
      var firstW: float32 = 0.0'f32
      var containerIdx = -1
      for childIdx in b.children(rowIdx):
        containerIdx = childIdx
        break
      if containerIdx >= 0:
        for indentChildIdx in b.children(containerIdx):
          firstW = b.frame.nodes[indentChildIdx].addr.size.x
          break
      let depth = int((firstW / step) + 0.5'f32)
      if depth > 0:
        let rowStyle2 = b.nodeStyle(row)
        let padY2 = rowStyle2.paddingY
        var indentAvail = b.frame.arena[].allocEmptyArray(depth, UiRenderCommand)
        for lvl in 0 ..< depth:
          let x = lvl.float32 * step + step * 0.5'f32 - indentThickness * 0.5'f32
          if x + indentThickness > firstW + 0.001'f32:
            continue
          indentAvail.add UiRenderCommand(
            kind: CmdRectFill,
            color: indentColor,
            pos: vec2(x, -padY2),
            size: vec2(indentThickness, row.size.y),
            radius: 0.0'f32,
          )
        if indentAvail.len > 0:
          var existing2 = b.ensureNodeCustomCommands(row)
          if existing2.len > 0:
            let total = existing2.len + indentAvail.len
            var combined2 = b.frame.arena[].allocEmptyArray(total, UiRenderCommand)
            for j in 0 ..< existing2.len: combined2.add existing2[j]
            for j in 0 ..< indentAvail.len: combined2.add indentAvail[j]
            b.ensureNodeCustomCommands(row) = combined2
          else:
            b.ensureNodeCustomCommands(row) = indentAvail

# Builds the row at `itemIndex` by walking the visible preorder from the root.
# `walkCursor` is cached across the deferred row builds within a frame (visited in
# increasing `itemIndex` order), so each row advances the walk incrementally.
proc buildTreeTableRow(b: var UiBuilder, itemIndex: int, userData: int) =
  prof("buildTreeTableRow")
  var ctx = b.getOrCreateStorage(b.frame.nodes[userData].addr)
  if ctx.nodes.len == 0:
    return
  if ctx.walkCursor == nil:
    ctx.walkCursor = ctx.cursor.clone()
    ctx.walkIndex = 0
  if ctx.walkIndex == 0:
    if not ctx.seek(itemIndex):
      return
  block:
    prof("step")
    while ctx.walkIndex < itemIndex:
      if not stepForward(ctx.walkCursor, ctx, ctx.walkNode):
        break
      ctx.walkIndex += 1
  treeTableField(b, ctx, itemIndex)

# Entry point with TreeTableOptions – all sizing and line options in one object.
# Logical column 0 is the combined indent+name column (physical 0+1); logical N
# (N>=1) maps to physical column N+1. Only starting at the third physical
# column are columns vertically aligned; logical 0 takes the indent width into
# account when sizing the name part.
proc treeTable*(b: var UiBuilder; cursor: TreeCursor, options: TreeTableOptions, rowRenderer: TreeTableRowRenderer) =
  var ctx = b.getOrCreateStorage(b.currentNode)
  ctx.cursor = cursor
  ctx.walkCursor = nil
  ctx.rowRenderer = rowRenderer
  ensureNodes(ctx)
  let count = if ctx.nodes.len == 0: 1 else: 1 + ctx.nodes[0].totalChildren
  b.layoutHorizontal:
    discard b.fit().gap(2)
    if b.button("Expand all"):
      expandAll(ctx)
  if b.button("Collapse all"):
    collapseAll(ctx)

  discard b.dynamicVirtualList(count, 24.0'f32, buildTreeTableRow, b.currentNodeIndex)
  let last = b.frame.nodes[b.lastNodeIndex].addr
  let containerIndex = b.frame.nodes[last.lastChild].nextSibling

  let hasColumns = options.columns.len > 0
  let hasColumnLines = options.showColumnLines
  let hasIndentLines = options.showIndentationLines
  if hasColumns or hasColumnLines or hasIndentLines:
    var colArr: ArrayView[TableColumn]
    var colPtr: ptr UncheckedArray[TableColumn] = nil
    var colCount = 0
    if hasColumns:
      colArr = b.frame.arena[].allocArray(options.columns.len, TableColumn)
      for i in 0 ..< options.columns.len:
        colArr[i] = options.columns[i]
      colPtr = colArr.data
      colCount = options.columns.len
    var layoutArr = b.frame.arena[].allocArray(1, TreeTableLayout)
    layoutArr[0] = TreeTableLayout(
      columnGap: if options.columnGap > 0.001'f32: options.columnGap else: 4.0'f32,
      columnCount: colCount,
      columns: colPtr,
      showColumnLines: hasColumnLines,
      columnLineThickness: if options.columnLineThickness > 0.001'f32: options.columnLineThickness else: 1.0'f32,
      columnLineColor: options.columnLineColor,
      hasCustomLineColor: options.hasCustomLineColor,
      showIndentationLines: hasIndentLines,
      indentationLineThickness: if options.indentationLineThickness > 0.001'f32: options.indentationLineThickness else: 1.0'f32,
      indentationLineColor: options.indentationLineColor,
      hasCustomIndentationLineColor: options.hasCustomIndentationLineColor,
      indentationStep: if options.indentationStep > 0.001'f32: options.indentationStep else: 20.0'f32,
    )
    b.withParent(b.frame.nodes[containerIndex].id):
      discard b.customLayout(treeTableColumnLayout, cast[int](layoutArr.data))
  else:
    b.withParent(b.frame.nodes[containerIndex].id):
      discard b.customLayout(treeTableColumnLayout, 0)

  if ctx.pendingToggleCursor != nil:
    toggleNode(ctx, ctx.pendingToggleCursor)
    ctx.pendingToggleCursor = nil
    b.anythingAnimating = true

proc treeTable*(b: var UiBuilder; cursor: TreeCursor, columns: openArray[TableColumn], columnGap: float32, rowRenderer: TreeTableRowRenderer) =
  var opts = defaultTreeTableOptions()
  opts.columns = @columns
  opts.columnGap = columnGap
  b.treeTable(cursor, opts, rowRenderer)

proc treeTable*(b: var UiBuilder; cursor: TreeCursor, columns: openArray[TableColumn], rowRenderer: TreeTableRowRenderer) =
  b.treeTable(cursor, columns, 4.0'f32, rowRenderer)

# Backwards-compatible entry point – all columns Fit (legacy behaviour).
proc treeTable*(b: var UiBuilder; cursor: TreeCursor, rowRenderer: TreeTableRowRenderer) =
  b.treeTable(cursor, defaultTreeTableOptions(), rowRenderer)
