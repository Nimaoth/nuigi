## Flexbox-style layout extension for nuigi nodes.
##
## Stores flex container and child properties in builder-side arrays and
## resolves direction, wrapping, basis, growth, shrinkage, gaps, alignment,
## and justification through nuigi's custom-layout hook. Configure children
## before their containing node is closed and laid out.

import nuigi, nuigi/core/[arena, array_view], nuigi/debug/profiler

type
  UiFlexAlign* = enum
    FlexAlignAuto
    FlexAlignStart
    FlexAlignCenter
    FlexAlignEnd
    FlexAlignStretch
    FlexAlignBaseline

  UiFlexWrap* = enum
    FlexNoWrap
    FlexWrap
    FlexWrapReverse

  UiFlexJustify* = enum
    FlexJustifyStart
    FlexJustifyEnd
    FlexJustifyCenter
    FlexJustifySpaceBetween
    FlexJustifySpaceAround
    FlexJustifySpaceEvenly

  UiFlexAlignContent* = enum
    FlexContentStart
    FlexContentEnd
    FlexContentCenter
    FlexContentStretch
    FlexContentSpaceBetween
    FlexContentSpaceAround
    FlexContentSpaceEvenly

  UiFlexDirection* = enum
    FlexDirectionRow
    FlexDirectionRowReverse
    FlexDirectionColumn
    FlexDirectionColumnReverse

  UiNodeFlex* = object
    grow*: float32
    shrink*: float32
    basis*: float32
    alignSelf*: UiFlexAlign
    order*: int32
    wrap*: UiFlexWrap
    justifyContent*: UiFlexJustify
    alignItems*: UiFlexAlign
    alignContent*: UiFlexAlignContent
    rowGap*: float32
    columnGap*: float32

var defaultFlexStorage* = UiNodeFlex(
  grow: 0.0'f32,
  shrink: 0.0'f32,
  basis: -1.0'f32,
  alignSelf: FlexAlignAuto,
  order: 0,
  wrap: FlexNoWrap,
  justifyContent: FlexJustifyStart,
  alignItems: FlexAlignStretch,
  alignContent: FlexContentStretch,
  rowGap: -1.0'f32,
  columnGap: -1.0'f32,
)

proc defaultFlex*(): UiNodeFlex =
  defaultFlexStorage

proc ensureNodeFlex*(b: var UiBuilder, node: ptr UiNode, childLayout = false): ptr UiNodeFlex {.inline.} =
  let layout = if childLayout: b.ensureNodeCustomChildLayout(node).addr else: b.ensureNodeCustomLayout(node).addr
  if layout.userData == 0:
    var dataArr = b.frame.arena[].allocArray(1, UiNodeFlex)
    dataArr.data()[0] = defaultFlex()
    layout.userData = cast[int](dataArr.data())
  cast[ptr UiNodeFlex](layout.userData)

proc nodeFlex*(b: UiBuilder, idx: int, childLayout = false): ptr UiNodeFlex {.inline.} =
  let n = b.frame.nodes[idx]
  let slot = if childLayout: int(n.customChildLayoutIndex) else: int(n.customLayoutIndex)
  if slot > 0 and slot <= b.frame.customLayouts.len:
    let layout = b.frame.customLayouts[slot - 1]
    if layout.userData != 0:
      cast[ptr UiNodeFlex](layout.userData)
    else:
      addr(defaultFlexStorage)
  else:
    addr(defaultFlexStorage)

proc nodeFlex*(b: UiBuilder, node: ptr UiNode, childLayout = false): ptr UiNodeFlex {.inline.} =
  let slot = if childLayout: int(node.customChildLayoutIndex) else: int(node.customLayoutIndex)
  if slot > 0 and slot <= b.frame.customLayouts.len:
    let layout = b.frame.customLayouts[slot - 1]
    if layout.userData != 0:
      cast[ptr UiNodeFlex](layout.userData)
    else:
      addr(defaultFlexStorage)
  else:
    addr(defaultFlexStorage)

proc applyFlexLayoutToChildren(b: var UiBuilder, parentIdx: int, parentFlex: ptr UiNodeFlex) {.raises: [].}

proc flexCustomLayout(b: var UiBuilder, nodeIdx: int, userData: int) {.raises: [].} =
  let parentFlex = cast[ptr UiNodeFlex](userData)
  if parentFlex == nil:
    return
  b.applyFlexLayoutToChildren(nodeIdx, parentFlex)

proc isFlexLayout*(flags: UiFlags): bool {.inline.} =
  FlexLayout in flags

proc flexLayout*(b: var UiBuilder, value = true): var UiBuilder {.discardable.} =
  if value:
    b.currentNode.flags.incl FlexLayout
    b.currentNode.flags.excl GridLayout
    discard b.customLayout(flexCustomLayout, cast[int](b.ensureNodeFlex(b.currentNode)))
  else:
    b.currentNode.flags.excl FlexLayout
    if b.currentNode.customLayoutIndex > 0 and b.frame.customLayouts[b.currentNode.customLayoutIndex - 1].layoutProc == flexCustomLayout:
      b.frame.customLayouts[b.currentNode.customLayoutIndex - 1] = default(UiNodeCustomLayout)
      b.currentNode.customLayoutIndex = 0
  b

proc flexDirection*(b: var UiBuilder, value: UiFlexDirection): var UiBuilder {.discardable.} =
  case value
  of FlexDirectionRow:
    b.currentNode.flags.setNodeLayoutKind(LayoutHorizontal)
    b.currentNode.flags.excl DirectionReverse
  of FlexDirectionRowReverse:
    b.currentNode.flags.setNodeLayoutKind(LayoutHorizontal)
    b.currentNode.flags.incl DirectionReverse
  of FlexDirectionColumn:
    b.currentNode.flags.setNodeLayoutKind(LayoutVertical)
    b.currentNode.flags.excl DirectionReverse
  of FlexDirectionColumnReverse:
    b.currentNode.flags.setNodeLayoutKind(LayoutVertical)
    b.currentNode.flags.incl DirectionReverse
  b.currentNode.flags.incl PostProcessChildren
  b

proc flexWrap*(b: var UiBuilder, value: UiFlexWrap): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode).wrap = value
  b.currentNode.flags.incl PostProcessChildren
  b

proc flexFlow*(b: var UiBuilder, direction: UiFlexDirection, wrap: UiFlexWrap): var UiBuilder {.discardable.} =
  discard b.flexDirection(direction)
  discard b.flexWrap(wrap)
  b

proc justifyContent*(b: var UiBuilder, value: UiFlexJustify): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode).justifyContent = value
  b.currentNode.flags.incl PostProcessChildren
  b

proc alignItems*(b: var UiBuilder, value: UiFlexAlign): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode).alignItems = value
  b.currentNode.flags.incl PostProcessChildren
  b

proc alignContent*(b: var UiBuilder, value: UiFlexAlignContent): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode).alignContent = value
  b.currentNode.flags.incl PostProcessChildren
  b

proc rowGap*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode).rowGap = max(0.0'f32, value)
  b.currentNode.flags.incl PostProcessChildren
  b

proc columnGap*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode).columnGap = max(0.0'f32, value)
  b.currentNode.flags.incl PostProcessChildren
  b

proc flexGaps*(b: var UiBuilder, row, column: float32): var UiBuilder {.discardable.} =
  let parentFlex = b.ensureNodeFlex(b.currentNode)
  parentFlex.rowGap = max(0.0'f32, row)
  parentFlex.columnGap = max(0.0'f32, column)
  b.currentNode.flags.incl PostProcessChildren
  b

proc markParentForPostProcessExt(b: var UiBuilder) {.inline.} =
  if b.stack.len <= 0:
    return
  let parentIdx = b.currentNode.parent
  if parentIdx >= 0:
    b.frame.nodes[parentIdx].flags.incl PostProcessChildren

proc flex*(b: var UiBuilder, grow = 0.0'f32, shrink = 1.0'f32, basis = -1.0'f32): var UiBuilder {.discardable.} =
  let nodeFlex = b.ensureNodeFlex(b.currentNode, true)
  nodeFlex.grow = max(0.0'f32, grow)
  nodeFlex.shrink = max(0.0'f32, shrink)
  nodeFlex.basis = basis
  b.markParentForPostProcessExt()
  b

proc flexGrow*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode, true).grow = max(0.0'f32, value)
  b.markParentForPostProcessExt()
  b

proc flexShrink*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode, true).shrink = max(0.0'f32, value)
  b.markParentForPostProcessExt()
  b

proc flexBasis*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode, true).basis = value
  b.markParentForPostProcessExt()
  b

proc flexAlignSelf*(b: var UiBuilder, value: UiFlexAlign): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode, true).alignSelf = value
  b.markParentForPostProcessExt()
  b

proc flexOrder*(b: var UiBuilder, value: int32): var UiBuilder {.discardable.} =
  b.ensureNodeFlex(b.currentNode, true).order = value
  b.markParentForPostProcessExt()
  b

proc applyFlexLayoutToChildren(b: var UiBuilder, parentIdx: int, parentFlex: ptr UiNodeFlex) {.raises: [].} =
  if parentIdx < 0 or parentIdx >= b.frame.nodes.len:
    return
  if parentFlex == nil:
    return

  let parent = b.frame.nodes[parentIdx].addr
  if not isFlexLayout(parent.flags):
    return

  prof("flex")

  # Stage 1: resolve parent flex context (axes, direction, wrapping mode, and effective gaps).
  let nodeStyle = b.nodeStyle(parent)
  let contentW = max(0.0'f32, parent.size.x - nodeStyle.paddingX * 2)
  let contentH = max(0.0'f32, parent.size.y - nodeStyle.paddingY * 2)
  let horizontal = not isVerticalLayout(parent.flags)
  let reverse = isReverseLayout(parent.flags)
  let contentMain = if horizontal: contentW else: contentH
  let contentCross = if horizontal: contentH else: contentW
  if contentMain <= 0.0'f32 or contentCross <= 0.0'f32:
    return
  let fallbackGap = max(0.0'f32, b.nodeGap(parent))
  let rowGap =
    if parentFlex.rowGap >= 0.0'f32:
      max(0.0'f32, parentFlex.rowGap)
    else:
      fallbackGap
  let columnGap =
    if parentFlex.columnGap >= 0.0'f32:
      max(0.0'f32, parentFlex.columnGap)
    else:
      fallbackGap
  let mainGap = if horizontal: columnGap else: rowGap
  let crossGap = if horizontal: rowGap else: columnGap
  let wrapMode = parentFlex.wrap

  type
    FlexItem = object
      child: ptr UiNode
      order: int32
      sourceOrder: int32

    FlexLine = object
      start: int32
      count: int32
      growSum: float32
      shrinkWeightSum: float32
      crossSize: float32

  # Stage 2: collect children as flex items and initialize their main-axis base size.
  var items = b.frame.arena[].allocEmptyArray(b.childCount(parentIdx), FlexItem)
  var sourceOrder = 0'i32
  for childIdx in b.children(parentIdx):
    let child = b.frame.nodes[childIdx].addr
    let childFlex = b.nodeFlex(child, true)
    let preferredBase =
      if childFlex.basis >= 0.0'f32:
        childFlex.basis
      elif horizontal:
        child.size.x
      else:
        child.size.y

    if horizontal:
      child.size.x = max(0.0'f32, preferredBase)
      if childFlex.basis >= 0.0'f32:
        child.flags.incl SizeXKnown
    else:
      child.size.y = max(0.0'f32, preferredBase)
      if childFlex.basis >= 0.0'f32:
        child.flags.incl SizeYKnown
    b.clampNodeSize(child)

    items.add(FlexItem(
      child: child,
      order: childFlex.order,
      sourceOrder: sourceOrder,
    ))
    inc sourceOrder

  if items.len <= 0:
    return

  # Stage 3: stable sort by CSS order, then original insertion order.
  var sortedItems = b.frame.arena[].allocEmptyArray(items.len, FlexItem)
  var usedItems = b.frame.arena[].allocArray(items.len, bool)
  for i in 0 ..< usedItems.len:
    usedItems[i] = false

  for _ in 0 ..< items.len:
    var hasBest = false
    var bestIdx = 0
    for i in 0 ..< items.len:
      if usedItems[i]:
        continue
      if not hasBest:
        bestIdx = i
        hasBest = true
      else:
        let better =
          items[i].order < items[bestIdx].order or
          (items[i].order == items[bestIdx].order and items[i].sourceOrder < items[bestIdx].sourceOrder)
        if better:
          bestIdx = i

    if hasBest:
      sortedItems.add(items[bestIdx])
      usedItems[bestIdx] = true

  items = sortedItems

  var lines = b.frame.arena[].allocEmptyArray(items.len, FlexLine)

  template mainSize(child: ptr UiNode): float32 =
    (if horizontal: child.size.x else: child.size.y)

  template crossSize(child: ptr UiNode): float32 =
    (if horizontal: child.size.y else: child.size.x)

  # Stage 4: split items into flex lines (single line or wrapped lines) and precompute line totals.
  if wrapMode == FlexNoWrap:
    lines.add(FlexLine(start: 0, count: items.len.int32))
    let addedIdx = lines.len - 1
    lines[addedIdx].growSum = 0.0'f32
    lines[addedIdx].shrinkWeightSum = 0.0'f32
    lines[addedIdx].crossSize = 0.0'f32
    for itemOffset in 0 ..< int(lines[addedIdx].count):
      let itemIdx = int(lines[addedIdx].start) + itemOffset
      let child = items[itemIdx].child
      let childFlex = b.nodeFlex(child, true)
      let main = max(0.0'f32, mainSize(child))
      lines[addedIdx].growSum += max(0.0'f32, childFlex.grow)
      lines[addedIdx].shrinkWeightSum += max(0.0'f32, childFlex.shrink) * max(0.0001'f32, main)
      lines[addedIdx].crossSize = max(lines[addedIdx].crossSize, crossSize(child))
  else:
    var lineStart = 0
    var lineCount = 0
    var usedMain = 0.0'f32
    for i in 0 ..< items.len:
      let childMain = max(0.0'f32, mainSize(items[i].child))
      let candidateUsed =
        if lineCount <= 0:
          childMain
        else:
          usedMain + mainGap + childMain
      let shouldWrap = lineCount > 0 and candidateUsed > contentMain + 0.0001'f32
      if shouldWrap:
        lines.add(FlexLine(start: lineStart.int32, count: lineCount.int32))
        let addedIdx = lines.len - 1
        lines[addedIdx].growSum = 0.0'f32
        lines[addedIdx].shrinkWeightSum = 0.0'f32
        lines[addedIdx].crossSize = 0.0'f32
        for itemOffset in 0 ..< int(lines[addedIdx].count):
          let itemIdx = int(lines[addedIdx].start) + itemOffset
          let child = items[itemIdx].child
          let childFlex = b.nodeFlex(child, true)
          let main = max(0.0'f32, mainSize(child))
          lines[addedIdx].growSum += max(0.0'f32, childFlex.grow)
          lines[addedIdx].shrinkWeightSum += max(0.0'f32, childFlex.shrink) * max(0.0001'f32, main)
          lines[addedIdx].crossSize = max(lines[addedIdx].crossSize, crossSize(child))
        lineStart = i
        lineCount = 1
        usedMain = childMain
      else:
        if lineCount <= 0:
          usedMain = childMain
        else:
          usedMain = candidateUsed
        inc lineCount

    if lineCount > 0:
      lines.add(FlexLine(start: lineStart.int32, count: lineCount.int32))
      let addedIdx = lines.len - 1
      lines[addedIdx].growSum = 0.0'f32
      lines[addedIdx].shrinkWeightSum = 0.0'f32
      lines[addedIdx].crossSize = 0.0'f32
      for itemOffset in 0 ..< int(lines[addedIdx].count):
        let itemIdx = int(lines[addedIdx].start) + itemOffset
        let child = items[itemIdx].child
        let childFlex = b.nodeFlex(child, true)
        let main = max(0.0'f32, mainSize(child))
        lines[addedIdx].growSum += max(0.0'f32, childFlex.grow)
        lines[addedIdx].shrinkWeightSum += max(0.0'f32, childFlex.shrink) * max(0.0001'f32, main)
        lines[addedIdx].crossSize = max(lines[addedIdx].crossSize, crossSize(child))

  if lines.len <= 0:
    return

  # Stage 5: resolve each line's main-axis free space via grow/shrink distribution.
  for lineIdx in 0 ..< lines.len:
    let line = lines[lineIdx].addr
    var baseSum = 0.0'f32
    for itemOffset in 0 ..< int(line.count):
      let itemIdx = int(line.start) + itemOffset
      baseSum += max(0.0'f32, mainSize(items[itemIdx].child))

    let totalGap = mainGap * max(0, int(line.count) - 1).float32
    let freeSpace = contentMain - baseSum - totalGap

    if freeSpace > 0.0'f32 and line.growSum > 0.0'f32:
      for itemOffset in 0 ..< int(line.count):
        let itemIdx = int(line.start) + itemOffset
        let child = items[itemIdx].child
        let childFlex = b.nodeFlex(child, true)
        let extra = freeSpace * (max(0.0'f32, childFlex.grow) / line.growSum)
        let oldSize = child.size
        if horizontal:
          child.size.x += extra
        else:
          child.size.y += extra
        b.clampNodeSize(child)
        if oldSize != child.size:
          child.flags.incl SizeDirty
          if horizontal and SizeXKnown in parent.flags:
            child.flags.incl SizeXKnown
          elif not horizontal and SizeYKnown in parent.flags:
            child.flags.incl SizeYKnown

    elif freeSpace < 0.0'f32 and line.shrinkWeightSum > 0.0'f32:
      let deficit = -freeSpace
      for itemOffset in 0 ..< int(line.count):
        let itemIdx = int(line.start) + itemOffset
        let child = items[itemIdx].child
        let childFlex = b.nodeFlex(child, true)
        let base = max(0.0'f32, mainSize(child))
        let weight = max(0.0'f32, childFlex.shrink) * max(0.0001'f32, base)
        let reduction = deficit * (weight / line.shrinkWeightSum)
        let oldSize = child.size
        if horizontal:
          child.size.x = max(0.0'f32, child.size.x - reduction)
        else:
          child.size.y = max(0.0'f32, child.size.y - reduction)
        b.clampNodeSize(child)
        if oldSize != child.size:
          child.flags.incl SizeDirty
          if horizontal and SizeXKnown in parent.flags:
            child.flags.incl SizeXKnown
          elif not horizontal and SizeYKnown in parent.flags:
            child.flags.incl SizeYKnown

    line.growSum = 0.0'f32
    line.shrinkWeightSum = 0.0'f32
    line.crossSize = 0.0'f32
    for itemOffset in 0 ..< int(line.count):
      let itemIdx = int(line.start) + itemOffset
      let child = items[itemIdx].child
      let childFlex = b.nodeFlex(child, true)
      let main = max(0.0'f32, mainSize(child))
      line.growSum += max(0.0'f32, childFlex.grow)
      line.shrinkWeightSum += max(0.0'f32, childFlex.shrink) * max(0.0001'f32, main)
      line.crossSize = max(line.crossSize, crossSize(child))

  # Stage 6: compute cross-axis line packing and optional line stretching from align-content.
  var totalCross = 0.0'f32
  for lineIdx in 0 ..< lines.len:
    totalCross += lines[lineIdx].crossSize
  if lines.len > 1:
    totalCross += crossGap * (lines.len - 1).float32
  let crossFree = contentCross - totalCross

  var lineStartOffset = 0.0'f32
  var extraLineGap = 0.0'f32
  var lineStretchAdd = 0.0'f32
  case parentFlex.alignContent
  of FlexContentEnd:
    lineStartOffset = max(0.0'f32, crossFree)
  of FlexContentCenter:
    lineStartOffset = max(0.0'f32, crossFree * 0.5'f32)
  of FlexContentStretch:
    if crossFree > 0.0'f32:
      lineStretchAdd = crossFree / lines.len.float32
  of FlexContentSpaceBetween:
    if lines.len > 1 and crossFree > 0.0'f32:
      extraLineGap = crossFree / (lines.len - 1).float32
  of FlexContentSpaceAround:
    if crossFree > 0.0'f32:
      extraLineGap = crossFree / lines.len.float32
      lineStartOffset = extraLineGap * 0.5'f32
  of FlexContentSpaceEvenly:
    if crossFree > 0.0'f32:
      extraLineGap = crossFree / (lines.len + 1).float32
      lineStartOffset = extraLineGap
  of FlexContentStart:
    discard

  if lineStretchAdd > 0.0'f32:
    for lineIdx in 0 ..< lines.len:
      lines[lineIdx].crossSize += lineStretchAdd

  # Stage 7: place lines and items; apply justify-content and per-item align-self/align-items.
  var consumedCrossBefore = 0.0'f32
  let wrapReverse = wrapMode == FlexWrapReverse
  for lineIdx in 0 ..< lines.len:
    let line = lines[lineIdx].addr
    let lineCrossPos =
      if wrapReverse:
        max(0.0'f32, contentCross - lineStartOffset - consumedCrossBefore - line.crossSize)
      else:
        lineStartOffset + consumedCrossBefore

    var occupiedMain = 0.0'f32
    for itemOffset in 0 ..< int(line.count):
      let itemIdx = int(line.start) + itemOffset
      occupiedMain += max(0.0'f32, mainSize(items[itemIdx].child))
    if line.count > 1:
      occupiedMain += mainGap * (int(line.count) - 1).float32
    let freeMain = contentMain - occupiedMain

    var mainStartOffset = 0.0'f32
    var extraMainGap = 0.0'f32
    case parentFlex.justifyContent
    of FlexJustifyEnd:
      mainStartOffset = max(0.0'f32, freeMain)
    of FlexJustifyCenter:
      mainStartOffset = max(0.0'f32, freeMain * 0.5'f32)
    of FlexJustifySpaceBetween:
      if line.count > 1 and freeMain > 0.0'f32:
        extraMainGap = freeMain / (line.count - 1).float32
    of FlexJustifySpaceAround:
      if line.count > 0 and freeMain > 0.0'f32:
        extraMainGap = freeMain / line.count.float32
        mainStartOffset = extraMainGap * 0.5'f32
    of FlexJustifySpaceEvenly:
      if freeMain > 0.0'f32:
        extraMainGap = freeMain / (line.count + 1).float32
        mainStartOffset = extraMainGap
    of FlexJustifyStart:
      discard

    var mainCursor =
      if reverse:
        contentMain - mainStartOffset
      else:
        mainStartOffset

    for itemOffset in 0 ..< int(line.count):
      let itemIdx = int(line.start) + itemOffset
      let child = items[itemIdx].child
      let childFlex = b.nodeFlex(child, true)
      let childMain = max(0.0'f32, mainSize(child))

      let childMainPos =
        if reverse:
          mainCursor = max(0.0'f32, mainCursor - childMain)
          let p = mainCursor
          mainCursor = max(0.0'f32, mainCursor - (mainGap + extraMainGap))
          p
        else:
          let p = mainCursor
          mainCursor = mainCursor + childMain + mainGap + extraMainGap
          p

      let autoCrossFill =
        childFlex.alignSelf == FlexAlignAuto and
        ((horizontal and FillY in child.flags) or ((not horizontal) and FillX in child.flags))

      var effectiveAlign = childFlex.alignSelf
      if effectiveAlign == FlexAlignAuto:
        effectiveAlign = parentFlex.alignItems
      if effectiveAlign == FlexAlignAuto:
        effectiveAlign = FlexAlignStart
      if autoCrossFill:
        effectiveAlign = FlexAlignStretch

      var childCrossPos = 0.0'f32
      case effectiveAlign
      of FlexAlignStretch:
        if horizontal:
          child.size.y = max(0.0'f32, line.crossSize)
          if SizeYKnown in parent.flags:
            child.flags.incl SizeYKnown
        else:
          child.size.x = max(0.0'f32, line.crossSize)
          if SizeXKnown in parent.flags:
            child.flags.incl SizeXKnown
        b.clampNodeSize(child)
        child.flags.incl SizeDirty
      of FlexAlignCenter:
        childCrossPos = max(0.0'f32, (line.crossSize - crossSize(child)) * 0.5'f32)
      of FlexAlignEnd:
        childCrossPos = max(0.0'f32, line.crossSize - crossSize(child))
      of FlexAlignStart, FlexAlignBaseline, FlexAlignAuto:
        discard

      if horizontal:
        child.pos.x = childMainPos
        child.pos.y = lineCrossPos + childCrossPos
      else:
        child.pos.y = childMainPos
        child.pos.x = lineCrossPos + childCrossPos

    consumedCrossBefore += line.crossSize
    if lineIdx < lines.len - 1:
      consumedCrossBefore += crossGap + extraLineGap
