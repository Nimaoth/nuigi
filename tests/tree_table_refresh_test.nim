import widgets/tree_table
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
  for index in path:
    result.add(index)

method clone(cursor: MutableCursor): TreeCursor =
  let copy = MutableCursor()
  copy.node = cursor.node
  copy.parents = cursor.parents
  copy.tree = cursor.tree
  copy.fieldName = cursor.fieldName
  copy.index = cursor.index
  copy.path = copyPath(cursor.path)
  return copy

method cursorKey(cursor: MutableCursor): string =
  cursor.node.key

method childCount(cursor: MutableCursor): int =
  cursor.node.children.len

method enterChild(cursor: MutableCursor): bool =
  if cursor.node.children.len == 0:
    return false
  cursor.parents.add(cursor.node)
  cursor.node = cursor.node.children[0]
  cursor.index = 0
  cursor.path.add(0)
  cursor.fieldName = cursor.node.key
  return true

method moveNext(cursor: MutableCursor, count: int = 1): bool =
  if cursor.parents.len == 0:
    return false
  let siblings = cursor.parents[^1].children
  if cursor.index + count >= siblings.len:
    return false
  cursor.index += count
  cursor.path[^1] = cursor.index
  cursor.node = siblings[cursor.index]
  cursor.fieldName = cursor.node.key
  return true

method exitChild(cursor: MutableCursor): bool =
  inc cursor.tree.exitCalls
  if cursor.parents.len == 0:
    return false
  cursor.node = cursor.parents[^1]
  cursor.parents.setLen(cursor.parents.len - 1)
  cursor.path.setLen(cursor.path.len - 1)
  cursor.index = if cursor.path.len > 0: cursor.path[^1] else: 0
  cursor.fieldName = cursor.node.key
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

  let resolved = MutableCursor(cursor.clone())
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
    if treeTable.nodes[index].cursor != nil and
        treeTable.nodes[index].cursor.cursorKey() == key:
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

  var treeTable = TreeTable(cursor: rootCursor)
  treeTable.toggleNode(rootCursor)
  treeTable.toggleNode(branchCursor)
  treeTable.toggleNode(leafCursor)

  root.children.insert(MutableNode(key: "inserted"), 0)
  treeTable.refreshRenderedNodes([leafCursor])

  let branchIndex = treeTable.expandedIndex("branch")
  let leafIndex = treeTable.expandedIndex("leaf")
  require(branchIndex >= 0, "shifted branch should remain expanded")
  require(leafIndex >= 0, "shifted descendant should remain expanded")
  require(treeTable.nodes[branchIndex].cursor.path == @[2],
    "branch path should use its current sibling index")
  require(treeTable.nodes[leafIndex].cursor.path == @[2, 0],
    "descendant path should be rebased with its parent")
  require(treeTable.nodes[0].totalChildren == 4,
    "visible count should include the inserted sibling")
  require(mutableTree.fallbackSearches > 0,
    "a stale index hint should fall back to stable-key lookup")

  mutableTree.resolveCalls = 0
  mutableTree.hintHits = 0
  mutableTree.fallbackSearches = 0
  treeTable.refreshRenderedNodes([treeTable.nodes[leafIndex].cursor])
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

  var treeTable = TreeTable(cursor: rootCursor)
  treeTable.toggleNode(rootCursor)
  treeTable.toggleNode(branchCursor)
  treeTable.toggleNode(leafCursor)

  root.children.delete(0)
  treeTable.refreshRenderedNodes([leafCursor])

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

  var treeTable = TreeTable(cursor: rootCursor)
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

  var treeTable = TreeTable(cursor: rootCursor)
  treeTable.toggleNode(rootCursor)
  treeTable.toggleNode(grandparentCursor)
  treeTable.toggleNode(parentCursor)

  mutableTree.resolveCalls = 0
  mutableTree.exitCalls = 0
  treeTable.refreshRenderedNodes([firstLeafCursor, secondLeafCursor])

  require(mutableTree.resolveCalls == 4,
    "shared expanded edges should resolve once, plus once per collapsed leaf")
  require(mutableTree.exitCalls == 5,
    "the second rendered chain should stop ascending at its refreshed parent")

proc runTests() =
  echo "tree table refresh tests"
  testVisibleChainRebasesShiftedIndices()
  testVisibleChainPrunesDeletedAncestor()
  testExpandedSlotsRemainStableAndReuseFreeSlots()
  testSharedParentChainsResolveExpandedEdgesOnce()
  runTreeTableSeekTests()
  echo "tree table refresh tests succeeded"

when isMainModule:
  runTests()