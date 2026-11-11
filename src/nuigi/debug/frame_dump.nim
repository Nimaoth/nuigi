## Plain-text dump of the current frame's node tree with resolved layout, for
## debugging spacing/padding/border issues without an interactive inspector.

import std/[math, strutils]
import nuigi

proc fmtNum(value: float32): string =
  if value == round(value):
    $int(value)
  else:
    formatFloat(value.float64, ffDecimal, 2)

proc layoutFlags(flags: UiFlags): string =
  const interesting = [FillX, FillY, FitX, FitY, AnchorX, AnchorY, LayoutVertical,
    LayoutHorizontal, FlexLayout, GridLayout, AlignCenter, MaskChildren, Scrollable,
    FillBackground, WrapText, IgnoreInContentExtent, UseCachedTexture]
  for flag in interesting:
    if flag in flags:
      if result.len > 0:
        result.add ','
      result.add ($flag)

proc textSnippet(b: UiBuilder, idx: int, maxLen: int): string =
  let text = b.nodeText(idx)
  var raw = newStringOfCap(min(text.text.len, maxLen + 3))
  for c in text.text.toOpenArray:
    if raw.len >= maxLen:
      raw.add "..."
      break
    raw.add c
  escape(raw)

proc dumpNode(b: UiBuilder, idx: int, depth: int, maxDepth: int, output: var string) =
  let node = b.frame.nodes[idx].addr
  let absolute = b.absoluteNodePos(idx)
  output.add repeat("  ", depth)
  output.add "#" & $idx
  let name = node[].nodeDebugName()
  if name != "<unnamed>":
    output.add " " & name
  output.add " [" & fmtNum(absolute.x) & "," & fmtNum(absolute.y) & " " &
    fmtNum(node.size.x) & "x" & fmtNum(node.size.y) & "]"
  if node.pos != absolute:
    output.add " rel=" & fmtNum(node.pos.x) & "," & fmtNum(node.pos.y)
  let flags = layoutFlags(node.flags)
  if flags.len > 0:
    output.add " {" & flags & "}"
  if node.styleIndex > 0:
    let style = b.nodeStyle(idx)
    output.add " style=" & $node.styleIndex
    if style.paddingX != 0 or style.paddingY != 0:
      output.add " pad=" & fmtNum(style.paddingX) & "," & fmtNum(style.paddingY)
    if style.borderWidth != 0:
      output.add " border=" & fmtNum(style.borderWidth)
  let gap = b.nodeGap(idx)
  if gap != 0:
    output.add " gap=" & fmtNum(gap)
  if DrawText in node.flags:
    output.add " text=" & b.textSnippet(idx, 60)
  output.add '\n'
  if maxDepth >= 0 and depth >= maxDepth:
    if node.lastChild >= 0:
      output.add repeat("  ", depth + 1) & "... (" & $b.childCount(idx) & " children)\n"
    return
  for child in b.children(idx):
    b.dumpNode(child, depth + 1, maxDepth, output)

proc dumpFrameLayout*(b: UiBuilder, maxDepth = -1): string =
  ## Tree of all nodes in the current frame (call after `endUiFrame`).
  ## Each line: `#index [absX,absY WxH] rel=x,y {flags} style=N pad=x,y border=w gap=g text="..."`.
  ## Absolute positions include parent padding but ignore render transforms.
  result = "nodes " & $b.frame.nodes.len & "\n"
  if b.frame.nodes.len > 0:
    b.dumpNode(0, 0, maxDepth, result)
