## Expandable section header with a backend-appropriate chevron.

import nuigi
import nuigi/core/[vecmath, arena, array_view]
import nuigi/debug/profiler
import nuigi/rendering/mesh

proc buildCollapsingHeaderChevron(b: var UiBuilder, nodeIdx: int, expandedRaw: int) =
  let arena = b.frame.arena
  if arena == nil or nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return

  let node = b.frame.nodes[nodeIdx].addr
  let inset = 3.0'f32
  let iconSize = vec2(
    max(0.0'f32, node.size.x - inset * 2.0'f32),
    max(0.0'f32, node.size.y - inset * 2.0'f32))
  if iconSize.x <= 0.0'f32 or iconSize.y <= 0.0'f32:
    return

  let color = b.themeTextStyle(UiStyleIndexHeaderText)[].textColor
  let direction = if expandedRaw != 0: vec2(0.0'f32, 1.0'f32) else: vec2(1.0'f32, 0.0'f32)
  let (vertices, vertexCount) = buildChevronVertices(
    arena,
    b.absoluteNodePos(nodeIdx) + vec2(inset),
    iconSize,
    direction,
    color,
    antialiasMeshWidth = b.antialiasMeshWidth)
  if vertices == nil or vertexCount == 0:
    return

  var commands = arena[].allocEmptyArray(1, UiRenderCommand)
  commands.add UiRenderCommand(
    kind: CmdRawVertices,
    vertexData: vertices,
    vertexCount: vertexCount.int32,
    color: color)
  b.withParent(nodeIdx):
    discard b.customRenderCommands(commands)

template collapsingHeader*(b: var UiBuilder, label: string,
    expanded: var bool, body: untyped): untyped =
  block:
    prof("collapsingHeader")
    discard b.pushId(label)
    b.layoutVertical:
      b.debugName("collapsing-header")
      discard b.fillX().fitY()

      b.layoutHorizontal:
        b.debugName("collapsing-header-toggle")
        let headerId = b.currentNode.id
        discard b.fillX().fitY().noChildHover()
        discard b.styleIndex(UiStyleIndexHeader)
        discard b.fillBackground()
        discard b.focusable({FocusTabStop, FocusActivatable})

        b.node:
          b.debugName("collapsing-header-chevron")
          if b.backendType == UiBackendType.Terminal:
            discard b.fitX().fitY()
            discard b.copyTextStyleIndex(UiStyleIndexHeaderText)
            discard b.text(if expanded: "▼" else: "▶")
          else:
            discard b.sizeRelative(1.0'f32, 1.0'f32)
            discard b.deferBuild(buildCollapsingHeaderChevron, int(expanded))

        b.node:
          b.debugName("collapsing-header-label")
          discard b.fitX().fitY().alignCenter()
          discard b.copyTextStyleIndex(UiStyleIndexHeaderText)
          discard b.text(label)

        if b.previousOutput.clickedId == headerId:
          b.requestFocus()
          expanded = not expanded
        elif b.wasFocusActivated():
          expanded = not expanded
        discard b.focusHighlight()

      b.node:
        b.debugName("collapsing-header-content")
        let previousContentIdx = b.previousNodeIndex(
          b.currentNode.id, b.currentNodeIndex)
        let renderContent = expanded or
          (previousContentIdx >= 0 and
            b.previousFrame.nodes[previousContentIdx].size.y > 0.0'f32)
        discard b.fillX().maskChildren()
        if expanded:
          discard b.fitY()
        else:
          discard b.height(0.0'f32)
        discard b.animateSize().animateDelayed()
        if renderContent:
          body
    discard b.popId()