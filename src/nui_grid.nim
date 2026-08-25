import nui, nui_flex, arena, array_view, profiler, mymath

type
  UiGridTrackKind* = enum
    GridTrackAuto
    GridTrackPixels
    GridTrackFraction

  UiGridAutoFlow* = enum
    GridAutoFlowRow
    GridAutoFlowColumn

  UiGridTrack* = object
    kind*: UiGridTrackKind
    value*: float32

  UiNodeGridParent* = object
    columns*: ArrayView[UiGridTrack]
    rows*: ArrayView[UiGridTrack]
    autoFlow*: UiGridAutoFlow
    justifyItems*: UiFlexAlign
    alignItems*: UiFlexAlign
    justifyContent*: UiFlexAlignContent
    alignContent*: UiFlexAlignContent

    rowGap*: float32
    columnGap*: float32

  UiNodeGridChild* = object
    columnStart*: int32
    rowStart*: int32
    columnSpan*: int32
    rowSpan*: int32
    justifySelf*: UiFlexAlign
    alignSelf*: UiFlexAlign

  UiGridPlacedItem = object
    child: ptr UiNode
    colStart: int32
    rowStart: int32
    colSpan: int32
    rowSpan: int32

proc applyGridLayoutToChildren(b: var UiBuilder, parentIdx: int, parentGrid: ptr UiNodeGridParent)
proc pushGridDebugRenderCommands*(b: var UiBuilder, idx: int, contentOrigin, contentSize: Vec2, layoutIndex: int32, clipStack: seq[UiClipRect])
proc resolveGridLayoutScratch(b: var UiBuilder, parentIdx: int, parentGrid: ptr UiNodeGridParent, layoutContentSize: Vec2,
  rowGapOut, columnGapOut: var float32,
  usedColsOut, usedRowsOut: var int,
  placedItems: var ArrayView[UiGridPlacedItem],
  colPositions, rowPositions, colSizes, rowSizes: var ArrayView[float32]): bool {.raises: [].}

var defaultGridParentStorage* = UiNodeGridParent(
  autoFlow: GridAutoFlowRow,
  justifyItems: FlexAlignStretch,
  alignItems: FlexAlignStretch,
  justifyContent: FlexContentStart,
  alignContent: FlexContentStart,
  rowGap: -1.0'f32,
  columnGap: -1.0'f32,
)

var defaultGridChildStorage* = UiNodeGridChild(
  columnStart: 0,
  rowStart: 0,
  columnSpan: 1,
  rowSpan: 1,
  justifySelf: FlexAlignAuto,
  alignSelf: FlexAlignAuto,
)

proc defaultGridParent*(): UiNodeGridParent =
  defaultGridParentStorage

proc defaultGridChild*(): UiNodeGridChild =
  defaultGridChildStorage

proc ensureNodeGridParent*(b: var UiBuilder, node: ptr UiNode): ptr UiNodeGridParent {.inline.} =
  let layout = b.ensureNodeCustomLayout(node).addr
  if layout.userData == 0:
    var dataArr = b.frame.arena[].allocArray(1, UiNodeGridParent)
    dataArr.data()[0] = defaultGridParent()
    layout.userData = cast[int](dataArr.data())
  cast[ptr UiNodeGridParent](layout.userData)

proc ensureNodeGridChild*(b: var UiBuilder, node: ptr UiNode): ptr UiNodeGridChild {.inline.} =
  let layout = b.ensureNodeCustomChildLayout(node).addr
  if layout.userData == 0:
    var dataArr = b.frame.arena[].allocArray(1, UiNodeGridChild)
    dataArr.data()[0] = defaultGridChild()
    layout.userData = cast[int](dataArr.data())
  cast[ptr UiNodeGridChild](layout.userData)

proc nodeGridParent*(b: UiBuilder, idx: int): ptr UiNodeGridParent {.inline.} =
  let n = b.frame.nodes[idx]
  let slot = int(n.customLayoutIndex)
  if slot > 0 and slot <= b.frame.customLayouts.len:
    let layout = b.frame.customLayouts[slot - 1]
    if layout.userData != 0:
      cast[ptr UiNodeGridParent](layout.userData)
    else:
      addr(defaultGridParentStorage)
  else:
    addr(defaultGridParentStorage)

proc nodeGridChild*(b: UiBuilder, idx: int): ptr UiNodeGridChild {.inline.} =
  let n = b.frame.nodes[idx]
  let slot = int(n.customChildLayoutIndex)
  if slot > 0 and slot <= b.frame.customLayouts.len:
    let layout = b.frame.customLayouts[slot - 1]
    if layout.userData != 0:
      cast[ptr UiNodeGridChild](layout.userData)
    else:
      addr(defaultGridChildStorage)
  else:
    addr(defaultGridChildStorage)

proc nodeGridParent*(b: UiBuilder, node: ptr UiNode): ptr UiNodeGridParent {.inline.} =
  let slot = int(node.customLayoutIndex)
  if slot > 0 and slot <= b.frame.customLayouts.len:
    let layout = b.frame.customLayouts[slot - 1]
    if layout.userData != 0:
      cast[ptr UiNodeGridParent](layout.userData)
    else:
      addr(defaultGridParentStorage)
  else:
    addr(defaultGridParentStorage)

proc nodeGridChild*(b: UiBuilder, node: ptr UiNode): ptr UiNodeGridChild {.inline.} =
  let slot = int(node.customChildLayoutIndex)
  if slot > 0 and slot <= b.frame.customLayouts.len:
    let layout = b.frame.customLayouts[slot - 1]
    if layout.userData != 0:
      cast[ptr UiNodeGridChild](layout.userData)
    else:
      addr(defaultGridChildStorage)
  else:
    addr(defaultGridChildStorage)

proc setNodeGridParent*(b: var UiBuilder, idx: int, value: UiNodeGridParent) {.inline.} =
  b.ensureNodeGridParent(b.frame.nodes[idx].addr)[] = value

proc setNodeGridChild*(b: var UiBuilder, idx: int, value: UiNodeGridChild) {.inline.} =
  b.ensureNodeGridChild(b.frame.nodes[idx].addr)[] = value

proc currentNodeGridParent*(b: var UiBuilder): ptr UiNodeGridParent {.inline.} =
  b.nodeGridParent(b.currentNode)

proc currentNodeGridChild*(b: var UiBuilder): ptr UiNodeGridChild {.inline.} =
  b.nodeGridChild(b.currentNode)

proc setCurrentNodeGridParent*(b: var UiBuilder, value: UiNodeGridParent) {.inline.} =
  b.ensureNodeGridParent(b.currentNode)[] = value

proc setCurrentNodeGridChild*(b: var UiBuilder, value: UiNodeGridChild) {.inline.} =
  b.ensureNodeGridChild(b.currentNode)[] = value

proc gridCustomLayout(b: var UiBuilder, nodeIdx: int, userData: int) {.raises: [].} =
  let parentGrid = cast[ptr UiNodeGridParent](userData)
  if parentGrid == nil:
    return
  try:
    b.applyGridLayoutToChildren(nodeIdx, parentGrid)
  except:
    discard

proc isGridLayout*(flags: UiFlags): bool {.inline.} =
  GridLayout in flags

    # defaultGridParent: UiNodeGridParent(
    #   autoFlow: GridAutoFlowRow,
    #   justifyItems: FlexAlignStretch,
    #   alignItems: FlexAlignStretch,
    #   justifyContent: FlexContentStart,
    #   alignContent: FlexContentStart,
    #   rowGap: -1.0'f32,
    #   columnGap: -1.0'f32,
    # ),
    # defaultGridChild: UiNodeGridChild(
    #   columnStart: 0,
    #   rowStart: 0,
    #   columnSpan: 1,
    #   rowSpan: 1,
    #   justifySelf: FlexAlignAuto,
    #   alignSelf: FlexAlignAuto,
    # ),

proc gridLayout*(b: var UiBuilder, value = true): var UiBuilder {.discardable.} =
  if value:
    b.currentNode.flags.incl GridLayout
    b.currentNode.flags.excl FlexLayout
    discard b.customLayout(gridCustomLayout, cast[int](b.ensureNodeGridParent(b.currentNode)))
  else:
    b.currentNode.flags.excl GridLayout
    if b.currentNode.customLayoutIndex > 0 and b.frame.customLayouts[b.currentNode.customLayoutIndex - 1].layoutProc == gridCustomLayout:
      b.frame.customLayouts[b.currentNode.customLayoutIndex - 1] = default(UiNodeCustomLayout)
      b.currentNode.customLayoutIndex = 0
  b

proc gridAuto*(): UiGridTrack {.inline.} =
  UiGridTrack(kind: GridTrackAuto, value: 0.0'f32)

proc gridPx*(value: float32): UiGridTrack {.inline.} =
  UiGridTrack(kind: GridTrackPixels, value: max(0.0'f32, value))

proc gridFr*(value: float32): UiGridTrack {.inline.} =
  UiGridTrack(kind: GridTrackFraction, value: max(0.0'f32, value))

proc gridTemplateColumns*(b: var UiBuilder, tracks: openArray[UiGridTrack]): var UiBuilder {.discardable.} =
  let grid = b.ensureNodeGridParent(b.currentNode)
  grid.columns = b.frame.arena[].allocEmptyArray(max(1, tracks.len), UiGridTrack)
  for i in 0 ..< tracks.len:
    grid.columns.add tracks[i]
  b.currentNode.flags.incl PostProcessChildren
  b

proc gridTemplateRows*(b: var UiBuilder, tracks: openArray[UiGridTrack]): var UiBuilder {.discardable.} =
  let grid = b.ensureNodeGridParent(b.currentNode)
  grid.rows = b.frame.arena[].allocEmptyArray(max(1, tracks.len), UiGridTrack)
  for i in 0 ..< tracks.len:
    grid.rows.add tracks[i]
  b.currentNode.flags.incl PostProcessChildren
  b

proc gridAutoFlow*(b: var UiBuilder, value: UiGridAutoFlow): var UiBuilder {.discardable.} =
  b.ensureNodeGridParent(b.currentNode).autoFlow = value
  b.currentNode.flags.incl PostProcessChildren
  b

proc gridJustifyItems*(b: var UiBuilder, value: UiFlexAlign): var UiBuilder {.discardable.} =
  b.ensureNodeGridParent(b.currentNode).justifyItems = value
  b.currentNode.flags.incl PostProcessChildren
  b

proc gridAlignItems*(b: var UiBuilder, value: UiFlexAlign): var UiBuilder {.discardable.} =
  b.ensureNodeGridParent(b.currentNode).alignItems = value
  b.currentNode.flags.incl PostProcessChildren
  b

proc gridJustifyContent*(b: var UiBuilder, value: UiFlexAlignContent): var UiBuilder {.discardable.} =
  b.ensureNodeGridParent(b.currentNode).justifyContent = value
  b.currentNode.flags.incl PostProcessChildren
  b

proc gridAlignContent*(b: var UiBuilder, value: UiFlexAlignContent): var UiBuilder {.discardable.} =
  b.ensureNodeGridParent(b.currentNode).alignContent = value
  b.currentNode.flags.incl PostProcessChildren
  b

proc gridRowGap*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  b.ensureNodeGridParent(b.currentNode).rowGap = max(0.0'f32, value)
  b.currentNode.flags.incl PostProcessChildren
  b

proc gridColumnGap*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  b.ensureNodeGridParent(b.currentNode).columnGap = max(0.0'f32, value)
  b.currentNode.flags.incl PostProcessChildren
  b

proc gridGaps*(b: var UiBuilder, row, column: float32): var UiBuilder {.discardable.} =
  let grid = b.ensureNodeGridParent(b.currentNode)
  grid.rowGap = max(0.0'f32, row)
  grid.columnGap = max(0.0'f32, column)
  b.currentNode.flags.incl PostProcessChildren
  b

proc markParentForPostProcessExt(b: var UiBuilder) {.inline.} =
  if b.stack.len <= 0:
    return
  let parentIdx = b.currentNode.parent
  if parentIdx >= 0:
    b.frame.nodes[parentIdx].flags.incl PostProcessChildren

proc gridColumn*(b: var UiBuilder, start: int32, span = 1'i32): var UiBuilder {.discardable.} =
  let grid = b.ensureNodeGridChild(b.currentNode)
  grid.columnStart = max(0'i32, start)
  grid.columnSpan = max(1'i32, span)
  b.markParentForPostProcessExt()
  b

proc gridRow*(b: var UiBuilder, start: int32, span = 1'i32): var UiBuilder {.discardable.} =
  let grid = b.ensureNodeGridChild(b.currentNode)
  grid.rowStart = max(0'i32, start)
  grid.rowSpan = max(1'i32, span)
  b.markParentForPostProcessExt()
  b

proc gridArea*(b: var UiBuilder, columnStart, rowStart: int32, columnSpan = 1'i32, rowSpan = 1'i32): var UiBuilder {.discardable.} =
  let grid = b.ensureNodeGridChild(b.currentNode)
  grid.columnStart = max(0'i32, columnStart)
  grid.rowStart = max(0'i32, rowStart)
  grid.columnSpan = max(1'i32, columnSpan)
  grid.rowSpan = max(1'i32, rowSpan)
  b.markParentForPostProcessExt()
  b

proc gridJustifySelf*(b: var UiBuilder, value: UiFlexAlign): var UiBuilder {.discardable.} =
  b.ensureNodeGridChild(b.currentNode).justifySelf = value
  b.markParentForPostProcessExt()
  b

proc gridAlignSelf*(b: var UiBuilder, value: UiFlexAlign): var UiBuilder {.discardable.} =
  b.ensureNodeGridChild(b.currentNode).alignSelf = value
  b.markParentForPostProcessExt()
  b

proc pushGridDebugRenderCommands*(b: var UiBuilder, idx: int, contentOrigin, contentSize: Vec2, layoutIndex: int32, clipStack: seq[UiClipRect]) =
  if not b.debugDrawGridLines:
    return
  if idx < 0 or idx >= b.frame.nodes.len:
    return

  let parent = b.frame.nodes[idx].addr
  if not isGridLayout(parent.flags):
    return
  let parentGrid = b.nodeGridParent(parent)

  let layoutCheckpoint = b.frame.arena[].checkpoint()
  var placedItems = default(ArrayView[UiGridPlacedItem])
  var colPositions = default(ArrayView[float32])
  var rowPositions = default(ArrayView[float32])
  var colSizes = default(ArrayView[float32])
  var rowSizes = default(ArrayView[float32])
  var rowGap = 0.0'f32
  var columnGap = 0.0'f32
  var usedCols = 0
  var usedRows = 0
  if b.resolveGridLayoutScratch(idx, parentGrid, contentSize, rowGap, columnGap, usedCols, usedRows,
      placedItems, colPositions, rowPositions, colSizes, rowSizes):
    let lineColor = rgba(0.98'f32, 0.82'f32, 0.30'f32, 0.85'f32)
    let lineThickness = 1.0'f32
    let topY = contentOrigin.y + rowPositions[0]
    let bottomY = contentOrigin.y + rowPositions[usedRows - 1] + rowSizes[usedRows - 1]
    let leftX = contentOrigin.x + colPositions[0]
    let rightX = contentOrigin.x + colPositions[usedCols - 1] + colSizes[usedCols - 1]

    let verticalLineHeight = max(0.0'f32, bottomY - topY)
    var lastVerticalX = -1.0e30'f32
    for i in 0 ..< usedCols:
      let startX = contentOrigin.x + colPositions[i]
      let endX = startX + colSizes[i]
      if startX - lastVerticalX > 0.001'f32:
        b.pushRenderCommand(layoutIndex, UiRenderCommand(
          kind: CmdRectFill,
          nodeIndex: idx.int32,
          color: lineColor,
          pos: vec2(startX, topY),
          size: vec2(lineThickness, verticalLineHeight),
        ), clipStack)
        lastVerticalX = startX
      if endX - lastVerticalX > 0.001'f32:
        b.pushRenderCommand(layoutIndex, UiRenderCommand(
          kind: CmdRectFill,
          nodeIndex: idx.int32,
          color: lineColor,
          pos: vec2(endX, topY),
          size: vec2(lineThickness, verticalLineHeight),
        ), clipStack)
        lastVerticalX = endX

    let horizontalLineWidth = max(0.0'f32, rightX - leftX)
    var lastHorizontalY = -1.0e30'f32
    for i in 0 ..< usedRows:
      let startY = contentOrigin.y + rowPositions[i]
      let endY = startY + rowSizes[i]
      if startY - lastHorizontalY > 0.001'f32:
        b.pushRenderCommand(layoutIndex, UiRenderCommand(
          kind: CmdRectFill,
          nodeIndex: idx.int32,
          color: lineColor,
          pos: vec2(leftX, startY),
          size: vec2(horizontalLineWidth, lineThickness),
        ), clipStack)
        lastHorizontalY = startY
      if endY - lastHorizontalY > 0.001'f32:
        b.pushRenderCommand(layoutIndex, UiRenderCommand(
          kind: CmdRectFill,
          nodeIndex: idx.int32,
          color: lineColor,
          pos: vec2(leftX, endY),
          size: vec2(horizontalLineWidth, lineThickness),
        ), clipStack)
        lastHorizontalY = endY

  b.frame.arena[].restoreCheckpoint(layoutCheckpoint)

proc resolveGridLayoutScratch(b: var UiBuilder, parentIdx: int, parentGrid: ptr UiNodeGridParent, layoutContentSize: Vec2,
    rowGapOut, columnGapOut: var float32,
    usedColsOut, usedRowsOut: var int,
    placedItems: var ArrayView[UiGridPlacedItem],
    colPositions, rowPositions, colSizes, rowSizes: var ArrayView[float32]): bool {.raises: [].} =
  if parentIdx < 0 or parentIdx >= b.frame.nodes.len:
    return false
  if parentGrid == nil:
    return false

  let parent = b.frame.nodes[parentIdx].addr
  if not isGridLayout(parent.flags):
    return false
  let contentW = max(0.0'f32, layoutContentSize.x)
  let contentH = max(0.0'f32, layoutContentSize.y)
  let fallbackGap = max(0.0'f32, b.nodeGap(parent))
  rowGapOut = if parentGrid.rowGap >= 0.0'f32: max(0.0'f32, parentGrid.rowGap) else: fallbackGap
  columnGapOut = if parentGrid.columnGap >= 0.0'f32: max(0.0'f32, parentGrid.columnGap) else: fallbackGap

  let childTotal = b.childCount(parentIdx)
  if childTotal <= 0:
    return false

  var explicitCols = parentGrid.columns
  var explicitRows = parentGrid.rows
  let explicitColsData = explicitCols.data()
  let explicitRowsData = explicitRows.data()
  let baseCols = max(1, explicitCols.len)
  let baseRows = max(1, explicitRows.len)
  let maxCols = if parentGrid.autoFlow == GridAutoFlowColumn: baseCols + childTotal else: baseCols
  let maxRows = if parentGrid.autoFlow == GridAutoFlowRow: baseRows + childTotal else: baseRows

  var occupied = b.frame.arena[].allocArray(maxCols * maxRows, bool)
  for i in 0 ..< occupied.len:
    occupied[i] = false

  placedItems = b.frame.arena[].allocEmptyArray(childTotal, UiGridPlacedItem)

  template cellIndex(row, col: int): int =
    row * maxCols + col

  template fitsAt(rowStart, colStart, rowSpan, colSpan: int): bool =
    rowStart >= 0 and colStart >= 0 and rowStart + rowSpan <= maxRows and colStart + colSpan <= maxCols

  var autoRow = 0
  var autoCol = 0

  for childIdx in b.children(parentIdx):
    let child = b.frame.nodes[childIdx].addr
    let childGrid = b.nodeGridChild(child)
    let colSpan = max(1, childGrid.columnSpan.int)
    let rowSpan = max(1, childGrid.rowSpan.int)
    var placedRow = -1
    var placedCol = -1

    let requestedCol = if childGrid.columnStart > 0: childGrid.columnStart.int - 1 else: -1
    let requestedRow = if childGrid.rowStart > 0: childGrid.rowStart.int - 1 else: -1

    if requestedCol >= 0 and requestedRow >= 0:
      if fitsAt(requestedRow, requestedCol, rowSpan, colSpan):
        var blocked = false
        for rowOffset in 0 ..< rowSpan:
          for colOffset in 0 ..< colSpan:
            if occupied[cellIndex(requestedRow + rowOffset, requestedCol + colOffset)]:
              blocked = true
        if not blocked:
          placedRow = requestedRow
          placedCol = requestedCol

    if placedRow < 0 and requestedCol >= 0:
      for rowCandidate in 0 ..< maxRows:
        if not fitsAt(rowCandidate, requestedCol, rowSpan, colSpan):
          continue
        var blocked = false
        for rowOffset in 0 ..< rowSpan:
          for colOffset in 0 ..< colSpan:
            if occupied[cellIndex(rowCandidate + rowOffset, requestedCol + colOffset)]:
              blocked = true
        if not blocked:
          placedRow = rowCandidate
          placedCol = requestedCol
          break

    if placedRow < 0 and requestedRow >= 0:
      for colCandidate in 0 ..< maxCols:
        if not fitsAt(requestedRow, colCandidate, rowSpan, colSpan):
          continue
        var blocked = false
        for rowOffset in 0 ..< rowSpan:
          for colOffset in 0 ..< colSpan:
            if occupied[cellIndex(requestedRow + rowOffset, colCandidate + colOffset)]:
              blocked = true
        if not blocked:
          placedRow = requestedRow
          placedCol = colCandidate
          break

    if placedRow < 0:
      if parentGrid.autoFlow == GridAutoFlowColumn:
        var colCandidate = autoCol
        while placedRow < 0 and colCandidate < maxCols:
          var rowCandidate = if colCandidate == autoCol: autoRow else: 0
          while rowCandidate < maxRows:
            if fitsAt(rowCandidate, colCandidate, rowSpan, colSpan):
              var blocked = false
              for rowOffset in 0 ..< rowSpan:
                for colOffset in 0 ..< colSpan:
                  if occupied[cellIndex(rowCandidate + rowOffset, colCandidate + colOffset)]:
                    blocked = true
              if not blocked:
                placedRow = rowCandidate
                placedCol = colCandidate
                break
            inc rowCandidate
          inc colCandidate
      else:
        var rowCandidate = autoRow
        while placedRow < 0 and rowCandidate < maxRows:
          var colCandidate = if rowCandidate == autoRow: autoCol else: 0
          while colCandidate < maxCols:
            if fitsAt(rowCandidate, colCandidate, rowSpan, colSpan):
              var blocked = false
              for rowOffset in 0 ..< rowSpan:
                for colOffset in 0 ..< colSpan:
                  if occupied[cellIndex(rowCandidate + rowOffset, colCandidate + colOffset)]:
                    blocked = true
              if not blocked:
                placedRow = rowCandidate
                placedCol = colCandidate
                break
            inc colCandidate
          inc rowCandidate

    if placedRow < 0 or placedCol < 0:
      continue

    for rowOffset in 0 ..< rowSpan:
      for colOffset in 0 ..< colSpan:
        occupied[cellIndex(placedRow + rowOffset, placedCol + colOffset)] = true

    placedItems.add UiGridPlacedItem(
      child: child,
      colStart: placedCol.int32,
      rowStart: placedRow.int32,
      colSpan: colSpan.int32,
      rowSpan: rowSpan.int32,
    )

    if parentGrid.autoFlow == GridAutoFlowColumn:
      autoCol = placedCol
      autoRow = min(maxRows - 1, placedRow + rowSpan)
      if autoRow >= maxRows:
        autoRow = 0
        autoCol = min(maxCols - 1, placedCol + colSpan)
    else:
      autoRow = placedRow
      autoCol = min(maxCols - 1, placedCol + colSpan)
      if autoCol >= maxCols:
        autoCol = 0
        autoRow = min(maxRows - 1, placedRow + rowSpan)

  if placedItems.len <= 0:
    return false

  usedColsOut = baseCols
  usedRowsOut = baseRows
  for i in 0 ..< placedItems.len:
    usedColsOut = max(usedColsOut, placedItems[i].colStart.int + placedItems[i].colSpan.int)
    usedRowsOut = max(usedRowsOut, placedItems[i].rowStart.int + placedItems[i].rowSpan.int)

  colSizes = b.frame.arena[].allocArray(usedColsOut, float32)
  rowSizes = b.frame.arena[].allocArray(usedRowsOut, float32)
  var colFr = b.frame.arena[].allocArray(usedColsOut, float32)
  var rowFr = b.frame.arena[].allocArray(usedRowsOut, float32)
  for i in 0 ..< usedColsOut:
    colSizes[i] = 0.0'f32
    colFr[i] = 0.0'f32
    if i < explicitCols.len:
      let track = explicitColsData[i]
      case track.kind
      of GridTrackPixels:
        colSizes[i] = max(0.0'f32, track.value)
      of GridTrackFraction:
        colFr[i] = max(0.0'f32, track.value)
      of GridTrackAuto:
        discard
  for i in 0 ..< usedRowsOut:
    rowSizes[i] = 0.0'f32
    rowFr[i] = 0.0'f32
    if i < explicitRows.len:
      let track = explicitRowsData[i]
      case track.kind
      of GridTrackPixels:
        rowSizes[i] = max(0.0'f32, track.value)
      of GridTrackFraction:
        rowFr[i] = max(0.0'f32, track.value)
      of GridTrackAuto:
        discard

  for i in 0 ..< placedItems.len:
    let item = placedItems[i]
    let contentSize = b.contentSize(item.child)
    let childW = max(0.0'f32, contentSize.x)
    let childH = max(0.0'f32, contentSize.y)
    let requiredW = max(0.0'f32, childW - columnGapOut * max(0, item.colSpan.int - 1).float32)
    let requiredH = max(0.0'f32, childH - rowGapOut * max(0, item.rowSpan.int - 1).float32)
    let perCol = requiredW / item.colSpan.float32
    let perRow = requiredH / item.rowSpan.float32
    for colOffset in 0 ..< item.colSpan.int:
      let colIdx = item.colStart.int + colOffset
      if colIdx >= explicitCols.len or explicitColsData[colIdx].kind == GridTrackAuto:
        colSizes[colIdx] = max(colSizes[colIdx], perCol)
    for rowOffset in 0 ..< item.rowSpan.int:
      let rowIdx = item.rowStart.int + rowOffset
      if rowIdx >= explicitRows.len or explicitRowsData[rowIdx].kind == GridTrackAuto:
        rowSizes[rowIdx] = max(rowSizes[rowIdx], perRow)

  let totalColumnGaps = columnGapOut * max(0, usedColsOut - 1).float32
  let totalRowGaps = rowGapOut * max(0, usedRowsOut - 1).float32
  var fixedColSum = 0.0'f32
  var fixedRowSum = 0.0'f32
  var totalColFr = 0.0'f32
  var totalRowFr = 0.0'f32
  for i in 0 ..< usedColsOut:
    fixedColSum += colSizes[i]
    totalColFr += colFr[i]
  for i in 0 ..< usedRowsOut:
    fixedRowSum += rowSizes[i]
    totalRowFr += rowFr[i]

  let colFrSpace = max(0.0'f32, contentW - fixedColSum - totalColumnGaps)
  let rowFrSpace = max(0.0'f32, contentH - fixedRowSum - totalRowGaps)
  if totalColFr > 0.0'f32:
    for i in 0 ..< usedColsOut:
      if colFr[i] > 0.0'f32:
        colSizes[i] = colFrSpace * (colFr[i] / totalColFr)
  if totalRowFr > 0.0'f32:
    for i in 0 ..< usedRowsOut:
      if rowFr[i] > 0.0'f32:
        rowSizes[i] = rowFrSpace * (rowFr[i] / totalRowFr)

  var gridWidth = totalColumnGaps
  var gridHeight = totalRowGaps
  for i in 0 ..< usedColsOut:
    gridWidth += colSizes[i]
  for i in 0 ..< usedRowsOut:
    gridHeight += rowSizes[i]

  var colStartOffset = 0.0'f32
  var rowStartOffset = 0.0'f32
  var extraColGap = 0.0'f32
  var extraRowGap = 0.0'f32
  let colFree = contentW - gridWidth
  let rowFree = contentH - gridHeight

  case parentGrid.justifyContent
  of FlexContentEnd:
    colStartOffset = max(0.0'f32, colFree)
  of FlexContentCenter:
    colStartOffset = max(0.0'f32, colFree * 0.5'f32)
  of FlexContentStretch:
    if colFree > 0.0'f32 and usedColsOut > 0:
      let add = colFree / usedColsOut.float32
      for i in 0 ..< usedColsOut:
        colSizes[i] += add
  of FlexContentSpaceBetween:
    if usedColsOut > 1 and colFree > 0.0'f32:
      extraColGap = colFree / (usedColsOut - 1).float32
  of FlexContentSpaceAround:
    if usedColsOut > 0 and colFree > 0.0'f32:
      extraColGap = colFree / usedColsOut.float32
      colStartOffset = extraColGap * 0.5'f32
  of FlexContentSpaceEvenly:
    if colFree > 0.0'f32:
      extraColGap = colFree / (usedColsOut + 1).float32
      colStartOffset = extraColGap
  of FlexContentStart:
    discard

  case parentGrid.alignContent
  of FlexContentEnd:
    rowStartOffset = max(0.0'f32, rowFree)
  of FlexContentCenter:
    rowStartOffset = max(0.0'f32, rowFree * 0.5'f32)
  of FlexContentStretch:
    if rowFree > 0.0'f32 and usedRowsOut > 0:
      let add = rowFree / usedRowsOut.float32
      for i in 0 ..< usedRowsOut:
        rowSizes[i] += add
  of FlexContentSpaceBetween:
    if usedRowsOut > 1 and rowFree > 0.0'f32:
      extraRowGap = rowFree / (usedRowsOut - 1).float32
  of FlexContentSpaceAround:
    if usedRowsOut > 0 and rowFree > 0.0'f32:
      extraRowGap = rowFree / usedRowsOut.float32
      rowStartOffset = extraRowGap * 0.5'f32
  of FlexContentSpaceEvenly:
    if rowFree > 0.0'f32:
      extraRowGap = rowFree / (usedRowsOut + 1).float32
      rowStartOffset = extraRowGap
  of FlexContentStart:
    discard

  colPositions = b.frame.arena[].allocArray(usedColsOut, float32)
  rowPositions = b.frame.arena[].allocArray(usedRowsOut, float32)
  var cursorX = colStartOffset
  for i in 0 ..< usedColsOut:
    colPositions[i] = cursorX
    cursorX += colSizes[i]
    if i < usedColsOut - 1:
      cursorX += columnGapOut + extraColGap
  var cursorY = rowStartOffset
  for i in 0 ..< usedRowsOut:
    rowPositions[i] = cursorY
    cursorY += rowSizes[i]
    if i < usedRowsOut - 1:
      cursorY += rowGapOut + extraRowGap

  result = usedColsOut > 0 and usedRowsOut > 0

proc applyGridLayoutToChildren(b: var UiBuilder, parentIdx: int, parentGrid: ptr UiNodeGridParent) =
  if parentIdx < 0 or parentIdx >= b.frame.nodes.len:
    return
  if parentGrid == nil:
    return

  let parent = b.frame.nodes[parentIdx].addr
  if not isGridLayout(parent.flags):
    return

  let layoutCheckpoint = b.frame.arena[].checkpoint()
  prof("grid")
  let nodeStyle = b.nodeStyle(parent)
  let contentSize = vec2(
    max(0.0'f32, parent.size.x - nodeStyle.paddingX * 2),
    max(0.0'f32, parent.size.y - nodeStyle.paddingY * 2),
  )
  var placedItems = default(ArrayView[UiGridPlacedItem])
  var colPositions = default(ArrayView[float32])
  var rowPositions = default(ArrayView[float32])
  var colSizes = default(ArrayView[float32])
  var rowSizes = default(ArrayView[float32])
  var rowGap = 0.0'f32
  var columnGap = 0.0'f32
  var usedCols = 0
  var usedRows = 0

  if b.resolveGridLayoutScratch(parentIdx, parentGrid, contentSize, rowGap, columnGap, usedCols, usedRows,
      placedItems, colPositions, rowPositions, colSizes, rowSizes):
    for i in 0 ..< placedItems.len:
      let item = placedItems[i]
      let child = item.child
      let childGrid = b.nodeGridChild(child)
      let colIdx = item.colStart.int
      let rowIdx = item.rowStart.int
      var areaW = 0.0'f32
      var areaH = 0.0'f32
      for colOffset in 0 ..< item.colSpan.int:
        areaW += colSizes[colIdx + colOffset]
      for rowOffset in 0 ..< item.rowSpan.int:
        areaH += rowSizes[rowIdx + rowOffset]
      areaW += columnGap * max(0, item.colSpan.int - 1).float32
      areaH += rowGap * max(0, item.rowSpan.int - 1).float32

      var justify = childGrid.justifySelf
      if justify == FlexAlignAuto:
        justify = parentGrid.justifyItems
      if justify == FlexAlignAuto:
        justify = FlexAlignStart
      if FillX in child.flags and childGrid.justifySelf == FlexAlignAuto:
        justify = FlexAlignStretch

      var align = childGrid.alignSelf
      if align == FlexAlignAuto:
        align = parentGrid.alignItems
      if align == FlexAlignAuto:
        align = FlexAlignStart
      if FillY in child.flags and childGrid.alignSelf == FlexAlignAuto:
        align = FlexAlignStretch

      let oldSize = child.size

      if justify == FlexAlignStretch:
        child.size.x = max(0.0'f32, areaW)
      else:
        child.flags.incl FitX
        b.updateNodeFit(child)
      if align == FlexAlignStretch:
        child.size.y = max(0.0'f32, areaH)
      else:
        child.flags.incl FitY
        b.updateNodeFit(child)
      b.clampNodeSize(child)

      if oldSize != child.size:
        child.flags.incl SizeDirty

      var offsetX = 0.0'f32
      case justify
      of FlexAlignCenter:
        offsetX = max(0.0'f32, (areaW - child.size.x) * 0.5'f32)
      of FlexAlignEnd:
        offsetX = max(0.0'f32, areaW - child.size.x)
      of FlexAlignStretch, FlexAlignStart, FlexAlignBaseline, FlexAlignAuto:
        discard

      var offsetY = 0.0'f32
      case align
      of FlexAlignCenter:
        offsetY = max(0.0'f32, (areaH - child.size.y) * 0.5'f32)
      of FlexAlignEnd:
        offsetY = max(0.0'f32, areaH - child.size.y)
      of FlexAlignStretch, FlexAlignStart, FlexAlignBaseline, FlexAlignAuto:
        discard

      child.pos.x = colPositions[colIdx] + offsetX
      child.pos.y = rowPositions[rowIdx] + offsetY

  b.frame.arena[].restoreCheckpoint(layoutCheckpoint)
