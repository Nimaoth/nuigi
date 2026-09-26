## Virtualized table whose rows are built on demand.
##
## Each direct child created by the row renderer is treated as one table cell.
## Column widths are resolved across the currently rendered row batch, then the
## dynamic virtual list caches the resulting row heights.

import nuigi
import nuigi/core/[arena, array_view]
import nuigi/debug/profiler
import nuigi/widgets
import nuigi/widgets/dynamic_virtuallist
import std/math

type
  ListTableOptions* = object
    columns*: seq[TableColumn]
    columnGap*: float32
    itemHeightHint*: float32

  ListTableLayout = object
    columnGap: float32
    columnCount: int
    columns: nil ptr UncheckedArray[TableColumn]

proc defaultListTableOptions*(): ListTableOptions =
  ## Creates list-table options with fitted columns and a 24 px row hint.
  ListTableOptions(
    columns: @[],
    columnGap: 4.0'f32,
    itemHeightHint: 24.0'f32)

proc initListTableOptions*(columns: openArray[TableColumn],
    columnGap: float32 = 4.0'f32,
    itemHeightHint: float32 = 24.0'f32): ListTableOptions =
  ## Creates options from explicit column policies, gap, and row-height hint.
  ListTableOptions(
    columns: @columns,
    columnGap: max(0.0'f32, columnGap),
    itemHeightHint: max(1.0'f32, itemHeightHint))

proc listTableColumnLayout(b: var UiBuilder, nodeIdx: int, userData: int) {.raises: [].} =
  prof("listTableColumnLayout")
  if userData == 0 or nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let data = cast[ptr ListTableLayout](userData)
  let columnCount = data.columnCount
  if columnCount <= 0:
    return

  let listNode = b.frame.nodes[nodeIdx].addr
  let listStyle = b.nodeStyle(listNode)
  let contentWidth = max(0.0'f32,
    listNode.size.x - listStyle.paddingX * 2.0'f32)
  let columnGap = max(0.0'f32, data.columnGap)
  let totalGap = columnGap * max(0, columnCount - 1).float32
  var widths = b.frame.arena[].allocArray(columnCount, float32)
  var weights = b.frame.arena[].allocArray(columnCount, float32)
  # Arena allocs are NOT zeroed: every column kind below assigns only one of
  # the two arrays, so initialize both (garbage weights > 0 would clobber
  # fitted widths with garbage-derived shares every frame).
  for columnIndex in 0 ..< columnCount:
    widths[columnIndex] = 0.0'f32
    weights[columnIndex] = 0.0'f32

  for columnIndex in 0 ..< columnCount:
    let column = data.columns[columnIndex]
    case column.kind
    of TableColumnFixed:
      widths[columnIndex] = max(0.0'f32, column.fixedWidth.round())
    of TableColumnFit:
      widths[columnIndex] = 0.0'f32
    of TableColumnFill:
      weights[columnIndex] = 1.0'f32
    of TableColumnProportional:
      weights[columnIndex] = max(0.0001'f32, column.proportional)

  for rowIdx in b.children(nodeIdx):
    var columnIndex = 0
    for cellIdx in b.children(rowIdx):
      if columnIndex >= columnCount:
        break
      if data.columns[columnIndex].kind == TableColumnFit:
        widths[columnIndex] = max(widths[columnIndex],
          b.frame.nodes[cellIdx].size.x)
      inc columnIndex

  var fixedWidth = totalGap
  var totalWeight = 0.0'f32
  for columnIndex in 0 ..< columnCount:
    if weights[columnIndex] > 0.0'f32:
      totalWeight += weights[columnIndex]
    else:
      fixedWidth += widths[columnIndex]
  if totalWeight > 0.0'f32:
    let remainingWidth = max(0.0'f32, contentWidth - fixedWidth)
    for columnIndex in 0 ..< columnCount:
      if weights[columnIndex] > 0.0'f32:
        widths[columnIndex] =
          (remainingWidth * weights[columnIndex] / totalWeight).round()

  for rowIdx in b.children(nodeIdx):
    let row = b.frame.nodes[rowIdx].addr
    var columnIndex = 0
    var cursorX = 0.0'f32
    var rowHeight = 0.0'f32
    for cellIdx in b.children(rowIdx):
      let cell = b.frame.nodes[cellIdx].addr
      cell.pos.x = cursorX
      cell.pos.y = 0.0'f32
      if columnIndex < columnCount:
        let oldWidth = cell.size.x
        cell.size.x = widths[columnIndex]
        cell.flags.incl SizeXKnown
        if cell.size.x != oldWidth:
          discard b.postProcessChildren(cellIdx)
        cursorX += cell.size.x
        if columnIndex + 1 < columnCount:
          cursorX += columnGap
      else:
        cursorX += cell.size.x + columnGap
      rowHeight = max(rowHeight, cell.size.y)
      row.contentExtent.x = max(row.contentExtent.x, cell.pos.x + cell.size.x)
      row.contentExtent.y = max(row.contentExtent.y, cell.pos.y + cell.size.y)
      inc columnIndex
    for cellIdx in b.children(rowIdx):
      let cell = b.frame.nodes[cellIdx].addr
      cell.pos.y = ((rowHeight - cell.size.y) * 0.5'f32).floor()
    row.flags.incl FitY
    b.updateNodeFit(row)

proc listTable*(b: var UiBuilder,
    itemCount: int,
    options: ListTableOptions,
    rowRenderer: UiDynamicVirtualListItemProc,
    userData: int = 0): UiDynamicVirtualListStorage {.discardable.} =
  ## Builds a dynamic virtual list and aligns each row's direct children.
  var columnData: ArrayView[TableColumn]
  var columns: nil ptr UncheckedArray[TableColumn] = nil
  if options.columns.len > 0:
    columnData = b.frame.arena[].allocArray(options.columns.len, TableColumn)
    for columnIndex in 0 ..< options.columns.len:
      columnData[columnIndex] = options.columns[columnIndex]
    columns = columnData.data

  var layoutData = b.frame.arena[].allocArray(1, ListTableLayout)
  layoutData[0] = ListTableLayout(
    columnGap: max(0.0'f32, options.columnGap),
    columnCount: options.columns.len,
    columns: columns)
  b.dynamicVirtualList(
    itemCount,
    max(1.0'f32, options.itemHeightHint),
    rowRenderer,
    userData,
    listTableColumnLayout,
    cast[int](layoutData.data))

proc listTable*(b: var UiBuilder,
    itemCount: int,
    itemHeightHint: float32,
    columns: openArray[TableColumn],
    rowRenderer: UiDynamicVirtualListItemProc,
    userData: int = 0,
    columnGap: float32 = 4.0'f32): UiDynamicVirtualListStorage {.discardable.} =
  ## Builds a list table from explicit row and column sizing parameters.
  b.listTable(itemCount,
    initListTableOptions(columns, columnGap, itemHeightHint),
    rowRenderer,
    userData)