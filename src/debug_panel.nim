import nuigi
import mymath, arena
import array_view
import profiler
import flex, grid

import nev_navigation
import widgets

include compat2

type
  DebugCursorFrame = object
    parentIdx: int32
    lastChildIdx: int32

  DebugTreeCursor* = object
    nodeIdx*: int
    depth*: int
    valid*: bool
    parentStack: seq[DebugCursorFrame]

proc initDebugTreeCursor*(rootIdx: int): DebugTreeCursor =
  DebugTreeCursor(nodeIdx: rootIdx, depth: 0, valid: rootIdx >= 0)

# Advances one step in DFS pre-order (descend, then next sibling, then parent's next sibling).
proc advance*(cursor: var DebugTreeCursor, nodes: openArray[UiNode], cutoff: int) =
  if not cursor.valid:
    return
  let cur = cursor.nodeIdx
  let tail = int(nodes[cur].lastChild)
  if tail >= 0 and tail < cutoff:
    let firstChild = int(nodes[tail].nextSibling)
    cursor.parentStack.add(DebugCursorFrame(parentIdx: cur.int32, lastChildIdx: tail.int32))
    cursor.nodeIdx = firstChild
    cursor.depth += 1
    return
  while cursor.parentStack.len > 0:
    let frame = cursor.parentStack[^1]
    if cursor.nodeIdx != int(frame.lastChildIdx):
      cursor.nodeIdx = int(nodes[cursor.nodeIdx].nextSibling)
      return
    cursor.parentStack.setLen(cursor.parentStack.len - 1)
    cursor.nodeIdx = int(frame.parentIdx)
    cursor.depth -= 1
  cursor.valid = false

# Skips the cursor forward by n steps from its current position.
proc skipToN*(cursor: var DebugTreeCursor, nodes: openArray[UiNode], cutoff: int, n: int) =
  for _ in 0 ..< n:
    if not cursor.valid:
      break
    cursor.advance(nodes, cutoff)

# Returns the DFS pre-order index of targetNodeIdx, or -1 if not found.
proc dfsIndexOf*(nodes: openArray[UiNode], cutoff, targetNodeIdx: int): int =
  var cursor = initDebugTreeCursor(0)
  var i = 0
  while cursor.valid:
    if cursor.nodeIdx == targetNodeIdx:
      return i
    cursor.advance(nodes, cutoff)
    inc i
  -1

proc applyDebugOutlineToNode(b: var UiBuilder, targetId: UiNodeId, cutoff: int) =
  if targetId == noneNodeId():
    return

  var targetIdx = -1
  for i in 0 ..< min(cutoff, b.nodes.len):
    if b.nodes[i].id == targetId:
      targetIdx = i
      break

  if targetIdx >= 0:
    var s = b.ensureNodeStyle(b.nodes[targetIdx].addr).addr
    s.borderWidth = max(s.borderWidth, 2.0'f32)
    s.borderColor = accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, -0.46'f32, 1.0)

type
  UiNodeStorageStats = object
    count: int
    structBytes: int
    textBytes: int
    childLinkBytes: int
    customCommandBytes: int

proc fmtGridTracks(tracks: ArrayView[UiGridTrack]): string
proc fmtBytes(value: int): string

proc appendFlagName(result: var string, flags: UiFlags, flagName: UiFlag, label: string) =
  if flagName in flags:
    if result.len > 0:
      result.add(", ")
    result.add(label)

proc fmtFlagList(flags: UiFlags): string =
  var output = ""
  appendFlagName(output, flags, AlignCenter, "AlignCenter")
  appendFlagName(output, flags, SizeXKnown, "SizeXKnown")
  appendFlagName(output, flags, SizeYKnown, "SizeYKnown")
  appendFlagName(output, flags, FillX, "FillX")
  appendFlagName(output, flags, FillY, "FillY")
  appendFlagName(output, flags, FitX, "FitX")
  appendFlagName(output, flags, FitY, "FitY")
  appendFlagName(output, flags, AnchorX, "AnchorX")
  appendFlagName(output, flags, AnchorY, "AnchorY")
  appendFlagName(output, flags, DrawText, "DrawText")
  appendFlagName(output, flags, FillBackground, "FillBackground")
  appendFlagName(output, flags, MaskChildren, "MaskChildren")
  appendFlagName(output, flags, PostProcessChildren, "PostProcessChildren")
  appendFlagName(output, flags, LayoutVertical, "LayoutVertical")
  appendFlagName(output, flags, LayoutHorizontal, "LayoutHorizontal")
  appendFlagName(output, flags, FlexLayout, "FlexLayout")
  appendFlagName(output, flags, GridLayout, "GridLayout")
  appendFlagName(output, flags, DirectionReverse, "DirectionReverse")
  appendFlagName(output, flags, NoHover, "NoHover")
  appendFlagName(output, flags, NoChildHover, "NoChildHover")
  appendFlagName(output, flags, SizeDirty, "SizeDirty")
  if output.len == 0:
    output = "none"
  result = output

proc fmtLayoutInfo(flags: UiFlags): string =
  var output = ""
  if isHorizontalLayout(flags):
    output = "horizontal"
  elif isVerticalLayout(flags):
    output = "vertical"
  if output.len > 0 and isReverseLayout(flags):
    output.add(" reverse")
  result = output

proc fmtAnchorInfo(flags: UiFlags): string =
  result = ""
  var anchorFlags = default(UiFlags)
  if AnchorX in flags:
    anchorFlags.incl AnchorX
  if AnchorY in flags:
    anchorFlags.incl AnchorY
  if anchorFlags != default(UiFlags):
    result = fmtFlagList(anchorFlags)

proc detailRow(b: var UiBuilder, labelText, valueText: string, valueColor = UiColor()) =
  var vc = valueColor
  if vc.a <= 0.0'f32:
    vc = b.themeTextStyle(UiStyleIndexDefaultText)[].textColor
  discard b.pushId(labelText)
  b.layoutHorizontal("debug-panel-detail-row"):
    discard b.fillX().fitY().gap(4)
    b.node("debug-panel-detail-label"):
      discard b.fitX().fitY()
      discard b.text(labelText & ":")
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    b.node("debug-panel-detail-value"):
      discard b.fitX().fitY()
      discard b.text(valueText)
      discard b.textColor(vc)
  discard b.popId()

proc fmtStyleFloatProps(style: UiStyle, gapValue: float32): string =
  "padding=(" & fmt2(style.paddingX) & ", " & fmt2(style.paddingY) & ")" &
  " gap=" & fmt2(gapValue) &
  " border=" & fmt2(style.borderWidth) &
  " corner=" & fmt2(style.cornerRadius)

proc detailColorRow(b: var UiBuilder, labelText: string, textColor, backgroundColor: UiColor) =
  discard b.pushId(labelText)
  b.layoutHorizontal("debug-panel-detail-color-row"):
    discard b.fillX().fitY().gap(4)
    b.node("debug-panel-detail-label"):
      discard b.fitX().fitY()
      discard b.text(labelText & ":")
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor).alignCenter()
    b.node("debug-panel-detail-text-color"):
      discard b.fitX().fitY()
      discard b.text("text")
      discard b.textColor(b.themeTextStyle(UiStyleIndexDefaultText)[].textColor).alignCenter()
    b.node("debug-panel-detail-text-swatch"):
      discard b.size(14, 12)
      discard b.fillBackground()
      discard b.backgroundColor(textColor)
      discard b.borderWidth(1)
      discard b.borderColor(b.themeStyle(UiStyleIndexStage)[].borderColor)
      discard b.cornerRadius(2).alignCenter()
    b.node("debug-panel-detail-background-label"):
      discard b.fitX().fitY()
      discard b.text("background")
      discard b.textColor(b.themeTextStyle(UiStyleIndexDefaultText)[].textColor).alignCenter()
    b.node("debug-panel-detail-background-swatch"):
      discard b.size(14, 12)
      discard b.fillBackground()
      discard b.backgroundColor(backgroundColor)
      discard b.borderWidth(1)
      discard b.borderColor(b.themeStyle(UiStyleIndexStage)[].borderColor)
      discard b.cornerRadius(2).alignCenter()
  discard b.popId()

proc buildDebugPanelDetails(b: var UiBuilder, inspectedId: UiNodeId) =
  b.layoutVertical("debug-panel-details"):
    discard b.fillX().fitY()
    discard b.padding(6).gap(2)
    discard b.fillBackground()
    # discard b.maskChildren()
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)
    discard b.borderWidth(1)
    discard b.borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
    discard b.cornerRadius(4)

    b.node("debug-panel-details-title"):
      discard b.fitX().fitY()
      discard b.text("Hovered Node")
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    let inspectedIdx = b.previousNodeIndex(inspectedId)
    if inspectedIdx >= 0 and inspectedIdx < b.previousFrame.nodes.len:
      let n = b.previousFrame.nodes[inspectedIdx].addr
      var debugName = n[].nodeDebugName()
      when defined(nuiDebug):
        debugName.add " " & "postProcessCounter: " & $n.postProcessCounter
      detailRow(
        b,
        "node",
        "idx=" & $inspectedIdx &
        " id=" & $nodeIdValue(n.id) &
        " parent=" & $n.parent &
        " children=" & $b.childCount(inspectedIdx) &
        " " & debugName,
      )

      let layoutParts = fmtLayoutInfo(n.flags)
      if layoutParts.len > 0:
        detailRow(b, "layout", layoutParts)

      let anchorParts = fmtAnchorInfo(n.flags)
      if anchorParts.len > 0:
        detailRow(b, "anchors", anchorParts)

      let flagList = fmtFlagList(n.flags)
      if flagList != "none":
        detailRow(b, "flags", flagList)

      var parentIsFlex = false
      var parentIsGrid = false
      if n.parent >= 0 and n.parent < b.previousFrame.nodes.len:
        let parent = b.previousFrame.nodes[n.parent]
        parentIsFlex = isFlexLayout(parent.flags)
        parentIsGrid = isGridLayout(parent.flags)

      var hasFlexData = false
      var flexData = defaultFlex()
      if n.customChildLayoutIndex > 0 and int(n.customChildLayoutIndex) <= b.previousFrame.customLayouts.len:
        let childLayout = b.previousFrame.customLayouts[int(n.customChildLayoutIndex) - 1]
        if childLayout.userData != 0 and parentIsFlex:
          flexData = cast[ptr UiNodeFlex](childLayout.userData)[]
          hasFlexData = true
      if not hasFlexData and n.customLayoutIndex > 0 and int(n.customLayoutIndex) <= b.previousFrame.customLayouts.len:
        let parentLayout = b.previousFrame.customLayouts[int(n.customLayoutIndex) - 1]
        if parentLayout.userData != 0 and isFlexLayout(n.flags):
          flexData = cast[ptr UiNodeFlex](parentLayout.userData)[]
          hasFlexData = true

      if hasFlexData:
        detailRow(
          b,
          "flex",
          "grow=" & fmt2(flexData.grow) &
          " shrink=" & fmt2(flexData.shrink) &
          " basis=" & fmt2(flexData.basis) &
          " order=" & $flexData.order &
          " self=" & $flexData.alignSelf,
        )

      if n.customLayoutIndex > 0 and int(n.customLayoutIndex) <= b.previousFrame.customLayouts.len and isGridLayout(n.flags):
        let parentLayout = b.previousFrame.customLayouts[int(n.customLayoutIndex) - 1]
        var gridParentData = defaultGridParent()
        if parentLayout.userData != 0:
          gridParentData = cast[ptr UiNodeGridParent](parentLayout.userData)[]
        detailRow(
          b,
          "grid",
          "flow=" & $gridParentData.autoFlow &
          " items=" & $gridParentData.justifyItems & "/" & $gridParentData.alignItems &
          " content=" & $gridParentData.justifyContent & "/" & $gridParentData.alignContent &
          " tracks=" & fmtGridTracks(gridParentData.columns) & "|" & fmtGridTracks(gridParentData.rows),
        )

      if n.customChildLayoutIndex > 0 and int(n.customChildLayoutIndex) <= b.previousFrame.customLayouts.len and parentIsGrid:
        let childLayout = b.previousFrame.customLayouts[int(n.customChildLayoutIndex) - 1]
        var gridChildData = defaultGridChild()
        if childLayout.userData != 0:
          gridChildData = cast[ptr UiNodeGridChild](childLayout.userData)[]
        detailRow(
          b,
          "grid child",
          "col=" & $gridChildData.columnStart & ".." & $(gridChildData.columnStart + gridChildData.columnSpan - 1) &
          " row=" & $gridChildData.rowStart & ".." & $(gridChildData.rowStart + gridChildData.rowSpan - 1) &
          " self=" & $gridChildData.justifySelf & "/" & $gridChildData.alignSelf,
        )

      let textSize = b.cachedMeasuredTextSize(n)
      let absolutePos = b.absoluteNodePosPrev(n.id, inspectedIdx)
      detailRow(
        b,
        "pos/size/content",
        "pos=(" & fmt2(n.pos.x) & ", " & fmt2(n.pos.y) & ")" &
        " size=(" & fmt2(n.size.x) & ", " & fmt2(n.size.y) & ")" &
        " content=(" & fmt2(n.contentExtent.x) & ", " & fmt2(n.contentExtent.y) & ")" &
        " text=(" & fmt2(textSize.x) & ", " & fmt2(textSize.y) & ")",
      )
      detailRow(
        b,
        "abs",
        " (" & formatFloat(absolutePos.x.float64, ffDecimal, 20) & ", " & formatFloat(absolutePos.y.float64, ffDecimal, 20) & ")"
      )
      if n.styleIndex > 0 and (int(n.styleIndex) - 1) < b.previousFrame.styles.len:
        let style = b.previousFrame.styles[int(n.styleIndex) - 1]
        let gapValue =
          if n.gapIndex > 0 and int(n.gapIndex) <= b.previousFrame.gaps.len:
            b.previousFrame.gaps[int(n.gapIndex) - 1]
          else:
            0.0'f32
        detailRow(b, "style", fmtStyleFloatProps(style, gapValue))
        detailColorRow(b, "colors", style.fillColor, style.fillColor)

      let eventHistory = b.eventTracesFor(inspectedId)
      if eventHistory.len > 0:
        detailRow(
          b,
          "events",
          $eventHistory.len & " recorded (trace mode: " & $b.traceMode & ")",
          accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, -0.26'f32, 1.0),
        )
        for evIdx in 0 ..< eventHistory.len:
          detailRow(
            b,
            "  event " & $evIdx,
            eventHistory[evIdx],
            accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, -0.26'f32, 1.0),
          )
    else:
      b.node("debug-panel-details-empty"):
        discard b.fitX().fitY()
        discard b.text("No hovered node")
        discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

proc buildDebugPanelStats(b: var UiBuilder, inspectedId: UiNodeId, currentNodeStats, previousNodeStats: UiNodeStorageStats,
    previousCommandCount, previousCommandBytes, frameArenaUsed, frameArenaCapacity,
    frameArenaBuckets, previousFrameArenaUsed, previousFrameArenaCapacity,
    previousFrameArenaBuckets, activeAnimationCount, activeAnimatedFieldCount: int) =
  let statsColor = b.themeTextStyle(UiStyleIndexMutedText)[].textColor

  b.layoutVertical("debug-panel-stats"):
    discard b.fillX().fitY()
    discard b.padding(6).gap(2)
    discard b.fillBackground()
    # discard b.maskChildren()
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)
    discard b.borderWidth(1)
    discard b.borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
    discard b.cornerRadius(4)

    b.node("debug-panel-stats-title"):
      discard b.fitX().fitY()
      discard b.text("UI Stats")
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.layoutHorizontal("debug-panel-debug-toggles"):
      discard b.fillX().fitY().gap(6)
      var drawGridLines = b.debugDrawGridLines
      if b.checkbox("Draw grid lines", drawGridLines):
        discard
      b.debugDrawGridLines = drawGridLines

      b.label(" Trace Mode: ")
      var traceModeIndex = b.traceMode.ord
      if b.dropdown(["None", "All", "Current"], traceModeIndex):
        case traceModeIndex
        of 0:
          discard b.setTraceMode(TraceNone)
        of 1:
          discard b.setTraceMode(TraceAll)
        of 2:
          discard b.setTraceMode(TraceNodeId, inspectedId)
        else:
          discard

    b.node("debug-panel-stats-nodes"):
      discard b.fitX().fitY()
      discard b.text("nodes: current=" & $currentNodeStats.count & " previous=" & $previousNodeStats.count)
      discard b.textColor(statsColor)

    b.node("debug-panel-stats-node-struct"):
      discard b.fitX().fitY()
      discard b.text("node structs: current=" & fmtBytes(currentNodeStats.structBytes) & " previous=" & fmtBytes(previousNodeStats.structBytes))
      discard b.textColor(statsColor)

    b.node("debug-panel-stats-node-text"):
      discard b.fitX().fitY()
      discard b.text("node text buffers: current=" & fmtBytes(currentNodeStats.textBytes) & " previous=" & fmtBytes(previousNodeStats.textBytes))
      discard b.textColor(statsColor)

    b.node("debug-panel-stats-node-children"):
      discard b.fitX().fitY()
      discard b.text("node links: current=" & fmtBytes(currentNodeStats.childLinkBytes) & " previous=" & fmtBytes(previousNodeStats.childLinkBytes))
      discard b.textColor(statsColor)

    b.node("debug-panel-stats-node-custom"):
      discard b.fitX().fitY()
      discard b.text("node custom cmds: current=" & fmtBytes(currentNodeStats.customCommandBytes) & " previous=" & fmtBytes(previousNodeStats.customCommandBytes))
      discard b.textColor(statsColor)

    b.node("debug-panel-stats-frame-commands"):
      discard b.fitX().fitY()
      discard b.text("frame commands(prev): count=" & $previousCommandCount & " mem=" & fmtBytes(previousCommandBytes))
      discard b.textColor(statsColor)

    b.node("debug-panel-stats-animations"):
      discard b.fitX().fitY()
      discard b.text("animations: nodes=" & $activeAnimationCount & " fields=" & $activeAnimatedFieldCount)
      discard b.textColor(statsColor)

    b.node("debug-panel-stats-node-storage"):
      discard b.fitX().fitY()
      discard b.text("node storage: count=" & $b.nodeStorageCount())
      discard b.textColor(statsColor)

    b.node("debug-panel-stats-frame-arena"):
      discard b.fitX().fitY()
      discard b.text("frame arena: used=" & fmtBytes(frameArenaUsed) & " cap=" & fmtBytes(frameArenaCapacity) & " buckets=" & $frameArenaBuckets)
      discard b.textColor(statsColor)

    b.node("debug-panel-stats-prev-arena"):
      discard b.fitX().fitY()
      discard b.text("prev frame arena: used=" & fmtBytes(previousFrameArenaUsed) & " cap=" & fmtBytes(previousFrameArenaCapacity) & " buckets=" & $previousFrameArenaBuckets)
      discard b.textColor(statsColor)

proc fmtBytes(value: int): string =
  let v = max(0, value)
  if v < 1024:
    return $v & " B"
  if v < 1024 * 1024:
    return fmt2(v.float32 / 1024.0'f32) & " KB"
  return fmt2(v.float32 / (1024.0'f32 * 1024.0'f32)) & " MB"

proc fmtGridTracks(tracks: ArrayView[UiGridTrack]): string =
  if tracks.len <= 0:
    return "[]"

  var trackView = tracks
  let trackData = trackView.data()
  result = "["
  for i in 0 ..< trackView.len:
    let track = trackData[i]
    if i > 0:
      result.add(", ")
    case track.kind
    of GridTrackAuto:
      result.add("auto")
    of GridTrackPixels:
      result.add(fmt2(track.value) & "px")
    of GridTrackFraction:
      result.add(fmt2(track.value) & "fr")
  result.add("]")

proc collectNodeStorageStats(nodes: openArray[UiNode], frame: UiFrame): UiNodeStorageStats =
  result = default(UiNodeStorageStats)
  result.count = nodes.len
  result.structBytes = nodes.len * sizeof(UiNode)
  for i in 0 ..< nodes.len:
    let n = nodes[i].addr
    if n.textIndex > 0:
      result.textBytes += frame.texts[n.textIndex - 1].text.len
    result.childLinkBytes += sizeof(int32) * 2
    if n.commandsIndex > 0:
      result.customCommandBytes += len(frame.customCommands[n.commandsIndex - 1]) * sizeof(UiRenderCommand)

proc ptrArenaUsedBytes(a: ptr Arena): int =
  if a == nil:
    return 0
  return a[].usedBytes()

proc ptrArenaCapacityBytes(a: ptr Arena): int =
  if a == nil:
    return 0
  return a[].capacityBytes()

proc ptrArenaBucketCount(a: ptr Arena): int =
  if a == nil:
    return 0
  return a[].bucketCount()

type
  DebugTreeListData = object
    cursor: DebugTreeCursor
    lastRenderedIndex: int
    cutoff: int
    viewportH: float32

  DebugPanel* = object
    scrollOffset: float
    scrollOffset2: float
    rowHoverTarget: UiNodeId
    rowHoverFromTree: bool
    treeListData: DebugTreeListData

proc buildDebugListEntry(b: var UiBuilder, itemIndex: int, userData: int) {.nimcall.} =
  prof("buildDebugListEntry")
  if userData == 0:
    return
  let panel = cast[ptr DebugPanel](userData)
  let data = panel.treeListData.addr
  if data.lastRenderedIndex < 0:
    if b.stack.len >= 2:
      data.viewportH = b.frame.nodes[b.stack[^2]].size.y
    data.cursor = initDebugTreeCursor(0)
    data.cursor.skipToN(b.nodes, data.cutoff, itemIndex)
  else:
    data.cursor.advance(b.nodes, data.cutoff)
  data.lastRenderedIndex = itemIndex
  if not data.cursor.valid:
    return
  let nodeIdx = data.cursor.nodeIdx
  let depth = data.cursor.depth
  let n = b.nodes[nodeIdx].addr

  let rowNodeId = b.currentNode.id
  let prevRowIdx = b.previousNodeIndex(rowNodeId, indexHint = b.stack[^1])
  let rowIsHovered = prevRowIdx >= 0 and b.previousOutput.hoveredIndex == prevRowIdx
  let prevTargetIdx = b.previousNodeIndex(n.id, indexHint = nodeIdx)
  let targetIsHovered = prevTargetIdx >= 0 and b.previousOutput.hoveredIndex == prevTargetIdx

  if rowIsHovered and ModAlt in b.frameCtx.input.modsDown:
    panel.rowHoverTarget = n.id
    panel.rowHoverFromTree = true

  if rowIsHovered or targetIsHovered:
    discard b.fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, 0.0'f32, 0.6'f32))
  else:
    let evenBg = b.themeStyle(UiStyleIndexRow)[].fillColor
    let oddBg  = b.themeStyle(UiStyleIndexRowAlt)[].fillColor
    discard b.fillBackground().backgroundColor(if itemIndex mod 2 == 0: evenBg else: oddBg)

  if panel.rowHoverTarget == n.id:
    discard b.borderWidth(2.0).borderColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, -0.46'f32, 1.0))

  when not defined(nimony) and defined(nuiDebug):
    let rowNodeIdx = b.stack[^1]
    if b.wasRightClicked(rowNodeIdx, includeChildren = true):
      if n.debugSourceFile.len > 0:
        openInNev(n.debugSourceFile, n.debugSourceLine.int)

  var label = newStringOfCap(100)
  for _ in 0 ..< depth:
    label.add("  ")
  label.add("- #")
  label.add($nodeIdx)
  label.add(" ")
  label.add(n[].nodeDebugName())
  label.add(" id=")
  label.add($nodeIdValue(n.id))
  discard b.copyTextStyleIndex(UiStyleIndexSmallText)
  discard b.text(label)

proc debugPanel*(b: var UiBuilder, debugPanel: var DebugPanel): var UiBuilder {.discardable.} =
  prof("debugPanel")
  b.flushDeferredNodes()
  # Set rowHoverTarget to hovered node if we're hovering something not part of the debug ui
  let currentHoveredIndex = b.currentNodeIndex(b.previousOutput.hoveredId)
  if currentHoveredIndex != -1 and ModAlt in b.frameCtx.input.modsDown:
    debugPanel.rowHoverTarget = b.previousOutput.hoveredId
    debugPanel.rowHoverFromTree = false

  var f = b.defaultText.fontSize
  b.defaultText.fontSize = 13
  let cutoff = b.nodes.len
  let currentNodeStats = collectNodeStorageStats(b.nodes, b.frame)
  let previousNodeStats = collectNodeStorageStats(b.previousFrame.nodes, b.previousFrame)
  let previousCommandCount = b.previousOutput.commands.len
  let previousCommandBytes = previousCommandCount * sizeof(UiRenderCommand)
  let frameArenaUsed = ptrArenaUsedBytes(b.frame.arena)
  let frameArenaCapacity = ptrArenaCapacityBytes(b.frame.arena)
  let frameArenaBuckets = ptrArenaBucketCount(b.frame.arena)
  let previousFrameArenaUsed = ptrArenaUsedBytes(b.previousFrame.arena)
  let previousFrameArenaCapacity = ptrArenaCapacityBytes(b.previousFrame.arena)
  let previousFrameArenaBuckets = ptrArenaBucketCount(b.previousFrame.arena)
  let activeAnimationCount = b.animations.len
  var activeAnimatedFieldCount = 0
  for i in 0 ..< b.animations.len:
    activeAnimatedFieldCount += b.animations[i].fields.len

  let inspectedId = debugPanel.rowHoverTarget

  b.layoutVerticalReverse("debug-panel"):
    discard b.deferPostProcess()
    discard b.fillX()
    discard b.fillY()
    discard b.padding(8).gap(4)
    discard b.fillBackground()
    discard b.backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)

    buildDebugPanelDetails(b, inspectedId)
    buildDebugPanelStats(b, inspectedId, currentNodeStats, previousNodeStats, previousCommandCount,
      previousCommandBytes, frameArenaUsed, frameArenaCapacity, frameArenaBuckets,
      previousFrameArenaUsed, previousFrameArenaCapacity, previousFrameArenaBuckets,
      activeAnimationCount, activeAnimatedFieldCount)

    b.layoutVertical("debug-panel-tree"):
      discard b.fillX().fillY()
      discard b.padding(2).gap(4)
      discard b.maskChildren()

      b.node("debug-panel-title"):
        discard b.fitX().fitY()
        discard b.text("UI Tree")
        discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

      b.node("vlist-container"):
        discard b.fill()
        debugPanel.treeListData.lastRenderedIndex = -1
        debugPanel.treeListData.cutoff = cutoff
        if ModAlt in b.frameCtx.input.modsDown and debugPanel.rowHoverTarget != noneNodeId():
          let targetNodeIdx = b.currentNodeIndex(debugPanel.rowHoverTarget)
          if targetNodeIdx >= 0 and targetNodeIdx < cutoff:
            let targetItemIdx = dfsIndexOf(b.nodes, cutoff, targetNodeIdx)
            if targetItemIdx >= 0:
              let itemH = 24.0'f32
              let vpH = debugPanel.treeListData.viewportH
              if debugPanel.rowHoverFromTree:
                let margin = float(itemH)
                let itemTop = float(targetItemIdx) * float(itemH)
                let itemBot = itemTop + float(itemH)
                if itemTop - margin < debugPanel.scrollOffset2:
                  debugPanel.scrollOffset2 = itemTop - margin
                elif itemBot + margin > debugPanel.scrollOffset2 + float(vpH):
                  debugPanel.scrollOffset2 = itemBot + margin - float(vpH)
              else:
                let itemCenter = float(targetItemIdx) * float(itemH) + float(itemH) * 0.5
                debugPanel.scrollOffset2 = itemCenter - float(vpH) * 0.5
        let rowHeight = b.themeTextStyle(UiStyleIndexDefaultText).fontSize * b.fontScale + 6
        b.virtualList(debugPanel.scrollOffset2, cutoff, rowHeight, buildDebugListEntry, cast[int](debugPanel.addr))

  if debugPanel.rowHoverTarget != noneNodeId():
    b.applyDebugOutlineToNode(debugPanel.rowHoverTarget, cutoff)

  b.defaultText.fontSize = f
  b
