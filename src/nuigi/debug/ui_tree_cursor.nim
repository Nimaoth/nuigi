import nuigi
import nuigi/widgets/tree_table

include nuigi/util/compat2

# Walks the live UiBuilder node tree without caching.
# Each call recomputes children from `builder.previousFrame.nodes` links.
# `cutoff` snapshots `frame.nodes.len` at cursor creation so the
# virtual-list rows created for the tree-table itself are not
# visible as children (avoids self-recursion). No other caching.
type
  UiTreeCursor* = ref object of TreeCursor
    builder*: ptr UiBuilder
    rootIdx*: int
    nodeIdx*: int
    cutoff*: int

proc uiNodeLabel(b: ptr UiBuilder, idx: int): string =
  if b == nil or idx < 0 or idx >= b.previousFrame.nodes.len:
    return ""
  let n = b.previousFrame.nodes[idx]
  let dn = nodeDebugName(n)
  if dn != "<unnamed>":
    return dn
  result = "node " & $idx & " id=" & $nodeIdValue(n.id)

proc validChildrenCount(b: ptr UiBuilder, parentIdx, cutoff: int): int =
  if b == nil or parentIdx < 0 or parentIdx >= b.previousFrame.nodes.len:
    return 0
  let tail = b.previousFrame.nodes[parentIdx].lastChild
  if tail < 0:
    return 0
  let start = int(b.previousFrame.nodes[int(tail)].nextSibling)
  var cur = start
  var cnt = 0
  while true:
    if cur >= 0 and cur < cutoff and cur < b.previousFrame.nodes.len:
      inc cnt
    if cur == int(tail):
      break
    cur = int(b.previousFrame.nodes[cur].nextSibling)
    if cur == start: # safety against corrupt ring
      break
  return cnt

proc firstValidChild(b: ptr UiBuilder, parentIdx, cutoff: int): int =
  if b == nil or parentIdx < 0 or parentIdx >= b.previousFrame.nodes.len:
    return -1
  let tail = b.previousFrame.nodes[parentIdx].lastChild
  if tail < 0:
    return -1
  let start = int(b.previousFrame.nodes[int(tail)].nextSibling)
  var cur = start
  while true:
    if cur >= 0 and cur < cutoff and cur < b.previousFrame.nodes.len:
      return cur
    if cur == int(tail):
      break
    cur = int(b.previousFrame.nodes[cur].nextSibling)
  return -1

proc nextValidSibling(b: ptr UiBuilder, parentIdx, curIdx, cutoff: int): int =
  if b == nil or parentIdx < 0 or curIdx < 0:
    return -1
  let tail = b.previousFrame.nodes[parentIdx].lastChild
  if tail < 0 or curIdx == int(tail):
    return -1
  var cur = int(b.previousFrame.nodes[curIdx].nextSibling)
  let start = int(b.previousFrame.nodes[int(tail)].nextSibling)
  while true:
    if cur >= 0 and cur < cutoff and cur < b.previousFrame.nodes.len:
      return cur
    if cur == int(tail):
      break
    # skip invalid (beyond cutoff) siblings
    if cur == start:
      break
    cur = int(b.previousFrame.nodes[cur].nextSibling)
  return -1

proc prevValidSibling(b: ptr UiBuilder, parentIdx, curIdx, cutoff: int): int =
  if b == nil or parentIdx < 0 or parentIdx >= b.previousFrame.nodes.len:
    return -1
  let tail = b.previousFrame.nodes[parentIdx].lastChild
  if tail < 0:
    return -1
  let start = int(b.previousFrame.nodes[int(tail)].nextSibling)
  if curIdx == start:
    return -1
  var cur = start
  var prev = -1
  while true:
    if cur == curIdx:
      # prev holds last valid before curIdx
      if prev >= 0 and prev < cutoff:
        return prev
      # need to scan back for last valid before curIdx
      # `prev` may be invalid, search from start
      var scan = start
      var lastValid = -1
      while scan != curIdx:
        if scan >= 0 and scan < cutoff and scan < b.previousFrame.nodes.len:
          lastValid = scan
        if scan == int(tail):
          break
        scan = int(b.previousFrame.nodes[scan].nextSibling)
      return lastValid
    if cur >= 0 and cur < cutoff and cur < b.previousFrame.nodes.len:
      prev = cur
    if cur == int(tail):
      break
    cur = int(b.previousFrame.nodes[cur].nextSibling)
  return -1

proc indexOfChild(b: ptr UiBuilder, parentIdx, childIdx, cutoff: int): int =
  if b == nil or parentIdx < 0 or parentIdx >= b.previousFrame.nodes.len:
    return 0
  let tail = b.previousFrame.nodes[parentIdx].lastChild
  if tail < 0:
    return 0
  let start = int(b.previousFrame.nodes[int(tail)].nextSibling)
  var cur = start
  var pos = 0
  var validPos = -1
  while true:
    if cur >= 0 and cur < cutoff and cur < b.previousFrame.nodes.len:
      if cur == childIdx:
        return pos
      inc pos
    elif cur == childIdx:
      # child itself is beyond cutoff – shouldn't happen for valid nodes,
      # but return its valid position as if it were counted
      return pos
    if cur == int(tail):
      break
    cur = int(b.previousFrame.nodes[cur].nextSibling)
    if cur == start:
      break
  return 0

method clone*(c: UiTreeCursor): TreeCursor =
  let r = UiTreeCursor()
  r.builder = c.builder
  r.rootIdx = c.rootIdx
  r.nodeIdx = c.nodeIdx
  r.cutoff = c.cutoff
  r.index = c.index
  r.fieldName = c.fieldName
  r.path = c.path
  return r

method cursorKey*(c: UiTreeCursor): string =
  if c.builder == nil or c.nodeIdx < 0 or c.nodeIdx >= c.builder.previousFrame.nodes.len:
    return ""
  return $c.builder.previousFrame.nodes[c.nodeIdx].id.uint64

method childCount*(c: UiTreeCursor): int =
  if c.builder == nil:
    return 0
  if c.nodeIdx < 0 or c.nodeIdx >= c.builder.previousFrame.nodes.len:
    return 0
  if c.nodeIdx >= c.cutoff:
    return 0
  return validChildrenCount(c.builder, c.nodeIdx, c.cutoff)

method enterChild*(c: UiTreeCursor): bool =
  if c.builder == nil:
    return false
  if c.nodeIdx < 0 or c.nodeIdx >= c.builder.previousFrame.nodes.len:
    return false
  if c.nodeIdx >= c.cutoff:
    return false
  let first = firstValidChild(c.builder, c.nodeIdx, c.cutoff)
  if first < 0:
    return false
  c.nodeIdx = first
  c.index = 0
  c.path.add(0)
  c.fieldName = uiNodeLabel(c.builder, c.nodeIdx)
  return true

method moveNext*(c: UiTreeCursor, count: int = 1): bool =
  if c.builder == nil:
    return false
  if count <= 0:
    return true
  if c.nodeIdx == c.rootIdx:
    return false
  var cur = c.nodeIdx
  for _ in 0 ..< count:
    if cur < 0 or cur >= c.builder.previousFrame.nodes.len:
      return false
    let parent = int(c.builder.previousFrame.nodes[cur].parent)
    if parent < 0 or parent >= c.builder.previousFrame.nodes.len:
      return false
    let nxt = nextValidSibling(c.builder, parent, cur, c.cutoff)
    if nxt < 0:
      return false
    cur = nxt
  c.nodeIdx = cur
  # recompute index as position among valid siblings
  let parent = int(c.builder.previousFrame.nodes[cur].parent)
  c.index = indexOfChild(c.builder, parent, cur, c.cutoff)
  if c.path.len > 0:
    c.path[^1] = c.index
  c.fieldName = uiNodeLabel(c.builder, c.nodeIdx)
  return true

method movePrev*(c: UiTreeCursor, count: int = 1): bool =
  if c.builder == nil:
    return false
  if count <= 0:
    return true
  if c.nodeIdx == c.rootIdx:
    return false
  var cur = c.nodeIdx
  for _ in 0 ..< count:
    if cur < 0 or cur >= c.builder.previousFrame.nodes.len:
      return false
    let parent = int(c.builder.previousFrame.nodes[cur].parent)
    if parent < 0 or parent >= c.builder.previousFrame.nodes.len:
      return false
    let prv = prevValidSibling(c.builder, parent, cur, c.cutoff)
    if prv < 0:
      return false
    cur = prv
  c.nodeIdx = cur
  let parent = int(c.builder.previousFrame.nodes[cur].parent)
  c.index = indexOfChild(c.builder, parent, cur, c.cutoff)
  if c.path.len > 0:
    c.path[^1] = c.index
  c.fieldName = uiNodeLabel(c.builder, c.nodeIdx)
  return true

method exitChild*(c: UiTreeCursor): bool =
  if c.builder == nil:
    return false
  if c.nodeIdx == c.rootIdx:
    return false
  if c.nodeIdx < 0 or c.nodeIdx >= c.builder.previousFrame.nodes.len:
    return false
  let parent = int(c.builder.previousFrame.nodes[c.nodeIdx].parent)
  if parent < 0 or parent >= c.builder.previousFrame.nodes.len:
    return false
  if c.path.len > 0:
    c.path.setLen(c.path.len - 1)
  c.nodeIdx = parent
  if parent == c.rootIdx:
    c.index = 0
  else:
    let grand = int(c.builder.previousFrame.nodes[parent].parent)
    if grand < 0 or grand >= c.builder.previousFrame.nodes.len:
      c.index = 0
    else:
      c.index = indexOfChild(c.builder, grand, parent, c.cutoff)
  c.fieldName = uiNodeLabel(c.builder, c.nodeIdx)
  return true

proc uiTreeCursor*(b: var UiBuilder, rootIdx: int = 0): UiTreeCursor =
  ## Create a cursor rooted at `rootIdx` in `b`'s current frame.
  ## No caching is performed; every navigation call walks `b.previousFrame.nodes`.
  ## `cutoff` snapshots `b.previousFrame.nodes.len` so rows created for the
  ## tree-table itself are not visited (avoids self-recursion).
  let cutoff = b.previousFrame.nodes.len
  let idx = if rootIdx >= 0 and rootIdx < cutoff: rootIdx else: 0
  result = UiTreeCursor()
  result.builder = addr b
  result.rootIdx = idx
  result.nodeIdx = idx
  result.cutoff = cutoff
  result.index = 0
  result.path = @[]
  result.fieldName = uiNodeLabel(result.builder, idx)

proc uiTreeCursor*(b: ptr UiBuilder, rootIdx: int = 0): UiTreeCursor =
  if b == nil:
    result = UiTreeCursor()
    result.builder = nil
    result.rootIdx = 0
    result.nodeIdx = 0
    result.cutoff = 0
    result.index = 0
    result.path = @[]
    result.fieldName = ""
    return result
  let cutoff = b.previousFrame.nodes.len
  let idx = if rootIdx >= 0 and rootIdx < cutoff: rootIdx else: 0
  result = UiTreeCursor()
  result.builder = b
  result.rootIdx = idx
  result.nodeIdx = idx
  result.cutoff = cutoff
  result.index = 0
  result.path = @[]
  result.fieldName = uiNodeLabel(b, idx)
