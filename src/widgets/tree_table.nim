import nuigi
import mymath

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

func depth*(c: TreeCursor): int = c.path.len

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
      assert e.walkCursor.enterChild()
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

# Renders a single row for the node under `cursor`. A leading symbol
# indicates whether the node has children and its expanded/collapsed state.
proc treeTableField*(b: var UiBuilder; e: var TreeTable) =
  prof("treeTableField")
  let hasChildren = e.walkCursor.childCount() > 0
  var symbol = "• "
  if hasChildren:
    symbol = if nodeIsExpanded(e, e.walkCursor, 0): "▾ " else: "▸ "

  let hovered = b.wasHovered(includeChildren = true)
  if hovered:
    discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexRowAlt)[].fillColor)

  # current node is table row, each node created here is one column

  b.debugName("tree-table-row")
  discard b.fitY().gap(4)

  b.layoutHorizontal:
    discard b.fit().gap(2)
    b.node:
      discard b.size(e.walkCursor.depth.float32 * 20, 1)
  # discard b.fillX().fitY().padding(4).offsetsX(e.walkCursor.path.len.float32 * 12.0'f32, 0.0'f32).gap(8)
    b.node:
      b.debugName("symbol")
      discard b.fitX().fitY()
      if hasChildren and b.wasClicked(includeChildren = true):
        e.pendingToggleCursor = e.walkCursor.clone()
      b.label(symbol):
        discard b.fitX().fitY()
    b.label(e.walkCursor.fieldName & ":"):
      discard b.fitX().fitY()

  b.label("dummy value"):
    discard b.fillX().fitY()

# Custom layout for the virtual list viewport: lays out every row's children as
# columns, table-style. First pass measures the maximum width of each column index
# across all visible rows; the second pass positions each row's columns using those
# shared widths so columns line up vertically. Each column is fit-sized; the row
# height follows the tallest column in that row.
proc treeTableColumnLayout(b: var UiBuilder, nodeIdx: int, userData: int) {.raises: [].} =
  prof "treeTableColumnLayout"
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let n = b.frame.nodes[nodeIdx].addr
  let gap = b.nodeGap(n)
  # Pass 1: widest column per column index, across all rows (table alignment).
  var colWidths: seq[float32]
  for rowIdx in b.children(nodeIdx):
    var k = 0
    for childIdx in b.children(rowIdx):
      let w = b.frame.nodes[childIdx].addr.size.x
      if k >= colWidths.len:
        colWidths.add(w)
      elif w > colWidths[k]:
        colWidths[k] = w
      k += 1
  # Pass 2: position each row's columns left-to-right using the shared widths.
  for rowIdx in b.children(nodeIdx):
    let row = b.frame.nodes[rowIdx].addr
    let rowGap = b.nodeGap(row)
    var cursor = 0.0'f32
    var k = 0
    for childIdx in b.children(rowIdx):
      let child = b.frame.nodes[childIdx].addr
      let cw = if k < colWidths.len: colWidths[k] else: child.size.x
      child.pos.x = cursor
      child.pos.y = 0.0'f32
      cursor += cw + rowGap
      row.contentExtent.x = max(row.contentExtent.x, child.pos.x + child.size.x)
      row.contentExtent.y = max(row.contentExtent.y, child.pos.y + child.size.y)
      k += 1
    b.updateNodeFit(row)

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
  treeTableField(b, ctx)

# Entry point: attaches state, ensures the node list is seeded, then renders the
# visible rows through a dynamic virtual list.
proc treeTable*(b: var UiBuilder; cursor: TreeCursor) =
  var ctx = b.getOrCreateStorage(b.currentNode)
  ctx.cursor = cursor
  ctx.walkCursor = nil
  ensureNodes(ctx)
  let count = if ctx.nodes.len == 0: 1 else: ctx.nodes[0].totalChildren
  b.layoutHorizontal:
    discard b.fit().gap(2)
    if b.button("Expand all"):
      expandAll(ctx)
  if b.button("Collapse all"):
    collapseAll(ctx)

  discard b.dynamicVirtualList(count, 24.0'f32, buildTreeTableRow, b.currentNodeIndex)
  let last = b.frame.nodes[b.lastNodeIndex].addr
  let containerIndex = b.frame.nodes[last.lastChild].nextSibling

  # The virtual list viewport's children are rows; give it a table-style column
  # layout so every row's columns align.
  b.withParent(b.frame.nodes[containerIndex].id):
    discard b.customLayout(treeTableColumnLayout, 0)

  if ctx.pendingToggleCursor != nil:
    toggleNode(ctx, ctx.pendingToggleCursor)
    ctx.pendingToggleCursor = nil
    b.anythingAnimating = true
