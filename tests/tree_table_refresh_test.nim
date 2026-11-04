when defined(nimony):
  {.feature: "lenientnils".}

import nuigi/widgets/tree_table
import tree_table_seek_test

when defined(nimony):
  import std/assertions

proc require(condition: bool, message: string) =
  when defined(nimony):
    assert condition, message
  else:
    doAssert(condition, message)

type
  MutableNode = ref object
    key: string
    children: seq[MutableNode]


type
  MutableTree = ref object
    resolveCalls: int
    exitCalls: int
    hintHits: int
    fallbackSearches: int

  MutableCursor = ref object of TreeCursor
    node: MutableNode
    parents: seq[MutableNode]
    tree: MutableTree

proc copyPath(path: seq[int]): seq[int] =
  result = @[]
  for index in path:
    result.add(index)

method clone(cursor: MutableCursor): TreeCursor {.gcsafe, raises: [].} =
  let copy = MutableCursor(
    node: cursor.node,
    parents: cursor.parents,
    tree: cursor.tree,
    fieldName: cursor.fieldName,
    index: cursor.index,
    path: copyPath(cursor.path))
  return copy

method cursorKey(cursor: MutableCursor): string =
  cursor.node.key

method childCount(cursor: MutableCursor): int =
  cursor.node.children.len

method enterChild(cursor: MutableCursor): bool =
  if cursor.node.children.len == 0:
    return false
  cursor.parents.add(cursor.node)
  let child = cursor.node.children[0]
  cursor.node = child
  cursor.index = 0
  cursor.path.add(0)
  cursor.fieldName = child.key
  return true

method moveNext(cursor: MutableCursor, count: int = 1): bool =
  if cursor.parents.len == 0:
    return false
  let parent = cursor.parents[cursor.parents.len - 1]
  if parent == nil:
    return false
  let siblings = parent.children
  if cursor.index + count >= siblings.len:
    return false
  cursor.index += count
  cursor.path[cursor.path.high] = cursor.index
  let child = siblings[cursor.index]
  cursor.node = child
  cursor.fieldName = child.key
  return true

method exitChild(cursor: MutableCursor): bool =
  inc cursor.tree.exitCalls
  if cursor.parents.len == 0:
    return false
  let parent = cursor.parents[cursor.parents.len - 1]
  if parent == nil:
    return false
  cursor.node = parent
  cursor.parents.setLen(cursor.parents.len - 1)
  cursor.path.setLen(cursor.path.len - 1)
  cursor.index = if cursor.path.len > 0: cursor.path[^1] else: 0
  cursor.fieldName = parent.key
  return true

method resolveChild(cursor: MutableCursor, child: TreeCursor): TreeCursor =
  inc cursor.tree.resolveCalls
  let expectedKey = child.cursorKey()
  var foundIndex = -1
  if child.index >= 0 and child.index < cursor.node.children.len and
      cursor.node.children[child.index].key == expectedKey:
    foundIndex = child.index
    inc cursor.tree.hintHits
  else:
    inc cursor.tree.fallbackSearches
    for index in 0 ..< cursor.node.children.len:
      if cursor.node.children[index].key == expectedKey:
        foundIndex = index
        break
  if foundIndex < 0:
    return nil

  let resolved = MutableCursor(
    node: cursor.node,
    parents: cursor.parents,
    tree: cursor.tree,
    fieldName: cursor.fieldName,
    index: cursor.index,
    path: copyPath(cursor.path))
  resolved.parents.add(cursor.node)
  resolved.node = cursor.node.children[foundIndex]
  resolved.index = foundIndex
  resolved.path.add(foundIndex)
  resolved.fieldName = resolved.node.key
  return resolved

proc newCursor(node: MutableNode, tree: MutableTree): MutableCursor =
  MutableCursor(node: node, tree: tree, fieldName: node.key, path: @[])

proc childCursor(parent: TreeCursor, index: int): TreeCursor =
  result = parent.clone()
  require(result.enterChild(), "parent should have a child")
  if index > 0:
    require(result.moveNext(index), "requested child should exist")

proc expandedIndex(treeTable: TreeTable, key: string): int =
  for index in 0 .. treeTable.nodes.high:
    let cursor = treeTable.nodes[index].cursor
    if cursor != nil and cursor.cursorKey() == key:
      return index
  return -1

proc testVisibleChainRebasesShiftedIndices() =
  let leaf = MutableNode(key: "leaf")
  let branch = MutableNode(key: "branch", children: @[leaf])
  let first = MutableNode(key: "first")
  let root = MutableNode(key: "root", children: @[first, branch])
  let mutableTree = MutableTree()
  let rootCursor = newCursor(root, mutableTree)
  let branchCursor = rootCursor.childCursor(1)
  let leafCursor = branchCursor.childCursor(0)

  var treeTable = newTreeTable(rootCursor)
  treeTable.toggleNode(rootCursor)
  treeTable.toggleNode(branchCursor)
  treeTable.toggleNode(leafCursor)

  root.children = @[MutableNode(key: "inserted"), first, branch]
  treeTable.renderedCursors.setLen(0)
  treeTable.renderedCursors.add(leafCursor)
  treeTable.refreshRenderedNodes()

  let branchIndex = treeTable.expandedIndex("branch")
  let leafIndex = treeTable.expandedIndex("leaf")
  require(branchIndex >= 0, "shifted branch should remain expanded")
  require(leafIndex >= 0, "shifted descendant should remain expanded")
  let branchExpandedCursor = treeTable.nodes[branchIndex].cursor
  let leafExpandedCursor = treeTable.nodes[leafIndex].cursor
  require(branchExpandedCursor != nil and branchExpandedCursor.path == @[2],
    "branch path should use its current sibling index")
  require(leafExpandedCursor != nil and leafExpandedCursor.path == @[2, 0],
    "descendant path should be rebased with its parent")
  require(treeTable.nodes[0].totalChildren == 4,
    "visible count should include the inserted sibling")
  require(mutableTree.fallbackSearches > 0,
    "a stale index hint should fall back to stable-key lookup")

  mutableTree.resolveCalls = 0
  mutableTree.hintHits = 0
  mutableTree.fallbackSearches = 0
  treeTable.renderedCursors = @[treeTable.nodes[leafIndex].cursor]
  treeTable.refreshRenderedNodes()
  require(mutableTree.resolveCalls > 0, "visible chain should be validated")
  require(mutableTree.fallbackSearches == 0,
    "unchanged visible chains should resolve entirely through index hints")

proc testVisibleChainPrunesDeletedAncestor() =
  let leaf = MutableNode(key: "leaf")
  let branch = MutableNode(key: "branch", children: @[leaf])
  let sibling = MutableNode(key: "sibling")
  let root = MutableNode(key: "root", children: @[branch, sibling])
  let mutableTree = MutableTree()
  let rootCursor = newCursor(root, mutableTree)
  let branchCursor = rootCursor.childCursor(0)
  let leafCursor = branchCursor.childCursor(0)

  var treeTable = newTreeTable(rootCursor)
  treeTable.toggleNode(rootCursor)
  treeTable.toggleNode(branchCursor)
  treeTable.toggleNode(leafCursor)

  root.children.delete(0)
  treeTable.renderedCursors.setLen(0)
  treeTable.renderedCursors.add(leafCursor)
  treeTable.refreshRenderedNodes()

  require(treeTable.expandedIndex("branch") < 0,
    "a deleted visible ancestor should be removed")
  require(treeTable.expandedIndex("leaf") < 0,
    "the deleted ancestor's expanded subtree should be removed")
  require(treeTable.expandedCount == 1, "only the expanded root should remain")
  require(treeTable.nodes[0].childCount == 1,
    "root child count should be refreshed before rendering")
  require(treeTable.nodes[0].totalChildren == 1,
    "root visible total should exclude the deleted subtree")

proc testExpandedSlotsRemainStableAndReuseFreeSlots() =
  let first = MutableNode(key: "first")
  let second = MutableNode(key: "second")
  let root = MutableNode(key: "root", children: @[first, second])
  let mutableTree = MutableTree()
  let rootCursor = newCursor(root, mutableTree)
  let firstCursor = rootCursor.childCursor(0)
  let secondCursor = rootCursor.childCursor(1)

  var treeTable = newTreeTable(rootCursor)
  treeTable.toggleNode(rootCursor)
  treeTable.toggleNode(firstCursor)
  treeTable.toggleNode(secondCursor)
  let firstSlot = treeTable.expandedIndex("first")
  let secondSlot = treeTable.expandedIndex("second")

  treeTable.toggleNode(firstCursor)
  require(treeTable.expandedIndex("second") == secondSlot,
    "removing a sibling should not change another node's slot")
  require(treeTable.nodes[firstSlot].cursor == nil,
    "removed expanded nodes should leave an empty slot")

  let third = MutableNode(key: "third")
  root.children.add(third)
  let thirdCursor = rootCursor.childCursor(2)
  treeTable.toggleNode(thirdCursor)
  require(treeTable.expandedIndex("third") == firstSlot,
    "new expanded nodes should reuse the free-list head")
  require(treeTable.expandedIndex("second") == secondSlot,
    "free-slot reuse should preserve existing node slots")
  require(treeTable.expandedCount == 3,
    "expanded count should exclude empty slots")

proc testSharedParentChainsResolveExpandedEdgesOnce() =
  let firstLeaf = MutableNode(key: "first-leaf")
  let secondLeaf = MutableNode(key: "second-leaf")
  let parent = MutableNode(key: "parent", children: @[firstLeaf, secondLeaf])
  let grandparent = MutableNode(key: "grandparent", children: @[parent])
  let root = MutableNode(key: "root", children: @[grandparent])
  let mutableTree = MutableTree()
  let rootCursor = newCursor(root, mutableTree)
  let grandparentCursor = rootCursor.childCursor(0)
  let parentCursor = grandparentCursor.childCursor(0)
  let firstLeafCursor = parentCursor.childCursor(0)
  let secondLeafCursor = parentCursor.childCursor(1)

  var treeTable = newTreeTable(rootCursor)
  treeTable.toggleNode(rootCursor)
  treeTable.toggleNode(grandparentCursor)
  treeTable.toggleNode(parentCursor)

  mutableTree.resolveCalls = 0
  mutableTree.exitCalls = 0
  treeTable.renderedCursors.setLen(0)
  treeTable.renderedCursors.add(firstLeafCursor)
  treeTable.renderedCursors.add(secondLeafCursor)
  treeTable.refreshRenderedNodes()

  require(mutableTree.resolveCalls == 4,
    "shared expanded edges should resolve once, plus once per collapsed leaf")
  require(mutableTree.exitCalls == 5,
    "the second rendered chain should stop ascending at its refreshed parent")

proc testIncrementalExpandAllCompletesAcrossBudgets() =
  let cursor = newTreeCursor(4, 4)
  var expected = newTreeTable(cursor)
  expected.expandAll()

  var incremental = newTreeTable(cursor)
  incremental.startExpandAll()
  require(incremental.isExpandingAll(),
    "incremental expand all should retain work after initialization")
  require(incremental.continueExpandAll(0),
    "a zero budget should process one item and leave larger trees unfinished")
  require(incremental.expandedCount < expected.expandedCount,
    "the first incremental step should not synchronously expand the whole tree")

  var stepCount = 1
  while incremental.continueExpandAll(0):
    inc stepCount
    require(stepCount < 10_000, "incremental expand all should terminate")

  require(stepCount > 1, "incremental expansion should span multiple budget steps")
  require(incremental.expandedCount == expected.expandedCount,
    "incremental expansion should create the same expanded nodes")
  require(incremental.nodes[incremental.rootNode].totalChildren ==
      expected.nodes[expected.rootNode].totalChildren,
    "incremental expansion should produce the same visible row count")

proc testExpandNodeIsIdempotent() =
  let leaf = MutableNode(key: "leaf")
  let branch = MutableNode(key: "branch", children: @[leaf])
  let root = MutableNode(key: "root", children: @[branch])
  let mutableTree = MutableTree()
  let rootCursor = newCursor(root, mutableTree)
  let branchCursor = rootCursor.childCursor(0)
  var treeTable = newTreeTable(rootCursor)

  treeTable.expandNode(branchCursor)
  let expandedCount = treeTable.expandedCount
  let visibleCount = treeTable.nodes[treeTable.rootNode].totalChildren
  require(treeTable.expandedIndex("branch") >= 0,
    "requested node should become expanded")
  require(visibleCount == 2,
    "expanded branch should expose its child in the visible total")

  treeTable.expandNode(branchCursor)
  require(treeTable.expandedCount == expandedCount,
    "expanding an expanded node should not create another slot")
  require(treeTable.nodes[treeTable.rootNode].totalChildren == visibleCount,
    "expanding an expanded node should not change visible totals")

proc testHiddenRootRemainsExpanded() =
  let root = MutableNode(key: "root", children: @[
    MutableNode(key: "first"),
    MutableNode(key: "second")])
  let rootCursor = newCursor(root, MutableTree())
  var treeTable = newTreeTable(rootCursor)
  treeTable.hideRoot = true

  treeTable.toggleNode(rootCursor)
  require(treeTable.rootNode >= 0,
    "a hidden root should be initialized as expanded")
  require(treeTable.nodes[treeTable.rootNode].totalChildren == 2,
    "a hidden expanded root should expose its children")

  treeTable.toggleNode(rootCursor)
  require(treeTable.rootNode >= 0,
    "a hidden root should not be collapsible")
  require(treeTable.expandedCount == 1,
    "repeated hidden-root toggles should not duplicate its expanded slot")

  let defaults = defaultTreeTableOptions()
  require(not defaults.hideRoot,
    "tree tables should render their root by default")
  let hidden = initTreeTableOptions([], hideRoot = true)
  require(hidden.hideRoot,
    "the options initializer should accept hidden-root mode")

proc runTests() =
  debugLog("tree table refresh tests")
  testVisibleChainRebasesShiftedIndices()
  testVisibleChainPrunesDeletedAncestor()
  testExpandedSlotsRemainStableAndReuseFreeSlots()
  testSharedParentChainsResolveExpandedEdgesOnce()
  testIncrementalExpandAllCompletesAcrossBudgets()
  testExpandNodeIsIdempotent()
  testHiddenRootRemainsExpanded()
  runTreeTableSeekTests()
  debugLog("tree table refresh tests succeeded")

when isMainModule:
  runTests()