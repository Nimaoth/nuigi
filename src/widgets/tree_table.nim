import nuigi
import mymath
import mesh
import arena, array_view
import std/[monotimes, tables, times, assertions]

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

  # A cached expanded node. Active nodes form an intrinsic tree through stable
  # slot indices; removed nodes leave reusable free-list slots.
  ExpandedNode* = object
    cursor*: TreeCursor
    childIndex*: int
    depth*: int
    childCount*: int
    totalChildren*: int
    parent*: int
    firstChild*: int
    nextSibling*: int
    previousSibling*: int
    nextFree: int

  ExpandAllWork = object
    nextChild: TreeCursor
    parentIndex: int

  # Per-instance state for one tree table, kept in the builder's node storage.
  TreeTable* = ref object of UiNodeStorageData
    cursor*: TreeCursor
    nodes*: seq[ExpandedNode]
    rootNode*: int
    freeNode: int
    expandedCount*: int
    nodeByKey: Table[string, int]
    initialized*: bool
    pendingToggleCursor*: TreeCursor
    pendingExpandCursor: TreeCursor
    expandAllWork: seq[ExpandAllWork]
    expandingAll: bool
    walkCursor*: TreeCursor
    walkIndex*: int
    walkNode*: int # Index into TreeTable.nodes which is the walkCursors ExpandedNode or the parents ExpandedNode
    nodesIndex: int # Index into nodes where we currently are while rendering items
    renderedCursors*: seq[TreeCursor]
    searchFilter*: string
    scrollOffset*: Vec2
    rowRenderer: TreeTableRowRenderer
    alternatingRowBackground*: bool
    alternatingColorEven*: UiColor
    alternatingColorOdd*: UiColor
    hasCustomAlternatingColors*: bool
    highlightHoveredRow*: bool
    hoverColor*: UiColor
    hasCustomHoverColor*: bool
    focusRootId: UiNodeId
    focusCursors: Table[uint64, TreeCursor]
    focusCursorsInitialized: bool
    listStorage: UiDynamicVirtualListStorage

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
    alternatingRowBackground*: bool
      ## When true, rows get alternating background colors (zebra stripes) for readability.
    alternatingColorEven*: UiColor
      ## Background for even rows (index % 2 == 0). Falls back to `UiStyleIndexRow`.
    alternatingColorOdd*: UiColor
      ## Background for odd rows (index % 2 == 1). Falls back to `UiStyleIndexRowAlt`.
    hasCustomAlternatingColors*: bool
    highlightHoveredRow*: bool
      ## When true, hovering a row highlights its full background.
    hoverColor*: UiColor
      ## Hover highlight. When custom, used verbatim; otherwise a theme hover
      ## color distinct from both alternating colors (`ButtonHover`).
    hasCustomHoverColor*: bool

  TreeTableLayout* = object
    ## Internal layout payload passed as `userData` to `treeTableColumnLayout`.
    ## Mirrors `TreeTableOptions` but stores columns as an arena pointer for the layout pass.
    columnGap*: float32
    columnCount*: int
    columns*: nil ptr UncheckedArray[TableColumn]
    showColumnLines*: bool
    columnLineThickness*: float32
    columnLineColor*: UiColor
    hasCustomLineColor*: bool
    showIndentationLines*: bool
    indentationLineThickness*: float32
    indentationLineColor*: UiColor
    hasCustomIndentationLineColor*: bool
    indentationStep*: float32
    alternatingRowBackground*: bool
    alternatingColorEven*: UiColor
    alternatingColorOdd*: UiColor
    hasCustomAlternatingColors*: bool
    hoverColor*: UiColor
    hasCustomHoverColor*: bool

const TreeTableExpandAllBudgetNanoseconds* = 4_000_000'i64
  ## Default time spent expanding tree-table items per frame.

func depth*(c: TreeCursor): int =
  ## Returns the cursor's depth below the root.
  c.path.len

proc defaultTreeTableOptions*(): TreeTableOptions =
  ## Creates the standard tree-table appearance and layout options.
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
    alternatingRowBackground: false,
    alternatingColorEven: UiColor(r: 0, g: 0, b: 0, a: 0),
    alternatingColorOdd: UiColor(r: 0, g: 0, b: 0, a: 0),
    hasCustomAlternatingColors: false,
    highlightHoveredRow: true,
    hoverColor: UiColor(r: 0, g: 0, b: 0, a: 0),
    hasCustomHoverColor: false,
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
    indentationStep: float32 = 20.0'f32,
    alternatingRowBackground: bool = false,
    alternatingColorEven: UiColor = UiColor(r: 0, g: 0, b: 0, a: 0),
    alternatingColorOdd: UiColor = UiColor(r: 0, g: 0, b: 0, a: 0),
    hasCustomAlternatingColors: bool = false,
    highlightHoveredRow: bool = true,
    hoverColor: UiColor = UiColor(r: 0, g: 0, b: 0, a: 0),
    hasCustomHoverColor: bool = false): TreeTableOptions =
  ## Creates options from explicit column, separator, indentation, and row colors.
  result = default(TreeTableOptions)
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
  result.alternatingRowBackground = alternatingRowBackground
  result.alternatingColorEven = alternatingColorEven
  result.alternatingColorOdd = alternatingColorOdd
  result.hasCustomAlternatingColors = hasCustomAlternatingColors or
    (alternatingColorEven.a > 0.001'f32 or alternatingColorOdd.a > 0.001'f32)
  result.highlightHoveredRow = highlightHoveredRow
  result.hoverColor = hoverColor
  result.hasCustomHoverColor = hasCustomHoverColor or hoverColor.a > 0.001'f32

proc getOrCreateStorage(b: var UiBuilder, node: ptr UiNode): TreeTable =
  ## Returns the editor state attached to `node`, creating it on first use.
  let existing = nodeStorageGet(b, node)
  if existing != nil:
    return cast[TreeTable](existing)
  var storage = TreeTable()
  nodeStorage(b, node, storage)
  return storage

method clone*(c: TreeCursor): TreeCursor {.base.} =
  ## Copies a cursor so callers can navigate without mutating the original.
  result = TreeCursor()
  result.fieldName = c.fieldName
  result.index = c.index
  result.path = c.path

method cursorKey*(c: TreeCursor): string {.base.} =
  ## Returns stable node identity used to preserve expansion state.
  ## Subtypes should override this, for example with a filesystem path.
  result = ""
  for i in c.path:
    result.add($i)
    result.add("/")

method moveNext*(c: TreeCursor, count: int = 1): bool {.base.} =
  ## Moves to a later sibling and returns false when it does not exist.
  false

method movePrev*(c: TreeCursor, count: int = 1): bool {.base.} =
  ## Moves to an earlier sibling and returns false when it does not exist.
  false

method childCount*(c: TreeCursor): int {.base.} =
  ## Returns the number of direct children under the current node.
  0

method enterChild*(c: TreeCursor): bool {.base.} =
  ## Moves to the first child and returns false when the current node is a leaf.
  false

method exitChild*(c: TreeCursor): bool {.base.} =
  ## Moves to the parent and returns false when already at the cursor root.
  false

method updatePath*(c: TreeCursor, path: seq[int]) {.base.} =
  ## Replaces the positional path and keeps the sibling index synchronized.
  c.path = path
  c.index = if path.len > 0: path[^1] else: 0

method replacePathPrefix*(c: TreeCursor, oldPrefixLen: int, newPrefix: seq[int]) {.base.} =
  ## Rebases after an ancestor moves while preserving the descendant suffix.
  if oldPrefixLen == newPrefix.len:
    for index in 0 ..< newPrefix.len:
      c.path[index] = newPrefix[index]
    c.index = if c.path.len > 0: c.path[^1] else: 0
    return

  let suffixLen = max(0, c.path.len - oldPrefixLen)
  var path = newSeq[int](newPrefix.len + suffixLen)
  for index in 0 ..< newPrefix.len:
    path[index] = newPrefix[index]
  for index in 0 ..< suffixLen:
    path[newPrefix.len + index] = c.path[oldPrefixLen + index]
  c.updatePath(path)

method resolveChild*(c: TreeCursor, child: TreeCursor): TreeCursor {.base.} =
  ## Resolves `child` against the current children using its index only as a hint.
  ## Identity comes from cursorKey; indexed data sources should override this.
  prof("resolveChild")
  let childKey = child.cursorKey()
  var current = c.clone()
  if not current.enterChild():
    return nil

  if child.index > 0:
    var hinted = current.clone()
    if hinted.moveNext(child.index) and hinted.cursorKey() == childKey:
      return hinted

  while true:
    if current.cursorKey() == childKey:
      return current
    if not current.moveNext():
      return nil

proc nodeIsExpanded(e: TreeTable, c: TreeCursor, startIndex: int): bool =
  ## Returns whether the cursor has an active expanded-node slot.
  prof("nodeIsExpanded")
  discard startIndex
  e.nodeByKey.hasKey(cursorKey(c))

proc stepForward(c: var TreeCursor, e: TreeTable, startIndex: int): bool =
  ## Advances to the next visible preorder row, descending only when expanded.
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
  ## Yields active expanded direct children in current sibling order.
  if nodeIndex >= 0 and nodeIndex < e.nodes.len and e.nodes[nodeIndex].cursor != nil:
    var childIndex = e.nodes[nodeIndex].firstChild
    while childIndex >= 0:
      let nextIndex = e.nodes[childIndex].nextSibling
      yield (childIndex, e.nodes[childIndex].addr)
      childIndex = nextIndex

proc allocateExpandedNode(e: TreeTable, node: ExpandedNode): int =
  ## Allocates a stable slot, preferring the free list, and indexes its key.
  if e.freeNode >= 0:
    result = e.freeNode
    e.freeNode = e.nodes[result].nextFree
    e.nodes[result] = node
  else:
    result = e.nodes.len
    e.nodes.add(node)
  inc e.expandedCount
  e.nodeByKey[node.cursor.cursorKey()] = result

proc linkChild(e: TreeTable, parentIndex, nodeIndex: int) =
  ## Inserts a slot into its parent's child list in source sibling order.
  e.nodes[nodeIndex].parent = parentIndex
  var previousIndex = -1
  var currentIndex = e.nodes[parentIndex].firstChild
  while currentIndex >= 0 and e.nodes[currentIndex].childIndex < e.nodes[nodeIndex].childIndex:
    previousIndex = currentIndex
    currentIndex = e.nodes[currentIndex].nextSibling
  e.nodes[nodeIndex].previousSibling = previousIndex
  e.nodes[nodeIndex].nextSibling = currentIndex
  if previousIndex >= 0:
    e.nodes[previousIndex].nextSibling = nodeIndex
  else:
    e.nodes[parentIndex].firstChild = nodeIndex
  if currentIndex >= 0:
    e.nodes[currentIndex].previousSibling = nodeIndex

proc unlinkNode(e: TreeTable, nodeIndex: int) =
  ## Detaches a slot from its parent and siblings without releasing it.
  let parentIndex = e.nodes[nodeIndex].parent
  let previousIndex = e.nodes[nodeIndex].previousSibling
  let nextIndex = e.nodes[nodeIndex].nextSibling
  if previousIndex >= 0:
    e.nodes[previousIndex].nextSibling = nextIndex
  elif parentIndex >= 0:
    e.nodes[parentIndex].firstChild = nextIndex
  if nextIndex >= 0:
    e.nodes[nextIndex].previousSibling = previousIndex
  e.nodes[nodeIndex].parent = -1
  e.nodes[nodeIndex].previousSibling = -1
  e.nodes[nodeIndex].nextSibling = -1

proc releaseNode(e: TreeTable, nodeIndex: int) =
  ## Removes a key mapping and pushes the cleared slot onto the free list.
  e.nodeByKey.del(e.nodes[nodeIndex].cursor.cursorKey())
  e.nodes[nodeIndex] = ExpandedNode(
    parent: -1,
    firstChild: -1,
    nextSibling: -1,
    previousSibling: -1,
    nextFree: e.freeNode)
  e.freeNode = nodeIndex
  dec e.expandedCount

proc initializeTopology(e: TreeTable) =
  ## Resets expanded topology and lookup state to an empty initialized tree.
  e.initialized = true
  e.nodes.setLen(0)
  e.nodeByKey = initTable[string, int]()
  e.rootNode = -1
  e.freeNode = -1
  e.expandedCount = 0
  e.expandAllWork.setLen(0)
  e.expandingAll = false

proc addExpandedNode(e: TreeTable, cursor: TreeCursor, parentIndex: int): int =
  ## Caches a newly expanded cursor and links it below its expanded parent.
  let childCount = cursor.childCount()
  result = e.allocateExpandedNode(ExpandedNode(
    cursor: cursor.clone(),
    childIndex: cursor.index,
    depth: cursor.path.len,
    childCount: childCount,
    totalChildren: childCount,
    parent: parentIndex,
    firstChild: -1,
    nextSibling: -1,
    previousSibling: -1,
    nextFree: -1))
  if parentIndex >= 0:
    e.linkChild(parentIndex, result)
  else:
    e.rootNode = result

proc recomputeTotals(e: TreeTable) =
  ## Recomputes visible descendant totals bottom-up for all expanded slots.
  prof("recomputeTotals")
  if e.rootNode < 0:
    return
  var stack: seq[(int, bool)] = @[]
  stack.add((e.rootNode, false))
  while stack.len > 0:
    let (nodeIndex, visited) = stack.pop()
    if visited:
      var total = e.nodes[nodeIndex].childCount
      var childIndex = e.nodes[nodeIndex].firstChild
      while childIndex >= 0:
        total += e.nodes[childIndex].totalChildren
        childIndex = e.nodes[childIndex].nextSibling
      e.nodes[nodeIndex].totalChildren = total
    else:
      stack.add((nodeIndex, true))
      var childIndex = e.nodes[nodeIndex].firstChild
      while childIndex >= 0:
        stack.add((childIndex, false))
        childIndex = e.nodes[childIndex].nextSibling

proc removeExpandedSubtree(e: TreeTable, nodeIndex: int) =
  ## Unlinks a subtree and releases all of its slots to the free list.
  prof("removeExpandedSubtree")
  let removesRoot = nodeIndex == e.rootNode
  e.unlinkNode(nodeIndex)
  var stack = @[nodeIndex]
  while stack.len > 0:
    let removeIndex = stack.pop()
    var childIndex = e.nodes[removeIndex].firstChild
    while childIndex >= 0:
      let nextIndex = e.nodes[childIndex].nextSibling
      stack.add(childIndex)
      childIndex = nextIndex
    e.releaseNode(removeIndex)
  if removesRoot:
    e.rootNode = -1

iterator expandedSubtree(e: TreeTable, nodeIndex: int): int =
  ## Yields expanded descendants in preorder, excluding the supplied root slot.
  var currentIndex = e.nodes[nodeIndex].firstChild
  while currentIndex >= 0:
    yield currentIndex
    if e.nodes[currentIndex].firstChild >= 0:
      currentIndex = e.nodes[currentIndex].firstChild
      continue
    while currentIndex != nodeIndex and e.nodes[currentIndex].nextSibling < 0:
      currentIndex = e.nodes[currentIndex].parent
    if currentIndex == nodeIndex:
      break
    currentIndex = e.nodes[currentIndex].nextSibling

proc updateExpandedCursor(e: TreeTable, nodeIndex: int, cursor: TreeCursor) =
  ## Replaces a cached cursor and rebases descendants when its path changed.
  prof("updateExpandedCursor")
  let oldPath = e.nodes[nodeIndex].cursor.path
  let newPath = cursor.path
  if oldPath == newPath:
    e.nodes[nodeIndex].cursor = cursor
    e.nodes[nodeIndex].childIndex = cursor.index
    return

  for subtreeIndex in e.expandedSubtree(nodeIndex):
    e.nodes[subtreeIndex].cursor.replacePathPrefix(oldPath.len, newPath)
  e.nodes[nodeIndex].cursor = cursor
  e.nodes[nodeIndex].childIndex = cursor.index

proc findExpandedNode(e: TreeTable, key: string): int =
  ## Returns the active slot for a key, or -1 when it is not expanded.
  prof("findExpandedNode")
  if e.nodeByKey.hasKey(key): e.nodeByKey.getOrQuit(key) else: -1

proc refreshNode(e: TreeTable, cursor: TreeCursor): int =
  ## Refreshes one expanded node and reconciles its expanded direct children.
  prof("refreshNode")
  let nodeIndex = e.findExpandedNode(cursor.cursorKey())
  if nodeIndex < 0:
    return -1

  e.updateExpandedCursor(nodeIndex, cursor.clone())
  e.nodes[nodeIndex].childCount = cursor.childCount()
  var expandedChildIndex = e.nodes[nodeIndex].firstChild
  while expandedChildIndex >= 0:
    let nextExpandedChild = e.nodes[expandedChildIndex].nextSibling
    let resolved = cursor.resolveChild(e.nodes[expandedChildIndex].cursor)
    if resolved == nil:
      e.removeExpandedSubtree(expandedChildIndex)
    else:
      let oldChildIndex = e.nodes[expandedChildIndex].childIndex
      e.updateExpandedCursor(expandedChildIndex, resolved)
      if e.nodes[expandedChildIndex].childIndex != oldChildIndex:
        e.unlinkNode(expandedChildIndex)
        e.linkChild(nodeIndex, expandedChildIndex)
    expandedChildIndex = nextExpandedChild
  return nodeIndex

proc refreshRenderedNode*(e: TreeTable, cursor: TreeCursor) =
  ## Refreshes cached expansion bookkeeping for one row rendered this frame.
  prof("refreshRenderedNode")
  discard e.refreshNode(cursor)
  e.recomputeTotals()

proc refreshRenderedNodes*(e: TreeTable) =
  ## Validates retained visible cursors and their ancestors without scanning
  ## unrelated branches.
  prof("refreshRenderedNodes")
  var refreshedIndexes = initTable[string, int]()
  for renderedCursor in e.renderedCursors:
    var chain: seq[TreeCursor] = @[]
    var chainCursor = renderedCursor.clone()
    var refreshedAncestorIndex = -1
    block:
      prof("cursorChain")
      chain.add(chainCursor.clone())
      while chainCursor.exitChild():
        chain.add(chainCursor.clone())
        if refreshedIndexes.len > 0:
          let ancestorKey = chainCursor.cursorKey()
          let ancestorIndex = refreshedIndexes.getOrDefault(ancestorKey, -1)
          if ancestorIndex >= 0 and ancestorIndex < e.nodes.len and
              e.nodes[ancestorIndex].cursor != nil and
              e.nodes[ancestorIndex].cursor.cursorKey() == ancestorKey:
            refreshedAncestorIndex = ancestorIndex
            break

    if chain.len == 0 or
        (refreshedAncestorIndex < 0 and
          chain[^1].cursorKey() != e.cursor.cursorKey()):
      continue

    prof("loop")
    var current = if refreshedAncestorIndex >= 0:
      e.nodes[refreshedAncestorIndex].cursor.clone()
    else:
      e.cursor.clone()
    var expandedNodeIndex = if refreshedAncestorIndex >= 0:
      refreshedAncestorIndex
    else:
      e.rootNode
    for chainIndex in countdown(chain.high, 0):
      prof("body")
      let currentKey = current.cursorKey()
      let refreshedIndex = refreshedIndexes.getOrDefault(currentKey, -1)
      if refreshedIndex < 0:
        expandedNodeIndex = e.refreshNode(current)
        if expandedNodeIndex < 0:
          break
        refreshedIndexes[currentKey] = expandedNodeIndex
      else:
        if refreshedIndex < e.nodes.len and
            e.nodes[refreshedIndex].cursor != nil and
            e.nodes[refreshedIndex].cursor.cursorKey() == currentKey:
          expandedNodeIndex = refreshedIndex
        else:
          expandedNodeIndex = e.findExpandedNode(currentKey)
          if expandedNodeIndex >= 0:
            refreshedIndexes[currentKey] = expandedNodeIndex
        if expandedNodeIndex < 0:
          break
      if chainIndex == 0:
        break
      let expectedChild = chain[chainIndex - 1]
      let expectedKey = expectedChild.cursorKey()
      var linkedChildIndex = refreshedIndexes.getOrDefault(expectedKey, -1)
      if linkedChildIndex < 0:
        linkedChildIndex = e.findExpandedNode(expectedKey)
      if linkedChildIndex >= 0 and
          linkedChildIndex < e.nodes.len and
          e.nodes[linkedChildIndex].cursor != nil and
          e.nodes[linkedChildIndex].cursor.cursorKey() == expectedKey and
          e.nodes[linkedChildIndex].parent == expandedNodeIndex:
        current = e.nodes[linkedChildIndex].cursor.clone()
        expandedNodeIndex = linkedChildIndex
        continue

      let resolved = current.resolveChild(expectedChild)
      if resolved == nil:
        break
      current = resolved
      expandedNodeIndex = -1
      if chainIndex > 1:
        break
  e.recomputeTotals()

proc seek*(e: TreeTable, targetRow: int): bool =
  ## Positions the frame walk cursor at a visible row using cached subtree totals.
  prof("seek")
  assert e.walkIndex == 0

  e.walkCursor = e.cursor.clone()
  e.walkIndex = 0
  e.walkNode = e.rootNode
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
        echo "failed to enter child ", e.walkIndex, " < ", targetRow, ", ", targetChild
        e.walkIndex = targetRow
        return false
      inc e.walkIndex
      if targetChild > 0:
        if not e.walkCursor.moveNext(targetChild):
          return false
  e.walkIndex = targetRow
  return true

func isAncestorPath*(a, b: seq[int]): bool =
  ## Returns whether `a` is a strict ancestor path of `b`.
  if a.len >= b.len:
    return false
  for i in 0 ..< a.len:
    if a[i] != b[i]:
      return false
  return true

func preorderLess*(a, b: TreeCursor): bool =
  ## Returns whether `a` precedes `b` in a preorder traversal.
  let n = min(a.path.len, b.path.len)
  for i in 0 ..< n:
    if a.path[i] != b.path[i]:
      return a.path[i] < b.path[i]
  return a.path.len < b.path.len

proc toggleNode*(e: var TreeTable, cursor: TreeCursor) =
  ## Toggles expansion while preserving stable slots and linked logical order.
  prof("toggleNode")
  e.expandAllWork.setLen(0)
  e.expandingAll = false
  if not e.initialized:
    e.initialized = true
    e.initializeTopology()
  let key = cursorKey(cursor)
  let idx = e.findExpandedNode(key)
  if idx >= 0:
    e.removeExpandedSubtree(idx)
  else:
    var parentIndex = -1
    if cursor.path.len > 0:
      var parentCursor = cursor.clone()
      if not parentCursor.exitChild():
        return
      parentIndex = e.findExpandedNode(parentCursor.cursorKey())
      if parentIndex < 0:
        return
    discard e.addExpandedNode(cursor, parentIndex)
  e.recomputeTotals()

proc expandNode*(e: TreeTable, cursor: TreeCursor) =
  ## Expands one node if needed while preserving already-expanded descendants.
  e.expandAllWork.setLen(0)
  e.expandingAll = false
  if not e.initialized:
    e.initializeTopology()
    discard e.addExpandedNode(e.cursor, -1)
  if e.findExpandedNode(cursor.cursorKey()) >= 0:
    return
  var parentIndex = -1
  var resolvedCursor = cursor.clone()
  if cursor.path.len > 0:
    var parentCursor = cursor.clone()
    if not parentCursor.exitChild():
      return
    parentIndex = e.findExpandedNode(parentCursor.cursorKey())
    if parentIndex < 0:
      return
    resolvedCursor = parentCursor.resolveChild(cursor)
    if resolvedCursor == nil:
      return
  discard e.addExpandedNode(resolvedCursor, parentIndex)
  e.recomputeTotals()

proc requestTreeTableExpand*(b: var UiBuilder, cursor: TreeCursor): bool =
  ## Queues expansion on the nearest tree table owning the current deferred row.
  for storage in b.nodeStorageParents():
    if storage of TreeTable:
      TreeTable(storage).pendingExpandCursor = cursor.clone()
      return true
  return false

proc ensureNodes(e: var TreeTable) =
  ## Seeds expanded-node storage with only the root on first use.
  if e.initialized:
    return
  e.initialized = true
  e.initializeTopology()
  discard e.addExpandedNode(e.cursor, -1)

proc collapseAll*(e: var TreeTable) =
  ## Collapses the tree back to the root while keeping storage initialized.
  e.expandAllWork.setLen(0)
  e.expandingAll = false
  if e.rootNode < 0:
    e.initializeTopology()
    discard e.addExpandedNode(e.cursor, -1)
    return
  var childIndex = e.nodes[e.rootNode].firstChild
  while childIndex >= 0:
    let nextIndex = e.nodes[childIndex].nextSibling
    e.removeExpandedSubtree(childIndex)
    childIndex = nextIndex
  e.nodes[e.rootNode].cursor = e.cursor.clone()
  e.nodes[e.rootNode].childIndex = e.cursor.index
  e.nodes[e.rootNode].childCount = e.cursor.childCount()
  e.nodes[e.rootNode].totalChildren = e.nodes[e.rootNode].childCount

proc countVisible(e: TreeTable): int =
  ## Returns the root plus all visible descendants of expanded nodes.
  if e.rootNode < 0: 1 else: 1 + e.nodes[e.rootNode].totalChildren

proc treeFocusId(e: TreeTable, cursor: TreeCursor): UiNodeId =
  e.focusRootId.deriveNodeId("tree-table-row:" & cursor.cursorKey())

proc visibleRowIndex(e: TreeTable, cursor: TreeCursor): int =
  ## Resolves a visible cursor to its preorder row using expanded subtree totals.
  if cursor.path.len == 0:
    return 0
  if e.rootNode < 0:
    return -1
  result = 0
  var parentIndex = e.rootNode
  for depthIndex in 0 ..< cursor.path.len:
    if parentIndex < 0:
      return -1
    let childPosition = cursor.path[depthIndex]
    result += childPosition + 1
    var nextParentIndex = -1
    for (childIndex, childNode) in e.expandedChildren(parentIndex):
      if childNode.childIndex < childPosition:
        result += childNode.totalChildren
      elif childNode.childIndex == childPosition:
        nextParentIndex = childIndex
        break
      else:
        break
    if depthIndex < cursor.path.high:
      parentIndex = nextParentIndex

proc focusScopeId(e: TreeTable, cursor: TreeCursor): UiNodeId =
  if cursor.path.len == 0:
    return e.focusRootId
  var parent = cursor.clone()
  if parent.exitChild():
    return e.treeFocusId(parent)
  e.focusRootId

proc registerFocusScopes(b: var UiBuilder, e: TreeTable, cursor: TreeCursor) =
  ## Materializes the expanded ancestor scope chain for a visible row.
  var chain = @[cursor.clone()]
  var ancestor = cursor.clone()
  while ancestor.exitChild():
    chain.add(ancestor.clone())
  var parentScopeId = e.focusRootId
  for chainIndex in countdown(chain.high, 0):
    let scopeCursor = chain[chainIndex]
    if e.findExpandedNode(scopeCursor.cursorKey()) >= 0:
      let scopeId = e.treeFocusId(scopeCursor)
      b.registerFocusScope(scopeId, parentScopeId)
      parentScopeId = scopeId

proc registerFocusTarget(b: var UiBuilder, e: TreeTable, cursor: TreeCursor): UiNodeId =
  result = e.treeFocusId(cursor)
  e.focusCursors[result.nodeIdValue()] = cursor.clone()
  discard b.registerFocusItem(
    result,
    -1,
    e.focusScopeId(cursor),
    {FocusTabStop},
    e.visibleRowIndex(cursor))

proc nextVisibleCursor(e: TreeTable, cursor: TreeCursor): TreeCursor =
  ## Returns the next row in the same visible preorder used by Tab traversal.
  result = cursor.clone()
  if e.nodeIsExpanded(result, 0) and result.enterChild():
    return
  while true:
    if result.moveNext():
      return
    if not result.exitChild():
      return nil

proc previousVisibleCursor(e: TreeTable, cursor: TreeCursor): TreeCursor =
  ## Returns the previous row in the same visible preorder used by Tab traversal.
  result = cursor.clone()
  if not result.movePrev():
    if result.exitChild():
      return
    return nil
  while e.nodeIsExpanded(result, 0):
    var child = result.clone()
    if not child.enterChild():
      break
    while child.moveNext():
      discard
    result = child

proc expandAll*(e: TreeTable) =
  ## Expands every non-leaf node and builds the linked topology in preorder.
  e.initializeTopology()
  let rootIndex = e.addExpandedNode(e.cursor, -1)
  var stack: seq[(TreeCursor, int)] = @[]
  stack.add((e.cursor.clone(), rootIndex))
  while stack.len > 0:
    let (cursor, parentIndex) = stack.pop()
    let childCount = cursor.childCount()
    if childCount > 0:
      var child = cursor.clone()
      if child.enterChild():
        while true:
          if child.childCount() > 0:
            let childNodeIndex = e.addExpandedNode(child, parentIndex)
            stack.add((child.clone(), childNodeIndex))
          if not child.moveNext():
            break
  e.recomputeTotals()

proc startExpandAll*(e: TreeTable) =
  ## Starts a resumable expansion from the root, replacing current expansion state.
  e.initializeTopology()
  let rootIndex = e.addExpandedNode(e.cursor, -1)
  var firstChild = e.cursor.clone()
  if firstChild.enterChild():
    e.expandAllWork.add(ExpandAllWork(
      nextChild: firstChild,
      parentIndex: rootIndex))
  e.expandingAll = e.expandAllWork.len > 0

proc isExpandingAll*(e: TreeTable): bool =
  ## Returns whether an incremental expand-all traversal has unfinished work.
  e.expandingAll

proc continueExpandAll*(e: TreeTable,
  budgetNanoseconds = TreeTableExpandAllBudgetNanoseconds): bool =
  ## Expands nodes until the monotonic time budget expires and returns whether work remains.
  if not e.expandingAll:
    return false
  let started = getMonoTime()
  while e.expandAllWork.len > 0:
    let workIndex = e.expandAllWork.high
    let child = e.expandAllWork[workIndex].nextChild.clone()
    let parentIndex = e.expandAllWork[workIndex].parentIndex
    if not e.expandAllWork[workIndex].nextChild.moveNext():
      e.expandAllWork.setLen(workIndex)

    if child.childCount() > 0:
      let childIndex = e.addExpandedNode(child, parentIndex)
      var ancestorIndex = parentIndex
      while ancestorIndex >= 0:
        e.nodes[ancestorIndex].totalChildren += e.nodes[childIndex].childCount
        ancestorIndex = e.nodes[ancestorIndex].parent
      var grandchild = child.clone()
      if grandchild.enterChild():
        e.expandAllWork.add(ExpandAllWork(
          nextChild: grandchild,
          parentIndex: childIndex))

    if budgetNanoseconds >= 0 and
        (getMonoTime() - started).inNanoseconds >= budgetNanoseconds:
      break

  e.expandingAll = e.expandAllWork.len > 0
  e.expandingAll

proc buildChevronDeferred(b: var UiBuilder, nodeIdx: int, userData: int) =
  ## Builds the deferred chevron; userData selects expanded/down or collapsed/right.
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
  let (data, count) = buildChevronVertices(arena, innerPos, innerSize, dir, color,
    antialiasMeshWidth = b.antialiasMeshWidth)
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

proc treeTableField*(b: var UiBuilder; e: var TreeTable, index: int) =
  ## Renders one row with indentation, expansion control, background, and cells.
  prof("treeTableField")
  let hasChildren = e.walkCursor.childCount() > 0
  let isExpanded = hasChildren and nodeIsExpanded(e, e.walkCursor, 0)

  # Alternating row background (zebra) – drawn first so hover can override.
  if e.alternatingRowBackground:
    let isOdd = (index mod 2) == 1
    let bg = if isOdd:
      if e.hasCustomAlternatingColors: e.alternatingColorOdd
      else: b.themeStyle(UiStyleIndexRowAlt)[].fillColor
    else:
      if e.hasCustomAlternatingColors: e.alternatingColorEven
      else: b.themeStyle(UiStyleIndexRow)[].fillColor
    discard b.fillBackground().backgroundColor(bg)

  let hovered = b.wasHovered(includeChildren = true)
  if e.highlightHoveredRow and hovered:
    let hoverBg = if e.hasCustomHoverColor: e.hoverColor
      else: b.themeStyle(UiStyleIndexButtonHover)[].fillColor
    discard b.fillBackground().backgroundColor(hoverBg)

  # current node is table row, each node created here is one column

  b.debugName("tree-table-row")
  discard b.fitY().gap(4).paddingY(2)

  let rowFocusId = e.treeFocusId(e.walkCursor)
  e.focusCursors[rowFocusId.nodeIdValue()] = e.walkCursor.clone()
  b.registerFocusScopes(e, e.walkCursor)
  discard b.registerFocusItem(
    rowFocusId,
    b.currentNodeIndex,
    e.focusScopeId(e.walkCursor),
    {FocusTabStop},
    index)

  var targetCursor = e.previousVisibleCursor(e.walkCursor)
  if targetCursor != nil:
    b.focusNavigationTarget(rowFocusId, NavUp, b.registerFocusTarget(e, targetCursor))
  targetCursor = e.nextVisibleCursor(e.walkCursor)
  if targetCursor != nil:
    b.focusNavigationTarget(rowFocusId, NavDown, b.registerFocusTarget(e, targetCursor))
  targetCursor = e.walkCursor.clone()
  if targetCursor.movePrev():
    b.shiftFocusNavigationTarget(rowFocusId, NavUp, b.registerFocusTarget(e, targetCursor))
  targetCursor = e.walkCursor.clone()
  if targetCursor.moveNext():
    b.shiftFocusNavigationTarget(rowFocusId, NavDown, b.registerFocusTarget(e, targetCursor))
  if not isExpanded:
    targetCursor = e.walkCursor.clone()
    if targetCursor.exitChild():
      b.focusNavigationTarget(rowFocusId, NavLeft, b.registerFocusTarget(e, targetCursor))
  targetCursor = e.walkCursor.clone()
  if isExpanded and targetCursor.enterChild():
    b.focusNavigationTarget(rowFocusId, NavRight, b.registerFocusTarget(e, targetCursor))

  if b.wasClicked(includeChildren = true):
    discard b.requestFocus(rowFocusId)
  if b.focusedNode == rowFocusId:
    discard b.borderWidth(2.0'f32)
    discard b.borderColor(b.themeStyle(UiStyleIndexAccent)[].borderColor)

  b.layoutHorizontal:
    discard b.fit().gap(2)
    b.node:
      discard b.size(e.walkCursor.depth.float32 * 20, 1)
    b.node:
      b.debugName("symbol")
      discard b.size(14, 14).alignCenter()
      if hasChildren:
        if b.wasClicked(includeChildren = true):
          e.pendingToggleCursor = e.walkCursor.clone()
        # chevron mesh via custom render command (right when collapsed, down when expanded)
        discard b.deferBuild(buildChevronDeferred, if isExpanded: 1 else: 0)

  onRaiseQuit(e.rowRenderer(b, e.walkCursor, index))

iterator tableCells(b: UiBuilder, rowIdx: int): int =
  ## Yields direct row children that participate in tree-table column layout.
  for childIdx in b.children(rowIdx):
    let flags = b.frame.nodes[childIdx].flags
    if AnchorX notin flags and AnchorY notin flags:
      yield childIdx

proc tableCellCount(b: UiBuilder, rowIdx: int): int =
  ## Counts direct row children that participate in tree-table column layout.
  result = 0
  for childIdx in b.tableCells(rowIdx):
    discard childIdx
    inc result

proc treeTableColumnLayout(b: var UiBuilder, nodeIdx: int, userData: int) {.raises: [].} =
  ## Aligns visible row children into table columns and draws optional guides.
  ## Physical indentation and name cells form logical column zero; later cells
  ## map one-to-one to logical columns. Explicit specs support fixed, fit, fill,
  ## and proportional widths; zero userData selects the legacy fit-only layout.
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
    var colWidths: seq[float32] = @[0.0'f32]
    for rowIdx in b.children(nodeIdx):
      var k = 0
      var firstTwoColumns: float32 = 0.0
      for childIdx in b.tableCells(rowIdx):
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
      for childIdx in b.tableCells(rowIdx):
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
              discard b.postProcessChildren(childIdx)
        rowHeight = max(rowHeight, child.size.y)
        cursor += cw + rowGap
        row.contentExtent.x = max(row.contentExtent.x, child.pos.x + child.size.x)
        row.contentExtent.y = max(row.contentExtent.y, child.pos.y + child.size.y)
        k += 1
      for childIdx in b.tableCells(rowIdx):
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
        for childIdx in b.tableCells(rowIdx):
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
      for childIdx in b.tableCells(rowIdx):
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
      for childIdx in b.tableCells(rowIdx):
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
            discard b.postProcessChildren(childIdx)
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
            discard b.postProcessChildren(childIdx)
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
      for childIdx in b.tableCells(rowIdx):
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
            discard b.postProcessChildren(childIdx)
        rowHeight = max(rowHeight, child.size.y)
        cursor += cw + gap
        row.contentExtent.x = max(row.contentExtent.x, child.pos.x + child.size.x)
        row.contentExtent.y = max(row.contentExtent.y, child.pos.y + child.size.y)
        k += 1
      for childIdx in b.tableCells(rowIdx):
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
        let childCount = b.tableCellCount(rowIdx)
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
            let childCount = b.tableCellCount(rowIdx)
            if rightK >= childCount: continue
            var leftIdx = -1
            var rightIdx = -1
            var kk = 0
            for childIdx in b.tableCells(rowIdx):
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
      for childIdx in b.tableCells(rowIdx):
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

proc buildTreeTableRow(b: var UiBuilder, itemIndex: int, userData: int) =
  ## Builds one deferred row by incrementally walking the visible preorder.
  ## The frame walk cursor is shared across increasing virtual-list indices.
  prof("buildTreeTableRow")
  var ctx = b.getOrCreateStorage(b.frame.nodes[userData].addr)
  if ctx.walkCursor == nil:
    ctx.walkCursor = ctx.cursor.clone()
    ctx.walkIndex = 0
  if ctx.walkIndex == 0:
    if not ctx.seek(itemIndex):
      return
  block:
    prof("step")
    while ctx.walkIndex < itemIndex:
      var walkCursor = ctx.walkCursor
      if not stepForward(walkCursor, ctx, ctx.walkNode):
        break
      ctx.walkCursor = walkCursor
      ctx.walkIndex += 1
  ctx.renderedCursors.add(ctx.walkCursor.clone())
  treeTableField(b, ctx, itemIndex)

proc treeTable*(b: var UiBuilder; cursor: TreeCursor, options: TreeTableOptions, rowRenderer: TreeTableRowRenderer) =
  ## Builds a virtualized tree table using the complete options object.
  ## Logical column zero combines indentation and the first renderer cell.
  prof("treeTable")
  var ctx = b.getOrCreateStorage(b.currentNode)
  ctx.focusRootId = b.currentNode.id.deriveNodeId("tree-table-focus-scope")
  b.pushFocusScope(ctx.focusRootId)
  if not ctx.focusCursorsInitialized:
    ctx.focusCursors = initTable[uint64, TreeCursor]()
    ctx.focusCursorsInitialized = true
  if NodeStorageParent notin b.currentNode.flags:
    b.nodeStorageParent()
  ctx.cursor = cursor
  ctx.walkCursor = nil
  ctx.rowRenderer = rowRenderer
  ctx.alternatingRowBackground = options.alternatingRowBackground
  ctx.alternatingColorEven = options.alternatingColorEven
  ctx.alternatingColorOdd = options.alternatingColorOdd
  ctx.hasCustomAlternatingColors = options.hasCustomAlternatingColors
  ctx.highlightHoveredRow = options.highlightHoveredRow
  ctx.hoverColor = options.hoverColor
  ctx.hasCustomHoverColor = options.hasCustomHoverColor
  ensureNodes(ctx)

  let input = b.frameCtx.input
  let rightPressed = KeyRight in input.keysPressed or
    KeyRight in input.keysRepeated or NavRight in input.navigationPressed
  let leftPressed = KeyLeft in input.keysPressed or
    KeyLeft in input.keysRepeated or NavLeft in input.navigationPressed
  if rightPressed and not b.wasFocusNavigationHandled() and
      ctx.focusCursors.hasKey(b.focusedNode.nodeIdValue()):
    let focusedCursor = ctx.focusCursors.getOrQuit(b.focusedNode.nodeIdValue())
    if focusedCursor.childCount() > 0 and
        ctx.findExpandedNode(focusedCursor.cursorKey()) < 0:
      ctx.expandNode(focusedCursor)
      b.anythingAnimating = true
  elif leftPressed and not b.wasFocusNavigationHandled() and
      ctx.focusCursors.hasKey(b.focusedNode.nodeIdValue()):
    let focusedCursor = ctx.focusCursors.getOrQuit(b.focusedNode.nodeIdValue())
    if ctx.findExpandedNode(focusedCursor.cursorKey()) >= 0:
      ctx.toggleNode(focusedCursor)
      b.anythingAnimating = true

  ctx.refreshRenderedNodes()
  ctx.renderedCursors.setLen(0)

  try:
    if ctx.pendingExpandCursor != nil:
      ctx.expandNode(ctx.pendingExpandCursor)
      ctx.pendingExpandCursor = nil
      b.anythingAnimating = true
    let pendingToggleCursor = ctx.pendingToggleCursor
    if pendingToggleCursor != nil:
      toggleNode(ctx, pendingToggleCursor)
      ctx.pendingToggleCursor = nil
      b.anythingAnimating = true
  except:
    return

  b.layoutHorizontal:
    discard b.fit().gap(2)
    if b.button("Expand all"):
      startExpandAll(ctx)
    if b.button("Collapse all"):
      collapseAll(ctx)
    if ctx.isExpandingAll():
      b.label("Expanding..."):
        discard b.alignCenter()

  if ctx.isExpandingAll():
    if ctx.continueExpandAll():
      b.anythingAnimating = true

  let count = ctx.countVisible()
  if b.wasFocusChangedByKeyboard() and ctx.listStorage != nil and
      ctx.focusCursors.hasKey(b.focusedNode.nodeIdValue()):
    let focusedCursor = ctx.focusCursors.getOrQuit(b.focusedNode.nodeIdValue())
    let focusedRow = ctx.visibleRowIndex(focusedCursor)
    if focusedRow >= 0:
      ctx.listStorage.centerItem(focusedRow)
  b.label("Items: " & $count):
    discard b.fitX()
  let hasColumns = options.columns.len > 0
  let hasColumnLines = options.showColumnLines
  let hasIndentLines = options.showIndentationLines
  var layoutUserData = 0
  if hasColumns or hasColumnLines or hasIndentLines:
    var colArr: ArrayView[TableColumn]
    var colPtr: nil ptr UncheckedArray[TableColumn] = nil
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
      alternatingRowBackground: options.alternatingRowBackground,
      alternatingColorEven: options.alternatingColorEven,
      alternatingColorOdd: options.alternatingColorOdd,
      hasCustomAlternatingColors: options.hasCustomAlternatingColors,
      hoverColor: options.hoverColor,
      hasCustomHoverColor: options.hasCustomHoverColor,
    )
    layoutUserData = cast[int](layoutArr.data)
  ctx.listStorage = b.dynamicVirtualList(
    count,
    24.0'f32,
    buildTreeTableRow,
    b.currentNodeIndex,
    treeTableColumnLayout,
    layoutUserData)
  b.popFocusScope()

proc treeTable*(b: var UiBuilder; cursor: TreeCursor, columns: openArray[TableColumn], columnGap: float32, rowRenderer: TreeTableRowRenderer) =
  ## Builds a tree table with explicit column policies and column gap.
  var opts = defaultTreeTableOptions()
  opts.columns = @columns
  opts.columnGap = columnGap
  b.treeTable(cursor, opts, rowRenderer)

proc treeTable*(b: var UiBuilder; cursor: TreeCursor, columns: openArray[TableColumn], rowRenderer: TreeTableRowRenderer) =
  ## Builds a tree table with explicit columns and the default gap.
  b.treeTable(cursor, columns, 4.0'f32, rowRenderer)

proc treeTable*(b: var UiBuilder; cursor: TreeCursor, rowRenderer: TreeTableRowRenderer) =
  ## Builds a tree table with the backwards-compatible fit-only layout.
  b.treeTable(cursor, defaultTreeTableOptions(), rowRenderer)
