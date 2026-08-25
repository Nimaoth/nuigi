include "../compat2"

import std/[math, assertions, random]
import intro
import big_example
import "../nui", "../nui_widgets", "../nui_flex", "../nui_plot"
import "../nui_dynamic_virtualist"
import "../mymath", "../arena", "../array_view"
import "../profiler"

{.passL: "-Lbuild".}

when not defined(nimony):
  proc forceNim2ToIncludeUiBuilderInTheGeneratedCFile2*(): UiBuilder {.exportc.} = UiBuilder()

var demoTabIndex = 0
var demoMenuOpen = false
var demoMenuAnchor = vec2(0.0'f32, 0.0'f32)

# ---------------------------------------------------------------------------
# Type 1 #1 — Fill
# ---------------------------------------------------------------------------

var fillDemoX = false
var fillDemoY = false
var fillDemoBoth = false

proc buildFillExamples*(b: var UiBuilder) =
  b.layoutVertical("fill-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("fillX / fillY / fill — claim space from the parent along one or both axes"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    b.layoutHorizontal("fill-controls"):
      discard b.fillX().fitY().gap(8)
      if b.checkbox("fillX", fillDemoX): discard
      if b.checkbox("fillY", fillDemoY): discard
      if b.checkbox("fill (both)", fillDemoBoth): discard

    b.node("fill-stage"):
      discard b.size(360, 150).padding(6)
      discard b.fillBackground().backgroundColor(rgba(0.10, 0.11, 0.14, 1.0))
      discard b.borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))

      b.node("fill-child"):
        discard b.size(80, 36)
        if fillDemoBoth:
          discard b.fill()
        if fillDemoX:
          discard b.fillX()
        if fillDemoY:
          discard b.fillY()
        discard b.padding(6).fillBackground().backgroundColor(rgba(0.40, 0.66, 0.92, 1.0))
        discard b.text("child")

# ---------------------------------------------------------------------------
# Type 1 #2 — Fit
# ---------------------------------------------------------------------------

var stcDemoX = false
var stcDemoY = false

proc buildFitExamples*(b: var UiBuilder) =
  b.layoutVertical("stc-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("fitX / fitY / fit — size to text and children"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    b.layoutHorizontal("stc-controls"):
      discard b.fillX().fitY().gap(8)
      if b.checkbox("fitX", stcDemoX): discard
      if b.checkbox("fitY", stcDemoY): discard

    b.node("stc-stage"):
      discard b.size(360, 150).padding(6)
      discard b.fillBackground().backgroundColor(rgba(0.10, 0.11, 0.14, 1.0))
      discard b.borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))

      b.node("stc-child"):
        discard b.size(200, 50)
        if stcDemoX:
          discard b.fitX()
        if stcDemoY:
          discard b.fitY()
        discard b.padding(6).fillBackground().backgroundColor(rgba(0.42, 0.80, 0.56, 1.0))
        discard b.text("sizes to content")

# ---------------------------------------------------------------------------
# Type 1 #3 — Anchors (moved here from nui_demo.nim)
# ---------------------------------------------------------------------------

var anchorDemoMode = 0
var anchorDemoParentWidth = 320.0'f32
var anchorDemoParentHeight = 220.0'f32

proc buildAnchorExamples*(b: var UiBuilder) =
  b.layoutVertical("anchor-demos"):
    discard b.fillX().fitY().padding(6).gap(6)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("Anchors — position a child relative to its parent using normalized 0..1 coordinates"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    b.label("top-left and bottom-right are 0..1 fractions of the parent; offsets add pixels; pivot is the anchor point on the child"):
      discard b.textColor(rgba(0.80, 0.86, 0.94, 1.0)).fontSize(13)

    b.layoutHorizontal("anchor-controls"):
      const anchorModeLabels = ["Center", "TopLeft", "Bottom", "Right"]
      discard b.fillX().fitY().gap(4)
      if b.button("Mode: " & anchorModeLabels[anchorDemoMode]):
        anchorDemoMode = (anchorDemoMode + 1) mod anchorModeLabels.len
      b.withLast:
        discard b.alignCenter()
      discard b.slider("Parent width", anchorDemoParentWidth, 180.0'f32, 420.0'f32, 0.0'f32)
      discard b.slider("Parent height", anchorDemoParentHeight, 120.0'f32, 400.0'f32, 0.0'f32)

    b.node("anchor-stage"):
      b.animate:
        discard b.sizeAnim(anchorDemoParentWidth, anchorDemoParentHeight)
      discard b.maxWidth(440).alignCenter()
      discard b.fillBackground().backgroundColor(rgba(0.10, 0.11, 0.14, 1.0))
      discard b.borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))

      template place(name: string, ax, ay, bx, by, off, px, py: float32, col: UiColor) =
        b.node(name):
          discard b.fit()
          discard b.anchors(ax, ay, bx, by).offsets(off, off, off, off).pivot(px, py).finishAnchors()
          discard b.padding(4).fillBackground().backgroundColor(col)
          discard b.text(name)

      place("TL", 0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32, 8.0'f32, 0.0'f32, 0.0'f32, rgba(0.86, 0.33, 0.31, 1.0))
      place("TR", 1.0'f32, 0.0'f32, 1.0'f32, 0.0'f32, 8.0'f32, 1.0'f32, 0.0'f32, rgba(0.26, 0.62, 0.86, 1.0))
      place("BL", 0.0'f32, 1.0'f32, 0.0'f32, 1.0'f32, 8.0'f32, 0.0'f32, 1.0'f32, rgba(0.26, 0.78, 0.78, 1.0))
      place("BR", 1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32, 8.0'f32, 1.0'f32, 1.0'f32, rgba(0.88, 0.66, 0.24, 1.0))
      place("Center", 0.5'f32, 0.5'f32, 0.5'f32, 0.5'f32, 0.0'f32, 0.5'f32, 0.5, rgba(0.33, 0.74, 0.44, 1.0))

      let (ax, ay, bx, by, px, py) = case anchorDemoMode
        of 0: (0.5'f32, 0.5'f32, 0.5'f32, 0.5'f32, 0.5'f32, 0.5'f32)
        of 1: (0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32)
        of 2: (0.5'f32, 1.0'f32, 0.5'f32, 1.0'f32, 0.5'f32, 1.0'f32)
        else: (1.0'f32, 0.5'f32, 1.0'f32, 0.5'f32, 1.0'f32, 0.5'f32)

      b.node("blend"):
        b.animate:
          discard b.anchorsAnim(ax, ay, bx, by).offsetsAnim(0, 0, 0, 0).pivotAnim(px, py)
          discard b.finishAnchors()
        discard b.fit().padding(4).fillBackground().backgroundColor(rgba(0.62, 0.42, 0.78, 1.0))
        discard b.text("blend child")

# ---------------------------------------------------------------------------
# Type 1 #4 — Layout direction
# ---------------------------------------------------------------------------

var layoutDirMode = 0

proc buildLayoutDirectionExamples*(b: var UiBuilder) =
  b.layoutVertical("layout-dir-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("layoutVertical / layoutHorizontal + DirectionReverse (column / column-reverse / row / row-reverse)"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    b.layoutHorizontal("layout-dir-controls"):
      discard b.fillX().fitY().gap(6)
      const dirLabels = ["Column", "Column reverse", "Row", "Row reverse"]
      if b.button("Direction: " & dirLabels[layoutDirMode]):
        layoutDirMode = (layoutDirMode + 1) mod dirLabels.len

    b.node("layout-dir-stage"):
      discard b.fit().padding(6).gap(6)
      discard b.fillBackground().backgroundColor(rgba(0.10, 0.11, 0.14, 1.0))
      discard b.borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))
      case layoutDirMode
      of 0: discard b.layout(LayoutVertical).forwardLayout()
      of 1: discard b.layout(LayoutVertical).reverseLayout()
      of 2: discard b.layout(LayoutHorizontal).forwardLayout()
      else: discard b.layout(LayoutHorizontal).reverseLayout()
      discard b.animateSize(DefaultAnimationSpeed * 0.3'f32).animateDelayed()

      for i in 0 .. 3:
        b.node:
          discard b.fit().padding(6).fillBackground()
          discard b.backgroundColor(rgba(0.40 + i.float32 * 0.12, 0.60, 0.90 - i.float32 * 0.10, 1.0))
          discard b.text("item " & $i)
          discard b.animatePos(DefaultAnimationSpeed * 0.3'f32).animateDelayed()

# ---------------------------------------------------------------------------
# Type 1 #5 — Align
# ---------------------------------------------------------------------------

var alignDemoMode = 0

proc buildAlignExamples*(b: var UiBuilder) =
  b.layoutVertical("align-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("alignCenter and vertical alignment via anchors (anchorsY / pivotY)"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    b.layoutHorizontal("align-controls"):
      discard b.fillX().fitY().gap(6)
      const alignLabels = ["alignCenter", "Top", "Center", "Bottom"]
      if b.button("Mode: " & alignLabels[alignDemoMode]):
        alignDemoMode = (alignDemoMode + 1) mod alignLabels.len

    b.node("align-stage"):
      discard b.size(360, 150).padding(6)
      discard b.fillBackground().backgroundColor(rgba(0.10, 0.11, 0.14, 1.0))
      discard b.borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))

      b.node("align-child"):
        discard b.fit().padding(6).fillBackground().backgroundColor(rgba(0.96, 0.72, 0.28, 1.0))
        case alignDemoMode
        of 0: discard b.alignCenter()
        of 1: discard b.anchorsY(0.0'f32, 0.0'f32).offsetsY(0.0'f32, 0.0'f32).pivotY(0.0'f32).finishAnchors()
        of 2: discard b.anchorsY(0.5'f32, 0.5'f32).offsetsY(0.0'f32, 0.0'f32).pivotY(0.5'f32).finishAnchors()
        else: discard b.anchorsY(1.0'f32, 1.0'f32).offsetsY(0.0'f32, 0.0'f32).pivotY(1.0'f32).finishAnchors()
        discard b.text("aligned")

# ---------------------------------------------------------------------------
# Type 1 #6 — Gap & padding
# ---------------------------------------------------------------------------

var gapDemoGap = 12.0'f32
var gapDemoPadding = 10.0'f32

proc buildGapPaddingExamples*(b: var UiBuilder) =
  b.layoutVertical("gap-pad-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("gap (spacing between children, needs a layout) and padding (inset around a node's content box)"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    b.layoutHorizontal("gap-pad-controls"):
      discard b.fillX().fitY().gap(8)
      discard b.slider("gap", gapDemoGap, 0.0'f32, 48.0'f32, 12)
      discard b.slider("padding", gapDemoPadding, 0.0'f32, 40.0'f32, 10)

    b.node("gap-pad-stage"):
      discard b.width(360).fitY().padding(gapDemoPadding).gap(gapDemoGap)
      discard b.layout(LayoutVertical).forwardLayout()
      discard b.fillBackground().backgroundColor(rgba(0.10, 0.11, 0.14, 1.0))
      discard b.borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))

      for i in 0 .. 3:
        b.node:
          discard b.fit().padding(6).fillBackground()
          discard b.backgroundColor(rgba(0.40 + i.float32 * 0.12, 0.60, 0.90 - i.float32 * 0.10, 1.0))
          discard b.text("item " & $i)

# ---------------------------------------------------------------------------
# Type 1 #7 — Style (background, border, corner radius)
# ---------------------------------------------------------------------------

var styleDemoBg = rgba(0.40, 0.66, 0.92, 1.0)
var styleDemoBorderL = rgba(0.96, 0.72, 0.28, 1.0)
var styleDemoBorderT = rgba(0.96, 0.72, 0.28, 1.0)
var styleDemoBorderR = rgba(0.96, 0.72, 0.28, 1.0)
var styleDemoBorderB = rgba(0.96, 0.72, 0.28, 1.0)
var styleDemoBorderWL = 4.0'f32
var styleDemoBorderWT = 4.0'f32
var styleDemoBorderWR = 4.0'f32
var styleDemoBorderWB = 4.0'f32
var styleDemoRadiusTL = 12.0'f32
var styleDemoRadiusTR = 12.0'f32
var styleDemoRadiusBR = 12.0'f32
var styleDemoRadiusBL = 12.0'f32

proc buildStyleExamples*(b: var UiBuilder) =
  b.layoutVertical("style-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("backgroundColor, borderWidths (per side), cornerRadii (per corner), borderColors (per side)"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    b.node("style-child"):
      discard b.fit().padding(30)
      discard b.backgroundColor(styleDemoBg)
      discard b.borderWidths(styleDemoBorderWL, styleDemoBorderWT, styleDemoBorderWR, styleDemoBorderWB)
      discard b.cornerRadii(styleDemoRadiusTL, styleDemoRadiusTR, styleDemoRadiusBR, styleDemoRadiusBL)
      discard b.borderColors(styleDemoBorderL, styleDemoBorderT, styleDemoBorderR, styleDemoBorderB)
      discard b.text("styled box")

    b.layoutHorizontal("style-bg"):
      discard b.fillX().fitY().gap(8)
      b.node("bg-pick"):
        discard b.fit().gap(4)
        b.label("backgroundColor"): discard b.fontSize(13)
        if b.colorPicker(styleDemoBg): discard

    b.layoutVertical("style-widths"):
      discard b.fillX().fitY().gap(4)
      b.label("borderWidths (left / top / right / bottom)"): discard b.fontSize(13)
      b.layoutHorizontal:
        discard b.fillX().fitY().gap(8)
        discard b.slider("L", styleDemoBorderWL, 0.0'f32, 20.0'f32, 4)
        discard b.slider("T", styleDemoBorderWT, 0.0'f32, 20.0'f32, 4)
        discard b.slider("R", styleDemoBorderWR, 0.0'f32, 20.0'f32, 4)
        discard b.slider("B", styleDemoBorderWB, 0.0'f32, 20.0'f32, 4)

    b.layoutVertical("style-radii"):
      discard b.fillX().fitY().gap(4)
      b.label("cornerRadii (topLeft / topRight / bottomRight / bottomLeft)"): discard b.fontSize(13)
      b.layoutHorizontal:
        discard b.fillX().fitY().gap(8)
        discard b.slider("TL", styleDemoRadiusTL, 0.0'f32, 60.0'f32, 12)
        discard b.slider("TR", styleDemoRadiusTR, 0.0'f32, 60.0'f32, 12)
        discard b.slider("BR", styleDemoRadiusBR, 0.0'f32, 60.0'f32, 12)
        discard b.slider("BL", styleDemoRadiusBL, 0.0'f32, 60.0'f32, 12)

    b.layoutVertical("style-colors"):
      discard b.fillX().fitY().gap(4)
      b.label("borderColors (left / top / right / bottom)"): discard b.fontSize(13)
      b.layoutHorizontal:
        discard b.fillX().fitY().gap(8)
        template pick(name: string, col: var UiColor) =
          b.node(name):
            discard b.fit().gap(4)
            b.label(name): discard b.fontSize(13)
            if b.colorPicker(col): discard
        pick("L", styleDemoBorderL)
        pick("T", styleDemoBorderT)
        pick("R", styleDemoBorderR)
        pick("B", styleDemoBorderB)

    b.label("Per-corner radii and per-side borders"):
      discard b.fontSize(18)
      discard b.textColor(rgba(0.96, 0.90, 0.68, 1.0))

    b.node("border-style-gallery"):
      discard b.fillX().fitY().gap(12)
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexWrap(FlexWrap).flexGaps(12, 12)

      b.layoutVertical("asymmetric-corners"):
        discard b.size(260, 150).padding(14).gap(8)
        discard b.fillBackground().backgroundColor(rgba(0.16, 0.30, 0.34, 1.0))
        discard b.cornerRadii(30, 4, 24, 0)
        discard b.borderWidth(3)
        discard b.borderColor(rgba(0.36, 0.88, 0.80, 1.0))
        discard b.animatePos().animateDelayed()
        b.labelWrapped("Asymmetric corners"):
          discard b.fillX()
          discard b.fontSize(16).textColor(rgba(0.92, 1.0, 0.98, 1.0))
        b.labelWrapped("TL 30  TR 4  BR 24  BL 0"):
          discard b.fillX()
          discard b.textColor(rgba(0.72, 0.88, 0.86, 1.0))

      b.layoutVertical("asymmetric-widths"):
        discard b.size(260, 150).padding(14).gap(8)
        discard b.fillBackground().backgroundColor(rgba(0.24, 0.19, 0.30, 1.0))
        discard b.cornerRadius(12)
        discard b.borderWidths(2, 8, 14, 4)
        discard b.borderColor(rgba(0.84, 0.68, 0.96, 1.0))
        discard b.animatePos().animateDelayed()
        b.labelWrapped("Per-side widths"):
          discard b.fillX()
          discard b.fontSize(16).textColor(rgba(0.98, 0.94, 1.0, 1.0))
        b.labelWrapped("Left 2  Top 8  Right 14  Bottom 4"):
          discard b.fillX()
          discard b.textColor(rgba(0.84, 0.78, 0.92, 1.0))

      b.layoutVertical("combined-border-style"):
        discard b.size(260, 150).padding(14).gap(8)
        discard b.fillBackground().backgroundColor(rgba(0.18, 0.20, 0.25, 1.0))
        discard b.cornerRadii(28, 12, 28, 12)
        discard b.borderWidths(5, 9, 5, 9)
        discard b.animatePos().animateDelayed()
        discard b.borderColors(
          rgba(0.96, 0.34, 0.40, 1.0),
          rgba(0.98, 0.78, 0.24, 1.0),
          rgba(0.30, 0.72, 0.98, 1.0),
          rgba(0.40, 0.88, 0.54, 1.0))
        b.labelWrapped("Combined"):
          discard b.fillX()
          discard b.fontSize(16).textColor(rgba(0.98, 0.98, 0.98, 1.0))
        b.labelWrapped("Four side colors, two widths, four radii"):
          discard b.fillX()
          discard b.textColor(rgba(0.82, 0.86, 0.92, 1.0))

      b.layoutVertical("all"):
        discard b.size(260, 150).padding(14).gap(8)
        discard b.fillBackground().backgroundColor(rgba(0.16, 0.30, 0.34, 1.0))
        discard b.cornerRadii(30, 4, 60, 0)
        discard b.borderWidths(2, 8, 15, 1)
        discard b.animatePos().animateDelayed()
        discard b.borderColors(
          rgba(0.96, 0.34, 0.40, 1.0),
          rgba(0.98, 0.78, 0.24, 1.0),
          rgba(0.30, 0.72, 0.98, 1.0),
          rgba(0.40, 0.88, 0.54, 1.0))
        b.label("Asymmetric all"):
          discard b.fontSize(16).textColor(rgba(0.92, 1.0, 0.98, 1.0))
# ---------------------------------------------------------------------------
# Type 1 #8 — Text style
# ---------------------------------------------------------------------------

var textDemoText = "The quick brown fox jumps over the lazy dog. Edit me! 0123456789"
var textDemoSize = 18.0'f32
var textDemoColor = rgba(0.96, 0.92, 0.78, 1.0)
var textDemoWrap = true
var textDemoFontIdx = 0

proc buildTextStyleExamples*(b: var UiBuilder) =
  b.layoutVertical("text-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("text, fontSize, textColor, wrapText"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    b.layoutVertical("text-controls"):
      discard b.fillX().fitY().gap(6)
      b.label("text"): discard b.fontSize(13)
      if b.textField(textDemoText, "Type text..."): discard

      b.layoutHorizontal:
        discard b.fillX().fitY().gap(8)
        b.node("text-color"):
          discard b.fit().gap(4)
          b.label("textColor"): discard b.fontSize(13)
          if b.colorPicker(textDemoColor): discard
        if b.checkbox("wrapText", textDemoWrap): discard

      b.layoutHorizontal:
        discard b.fillX().fitY().gap(8)
        discard b.slider("fontSize", textDemoSize, 8.0'f32, 64.0'f32, 18)

      b.node("text-font"):
        discard b.fit().gap(4)
        b.label("font (b.fonts)"): discard b.fontSize(13)
        var fontNames: seq[string] = newSeq[string]()
        for name, id in b.fonts.pairs:
          fontNames.add(name)
        if fontNames.len > 0:
          if textDemoFontIdx >= fontNames.len:
            textDemoFontIdx = 0
          if b.dropdown(fontNames, textDemoFontIdx): discard

    b.node("text-stage"):
      discard b.size(360, 150).fitY().padding(8).gap(8)
      discard b.fillBackground().backgroundColor(rgba(0.10, 0.11, 0.14, 1.0))
      discard b.borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))
      var fontNames2: seq[string] = newSeq[string]()
      for name, id in b.fonts.pairs:
        fontNames2.add(name)
      if fontNames2.len > 0 and textDemoFontIdx < fontNames2.len:
        discard b.fontId(b.fonts.getOrDefault(fontNames2[textDemoFontIdx]))
      discard b.text(textDemoText).fontSize(textDemoSize).textColor(textDemoColor)
      if textDemoWrap:
        discard b.wrapText()

# ---------------------------------------------------------------------------
# Type 1 #9 — Mask children / hover flags
# ---------------------------------------------------------------------------

var maskDemoMask = false
var maskDemoNoHover = false
var maskDemoNoChildHover = false

proc buildMaskChildrenExamples*(b: var UiBuilder) =
  b.layoutVertical("mask-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("maskChildren (clip overflow), noHover, noChildHover"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    b.layoutHorizontal("mask-controls"):
      discard b.fillX().fitY().gap(8)
      if b.checkbox("maskChildren", maskDemoMask): discard
      if b.checkbox("noHover", maskDemoNoHover): discard
      if b.checkbox("noChildHover", maskDemoNoChildHover): discard

    b.node("mask-stage"):
      discard b.size(320, 170).padding(8)
      let h = b.wasHovered()
      discard b.backgroundColor(if h: rgba(0.96, 0.43, 0.41, 1.0) else: rgba(0.86, 0.33, 0.31, 1.0))
      if maskDemoMask:
        discard b.maskChildren()
      if maskDemoNoHover:
        discard b.noHover()
      if maskDemoNoChildHover:
        discard b.noChildHover()

      b.node("mask-hover"):
        discard b.fit().padding(8).fillBackground()
        discard b.anchors(1.0'f32, 0.5'f32, 1.0'f32, 0.5'f32).offsets(-8, -8, -8, -8).pivot(0.5'f32, 0.5'f32).finishAnchors()
        let h = b.wasHovered()
        discard b.backgroundColor(if h: rgba(0.40, 0.90, 0.50, 1.0) else: rgba(0.40, 0.66, 0.92, 1.0))
        discard b.text("hover me")

# ---------------------------------------------------------------------------
# Type 1 #10 — Animation (immediate + delayed)
# ---------------------------------------------------------------------------

var animDemoExpanded = false
var animDemoShow = false

proc buildAnimationExamples*(b: var UiBuilder) =
  b.layoutVertical("anim-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("animate (immediate, triggered on hover/click): sizeAnim, backgroundColorAnim, transformScaleAnim, positionAnim, widthAnim, heightAnim"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))
    b.label("animateDelayed: transformScaleAnim only when the node appears"):
      discard b.textColor(rgba(0.80, 0.86, 0.94, 1.0)).fontSize(13)

    b.layoutHorizontal("anim-controls"):
      discard b.fillX().fitY().gap(8)
      if b.button("Toggle expand"):
        animDemoExpanded = not animDemoExpanded
      if b.button("Toggle show"):
        animDemoShow = not animDemoShow
      var animationSpeed = b.animationSpeed
      discard b.slider("Animation speed", animationSpeed, 0.0'f32, 4.0'f32, 1.0'f32)
      b.animationSpeed = animationSpeed

    b.layoutHorizontal:
      discard b.fillX().fitY().gap(8)
      b.node("anim-hover-transform"):
        discard b.size(140, 90).padding(8).fillBackground().cornerRadius(8)
        if b.wasHovered():
          discard b.backgroundColor(rgba(0.40, 0.90, 0.50, 1.0))
        else:
          discard b.backgroundColor(rgba(0.40, 0.66, 0.92, 1.0))
        let h = b.wasHovered()
        b.animate:
          discard b.backgroundColorAnim(if h: rgba(0.40, 0.90, 0.50, 1.0) else: rgba(0.40, 0.66, 0.92, 1.0))
          discard b.transformScaleAnim(if h: 1.5'f32 else: 1.0'f32)
        discard b.alignCenter()
        discard b.text("animate transform")

      b.node("anim-hover-size"):
        discard b.size(140, 90).padding(8).fillBackground().cornerRadius(8)
        if b.wasHovered():
          discard b.backgroundColor(rgba(0.40, 0.90, 0.50, 1.0))
        else:
          discard b.backgroundColor(rgba(0.40, 0.66, 0.92, 1.0))
        let h = b.wasHovered()
        b.animate:
          discard b.sizeAnim(if h: 200.0'f32 else: 140.0'f32, if h: 130.0'f32 else: 90.0'f32)
          discard b.backgroundColorAnim(if h: rgba(0.40, 0.90, 0.50, 1.0) else: rgba(0.40, 0.66, 0.92, 1.0))
        discard b.alignCenter()
        discard b.text("animate size")

    b.node("anim-click"):
      discard b.size(360, 130).padding(8).fillBackground().backgroundColor(rgba(0.10, 0.11, 0.14, 1.0)).cornerRadius(8)
      discard b.borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))
      b.node("anim-click-box"):
        discard b.alignCenter().padding(6).fillBackground().backgroundColor(rgba(0.96, 0.72, 0.28, 1.0)).cornerRadius(6)
        let s = if animDemoExpanded: 110.0'f32 else: 60.0'f32
        let w = if animDemoExpanded: 220.0'f32 else: 120.0'f32
        b.animate:
          discard b.sizeAnim(w, s)
          discard b.transformScaleAnim(if animDemoExpanded: 1.1'f32 else: 1.0'f32)
        discard b.alignCenter()
        discard b.text(if animDemoExpanded: "expanded" else: "click Toggle expand")

    if animDemoShow:
      b.node("anim-delayed"):
        discard b.padding(12).fillBackground().cornerRadius(8)
        discard b.backgroundColor(rgba(0.62, 0.42, 0.78, 1.0))
        let firstAppearance = b.previousNodeIndex(b.currentNode.id, b.currentNodeIndex) < 0
        if firstAppearance:
          discard b.size(0, 0)
        else:
          discard b.fit()
        discard b.animatePos()
        discard b.animateSize()
        discard b.animateDelayed()
        discard b.alignCenter().maskChildren()
        discard b.text("Animate size on show")

# ---------------------------------------------------------------------------
# Type 1 #11 — Transform (offset / rotate / scale / pivot)
# ---------------------------------------------------------------------------

var transformDemoX = 0.0'f32
var transformDemoY = 0.0'f32
var transformDemoRot = 0.0'f32
var transformDemoScale = 1.0'f32
var transformDemoPivotX = 0.5'f32
var transformDemoPivotY = 0.5'f32
var transformDemoAnimate = true

proc buildTransformExamples*(b: var UiBuilder) =
  b.layoutVertical("transform-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("transformOffset, transformRotation, transformScale, transformPivot — render-space transform around a pivot"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))
    b.label("pivot is a 0..1 fraction of the node box; offset is in pixels; rotation in radians; scale is multiplicative"):
      discard b.textColor(rgba(0.80, 0.86, 0.94, 1.0)).fontSize(13)

    b.node("transform-controls"):
      discard b.fillX().fitY().flexLayout().flexFlow(FlexDirectionRow, FlexWrap).flexGaps(8, 8)
      discard b.slider("offset X", transformDemoX, -60.0'f32, 60.0'f32, 0)
      discard b.slider("offset Y", transformDemoY, -60.0'f32, 60.0'f32, 0)
      discard b.slider("rotation", transformDemoRot, -3.14159'f32, 3.14159'f32, 0)
      discard b.slider("scale", transformDemoScale, 0.25'f32, 2.5'f32, 1)
      discard b.slider("pivot X", transformDemoPivotX, 0.0'f32, 1.0'f32, 0.5)
      discard b.slider("pivot Y", transformDemoPivotY, 0.0'f32, 1.0'f32, 0.5)
      if b.checkbox("animate", transformDemoAnimate): discard
      if b.button("Randomize"):
        transformDemoX = rand(120.0'f32).float32 - 60.0'f32
        transformDemoY = rand(120.0'f32).float32 - 60.0'f32
        transformDemoRot = rand(6.28318'f32).float32 - 3.14159'f32
        transformDemoScale = rand(2.25'f32).float32 + 0.25'f32
        transformDemoPivotX = rand(1.0'f32).float32
        transformDemoPivotY = rand(1.0'f32).float32
      if b.button("Reset all"):
        transformDemoX = 0.0'f32
        transformDemoY = 0.0'f32
        transformDemoRot = 0.0'f32
        transformDemoScale = 1.0'f32
        transformDemoPivotX = 0.5'f32
        transformDemoPivotY = 0.5'f32

    b.node("transform-stage"):
      discard b.size(360, 200).padding(10)
      discard b.fillBackground().backgroundColor(rgba(0.10, 0.11, 0.14, 1.0))
      discard b.borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))

      b.node("transform-child"):
        discard b.fit().padding(10).alignCenter().fillBackground()
        if b.wasHovered():
          discard b.backgroundColor(rgba(0.60, 0.80, 0.99, 1.0))
        else:
          discard b.backgroundColor(rgba(0.40, 0.66, 0.92, 1.0))
        discard b.cornerRadius(6)
        if transformDemoAnimate:
          b.animate:
            discard b.transformOffsetAnim(transformDemoX, transformDemoY)
            discard b.transformRotationAnim(transformDemoRot)
            discard b.transformScaleAnim(transformDemoScale, transformDemoScale)
            discard b.transformPivotAnim(transformDemoPivotX, transformDemoPivotY)
        else:
          discard b.transformOffset(transformDemoX, transformDemoY)
          discard b.transformRotation(transformDemoRot)
          discard b.transformScale(transformDemoScale)
          discard b.transformPivot(transformDemoPivotX, transformDemoPivotY)
        discard b.text("transformed")

    b.layoutHorizontal("transform-corner-pivot-row"):
      discard b.fillX().fitY().gap(6)

      template cornerPivot(name: string, px, py: float32, col: UiColor) =
        b.node(name):
          discard b.size(110, 90).padding(4)
          discard b.fillBackground().backgroundColor(rgba(0.10, 0.11, 0.14, 1.0))
          discard b.borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))
          b.node("cp-child"):
            discard b.fit().padding(6).alignCenter().fillBackground().backgroundColor(col).cornerRadius(4)
            let spin = b.frameCtx.input.frameIndex.float32 * 0.03'f32 * b.animationSpeed
            discard b.transformPivot(px, py)
            discard b.transformRotation(spin)
            discard b.text("pivot")

      cornerPivot("cp-tl", 0.0'f32, 0.0'f32, rgba(0.86, 0.33, 0.31, 1.0))
      cornerPivot("cp-tr", 1.0'f32, 0.0'f32, rgba(0.26, 0.62, 0.86, 1.0))
      cornerPivot("cp-bl", 0.0'f32, 1.0'f32, rgba(0.26, 0.78, 0.78, 1.0))
      cornerPivot("cp-br", 1.0'f32, 1.0'f32, rgba(0.88, 0.66, 0.24, 1.0))

# ---------------------------------------------------------------------------
# Type 3 — every simple widget (vertical list)
# ---------------------------------------------------------------------------

var awClicked = 0
var awChecked = false
var awSlider = 0.5'f32
var awColor = rgba(0.40, 0.66, 0.92, 1.0)
var awDropdown = 0
var awDropdownOptions = ["Apple", "Banana", "Cherry", "Date"]
var awText = ""
var awMenuOpen = false

proc buildAllWidgetsExample*(b: var UiBuilder) =
  b.layoutVertical("all-widgets"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("Builtin widgets"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    b.tableLayout([tableColumnFit(), tableColumnFill()], 8.0, 4.0):
      discard b.fillX().fitY().padding(6)
      discard b.backgroundColor(rgba(0.10, 0.12, 0.17, 1.0))

      template headerCell(cap: string) =
        b.node:
          discard b.fitY().padding(4).fillBackground().backgroundColor(rgba(0.20, 0.25, 0.34, 1.0))
          discard b.text(cap).fit()
          discard b.textColor(rgba(0.96, 0.90, 0.55, 1.0))
      template labelCell(cap: string) =
        b.node:
          discard b.fitY().padding(4).fillBackground()
          discard b.text(cap).fit()
          discard b.textColor(rgba(0.88, 0.88, 0.92, 1.0))
      template widgetCell(body: untyped) =
        b.node:
          discard b.fillX().fitY().padding(4)
          body

      headerCell("Widget")
      headerCell("Preview")

      labelCell("label")
      widgetCell:
        b.label("Hello, world")
      labelCell("labelWrapped")
      widgetCell:
        b.labelWrapped("Text that wraps within the available width."):
          discard b.fontSize(13)
      labelCell("button")
      widgetCell:
        if b.button("Clicks: " & $awClicked):
          awClicked += 1
      labelCell("checkbox")
      widgetCell:
        if b.checkbox("Enabled", awChecked): discard
      labelCell("slider")
      widgetCell:
        discard b.slider("value", awSlider, 0.0'f32, 1.0'f32, 0.5'f32)
      labelCell("colorPicker")
      widgetCell:
        b.node("color-host"):
          discard b.fit().gap(4)
          if b.colorPicker(awColor): discard
      labelCell("dropdown")
      widgetCell:
        b.node("dropdown-host"):
          discard b.fit().gap(4)
          if b.dropdown(awDropdownOptions, awDropdown): discard
      labelCell("textField")
      widgetCell:
        b.node("textfield-host"):
          discard b.fit().gap(4)
          if b.textField(awText, "Type here..."): discard
      labelCell("tooltip")
      widgetCell:
        b.node("tooltip-host"):
          discard b.fit().gap(4)
          if b.button("Hover me"):
            discard
          if b.wasHovered(b.nodes.high):
            b.tooltip:
              discard b.fit().padding(4)
              discard b.backgroundColor(rgba(0.10, 0.12, 0.18, 1.0)).borderWidth(1).borderColor(rgba(0.32, 0.40, 0.52, 1.0))
              b.label("This is a tooltip"): discard
      labelCell("menu")
      widgetCell:
        b.menuBar:
          discard b.fit().fitY()
          b.menuBarItem(awMenuOpen):
            b.label("Menu")
          do:
            discard
          do:
            discard
          do:
            let itemNodeIndex = b.stack[^1]
            let itemPos = b.absoluteNodePosPrev(b.nodes[itemNodeIndex].id, itemNodeIndex)
            let itemSize = b.nodes[itemNodeIndex].size
            b.menu(awMenuOpen, itemPos.x, itemPos.y + itemSize.y):
              b.menuItem:
                b.label("Item A")
              do:
                discard
              do:
                discard
              b.menuItem:
                b.label("Item B")
              do:
                discard
              do:
                discard
              b.menuItem:
                b.label("Item C")
              do:
                discard
              do:
                discard

# ---------------------------------------------------------------------------
# Type 5 — complex widgets (virtual list + dynamic virtual list)
# ---------------------------------------------------------------------------

var cvScroll = 0.0
var cvItemCount = 200

proc cvFixedItem(b: var UiBuilder, itemIndex: int, userData: int) =
  discard b.fillX().fitY().padding(6)
  discard b.fillBackground().backgroundColor(if itemIndex mod 2 == 0: rgba(0.13, 0.15, 0.20, 1.0) else: rgba(0.15, 0.18, 0.24, 1.0))
  discard b.text("Item " & $itemIndex).fit()
  discard b.textColor(rgba(0.88, 0.88, 0.92, 1.0))

proc cvDynItem(b: var UiBuilder, itemIndex: int, userData: int) =
  discard b.fillX().fitY().padding(6).layout(LayoutVertical)
  discard b.fillBackground().backgroundColor(if itemIndex mod 2 == 0: rgba(0.13, 0.15, 0.20, 1.0) else: rgba(0.15, 0.18, 0.24, 1.0))
  b.label("Dynamic item " & $itemIndex):
    discard b.textColor(rgba(0.88, 0.88, 0.92, 1.0))
  if itemIndex mod 3 == 0:
    b.labelWrapped("This row is taller: wrapped text that spans multiple lines to show variable-height measurement in the dynamic virtual list."):
      discard b.fillX().fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))

proc buildComplexWidgetsExample*(b: var UiBuilder) =
  b.layoutVertical("complex-widgets"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("Complex widgets: virtualList (fixed-height rows) and dynamicVirtualList (variable-height rows)"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    var count = cvItemCount.float32
    discard b.slider("Virtual list item count", count, 1.0'f32, 1_000_000.0'f32, 200)
    cvItemCount = count.int

    b.tableLayout([tableColumnProportional(1), tableColumnProportional(2)], 8.0, 4.0):
      discard b.fillX().fitY().padding(6)
      discard b.backgroundColor(rgba(0.10, 0.12, 0.17, 1.0))

      template headerCell(cap: string) =
        b.node:
          discard b.fitY().padding(4).fillBackground().backgroundColor(rgba(0.20, 0.25, 0.34, 1.0))
          discard b.text(cap).fit()
          discard b.textColor(rgba(0.96, 0.90, 0.55, 1.0))

      template nameCell(name, desc: string) =
        b.layoutVertical:
          discard b.fitY().padding(4).gap(2).fillBackground()
          b.label(name):
            discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))
          b.labelWrapped(desc):
            discard b.fillX().fontSize(12).textColor(rgba(0.80, 0.86, 0.94, 1.0))

      headerCell("Widget")
      headerCell("Preview")

      nameCell("scrollBox", "Simple scrollable container for any content. No recycling, so great for a few items but heavy for thousands.")
      b.node:
        discard b.fillX().height(220).padding(4)
        b.scrollBox:
          b.layoutVertical:
            discard b.fillX().fitY().gap(4)
            for i in 0 .. 15:
              b.node:
                discard b.fillX().fitY().padding(6).fillBackground()
                discard b.backgroundColor(if i mod 2 == 0: rgba(0.13, 0.15, 0.20, 1.0) else: rgba(0.15, 0.18, 0.24, 1.0))
                discard b.text("Scrollable row " & $i).fit()
                discard b.textColor(rgba(0.88, 0.88, 0.92, 1.0))

      nameCell("virtualList", "Fixed row height; only renders visible rows. Very fast for huge lists, but every row must be the same height.")
      b.node:
        discard b.fillX().height(220).padding(4)
        b.virtualList(cvScroll, cvItemCount, 28.0'f32, cvFixedItem)

      nameCell("dynamicVirtualList", "Variable row heights; only renders visible rows. Very fast for huge lists, and handles mixed item height, caches rendered item heights for the scroll bar.")
      b.node:
        discard b.fillX().height(220).padding(4)
        b.dynamicVirtualList(cvItemCount, 40.0'f32, cvDynItem)

# ---------------------------------------------------------------------------
# Type 2 — combined common layouts (basic features composed)
# ---------------------------------------------------------------------------

var layoutDemoMusic = true
var layoutDemoVolume = 0.7'f32
var layoutDemoVsync = false
var layoutDemoFullscreen = true
var layoutDemoFormName = "Player One"
var layoutDemoFormRemember = true

proc buildLayoutExamples*(b: var UiBuilder) =
  b.layoutVertical("layout-examples"):
    discard b.fillX().fitY().padding(8).gap(12)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("Combined common layouts — Top bar, Sidebar, Card grid, Settings panel, Toolbar, Form"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))

    # 1. Top bar -----------------------------------------------------------
    b.label("Top bar — fixed blocks on the left/right, fills the middle"):
      discard b.fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))
    b.node("topbar"):
      discard b.fillX().fitY().padding(6).gap(6)
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexGaps(6, 6)
      discard b.backgroundColor(rgba(0.16, 0.20, 0.28, 1.0)).cornerRadius(4)
      b.node:
        discard b.fit().padding(6).fillBackground().backgroundColor(rgba(0.86, 0.33, 0.31, 1.0))
        discard b.text("Logo")
      b.node:
        discard b.fit().padding(6).fillBackground().backgroundColor(rgba(0.26, 0.62, 0.86, 1.0))
        discard b.text("File")
      b.node:
        discard b.fitY().flex(1, 1)
      b.node:
        discard b.fit().padding(6).fillBackground().backgroundColor(rgba(0.26, 0.78, 0.78, 1.0))
        discard b.text("Search")
      b.node:
        discard b.fit().padding(6).fillBackground().backgroundColor(rgba(0.88, 0.66, 0.24, 1.0))
        discard b.text("Profile")

    # 2. Sidebar -----------------------------------------------------------
    b.label("Sidebar — fixed-width sidebar next to a filling content area"):
      discard b.fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))
    b.node("sidebar"):
      discard b.fillX().height(150).padding(6).gap(6)
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexGaps(6, 6)
      discard b.backgroundColor(rgba(0.16, 0.20, 0.28, 1.0)).cornerRadius(4)
      b.node:
        discard b.size(90, 0).fitY().padding(6).gap(4)
        discard b.layout(LayoutVertical).forwardLayout()
        discard b.flex(0.0, 0.0, 90.0)
        discard b.backgroundColor(rgba(0.20, 0.24, 0.32, 1.0))
        b.label("Home"): discard b.textColor(rgba(0.88, 0.88, 0.92, 1.0))
        b.label("Projects"): discard b.textColor(rgba(0.80, 0.86, 0.94, 1.0))
        b.label("Settings"): discard b.textColor(rgba(0.80, 0.86, 0.94, 1.0))
      b.node:
        discard b.fillX().fitY().padding(8).gap(6)
        discard b.layout(LayoutVertical).forwardLayout()
        discard b.fillBackground().backgroundColor(rgba(0.10, 0.12, 0.18, 1.0))
        b.label("Content area"): discard b.textColor(rgba(0.88, 0.88, 0.92, 1.0))
        b.labelWrapped("This region grows to fill the remaining width while the sidebar keeps a fixed size."):
          discard b.fillX().fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))

    # 3. Card grid ---------------------------------------------------------
    b.label("Card grid — cards laid out from a loop in a wrapping flex"):
      discard b.fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))
    b.node("card-grid"):
      discard b.fillX().fitY().padding(8).gap(8)
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexWrap(FlexWrap).flexGaps(8, 8)
      discard b.backgroundColor(rgba(0.16, 0.20, 0.28, 1.0)).cornerRadius(4)
      for i in 0 .. 7:
        b.node:
          discard b.size(96, 64).padding(6).gap(4)
          discard b.layout(LayoutVertical).forwardLayout()
          discard b.flex(0.0, 1.0, 96.0)
          discard b.fillBackground().backgroundColor(rgba(0.30 + i.float32 * 0.05'f32, 0.50, 0.74 - i.float32 * 0.04'f32, 1.0)).cornerRadius(4)
          b.label("Card " & $i): discard b.textColor(rgba(0.96, 0.96, 0.98, 1.0))
          b.labelWrapped("item description"):
            discard b.fontSize(11).textColor(rgba(0.82, 0.86, 0.94, 1.0))

    # 4. Settings panel ---------------------------------------------------
    b.label("Settings panel — label + control rows"):
      discard b.fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))
    b.node("settings-panel"):
      discard b.fillX().fitY().padding(8)
      discard b.backgroundColor(rgba(0.16, 0.20, 0.28, 1.0)).cornerRadius(4)
      b.tableLayout([tableColumnFit(), tableColumnFill()], 8.0, 4.0):
        discard b.fillX().fitY()
        template settingRow(rowLabel: string, body: untyped) =
          b.node:
            discard b.fitY().padding(4).fillBackground()
            discard b.text(rowLabel).fit()
            discard b.textColor(rgba(0.88, 0.88, 0.92, 1.0))
          b.node:
            discard b.fillX().fitY().padding(4)
            body
        settingRow("Music"):
          if b.checkbox("", layoutDemoMusic): discard
        settingRow("Volume"):
          discard b.slider("", layoutDemoVolume, 0.0'f32, 1.0'f32, 0.7'f32)
        settingRow("VSync"):
          if b.checkbox("", layoutDemoVsync): discard
        settingRow("Fullscreen"):
          if b.checkbox("", layoutDemoFullscreen): discard

    # 5. Toolbar -----------------------------------------------------------
    b.label("Toolbar — wrapping row of buttons"):
      discard b.fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))
    b.node("toolbar"):
      discard b.fillX().fitY().padding(6).gap(6)
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexWrap(FlexWrap).flexGaps(6, 6)
      discard b.backgroundColor(rgba(0.16, 0.20, 0.28, 1.0)).cornerRadius(4)
      for name in ["New", "Open", "Save", "Cut", "Copy", "Paste", "Undo", "Redo", "Find", "Run"]:
        if b.button(name): discard

    # 6. Form --------------------------------------------------------------
    b.label("Form — text field, checkbox and button stacked"):
      discard b.fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))
    b.node("form"):
      discard b.fillX().fitY().padding(8).gap(8)
      discard b.layout(LayoutVertical).forwardLayout()
      discard b.backgroundColor(rgba(0.16, 0.20, 0.28, 1.0)).cornerRadius(4)
      b.label("Name"): discard b.textColor(rgba(0.88, 0.88, 0.92, 1.0))
      b.node("form-name"):
        discard b.fit().gap(4)
        if b.textField(layoutDemoFormName, "Enter name..."): discard
      if b.checkbox("Remember me", layoutDemoFormRemember, fillXInVertical = false): discard
      if b.button("Submit"): discard

# ---------------------------------------------------------------------------
# Text rendering showcases (mirrored from ui_example.nim)
# ---------------------------------------------------------------------------

const unicodeStressLines* = [
  "English: The quick brown fox jumps over the lazy dog 0123456789 English: The quick brown fox jumps over the lazy dog 0123456789",
  "Chinese (Simplified): 你好，世界。快速的棕色狐狸跳过懒狗。 Chinese (Simplified): 你好，世界。快速的棕色狐狸跳过懒狗。",
  "Chinese (Traditional): 你好，世界。敏捷的棕色狐狸跳過懶狗。 Chinese (Traditional): 你好，世界。敏捷的棕色狐狸跳過懶狗。",
  "Japanese (Hiragana/Katakana): こんにちは世界。すばやいキツネがのんびり犬を飛び越える。 Japanese (Hiragana/Katakana): こんにちは世界。すばやいキツネがのんびり犬を飛び越える。",
  "Japanese (Kanji): 日本語の表示テスト：漢字、ひらがな、カタカナ。 Japanese (Kanji): 日本語の表示テスト：漢字、ひらがな、カタカナ。",
  "Korean: 안녕하세요 세계. 빠른 갈색 여우가 게으른 개를 뛰어넘습니다. Korean: 안녕하세요 세계. 빠른 갈색 여우가 게으른 개를 뛰어넘습니다.",
  "Thai: สวัสดีชาวโลก จิ้งจอกสีน้ำตาลกระโดดข้ามสุนัขขี้เกียจ Thai: สวัสดีชาวโลก จิ้งจอกสีน้ำตาลกระโดดข้ามสุนัขขี้เกียจ",
  "Vietnamese: Xin chao the gioi. Chu cao nau nhanh nhay qua cho luoi. Vietnamese: Xin chao the gioi. Chu cao nau nhanh nhay qua cho luoi.",
  "Hindi: नमस्ते दुनिया। तेज भूरी लोमड़ी आलसी कुत्ते के ऊपर कूदती है। Hindi: नमस्ते दुनिया। तेज भूरी लोमड़ी आलसी कुत्ते के ऊपर कूदती है।",
  "Arabic: مرحبا بالعالم. الثعلب البني السريع يقفز فوق الكلب الكسول. Arabic: مرحبا بالعالم. الثعلب البني السريع يقفز فوق الكلب الكسول.",
  "Hebrew: שלום עולם. השועל החום המהיר קופץ מעל הכלב העצלן. Hebrew: שלום עולם. השועל החום המהיר קופץ מעל הכלב העצלן.",
  "Greek: Γεια σου κόσμε. Η γρήγορη καφέ αλεπού πηδά πάνω από το τεμπέλικο σκυλί. Greek: Γεια σου κόσμε. Η γρήγορη καφέ αλεπού πηδά πάνω από το τεμπέλικο σκυλί.",
  "Cyrillic: Привет, мир. Быстрая коричневая лиса прыгает через ленивую собаку. Cyrillic: Привет, мир. Быстрая коричневая лиса прыгает через ленивую собаку.",
  "IPA sample: /həˈloʊ/ /ˈjuːnɪkoʊd/ /ˈɹɛndərɪŋ/ IPA sample: /həˈloʊ/ /ˈjuːnɪkoʊd/ /ˈɹɛndərɪŋ/",
  "Math symbols: ∑ ∏ ∫ √ ∞ ≈ ≠ ≤ ≥ ± × ÷ ∂ ∇ Math symbols: ∑ ∏ ∫ √ ∞ ≈ ≠ ≤ ≥ ± × ÷ ∂ ∇",
  "Arrows: ← ↑ → ↓ ↔ ↕ ⇐ ⇒ ⇑ ⇓ ⇄ ⇆ Arrows: ← ↑ → ↓ ↔ ↕ ⇐ ⇒ ⇑ ⇓ ⇄ ⇆",
  "Box drawing: ┌─┬─┐ │ │ │ ├─┼─┤ └─┴─┘ Box drawing: ┌─┬─┐ │ │ │ ├─┼─┤ └─┴─┘",
  "Braille: ⠁⠃⠉ ⠋⠕⠕ ⠃⠁⠗ Braille: ⠁⠃⠉ ⠋⠕⠕ ⠃⠁⠗",
  "Currency: $ € ¥ £ ₹ ₩ ₽ ₺ ₪ ₫ Currency: $ € ¥ £ ₹ ₩ ₽ ₺ ₪ ₫",
  "Punctuation: ¡Hola! ¿Que tal? «Bonjour» - dashes, quotes, ellipsis... Punctuation: ¡Hola! ¿Que tal? «Bonjour» - dashes, quotes, ellipsis...",
  "Dingbats: ✓ ✗ ✦ ✧ ❖ ❘ ❙ ❚ Dingbats: ✓ ✗ ✦ ✧ ❖ ❘ ❙ ❚",
  "Mixed: English 中文 日本語 한국어 العربية हिन्दी ∑ ↔ Mixed: English 中文 日本語 한국어 العربية हिन्दी ∑ ↔",
  "Emoji: 💕👇👍👌👆👰🏻👰🏻‍♂️👰🏻‍♀️🤬😶‍🌫️👩🏿🐅🧍‍♂️🆗😍🤣😊🐱🤣😅👀🦴👩👩🏻👩🏼👩🏽👩🏾👩🏿🏊🏿‍♀️👆🏿🤝🎈🎨🪡👑🥏🎸📁📂🗂️📝🗒️⌛📎⌛⏳🚀💦🆎❌⭕💯🆗🆒🔝🟥🟧🟨🟩 Emoji: 💕👇👍👌👆",
]

proc buildFontAtlasCommands*(frameArena: ptr Arena, fontAtlasImageId: UiImageId, contentSize: Vec2): ArrayView[UiRenderCommand] =
  prof("buildFontAtlasCommands")
  if frameArena == nil:
    return default(ArrayView[UiRenderCommand])
  var commands = frameArena[].allocEmptyArray(1, UiRenderCommand)
  commands.add UiRenderCommand(
    kind: CmdImage,
    imageId: fontAtlasImageId,
    pos: vec2(0.0'f32, 0.0'f32),
    uv1: vec2(1),
    size: contentSize,
    color: rgba(1.0, 1.0, 1.0, 1.0),
  )
  commands

proc buildUnicodeExamples*(b: var UiBuilder) =
  b.layoutVertical("unicode-root"):
    discard b.sizeToParentX().fitY().padding(8).gap(6)
    discard b.backgroundColor(rgba(0.10, 0.13, 0.18, 1.0))

    b.label("Unicode stress test (one label per line)"):
      discard b.textColor(rgba(0.82, 0.88, 0.96, 1.0))

    for i, lineText in unicodeStressLines:
      b.label($i & ": " & lineText):
        discard b.textColor(rgba(0.90, 0.92, 0.96, 1.0))

    b.label("Raw text pass (fillX nodes, no labels)"):
      discard b.textColor(rgba(0.82, 0.88, 0.96, 1.0))

    for i, lineText in unicodeStressLines:
      b.node:
        discard b.fillX().fitY().wrapText()
        discard b.text($i & ": " & lineText)
        discard b.textColor(rgba(0.90, 0.92, 0.96, 1.0))

proc buildFontAtlasExamples*(b: var UiBuilder) =
  b.node("font-atlas"):
    discard b.size(1024, 1024)
    discard b.padding(6)
    discard b.backgroundColor(rgba(0.12, 0.13, 0.18, 1.0))
    discard b.borderWidth(1)
    discard b.borderColor(rgba(0.32, 0.38, 0.48, 1.0))
    let atlasNode = b.currentNode
    let atlasContentSize = vec2(
      max(0.0'f32, atlasNode.size.x - b.currentNodeStyle().paddingX * 2.0'f32),
      max(0.0'f32, atlasNode.size.y - b.currentNodeStyle().paddingY * 2.0'f32),
    )
    discard b.customRenderCommands(buildFontAtlasCommands(b.frame.arena, b.fontAtlasImageId, atlasContentSize))

proc buildSubpixelExamples*(b: var UiBuilder) =
  b.layoutVertical("unicode-root"):
    discard b.sizeToParentX().fitY().padding(8).gap(6)
    discard b.backgroundColor(rgba(0.10, 0.13, 0.18, 1.0))

    var parentId = b.generateId()
    var labelId = b.generateId()
    let previousIndex = b.previousNodeIndex(labelId)
    var offset: float32 = 0
    var absolutePosition = vec2(0)
    var absoluteSize = vec2(0)
    if previousIndex != -1:
      offset = b.previousFrame.nodes[previousIndex].pos.x
      absolutePosition = b.absoluteNodePosPrev(parentId)
    discard b.slider("Offset", offset, 0.0'f32, 1.0'f32, 0.5)

    b.nodeWithId(parentId):
      discard b.fitX().fitY()
      b.nodeWithId(labelId):
        discard b.position(offset, 0)
        discard b.fitX().fitY()
        discard b.copyTextStyleIndex(UiStyleIndexLabel)
        discard b.text("Subpixel stress test")
        absoluteSize = b.currentNode.size + vec2(5, 5)

    b.node("font-atlas"):
      discard b.size(absoluteSize * 10)
      discard b.backgroundColor(rgba(0.12, 0.13, 0.18, 1.0))
      discard b.borderWidth(1)
      discard b.borderColor(rgba(0.32, 0.38, 0.48, 1.0))
      var commands = b.frame.arena[].allocEmptyArray(2, UiRenderCommand)
      commands.add UiRenderCommand(
        kind: CmdImage,
        imageId: 1.UiImageId,
        pos: vec2(0.0'f32, 0.0'f32),
        size: vec2(0, 0),
        color: rgba(1.0, 1.0, 1.0, 1.0),
      )
      commands.add UiRenderCommand(
        kind: CmdImage,
        imageId: 2.UiImageId,
        pos: vec2(0.0'f32, 0.0'f32),
        size: absoluteSize * 10,
        uv0: absolutePosition / b.previousFrame.nodes[0].size,
        uv1: (absolutePosition + absoluteSize) / b.previousFrame.nodes[0].size,
        samplerMode: Nearest,
        color: rgba(1.0, 1.0, 1.0, 1.0),
      )
      discard b.customRenderCommands(commands)

# ---------------------------------------------------------------------------
# Custom render commands (sine wave, circle, star) — drawn with customRenderCommands
# ---------------------------------------------------------------------------

proc buildCircleCommands*(frameArena: ptr Arena, contentSize: Vec2): ArrayView[UiRenderCommand] =
  prof("buildCircleCommands")
  if frameArena == nil:
    return default(ArrayView[UiRenderCommand])
  let w = max(1.0'f32, contentSize.x)
  let h = max(1.0'f32, contentSize.y)
  var commands = frameArena[].allocEmptyArray(256, UiRenderCommand)
  let center = vec2(w * 0.5'f32, h * 0.5'f32)
  let radius = max(2.0'f32, min(w, h) * 0.5'f32 - 6.0'f32)
  let color = rgba(0.40, 0.78, 0.92, 1.0)
  let segments = 64
  for i in 0 .. segments:
    let a0 = (i.float32 / segments.float32) * (PI.float32 * 2.0'f32)
    let a1 = ((i + 1).float32 / segments.float32) * (PI.float32 * 2.0'f32)
    let p0 = center + vec2(cos(a0.float64).float32, sin(a0.float64).float32) * radius
    let p1 = center + vec2(cos(a1.float64).float32, sin(a1.float64).float32) * radius
    commands.add UiRenderCommand(kind: CmdLine, pos: p0, pos2: p1, thickness: 2.0'f32, color: color)
  commands

proc buildStarCommands*(frameArena: ptr Arena, contentSize: Vec2): ArrayView[UiRenderCommand] =
  prof("buildStarCommands")
  if frameArena == nil:
    return default(ArrayView[UiRenderCommand])
  let w = max(1.0'f32, contentSize.x)
  let h = max(1.0'f32, contentSize.y)
  var commands = frameArena[].allocEmptyArray(256, UiRenderCommand)
  let center = vec2(w * 0.5'f32, h * 0.5'f32)
  let outer = max(2.0'f32, min(w, h) * 0.5'f32 - 6.0'f32)
  let inner = outer * 0.45'f32
  let points = 5
  let color = rgba(0.92, 0.46, 0.62, 1.0)
  var verts: array[10, Vec2] = default(array[10, Vec2])
  for i in 0 ..< 10:
    let r = if i mod 2 == 0: outer else: inner
    let a = -PI.float32 * 0.5'f32 + (i.float32 / 10.0'f32) * (PI.float32 * 2.0'f32)
    verts[i] = center + vec2(cos(a.float64).float32, sin(a.float64).float32) * r
  for i in 0 ..< 10:
    let p0 = verts[i]
    let p1 = verts[(i + 1) mod 10]
    commands.add UiRenderCommand(kind: CmdLine, pos: p0, pos2: p1, thickness: 2.0'f32, color: color)
  commands

var plotTime = 0.0
proc sineFn(x: float32, userData: int): float32 = sin(x.float64 + plotTime).float32
proc cosineFn(x: float32, userData: int): float32 = cos(x.float64 - plotTime).float32

proc buildPlotCommands*(b: var UiBuilder, origin: Vec2, size: Vec2): ArrayView[UiRenderCommand] =
  prof("buildPlotCommands")
  let xRange = vec2(0.0'f32, PI.float32 * 2.0'f32)
  let yRange = vec2(-1.2'f32, 1.2'f32)
  var series = [
    PlotSeries(
      fn: sineFn,
      lineColor: rgba(0.96, 0.72, 0.18, 1.0),
      fillTopColor: rgba(0.66, 0.52, 0.18, 0.5),
      fillBottomColor: rgba(0.66, 0.52, 0.18, 0.0),
    ),
    PlotSeries(
      fn: cosineFn,
      lineColor: rgba(0.40, 0.78, 0.92, 1.0),
      fillTopColor: rgba(0.30, 0.58, 0.72, 0.5),
      fillBottomColor: rgba(0.30, 0.58, 0.72, 0.0),
    ),
  ]
  return buildPlotVertices(
    b, origin, size, xRange, yRange, series,
    resolution = 256, lineThickness = 2.0'f32)

proc buildPlotDeferred(b: var UiBuilder, nodeIdx: int, userData: int) =
  let node = b.frame.nodes[nodeIdx].addr
  let style = b.nodeStyle(node)
  let contentOrigin = b.absoluteNodePos(nodeIdx) + vec2(style.paddingX, style.paddingY)
  let contentSize = vec2(
    max(0.0'f32, node.size.x - style.paddingX * 2.0'f32),
    max(0.0'f32, node.size.y - style.paddingY * 2.0'f32),
  )
  b.withParent(nodeIdx):
    discard b.customRenderCommands(buildPlotCommands(b, contentOrigin, contentSize))
  plotTime += b.frameCtx.animationTick.float64

proc buildCustomRenderExamples*(b: var UiBuilder) =
  b.layoutVertical("custom-render-root"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(rgba(0.12, 0.16, 0.22, 1.0))

    b.label("Custom render commands — sine wave, circle and star drawn with customRenderCommands"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))
    b.label("Each shape is a node whose content box is filled with CmdLine segments each frame."):
      discard b.fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))

    b.layoutHorizontal("cr-shapes"):
      discard b.fillX().fitY().gap(8)
      b.node("cr-circle"):
        discard b.size(200, 180).padding(6)
        discard b.backgroundColor(rgba(0.12, 0.13, 0.18, 1.0)).borderWidth(1).borderColor(rgba(0.32, 0.38, 0.48, 1.0))
        let n = b.currentNode
        let cs = vec2(
          max(0.0'f32, n.size.x - b.currentNodeStyle().paddingX * 2.0'f32),
          max(0.0'f32, n.size.y - b.currentNodeStyle().paddingY * 2.0'f32),
        )
        discard b.customRenderCommands(buildCircleCommands(b.frame.arena, cs))
      b.node("cr-star"):
        discard b.size(200, 180).padding(6)
        discard b.backgroundColor(rgba(0.12, 0.13, 0.18, 1.0)).borderWidth(1).borderColor(rgba(0.32, 0.38, 0.48, 1.0))
        let n = b.currentNode
        let cs = vec2(
          max(0.0'f32, n.size.x - b.currentNodeStyle().paddingX * 2.0'f32),
          max(0.0'f32, n.size.y - b.currentNodeStyle().paddingY * 2.0'f32),
        )
        discard b.customRenderCommands(buildStarCommands(b.frame.arena, cs))

    b.label("Two plots (sine + cosine) drawn on top of each other via nui_plot.nim (CmdRawVertices):"):
      discard b.fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))
    b.node("cr-plot"):
      discard b.size(520, 240).padding(8)
      discard b.backgroundColor(rgba(0.12, 0.13, 0.18, 1.0)).borderWidth(1).borderColor(rgba(0.32, 0.38, 0.48, 1.0))
      discard b.deferBuild(buildPlotDeferred)

# ---------------------------------------------------------------------------
# Custom material — a quad drawn with a registered Render2D material (custom shader).
# The material id is hardcoded to match the first material registered in game_impl.nim.
# ---------------------------------------------------------------------------

const customMaterialId: MaterialId = 1

proc buildCustomQuadCommands*(frameArena: ptr Arena, origin: Vec2, size: Vec2, time: float32, mouseX: float32, mouseY: float32): ArrayView[UiRenderCommand] =
  prof("buildCustomQuadCommands")
  if frameArena == nil:
    return default(ArrayView[UiRenderCommand])
  let x0 = origin.x
  let y0 = origin.y
  let x1 = origin.x + size.x
  let y1 = origin.y + size.y
  var vdata = cast[nil ptr UncheckedArray[UiVertex]](frameArena[].alloc(6 * sizeof(UiVertex)))
  vdata[0] = UiVertex(pos: vec2(x0, y0), uv: vec2(0.0'f32, 0.0'f32), color: rgba(1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32))
  vdata[1] = UiVertex(pos: vec2(x1, y0), uv: vec2(1.0'f32, 0.0'f32), color: rgba(1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32))
  vdata[2] = UiVertex(pos: vec2(x1, y1), uv: vec2(1.0'f32, 1.0'f32), color: rgba(1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32))
  vdata[3] = UiVertex(pos: vec2(x0, y0), uv: vec2(0.0'f32, 0.0'f32), color: rgba(1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32))
  vdata[4] = UiVertex(pos: vec2(x1, y1), uv: vec2(1.0'f32, 1.0'f32), color: rgba(1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32))
  vdata[5] = UiVertex(pos: vec2(x0, y1), uv: vec2(0.0'f32, 1.0'f32), color: rgba(1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32))

  # Fragment uniform buffer (matches `cbuffer Effect` in custom.frag.hlsl: float4 params).
  # x = time, yz = mouse position relative to the node (0..1, y flipped into uv space).
  var uniform = frameArena[].allocArray(16, uint8, alignof(float32))
  let u = cast[ptr UncheckedArray[float32]](uniform.toOpenArray(0, uniform.high).data)
  u[0] = time
  u[1] = mouseX
  u[2] = mouseY
  u[3] = 0.0'f32

  var commands = frameArena[].allocEmptyArray(1, UiRenderCommand)
  commands.add UiRenderCommand(
    kind: CmdRawVertices,
    vertexData: vdata,
    vertexCount: 6,
    materialId: customMaterialId,
    materialUniform: uniform)
  commands

proc buildCustomDeferred(b: var UiBuilder, nodeIdx: int, userData: int) =
  let node = b.frame.nodes[nodeIdx].addr
  let style = b.nodeStyle(node)
  let contentOrigin = b.absoluteNodePos(nodeIdx) + vec2(style.paddingX, style.paddingY)
  let contentSize = vec2(
    max(0.0'f32, node.size.x - style.paddingX * 2.0'f32),
    max(0.0'f32, node.size.y - style.paddingY * 2.0'f32),
  )
  let mouse = b.frameCtx.input.mouse
  let denomX = max(contentSize.x, 1.0'f32)
  let denomY = max(contentSize.y, 1.0'f32)
  let mouseX = clamp((mouse.x - contentOrigin.x) / denomX, 0.0'f32, 1.0'f32)
  let mouseY = clamp((mouse.y - contentOrigin.y) / denomY, 0.0'f32, 1.0'f32)
  b.withParent(nodeIdx):
    discard b.customRenderCommands(buildCustomQuadCommands(b.frame.arena, contentOrigin, contentSize, float32(b.frameCtx.time), mouseX, mouseY))

proc buildCustomMaterialExample*(b: var UiBuilder) =
  let parent = b.currentNode
  b.layoutVertical("custom-material-root"):
    if FitY in parent.flags:
      discard b.height(500)
    else:
      discard b.fillY()
    discard b.fillX().padding(8).gap(8)
    b.label("Custom material — a quad rendered with a registered Render2D material (custom fragment shader)."):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0))
    b.label("The quad is drawn via CmdRawVertices with materialId = " & $customMaterialId):
      discard b.fontSize(13).textColor(rgba(0.80, 0.86, 0.94, 1.0))
    b.node("custom-mat-node"):
      discard b.fill().padding(6)
      discard b.backgroundColor(rgba(0.12, 0.13, 0.18, 1.0)).borderWidth(1).borderColor(rgba(0.32, 0.38, 0.48, 1.0))
      discard b.deferBuild(buildCustomDeferred)

proc buildAllExamples(b: var UiBuilder)

var examples = [
  (fun: buildIntroPage, scrollBox: true, title: "Intro"),
  (fun: buildFillExamples, scrollBox: true, title: "Fill"),
  (fun: buildFitExamples, scrollBox: true, title: "Fit"),
  (fun: buildAnchorExamples, scrollBox: true, title: "Anchors"),
  (fun: buildLayoutDirectionExamples, scrollBox: true, title: "Layout"),
  (fun: buildAlignExamples, scrollBox: true, title: "Align"),
  (fun: buildGapPaddingExamples, scrollBox: true, title: "Gap/Padding"),
  (fun: buildStyleExamples, scrollBox: true, title: "Style"),
  (fun: buildTextStyleExamples, scrollBox: true, title: "Text"),
  (fun: buildMaskChildrenExamples, scrollBox: true, title: "Mask/Hover"),
  (fun: buildAnimationExamples, scrollBox: true, title: "Animation"),
  (fun: buildTransformExamples, scrollBox: true, title: "Transform"),
  (fun: buildLayoutExamples, scrollBox: true, title: "Layouts"),
  (fun: buildAllWidgetsExample, scrollBox: true, title: "Widgets"),
  (fun: buildComplexWidgetsExample, scrollBox: true, title: "Complex"),
  (fun: buildFlexLayoutExamples, scrollBox: true, title: "Flex"),
  (fun: buildGridLayoutExamples, scrollBox: true, title: "Grid"),
  (fun: buildTableLayoutExamples, scrollBox: true, title: "Table"),
  (fun: buildUnicodeExamples, scrollBox: true, title: "Unicode"),
  (fun: buildSubpixelExamples, scrollBox: true, title: "Subpixel"),
  (fun: buildFontAtlasExamples, scrollBox: true, title: "Atlas"),
  (fun: buildCustomRenderExamples, scrollBox: true, title: "Custom"),
  (fun: buildCustomMaterialExample, scrollBox: false, title: "CustomMat"),
  (fun: buildAllExamples, scrollBox: false, title: "All"),
]

proc buildDemoItem(b: var UiBuilder, itemIndex: int, userData: int) =
  if itemIndex >= examples.len:
    return
  discard b.fillX().fitY()
  examples[itemIndex].fun(b)

proc buildAllExamples(b: var UiBuilder) =
  b.layoutVertical("all-root"):
    discard b.fill()
    b.dynamicVirtualList(examples.len - 1, 500, buildDemoItem)

proc buildDemoUi*(b: var UiBuilder) =
  prof("buildDemoUi")
  b.layoutVertical:
    discard b.fill()

    b.menuBar:
      discard b.sizeToParentX().fitY()
      b.menuBarItem(demoMenuOpen):
        b.label("Demo")
      do:
        discard
      do:
        discard
      do:
        let itemNodeIndex = b.stack[^1]
        let itemPos = b.absoluteNodePosPrev(b.nodes[itemNodeIndex].id, itemNodeIndex)
        let itemSize = b.nodes[itemNodeIndex].size
        b.menu(demoMenuOpen, itemPos.x, itemPos.y + itemSize.y):
          b.menuItem:
            b.label("Font size")
          do:
            discard
          do:
            var f = b.defaultText.fontSize
            discard b.slider("Font Size", f, 2.0'f32, 100.0'f32, 11)
            b.defaultText.fontSize = f

          b.menuItem:
            var showThemeEditor = b.showThemeEditor
            if b.checkbox("Show theme editor", showThemeEditor):
              discard
            b.showThemeEditor = showThemeEditor

          b.menuItem:
            var showDebugPanel = b.showDebugPanel
            if b.checkbox("Show debug panel", showDebugPanel):
              discard
            b.showDebugPanel = showDebugPanel

    var demoNames: seq[string] = @[]
    for e in examples:
      demoNames.add e.title
    b.tabBar(demoNames, demoTabIndex):
      discard b.pushId(demoTabIndex.uint64)
      if demoTabIndex >= 0 and demoTabIndex < examples.len:
        if examples[demoTabIndex].scrollBox:
          b.scrollBox():
            discard b.sizeToParentX().fitY()
            examples[demoTabIndex].fun(b)
        else:
          examples[demoTabIndex].fun(b)
      discard b.popId()
