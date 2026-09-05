import std/[monotimes, times]

import widgets/tree_table

type
  BenchNode = ref object
    key: string
    parent: BenchNode
    children: seq[BenchNode]

  BenchCursor = ref object of TreeCursor
    node: BenchNode
    parents: seq[BenchNode]

proc copyPath(path: seq[int]): seq[int] =
  result = @[]
  for index in path:
    result.add(index)

method clone(cursor: BenchCursor): TreeCursor =
  BenchCursor(
    node: cursor.node,
    parents: cursor.parents,
    fieldName: cursor.fieldName,
    index: cursor.index,
    path: copyPath(cursor.path))

method cursorKey(cursor: BenchCursor): string =
  cursor.node.key

method childCount(cursor: BenchCursor): int =
  cursor.node.children.len

method enterChild(cursor: BenchCursor): bool =
  if cursor.node.children.len == 0:
    return false
  cursor.parents.add(cursor.node)
  cursor.node = cursor.node.children[0]
  cursor.index = 0
  cursor.path.add(0)
  return true

method moveNext(cursor: BenchCursor, count: int = 1): bool =
  if cursor.parents.len == 0:
    return false
  let siblings = cursor.parents[^1].children
  if cursor.index + count >= siblings.len:
    return false
  cursor.index += count
  cursor.path[cursor.path.high] = cursor.index
  cursor.node = siblings[cursor.index]
  return true

method exitChild(cursor: BenchCursor): bool =
  if cursor.parents.len == 0:
    return false
  cursor.node = cursor.parents[^1]
  cursor.parents.setLen(cursor.parents.len - 1)
  cursor.path.setLen(cursor.path.len - 1)
  cursor.index = if cursor.path.len > 0: cursor.path[^1] else: 0
  return true

method resolveChild(cursor: BenchCursor, child: TreeCursor): TreeCursor =
  let expected = BenchCursor(child)
  var childIndex = expected.index
  if childIndex < 0 or childIndex >= cursor.node.children.len or
      cursor.node.children[childIndex] != expected.node:
    childIndex = -1
    for index in 0 ..< cursor.node.children.len:
      if cursor.node.children[index] == expected.node:
        childIndex = index
        break
  if childIndex < 0:
    return nil
  let resolved = BenchCursor(cursor.clone())
  resolved.parents.add(cursor.node)
  resolved.node = expected.node
  resolved.index = childIndex
  resolved.path.add(childIndex)
  return resolved

proc addChild(parent: BenchNode, key: string): BenchNode =
  result = BenchNode(key: key, parent: parent)
  parent.children.add(result)

proc cursorFor(node: BenchNode): BenchCursor =
  var nodes: seq[BenchNode] = @[]
  var current: nil BenchNode = node
  while current != nil:
    nodes.add(current)
    current = current.parent

  result = BenchCursor(node: nodes[^1], fieldName: nodes[^1].key)
  for nodeIndex in countdown(nodes.high - 1, 0):
    let child = nodes[nodeIndex]
    let parent = nodes[nodeIndex + 1]
    var childIndex = 0
    while parent.children[childIndex] != child:
      inc childIndex
    result.parents.add(parent)
    result.node = child
    result.index = childIndex
    result.path.add(childIndex)

proc buildScenario(prefixCount, depth: int): (TreeTable, TreeCursor) =
  let root = BenchNode(key: "root")
  let prefix = root.addChild("prefix")
  for index in 0 ..< prefixCount:
    discard prefix.addChild("prefix-" & $index).addChild("value-" & $index)

  var chainNode = root.addChild("chain-0")
  for level in 1 ..< depth:
    chainNode = chainNode.addChild("chain-" & $level)
  let tree = TreeTable(cursor: cursorFor(root))
  tree.expandAll()
  return (tree, cursorFor(chainNode))

proc benchmark(name: string, prefixCount, depth, iterations: int) =
  let (tree, visibleCursor) = buildScenario(prefixCount, depth)
  tree.renderedCursors = @[visibleCursor]
  for warmup in 0 ..< 3:
    tree.refreshRenderedNodes()

  let started = getMonoTime()
  for iteration in 0 ..< iterations:
    tree.refreshRenderedNodes()
  let elapsed = (getMonoTime() - started).inNanoseconds.float64 / 1_000_000.0
  debugLog(name & ": " & $(elapsed / iterations.float64) & " ms/refresh (" &
    $tree.expandedCount & " expanded nodes, depth " & $depth & ")")

proc benchmarkSharedChain(depth, leafCount, iterations: int) =
  let root = BenchNode(key: "root")
  var expandedNodes = @[root]
  var parent = root
  for level in 0 ..< depth:
    parent = parent.addChild("chain-" & $level)
    expandedNodes.add(parent)

  var visibleCursors: seq[TreeCursor] = @[]
  for index in 0 ..< leafCount:
    let leaf = parent.addChild("leaf-" & $index)
    visibleCursors.add(cursorFor(leaf))

  var tree = TreeTable(cursor: cursorFor(root))
  for node in expandedNodes:
    tree.toggleNode(cursorFor(node))
  tree.renderedCursors = visibleCursors
  for warmup in 0 ..< 3:
    tree.refreshRenderedNodes()

  let started = getMonoTime()
  for iteration in 0 ..< iterations:
    tree.refreshRenderedNodes()
  let elapsed = (getMonoTime() - started).inNanoseconds.float64 / 1_000_000.0
  debugLog("shared chain: " & $(elapsed / iterations.float64) & " ms/refresh (" &
    $leafCount & " rendered leaves, depth " & $depth & ")")

proc benchmarkShiftedSubtree(childCount, iterations: int) =
  let root = BenchNode(key: "root")
  let branch = root.addChild("branch")
  for index in 0 ..< childCount:
    discard branch.addChild("child-" & $index).addChild("value-" & $index)

  let tree = TreeTable(cursor: cursorFor(root))
  tree.expandAll()
  let visibleNode = branch.children[^1]
  tree.renderedCursors = @[TreeCursor(cursorFor(visibleNode))]

  let started = getMonoTime()
  for iteration in 0 ..< iterations:
    root.children.insert(BenchNode(key: "inserted", parent: root), 0)
    tree.refreshRenderedNodes()
    root.children.delete(0)
    tree.refreshRenderedNodes()
  let refreshCount = iterations * 2
  let elapsed = (getMonoTime() - started).inNanoseconds.float64 / 1_000_000.0
  debugLog("shifted subtree: " & $(elapsed / refreshCount.float64) &
    " ms/refresh (" & $tree.expandedCount & " expanded nodes)")

when isMainModule:
  debugLog("tree table refresh benchmark")
  benchmark("front chain", 0, 64, 100)
  benchmark("late chain", 10_000, 64, 20)
  benchmarkSharedChain(64, 1_000, 100)
  benchmarkShiftedSubtree(10_000, 10)