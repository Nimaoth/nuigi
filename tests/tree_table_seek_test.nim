import widgets/tree_table

when defined(nimony):
  import std/assertions

proc require(cond: bool, msg: string) =
  when defined(nimony):
    assert cond, msg
  else:
    doAssert(cond, msg)

# ---------------------------------------------------------------------------
# A deterministic tree cursor (mirrors the one used in the property editor UI
# tests): every non-leaf node has `childrenPerNode` children down to `maxDepth`.
# ---------------------------------------------------------------------------

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
  # Deep copy the path: Nim seq assignment aliases the backing array, and
  # stepForward mutates `path` in place (`path[^1] = ...`, `setLen`), so a
  # shallow clone would corrupt the original (e.g. the stored anchor cursors).
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

# ---------------------------------------------------------------------------
# Reference walk: identical to `stepForward` in property_editor.nim, but
# implemented here against the public cursor API + `nodes` list so the test is
# an independent oracle for `seek`.
# ---------------------------------------------------------------------------

proc isExpanded(e: TreeTable, c: TreeCursor, startIndex: int): bool =
  let key = c.cursorKey()
  for i in startIndex .. e.nodes.high:
    if e.nodes[i].cursor != nil and e.nodes[i].cursor.cursorKey() == key:
      return true
  return false

proc naiveStepForward(c: var TreeCursor, e: TreeTable): bool =
  if isExpanded(e, c, 0) and c.enterChild():
    return true
  while true:
    if c.moveNext():
      return true
    if not c.exitChild():
      return false
    if c.moveNext():
      return true

# Full preorder list of visible paths by naive stepping from the root.
proc naiveVisiblePaths(e: TreeTable): seq[seq[int]] =
  var c = e.cursor.clone()
  result = @[]
  result.add(c.path)
  while naiveStepForward(c, e):
    result.add(c.path)

# ---------------------------------------------------------------------------
# Test scaffolding for a single scenario.
# ---------------------------------------------------------------------------

proc navigateTo(root: TreeCursor, path: seq[int]): TreeCursor =
  result = root.clone()
  for p in path:
    if not result.enterChild():
      require(false, "enterChild failed while navigating test path")
      return
    for i in 0 ..< p:
      if not result.moveNext():
        require(false, "moveNext failed while navigating test path")
        return

proc newEditor(maxDepth, branching: int, expandedPaths: seq[seq[int]], full = false): TreeTable =
  result = TreeTable()
  result.cursor = newTreeCursor(maxDepth, branching)
  if full:
    expandAll(result)
  else:
    # Ensure the root is present (downward-closed: expandedPaths may reference it).
    for p in expandedPaths:
      let c = navigateTo(result.cursor, p)
      toggleNode(result, c)

proc runScenario(name: string, maxDepth, branching: int, expandedPaths: seq[seq[int]], full = false) =
  let e = newEditor(maxDepth, branching, expandedPaths, full)

  let expected = naiveVisiblePaths(e)
  let total = expected.len
  # echo expandedPaths
  # if e.nodes.len == 0:
  #   echo name, " e.cursor.path=", e.cursor.path, " node0.path=", " node0.row="
  # else:
  #   echo name, " e.cursor.path=", e.cursor.path, " node0.path=", e.nodes[0].cursor.path, " node0.row=", e.nodes[0].row
  # for i in 0 ..< e.nodes.len:
  #   echo "  node[", i, "].path=", e.nodes[i].cursor.path, " row=", e.nodes[i].row
  # when defined(debug):
  #   echo name, " expected=", expected

  # Seek to every row, both forward and backward order, and compare the cursor
  # the seek lands on with the naive reference path for that row.
  proc checkRow(name: string, e: TreeTable, expected: seq[seq[int]], row: int) =
    # Reset the walk state so each seek is independent (seek requires walkIndex==0).
    e.walkCursor = nil
    e.walkIndex = 0
    # echo "expect ", expected[row]
    let ok = e.seek(row)
    require(ok, name & ": seek(" & $row & ") returned false")
    require(e.walkCursor != nil, name & ": seek(" & $row & ") left walkCursor nil")
    require(e.walkIndex == row,
      name & ": seek(" & $row & ") ended at walkIndex " & $e.walkIndex & " expected " & $row)
    require(e.walkCursor.path == expected[row],
      name & ": seek(" & $row & ") reached the wrong path")

  for row in 0 ..< total:
    checkRow(name, e, expected, row)
  # Backward order must produce identical results (seek must be stateless).
  var row = total - 1
  while row >= 0:
    checkRow(name, e, expected, row)
    dec row

  # Cross-check: seeking every row and collecting the paths must reproduce the
  # entire visible preorder with no duplicates and no gaps.
  var seen: seq[seq[int]] = @[]
  for row in 0 ..< total:
    e.walkCursor = nil
    e.walkIndex = 0
    discard e.seek(row)
    seen.add(e.walkCursor.path)
  require(seen == expected,
    name & ": full seek sweep produced " & $seen.len & " paths, expected " & $expected.len)

  debugLog("  scenario '" & name & "' OK: " & $total & " visible rows")

# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

proc testSeekFullExpansion() =
  # Every node expanded: maxDepth=3, branching=2 => 15 visible rows. This
  # exercises the "skip ahead to next expanded anchor" branch of seek heavily.
  runScenario("full-3x2", 3, 2, @[], full = true)
  # Fully expand by listing every path in preorder.
  var all: seq[seq[int]] = @[]
  proc collect(all: var seq[seq[int]], prefix: seq[int]) =
    for i in 0 ..< 2:
      var p = newSeqOfCap[int](prefix.len + 1)
      for value in prefix:
        p.add(value)
      p.add(i)
      all.add(p)
      if p.len < 3:
        collect(all, p)
  collect(all, @[])
  runScenario("full-explicit-3x2", 3, 2, all)

proc testSeekSparseExpansion() =
  # Partial expansion with a realistic downward-closed set, mixed depths.
  let paths: seq[seq[int]] = @[
    newSeq[int](0), # root
    @[0],
    @[0, 0],
    @[0, 1],
    @[1],
    @[1, 1],
    @[1, 1, 0],
  ]
  runScenario("sparse-3x2", 3, 2, paths)

  # Deeper, sparser tree (maxDepth=5, branching=3) so seek must skip across
  # many collapsed levels between expanded anchors.
  let deep: seq[seq[int]] = @[
    newSeq[int](0),
    @[0],
    @[0, 0],
    @[0, 0, 1],
    @[2],
    @[2, 2],
    @[2, 2, 2],
    @[2, 2, 2, 0],
  ]
  runScenario("sparse-deep-5x3", 5, 3, deep)

  # Only the root expanded: single visible row.
  runScenario("root-only", 4, 3, newSeq[seq[int]](0))

  # Expanded root + first child subtree fully, rest collapsed.
  let branch: seq[seq[int]] = @[
    newSeq[int](0),
    @[0],
    @[0, 0],
    @[0, 1],
  ]
  runScenario("one-branch-3x2", 3, 2, branch)

proc runTreeTableSeekTests*() =
  debugLog("tree table seek tests")
  testSeekFullExpansion()
  testSeekSparseExpansion()

when isMainModule:
  runTreeTableSeekTests()
