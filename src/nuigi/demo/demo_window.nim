## Main catalog of interactive nuigi feature demonstrations.
##
## Composes tabs and examples for sizing, layout, controls, scrolling,
## virtualized data, plots, trees, and platform-dependent filesystem browsing.
## Module-level variables intentionally preserve demo control values between
## immediate-mode frames; production widgets should prefer node storage.

include nuigi/util/compat2

import std/[math, assertions, random]
import nuigi/demo/[intro, big_example, faq_tree_table]
import nuigi, nuigi/widgets, nuigi/layout/flex, nuigi/widgets/[plot, tree_table]
import nuigi/widgets/dynamic_virtuallist
import nuigi/core/[vecmath, arena, array_view]
import nuigi/debug/profiler

when not defined(wasm):
  import std/os
  import nuigi/widgets/file_system_cursor

{.passL: "-Lbuild".}

when not defined(nimony):
  proc forceNim2ToIncludeUiBuilderInTheGeneratedCFile2*(): UiBuilder {.exportc.} = UiBuilder()

var demoTabIndex = 0
var demoMenuOpen = false

# ---------------------------------------------------------------------------
# Type 1 #1 — Fill
# ---------------------------------------------------------------------------

var fillDemoX = false
var fillDemoY = false
var fillDemoBoth = false

proc buildFillExamples*(b: var UiBuilder) =
  b.layoutVertical("fill-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("fillX / fillY / fill — claim space from the parent along one or both axes"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.layoutHorizontal("fill-controls"):
      discard b.fillX().fitY().gap(8)
      if b.checkbox("fillX", fillDemoX): discard
      if b.checkbox("fillY", fillDemoY): discard
      if b.checkbox("fill (both)", fillDemoBoth): discard

    b.node("fill-stage"):
      discard b.size(360, 150).padding(6)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)

      b.node("fill-child"):
        discard b.size(80, 36)
        if fillDemoBoth:
          discard b.fill()
        if fillDemoX:
          discard b.fillX()
        if fillDemoY:
          discard b.fillY()
        discard b.padding(6).fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
        discard b.text("child")

# ---------------------------------------------------------------------------
# Type 1 #2 — Fit
# ---------------------------------------------------------------------------

var stcDemoX = false
var stcDemoY = false

proc buildFitExamples*(b: var UiBuilder) =
  b.layoutVertical("stc-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("fitX / fitY / fit — size to text and children"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.layoutHorizontal("stc-controls"):
      discard b.fillX().fitY().gap(8)
      if b.checkbox("fitX", stcDemoX): discard
      if b.checkbox("fitY", stcDemoY): discard

    b.node("stc-stage"):
      discard b.size(360, 150).padding(6)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)

      b.node("stc-child"):
        discard b.size(200, 50)
        if stcDemoX:
          discard b.fitX()
        if stcDemoY:
          discard b.fitY()
        discard b.padding(6).fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HGreen, 1.0))
        discard b.text("sizes to content")

# ---------------------------------------------------------------------------
# Type 1 #3 — Anchors (moved here from demo.nim)
# ---------------------------------------------------------------------------

var anchorDemoMode = 0
var anchorDemoParentWidth = 320.0'f32
var anchorDemoParentHeight = 220.0'f32

proc buildAnchorExamples*(b: var UiBuilder) =
  b.layoutVertical("anchor-demos"):
    discard b.fillX().fitY().padding(6).gap(6)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("Anchors — position a child relative to its parent using normalized 0..1 coordinates"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.label("top-left and bottom-right are 0..1 fractions of the parent; offsets add pixels; pivot is the anchor point on the child"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor).fontSize(13)

    b.layoutHorizontal("anchor-controls"):
      const anchorModeLabels = ["Center", "TopLeft", "Bottom", "Right"]
      discard b.fillX().fitY().gap(4)
      if b.button("Mode: " & anchorModeLabels[anchorDemoMode]):
        anchorDemoMode = (anchorDemoMode + 1) mod anchorModeLabels.len
      b.withLast:
        discard b.alignCenter()
      var anchorSize = vec2(anchorDemoParentWidth, anchorDemoParentHeight)
      discard b.dragFloat2(anchorSize, 0, 0.0'f32, 420.0'f32, dfCustom, @["W", "H"])
      anchorDemoParentWidth = anchorSize.x
      anchorDemoParentHeight = anchorSize.y

    b.node("anchor-stage"):
      b.animate:
        discard b.sizeAnim(anchorDemoParentWidth, anchorDemoParentHeight)
      discard b.maxWidth(440).alignCenter()
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)

      template place(name: string, ax, ay, bx, by, off, px, py: float32, col: UiColor) =
        b.node(name):
          discard b.fit()
          discard b.anchors(ax, ay, bx, by).offsets(off, off, off, off).pivot(px, py).finishAnchors()
          discard b.padding(4).fillBackground().backgroundColor(col)
          discard b.text(name)

      place("TL", 0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32, 8.0'f32, 0.0'f32, 0.0'f32, accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HRed, 1.0))
      place("TR", 1.0'f32, 0.0'f32, 1.0'f32, 0.0'f32, 8.0'f32, 1.0'f32, 0.0'f32, accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
      place("BL", 0.0'f32, 1.0'f32, 0.0'f32, 1.0'f32, 8.0'f32, 0.0'f32, 1.0'f32, accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HTeal, 1.0))
      place("BR", 1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32, 8.0'f32, 1.0'f32, 1.0'f32, accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HOrange, 1.0))
      place("Center", 0.5'f32, 0.5'f32, 0.5'f32, 0.5'f32, 0.0'f32, 0.5'f32, 0.5, accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HGreen, 1.0))

      let (ax, ay, bx, by, px, py) = case anchorDemoMode
        of 0: (0.5'f32, 0.5'f32, 0.5'f32, 0.5'f32, 0.5'f32, 0.5'f32)
        of 1: (0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32)
        of 2: (0.5'f32, 1.0'f32, 0.5'f32, 1.0'f32, 0.5'f32, 1.0'f32)
        else: (1.0'f32, 0.5'f32, 1.0'f32, 0.5'f32, 1.0'f32, 0.5'f32)

      b.node("blend"):
        b.animate:
          discard b.anchorsAnim(ax, ay, bx, by).offsetsAnim(0, 0, 0, 0).pivotAnim(px, py)
          discard b.finishAnchors()
        discard b.fit().padding(4).fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HPurple, 1.0))
        discard b.text("blend child")

# ---------------------------------------------------------------------------
# Type 1 #4 — Layout direction
# ---------------------------------------------------------------------------

var layoutDirMode = 0

proc buildLayoutDirectionExamples*(b: var UiBuilder) =
  b.layoutVertical("layout-dir-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("layoutVertical / layoutHorizontal + DirectionReverse (column / column-reverse / row / row-reverse)"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.layoutHorizontal("layout-dir-controls"):
      discard b.fillX().fitY().gap(6)
      const dirLabels = ["Column", "Column reverse", "Row", "Row reverse"]
      if b.button("Direction: " & dirLabels[layoutDirMode]):
        layoutDirMode = (layoutDirMode + 1) mod dirLabels.len

    b.node("layout-dir-stage"):
      discard b.fit().padding(6).gap(6)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
      case layoutDirMode
      of 0: discard b.layout(LayoutVertical).forwardLayout()
      of 1: discard b.layout(LayoutVertical).reverseLayout()
      of 2: discard b.layout(LayoutHorizontal).forwardLayout()
      else: discard b.layout(LayoutHorizontal).reverseLayout()
      discard b.animateSize(DefaultAnimationSpeed * 0.3'f32).animateDelayed()

      for i in 0 .. 3:
        b.node:
          discard b.fit().padding(6).fillBackground()
          discard b.backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0 - i.float32 * 0.05'f32))
          discard b.text("item " & $i)
          discard b.animatePos(DefaultAnimationSpeed * 0.3'f32).animateDelayed()

# ---------------------------------------------------------------------------
# Type 1 #5 — Align
# ---------------------------------------------------------------------------

var alignDemoMode = 0

proc buildAlignExamples*(b: var UiBuilder) =
  b.layoutVertical("align-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("alignCenter and vertical alignment via anchors (anchorsY / pivotY)"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.layoutHorizontal("align-controls"):
      discard b.fillX().fitY().gap(6)
      const alignLabels = ["alignCenter", "Top", "Center", "Bottom"]
      if b.button("Mode: " & alignLabels[alignDemoMode]):
        alignDemoMode = (alignDemoMode + 1) mod alignLabels.len

    b.node("align-stage"):
      discard b.size(360, 150).padding(6)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)

      b.node("align-child"):
        discard b.fit().padding(6).fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HYellow, 1.0))
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
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("gap (spacing between children, needs a layout) and padding (inset around a node's content box)"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.layoutHorizontal("gap-pad-controls"):
      discard b.fillX().fitY().gap(8)
      var gapPad = vec2(gapDemoGap, gapDemoPadding)
      discard b.dragFloat2(gapPad, 0, 0.0'f32, 48.0'f32, dfCustom, @["G", "P"])
      gapDemoGap = gapPad.x
      gapDemoPadding = gapPad.y

    b.node("gap-pad-stage"):
      discard b.width(360).fitY().padding(gapDemoPadding).gap(gapDemoGap)
      discard b.layout(LayoutVertical).forwardLayout()
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)

      for i in 0 .. 3:
        b.node:
          discard b.fit().padding(6).fillBackground()
          discard b.backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0 - i.float32 * 0.05'f32))
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
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("backgroundColor, borderWidths (per side), cornerRadii (per corner), borderColors (per side)"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

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
      var borderTmp = vec4(styleDemoBorderWL, styleDemoBorderWT, styleDemoBorderWR, styleDemoBorderWB)
      discard b.dragFloat4(borderTmp, 4, 0.0'f32, 20.0'f32, dfNoLabel)
      styleDemoBorderWL = borderTmp.x
      styleDemoBorderWT = borderTmp.y
      styleDemoBorderWR = borderTmp.z
      styleDemoBorderWB = borderTmp.w

    b.layoutVertical("style-radii"):
      discard b.fillX().fitY().gap(4)
      b.label("cornerRadii (topLeft / topRight / bottomRight / bottomLeft)"): discard b.fontSize(13)
      b.layoutHorizontal:
        discard b.fillX().fitY().gap(8)
      var radiusTmp = vec4(styleDemoRadiusTL, styleDemoRadiusTR, styleDemoRadiusBR, styleDemoRadiusBL)
      discard b.dragFloat4(radiusTmp, 12, 0.0'f32, 60.0'f32, dfNoLabel)
      styleDemoRadiusTL = radiusTmp.x
      styleDemoRadiusTR = radiusTmp.y
      styleDemoRadiusBR = radiusTmp.z
      styleDemoRadiusBL = radiusTmp.w

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
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeaderText)[].textColor)

    b.node("border-style-gallery"):
      discard b.fillX().fitY().gap(12)
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexWrap(FlexWrap).flexGaps(12, 12)

      b.layoutVertical("asymmetric-corners"):
        discard b.size(260, 150).padding(14).gap(8)
        discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
        discard b.cornerRadii(30, 4, 24, 0)
        discard b.borderWidth(3)
        discard b.borderColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HTeal, 1.0))
        discard b.animatePos().animateDelayed()
        b.labelWrapped("Asymmetric corners"):
          discard b.fillX()
          discard b.fontSize(16).textColor(b.themeTextStyle(UiStyleIndexDefaultText)[].textColor)
        b.labelWrapped("TL 30  TR 4  BR 24  BL 0"):
          discard b.fillX()
          discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

      b.layoutVertical("asymmetric-widths"):
        discard b.size(260, 150).padding(14).gap(8)
        discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
        discard b.cornerRadius(12)
        discard b.borderWidths(2, 8, 14, 4)
        discard b.borderColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HPurple, 1.0))
        discard b.animatePos().animateDelayed()
        b.labelWrapped("Per-side widths"):
          discard b.fillX()
          discard b.fontSize(16).textColor(b.themeTextStyle(UiStyleIndexDefaultText)[].textColor)
        b.labelWrapped("Left 2  Top 8  Right 14  Bottom 4"):
          discard b.fillX()
          discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

      b.layoutVertical("combined-border-style"):
        discard b.size(260, 150).padding(14).gap(8)
        discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
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
          discard b.fontSize(16).textColor(b.themeTextStyle(UiStyleIndexDefaultText)[].textColor)
        b.labelWrapped("Four side colors, two widths, four radii"):
          discard b.fillX()
          discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

      b.layoutVertical("all"):
        discard b.size(260, 150).padding(14).gap(8)
        discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
        discard b.cornerRadii(30, 4, 60, 0)
        discard b.borderWidths(2, 8, 15, 1)
        discard b.animatePos().animateDelayed()
        discard b.borderColors(
          rgba(0.96, 0.34, 0.40, 1.0),
          rgba(0.98, 0.78, 0.24, 1.0),
          rgba(0.30, 0.72, 0.98, 1.0),
          rgba(0.40, 0.88, 0.54, 1.0))
        b.label("Asymmetric all"):
          discard b.fontSize(16).textColor(b.themeTextStyle(UiStyleIndexDefaultText)[].textColor)
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
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("text, fontSize, textColor, wrapText"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

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
        b.layoutHorizontal:
          discard b.fitX().fitY().gap(2)
          b.label("fontSize")
          discard b.dragFloat(textDemoSize, 18, 8.0'f32, 64.0'f32)

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
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
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
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("maskChildren (clip overflow), noHover, noChildHover"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.layoutHorizontal("mask-controls"):
      discard b.fillX().fitY().gap(8)
      if b.checkbox("maskChildren", maskDemoMask): discard
      if b.checkbox("noHover", maskDemoNoHover): discard
      if b.checkbox("noChildHover", maskDemoNoChildHover): discard

    b.node("mask-stage"):
      discard b.size(320, 170).padding(8)
      let h = b.wasHovered()
      discard b.backgroundColor(if h: accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HRed, 1.0) else: accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HRed, 0.9'f32))
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
        discard b.backgroundColor(if h: accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HGreen, 1.0) else: accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
        discard b.text("hover me")

# ---------------------------------------------------------------------------
# Type 1 #10 — Animation (immediate + delayed)
# ---------------------------------------------------------------------------

var animDemoExpanded = false
var animDemoShow = false

proc buildAnimationExamples*(b: var UiBuilder) =
  b.layoutVertical("anim-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("animate (immediate, triggered on hover/click): sizeAnim, backgroundColorAnim, transformScaleAnim, positionAnim, widthAnim, heightAnim"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)
    b.label("animateDelayed: transformScaleAnim only when the node appears"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor).fontSize(13)

    b.layoutHorizontal("anim-controls"):
      discard b.fillX().fitY().gap(8)
      if b.button("Toggle expand"):
        animDemoExpanded = not animDemoExpanded
      if b.button("Toggle show"):
        animDemoShow = not animDemoShow
      var animationSpeed = b.animationSpeed
      b.layoutHorizontal:
        discard b.fitX().fitY().gap(2)
        b.label("Animation speed")
        discard b.dragFloat(animationSpeed, 1.0'f32, 0.0'f32, 4.0'f32)
      b.animationSpeed = animationSpeed

    b.layoutHorizontal:
      discard b.fillX().fitY().gap(8)
      b.node("anim-hover-transform"):
        discard b.size(140, 90).padding(8).fillBackground().cornerRadius(8)
        if b.wasHovered():
          discard b.backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HGreen, 1.0))
        else:
          discard b.backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
        let h = b.wasHovered()
        b.animate:
          discard b.backgroundColorAnim(if h: accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HGreen, 1.0) else: accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
          discard b.transformScaleAnim(if h: 1.5'f32 else: 1.0'f32)
        discard b.alignCenter()
        discard b.text("animate transform")

      b.node("anim-hover-size"):
        discard b.size(140, 90).padding(8).fillBackground().cornerRadius(8)
        if b.wasHovered():
          discard b.backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HGreen, 1.0))
        else:
          discard b.backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
        let h = b.wasHovered()
        b.animate:
          discard b.sizeAnim(if h: 200.0'f32 else: 140.0'f32, if h: 130.0'f32 else: 90.0'f32)
          discard b.backgroundColorAnim(if h: accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HGreen, 1.0) else: accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
        discard b.alignCenter()
        discard b.text("animate size")

    b.node("anim-click"):
      discard b.size(360, 130).padding(8).fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor).cornerRadius(8)
      discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
      b.node("anim-click-box"):
        discard b.alignCenter().padding(6).fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HYellow, 1.0)).cornerRadius(6)
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
        discard b.backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HPurple, 1.0))
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
  b.anythingAnimating = true
  b.layoutVertical("transform-demos"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("transformOffset, transformRotation, transformScale, transformPivot — render-space transform around a pivot"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)
    b.label("pivot is a 0..1 fraction of the node box; offset is in pixels; rotation in radians; scale is multiplicative"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor).fontSize(13)

    b.node("transform-controls"):
      discard b.fillX().fitY().flexLayout().flexFlow(FlexDirectionRow, FlexWrap).flexGaps(8, 8)
      var transformPos = vec2(transformDemoX, transformDemoY)
      discard b.dragFloat2(transformPos, 0, -60.0'f32, 60.0'f32, dfXYZW)
      transformDemoX = transformPos.x
      transformDemoY = transformPos.y
      b.layoutHorizontal:
        discard b.fitX().fitY().gap(2)
        b.label("rotation")
        discard b.dragFloat(transformDemoRot, 0, -3.14159'f32, 3.14159'f32)
      b.layoutHorizontal:
        discard b.fitX().fitY().gap(2)
        b.label("scale")
        discard b.dragFloat(transformDemoScale, 1, 0.25'f32, 2.5'f32)
      var transformPivot = vec2(transformDemoPivotX, transformDemoPivotY)
      discard b.dragFloat2(transformPivot, 0.5, 0.0'f32, 1.0'f32, dfXYZW)
      transformDemoPivotX = transformPivot.x
      transformDemoPivotY = transformPivot.y
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
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)

      b.node("transform-child"):
        discard b.fit().padding(10).alignCenter().fillBackground()
        if b.wasHovered():
          discard b.backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
        else:
          discard b.backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
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
          discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
          discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
          b.node("cp-child"):
            discard b.fit().padding(6).alignCenter().fillBackground().backgroundColor(col).cornerRadius(4)
            let spin = b.frameCtx.input.frameIndex.float32 * 0.03'f32 * b.animationSpeed
            discard b.transformPivot(px, py)
            discard b.transformRotation(spin)
            discard b.text("pivot")

      cornerPivot("cp-tl", 0.0'f32, 0.0'f32, accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HRed, 1.0))
      cornerPivot("cp-tr", 1.0'f32, 0.0'f32, accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
      cornerPivot("cp-bl", 0.0'f32, 1.0'f32, accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HTeal, 1.0))
      cornerPivot("cp-br", 1.0'f32, 1.0'f32, accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HOrange, 1.0))

# ---------------------------------------------------------------------------
# Type 3 — every simple widget (vertical list)
# ---------------------------------------------------------------------------

var awClicked = 0
var awChecked = false
var awSlider = 0.5'f32
var awDrag = 0.5'f32
var awDragFree = 2.0'f32
var awVec2 = vec2(0.5'f32, 0.5'f32)
var awVec3 = vec3(0.5'f32, 0.5'f32, 0.5'f32)
var awVec4 = vec4(0.5'f32, 0.5'f32, 0.5'f32, 1.0'f32)
var awColor = rgba(0.40, 0.66, 0.92, 1.0)
var awDropdown = 0
var awDropdownOptions = ["Apple", "Banana", "Cherry", "Date"]
var awText = ""
var awMenuOpen = false

proc buildAllWidgetsExample*(b: var UiBuilder) =
  b.layoutVertical("all-widgets"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("Builtin widgets"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.tableLayout([tableColumnFit(), tableColumnFill()], 8.0, 4.0):
      discard b.fillX().fitY().padding(6)
      discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

      template headerCell(cap: string) =
        b.node:
          discard b.fitY().padding(4).fillBackground().backgroundColor(b.themeStyle(UiStyleIndexHeader)[].fillColor)
          discard b.text(cap).fit()
          discard b.textColor(b.themeTextStyle(UiStyleIndexHeaderText)[].textColor)
      template labelCell(cap: string) =
        b.node:
          discard b.fitY().padding(4).fillBackground()
          discard b.text(cap).fit()
          discard b.textColor(b.themeTextStyle(UiStyleIndexLabelText)[].textColor)
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
        discard b.slider(awSlider, 0.0'f32, 1.0'f32, 0.5'f32)
      labelCell("dragFloat")
      widgetCell:
        discard b.dragFloat(awDrag, 0.5'f32, 0.0'f32, 1.0'f32)
      labelCell("dragFloat (free)")
      widgetCell:
        discard b.dragFloat(awDragFree, 2.0'f32)
      labelCell("dragFloat2")
      widgetCell:
        discard b.dragFloat2(awVec2, 0.5'f32, 0.0'f32, 1.0'f32, dfXYZW)
      labelCell("dragFloat3")
      widgetCell:
        discard b.dragFloat3(awVec3, 0.5'f32, 0.0'f32, 1.0'f32, dfXYZW)
      labelCell("dragFloat4")
      widgetCell:
        discard b.dragFloat4(awVec4, 0.5'f32, 0.0'f32, 1.0'f32, dfRGBA)
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
              discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor).borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
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
  discard b.fillBackground().backgroundColor(if itemIndex mod 2 == 0: b.themeStyle(UiStyleIndexRow)[].fillColor else: b.themeStyle(UiStyleIndexRowAlt)[].fillColor)
  discard b.text("Item " & $itemIndex).fit()
  discard b.textColor(b.themeTextStyle(UiStyleIndexLabelText)[].textColor)

proc cvDynItem(b: var UiBuilder, itemIndex: int, userData: int) =
  discard b.fillX().fitY().padding(6).layout(LayoutVertical)
  discard b.fillBackground().backgroundColor(if itemIndex mod 2 == 0: b.themeStyle(UiStyleIndexRow)[].fillColor else: b.themeStyle(UiStyleIndexRowAlt)[].fillColor)
  b.label("Dynamic item " & $itemIndex):
    discard b.textColor(b.themeTextStyle(UiStyleIndexLabelText)[].textColor)
  if itemIndex mod 3 == 0:
    b.labelWrapped("This row is taller: wrapped text that spans multiple lines to show variable-height measurement in the dynamic virtual list."):
      discard b.fillX().fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

proc buildComplexWidgetsExample*(b: var UiBuilder) =
  b.layoutVertical("complex-widgets"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("Complex widgets: virtualList (fixed-height rows) and dynamicVirtualList (variable-height rows)"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    var count = cvItemCount.float32
    b.layoutHorizontal:
      discard b.fitX().fitY().gap(2)
      b.label("Virtual list item count")
      discard b.dragFloat(count, 200, 1.0'f32, 1_000_000.0'f32)
    cvItemCount = count.int

    b.tableLayout([tableColumnProportional(1), tableColumnProportional(2)], 8.0, 4.0):
      discard b.fillX().fitY().padding(6)
      discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

      template headerCell(cap: string) =
        b.node:
          discard b.fitY().padding(4).fillBackground().backgroundColor(b.themeStyle(UiStyleIndexHeader)[].fillColor)
          discard b.text(cap).fit()
          discard b.textColor(b.themeTextStyle(UiStyleIndexHeaderText)[].textColor)

      template nameCell(name, desc: string) =
        b.layoutVertical:
          discard b.fitY().padding(4).gap(2).fillBackground()
          b.label(name):
            discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)
          b.labelWrapped(desc):
            discard b.fillX().fontSize(12).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

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
                discard b.backgroundColor(if i mod 2 == 0: b.themeStyle(UiStyleIndexRow)[].fillColor else: b.themeStyle(UiStyleIndexRowAlt)[].fillColor)
                discard b.text("Scrollable row " & $i).fit()
                discard b.textColor(b.themeTextStyle(UiStyleIndexLabelText)[].textColor)

      nameCell("virtualList", "Fixed row height; only renders visible rows. Very fast for huge lists, but every row must be the same height.")
      b.node:
        discard b.fillX().height(220).padding(4)
        b.virtualList(cvScroll, cvItemCount, 28.0'f32, cvFixedItem)

      nameCell("dynamicVirtualList", "Variable row heights; only renders visible rows. Very fast for huge lists, and handles mixed item height, caches rendered item heights for the scroll bar.")
      b.node:
        discard b.fillX().height(220).padding(4)
        discard b.dynamicVirtualList(cvItemCount, 40.0'f32, cvDynItem)

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
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("Combined common layouts — Top bar, Sidebar, Card grid, Settings panel, Toolbar, Form"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    # 1. Top bar -----------------------------------------------------------
    b.label("Top bar — fixed blocks on the left/right, fills the middle"):
      discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    b.node("topbar"):
      discard b.fillX().fitY().padding(6).gap(6)
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexGaps(6, 6)
      discard b.backgroundColor(b.themeStyle(UiStyleIndexCard)[].fillColor).cornerRadius(4)
      b.node:
        discard b.fit().padding(6).fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HRed, 1.0))
        discard b.text("Logo")
      b.node:
        discard b.fit().padding(6).fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0))
        discard b.text("File")
      b.node:
        discard b.fitY().flex(1, 1)
      b.node:
        discard b.fit().padding(6).fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HTeal, 1.0))
        discard b.text("Search")
      b.node:
        discard b.fit().padding(6).fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HOrange, 1.0))
        discard b.text("Profile")

    # 2. Sidebar -----------------------------------------------------------
    b.label("Sidebar — fixed-width sidebar next to a filling content area"):
      discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    b.node("sidebar"):
      discard b.fillX().height(150).padding(6).gap(6)
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexGaps(6, 6)
      discard b.backgroundColor(b.themeStyle(UiStyleIndexCard)[].fillColor).cornerRadius(4)
      b.node:
        discard b.size(90, 0).fitY().padding(6).gap(4)
        discard b.layout(LayoutVertical).forwardLayout()
        discard b.flex(0.0, 0.0, 90.0)
        discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)
        b.label("Home"): discard b.textColor(b.themeTextStyle(UiStyleIndexLabelText)[].textColor)
        b.label("Projects"): discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
        b.label("Settings"): discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
      b.node:
        discard b.fillX().fitY().padding(8).gap(6)
        discard b.layout(LayoutVertical).forwardLayout()
        discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
        b.label("Content area"): discard b.textColor(b.themeTextStyle(UiStyleIndexLabelText)[].textColor)
        b.labelWrapped("This region grows to fill the remaining width while the sidebar keeps a fixed size."):
          discard b.fillX().fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    # 3. Card grid ---------------------------------------------------------
    b.label("Card grid — cards laid out from a loop in a wrapping flex"):
      discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    b.node("card-grid"):
      discard b.fillX().fitY().padding(8).gap(8)
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexWrap(FlexWrap).flexGaps(8, 8)
      discard b.backgroundColor(b.themeStyle(UiStyleIndexCard)[].fillColor).cornerRadius(4)
      for i in 0 .. 7:
        b.node:
          discard b.size(96, 64).padding(6).gap(4)
          discard b.layout(LayoutVertical).forwardLayout()
          discard b.flex(0.0, 1.0, 96.0)
          discard b.fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HTeal, 0.9'f32 - i.float32 * 0.04'f32)).cornerRadius(4)
          b.label("Card " & $i): discard b.textColor(b.themeTextStyle(UiStyleIndexDefaultText)[].textColor)
          b.labelWrapped("item description"):
            discard b.fontSize(11).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    # 4. Settings panel ---------------------------------------------------
    b.label("Settings panel — label + control rows"):
      discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    b.node("settings-panel"):
      discard b.fillX().fitY().padding(8)
      discard b.backgroundColor(b.themeStyle(UiStyleIndexCard)[].fillColor).cornerRadius(4)
      b.tableLayout([tableColumnFit(), tableColumnFill()], 8.0, 4.0):
        discard b.fillX().fitY()
        template settingRow(rowLabel: string, body: untyped) =
          b.node:
            discard b.fitY().padding(4).fillBackground()
            discard b.text(rowLabel).fit()
            discard b.textColor(b.themeTextStyle(UiStyleIndexLabelText)[].textColor)
          b.node:
            discard b.fillX().fitY().padding(4)
            body
        settingRow("Music"):
          if b.checkbox("", layoutDemoMusic): discard
        settingRow("Volume"):
          discard b.dragFloat(layoutDemoVolume, 0.7'f32, 0.0'f32, 1.0'f32)
        settingRow("VSync"):
          if b.checkbox("", layoutDemoVsync): discard
        settingRow("Fullscreen"):
          if b.checkbox("", layoutDemoFullscreen): discard

    # 5. Toolbar -----------------------------------------------------------
    b.label("Toolbar — wrapping row of buttons"):
      discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    b.node("toolbar"):
      discard b.fillX().fitY().padding(6).gap(6)
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexWrap(FlexWrap).flexGaps(6, 6)
      discard b.backgroundColor(b.themeStyle(UiStyleIndexCard)[].fillColor).cornerRadius(4)
      for name in ["New", "Open", "Save", "Cut", "Copy", "Paste", "Undo", "Redo", "Find", "Run"]:
        if b.button(name): discard

    # 6. Form --------------------------------------------------------------
    b.label("Form — text field, checkbox and button stacked"):
      discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    b.node("form"):
      discard b.fillX().fitY().padding(8).gap(8)
      discard b.layout(LayoutVertical).forwardLayout()
      discard b.backgroundColor(b.themeStyle(UiStyleIndexCard)[].fillColor).cornerRadius(4)
      b.label("Name"): discard b.textColor(b.themeTextStyle(UiStyleIndexLabelText)[].textColor)
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
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("Unicode stress test (one label per line)"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    for i, lineText in unicodeStressLines:
      b.label($i & ": " & lineText):
        discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.label("Raw text pass (fillX nodes, no labels)"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    for i, lineText in unicodeStressLines:
      b.node:
        discard b.fillX().fitY().wrapText()
        discard b.text($i & ": " & lineText)
        discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

proc buildFontAtlasExamples*(b: var UiBuilder) =
  b.node("font-atlas"):
    discard b.size(1024, 1024)
    discard b.padding(6)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)
    discard b.borderWidth(1)
    discard b.borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
    let atlasNode = b.currentNode
    let atlasContentSize = vec2(
      max(0.0'f32, atlasNode.size.x - b.currentNodeStyle().paddingX * 2.0'f32),
      max(0.0'f32, atlasNode.size.y - b.currentNodeStyle().paddingY * 2.0'f32),
    )
    discard b.customRenderCommands(buildFontAtlasCommands(b.frame.arena, b.fontAtlasImageId, atlasContentSize))

proc buildSubpixelExamples*(b: var UiBuilder) =
  b.layoutVertical("unicode-root"):
    discard b.sizeToParentX().fitY().padding(8).gap(6)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    var parentId = b.generateId()
    var labelId = b.generateId()
    let previousIndex = b.previousNodeIndex(labelId)
    var offset: float32 = 0
    var absolutePosition = vec2(0)
    var absoluteSize = vec2(0)
    if previousIndex != -1:
      offset = b.previousFrame.nodes[previousIndex].pos.x
      absolutePosition = b.absoluteNodePosPrev(parentId)
    b.layoutHorizontal:
      discard b.fitX().fitY().gap(2)
      b.label("Offset")
      discard b.dragFloat(offset, 0.5, 0.0'f32, 1.0'f32)

    b.nodeWithId(parentId):
      discard b.fitX().fitY()
      b.nodeWithId(labelId):
        discard b.position(offset, 0)
        discard b.fitX().fitY()
        discard b.copyTextStyleIndex(UiStyleIndexLabelText)
        discard b.text("Subpixel stress test")
        absoluteSize = b.currentNode.size + vec2(5, 5)

    b.node("font-atlas"):
      discard b.size(absoluteSize * 10)
      discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)
      discard b.borderWidth(1)
      discard b.borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
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
  b.anythingAnimating = true
  b.layoutVertical("custom-render-root"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("Custom render commands — sine wave, circle and star drawn with customRenderCommands"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)
    b.label("Each shape is a node whose content box is filled with CmdLine segments each frame."):
      discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("cr-shapes"):
      discard b.fillX().fitY().gap(8)
      b.node("cr-circle"):
        discard b.size(200, 180).padding(6)
        discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor).borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
        let n = b.currentNode
        let cs = vec2(
          max(0.0'f32, n.size.x - b.currentNodeStyle().paddingX * 2.0'f32),
          max(0.0'f32, n.size.y - b.currentNodeStyle().paddingY * 2.0'f32),
        )
        discard b.customRenderCommands(buildCircleCommands(b.frame.arena, cs))
      b.node("cr-star"):
        discard b.size(200, 180).padding(6)
        discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor).borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
        let n = b.currentNode
        let cs = vec2(
          max(0.0'f32, n.size.x - b.currentNodeStyle().paddingX * 2.0'f32),
          max(0.0'f32, n.size.y - b.currentNodeStyle().paddingY * 2.0'f32),
        )
        discard b.customRenderCommands(buildStarCommands(b.frame.arena, cs))

    b.label("Two plots (sine + cosine) drawn on top of each other via plot.nim (CmdRawVertices):"):
      discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    b.node("cr-plot"):
      discard b.size(520, 240).padding(8)
      discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor).borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
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
  b.anythingAnimating = true
  let parent = b.currentNode
  b.layoutVertical("custom-material-root"):
    if FitY in parent.flags:
      discard b.height(500)
    else:
      discard b.fillY()
    discard b.fillX().padding(8).gap(8)
    b.label("Custom material — a quad rendered with a registered Render2D material (custom fragment shader)."):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)
    b.label("The quad is drawn via CmdRawVertices with materialId = " & $customMaterialId):
      discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    b.node("custom-mat-node"):
      discard b.fill().padding(6)
      discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor).borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)
      discard b.deferBuild(buildCustomDeferred)

type
  DemoTreeNode = ref object
    key: string
    name: string
    parent: DemoTreeNode
    children: seq[DemoTreeNode]

  DemoTreeCursor = ref object of TreeCursor
    node: DemoTreeNode
    parents: seq[DemoTreeNode]

  DemoTreeDragUserData = ref object of UiDragUserData
    node: DemoTreeNode

var demoTreeRoot: DemoTreeNode

proc addDemoTreeChild(parent: DemoTreeNode, key, name: string): DemoTreeNode =
  result = DemoTreeNode(key: key, name: name, parent: parent)
  parent.children.add(result)

proc createDemoTree(): DemoTreeNode =
  result = DemoTreeNode(key: "demo-root", name: "Root")
  for groupIndex in 0 ..< 10:
    let group = result.addDemoTreeChild(
      "group-" & $groupIndex, "Group " & $(groupIndex + 1))
    for itemIndex in 0 ..< (10 * groupIndex):
      let item = group.addDemoTreeChild(
        group.key & "-item-" & $itemIndex, "Item " & $(itemIndex + 1))
      for valueIndex in 0 ..< (10 * itemIndex):
        discard item.addDemoTreeChild(
          item.key & "-value-" & $valueIndex, "Value " & $(valueIndex + 1))

proc resetDemoTree() =
  demoTreeRoot = createDemoTree()

proc demoTreeCursor(root: DemoTreeNode): DemoTreeCursor =
  DemoTreeCursor(node: root, fieldName: root.name, path: @[])

method clone*(c: DemoTreeCursor): TreeCursor =
  let copy = DemoTreeCursor(node: c.node, fieldName: c.fieldName, index: c.index)
  for parent in c.parents:
    copy.parents.add(parent)
  for pathIndex in c.path:
    copy.path.add(pathIndex)
  return copy

method cursorKey*(c: DemoTreeCursor): string =
  c.node.key

method childCount*(c: DemoTreeCursor): int =
  c.node.children.len

method enterChild*(c: DemoTreeCursor): bool =
  if c.node.children.len == 0:
    return false
  c.parents.add(c.node)
  c.node = c.node.children[0]
  c.path.add(0)
  c.index = 0
  c.fieldName = c.node.name
  return true

method moveNext*(c: DemoTreeCursor, count: int = 1): bool =
  if c.parents.len == 0:
    return false
  let siblings = c.parents[^1].children
  if c.index + count < siblings.len:
    c.index += count
    c.path[c.path.high] = c.index
    c.node = siblings[c.index]
    c.fieldName = c.node.name
    return true
  return false

method movePrev*(c: DemoTreeCursor, count: int = 1): bool =
  if c.parents.len == 0:
    return false
  if count <= 0:
    return true
  if c.index >= count:
    c.index -= count
    c.path[c.path.high] = c.index
    c.node = c.parents[^1].children[c.index]
    c.fieldName = c.node.name
    return true
  return false

method exitChild*(c: DemoTreeCursor): bool =
  if c.parents.len == 0:
    return false
  c.node = c.parents[^1]
  c.parents.setLen(c.parents.len - 1)
  c.path.setLen(c.path.len - 1)
  c.index = if c.path.len > 0: c.path[^1] else: 0
  c.fieldName = c.node.name
  return true

method resolveChild*(c: DemoTreeCursor, child: TreeCursor): TreeCursor =
  let expected = DemoTreeCursor(child)
  var childIndex = expected.index
  if childIndex < 0 or childIndex >= c.node.children.len or
      c.node.children[childIndex].key != expected.node.key:
    childIndex = -1
    for index, candidate in c.node.children:
      if candidate.key == expected.node.key:
        childIndex = index
        break
  if childIndex < 0:
    return nil
  let resolved = DemoTreeCursor(c.clone())
  resolved.parents.add(c.node)
  resolved.node = c.node.children[childIndex]
  resolved.index = childIndex
  resolved.path.add(childIndex)
  resolved.fieldName = resolved.node.name
  return resolved

proc canMoveDemoTreeNodeBeside(source, target: DemoTreeNode): bool =
  if source == nil or target == nil or source == target or
      source.parent == nil or target.parent == nil:
    return false
  var destinationAncestor = target.parent
  while destinationAncestor != nil:
    if destinationAncestor == source:
      return false
    destinationAncestor = destinationAncestor.parent
  return true

proc moveDemoTreeNodeBeside(source, target: DemoTreeNode, insertAfter: bool) =
  if not source.canMoveDemoTreeNodeBeside(target):
    return
  let sourceParent = source.parent
  let targetParent = target.parent
  var sourceIndex = -1
  var targetIndex = -1
  for index, child in sourceParent.children:
    if child == source:
      sourceIndex = index
      break
  for index, child in targetParent.children:
    if child == target:
      targetIndex = index
  if sourceIndex < 0 or targetIndex < 0:
    return
  sourceParent.children.delete(sourceIndex)
  if sourceParent == targetParent and sourceIndex < targetIndex:
    dec targetIndex
  if insertAfter:
    inc targetIndex
  source.parent = targetParent
  targetParent.children.insert(source, targetIndex)

proc canReparentDemoTreeNode(source, target: DemoTreeNode): bool =
  if source == nil or target == nil or source == target or
      source.parent == nil or source.parent == target:
    return false
  var ancestor = target
  while ancestor != nil:
    if ancestor == source:
      return false
    ancestor = ancestor.parent
  return true

proc reparentDemoTreeNode(source, target: DemoTreeNode) =
  if not source.canReparentDemoTreeNode(target):
    return
  var sourceIndex = -1
  for index, child in source.parent.children:
    if child == source:
      sourceIndex = index
      break
  if sourceIndex < 0:
    return
  source.parent.children.delete(sourceIndex)
  source.parent = target
  target.children.add(source)

proc buildDemoTreeDragTooltip(
    b: var UiBuilder, userData: UiDragUserData, canDrop: bool) {.nimcall.} =
  if userData == nil or not (userData of DemoTreeDragUserData):
    return
  let dragData = DemoTreeDragUserData(userData)
  discard b.fit().padding(6).gap(4)
  discard b.fillBackground().styleIndex(UiStyleIndexTooltip)
  discard b.text(dragData.node.name &
    (if canDrop: " - release to move" else: " - cannot move here")).fit()

proc buildDemoTreeDropGradient(b: var UiBuilder, nodeIdx: int, userData: int) =
  if b.frame.arena == nil or nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return
  let node = b.frame.nodes[nodeIdx].addr
  if node.size.x <= 0.0'f32 or node.size.y <= 0.0'f32:
    return
  let origin = b.absoluteNodePos(nodeIdx)
  let farCorner = origin + node.size
  let accent = b.themeStyle(UiStyleIndexAccent)[].fillColor
  let transparent = rgba(accent.r, accent.g, accent.b, 0.0'f32)
  let topColor = if userData == 0: accent else: transparent
  let bottomColor = if userData == 0: transparent else: accent
  let vertices = cast[nil ptr UncheckedArray[UiVertex]](
    b.frame.arena[].alloc(6 * sizeof(UiVertex)))
  if vertices == nil:
    return
  vertices[0] = UiVertex(pos: origin, color: topColor)
  vertices[1] = UiVertex(pos: vec2(farCorner.x, origin.y), color: topColor)
  vertices[2] = UiVertex(pos: farCorner, color: bottomColor)
  vertices[3] = UiVertex(pos: origin, color: topColor)
  vertices[4] = UiVertex(pos: farCorner, color: bottomColor)
  vertices[5] = UiVertex(pos: vec2(origin.x, farCorner.y), color: bottomColor)
  var commands = b.frame.arena[].allocEmptyArray(1, UiRenderCommand)
  commands.add UiRenderCommand(
    kind: CmdRawVertices,
    vertexData: vertices,
    vertexCount: 6,
  )
  b.withParent(nodeIdx):
    discard b.customRenderCommands(commands)

when not defined(wasm):
  proc demoFileSystemRoot(): string {.raises: [].} =
    try:
      return getCurrentDir() / "fs-demo"
    except:
      return "." / "fs-demo"

  var fsCursor = fileSystemCursor(demoFileSystemRoot())
  type
    FileDragUserData = ref object of UiDragUserData
      cursor: FileSystemCursor

  proc buildFileDragTooltip(b: var UiBuilder, userData: UiDragUserData, canDrop: bool) {.nimcall.} =
    if userData == nil or not (userData of FileDragUserData):
      return
    let dragData = FileDragUserData(userData)
    discard b.fit().padding(6).gap(4)
    discard b.fillBackground().styleIndex(UiStyleIndexTooltip)
    discard b.text(dragData.cursor.fieldName & (if canDrop: " - move here" else: " - cannot move here")).fit()

var treeTableShowColumnLines = true
var treeTableHideRoot = false
var treeTableColumnGap = 4.0'f32
var treeTableColumnLineThickness = 1.0'f32
var treeTableColumnLineColor = rgba(0.55, 0.58, 0.64, 1.0)
var treeTableCustomColumnLineColor = false
var treeTableShowIndentationLines = true
var treeTableIndentationLineThickness = 1.0'f32
var treeTableIndentationLineColor = rgba(0.45, 0.48, 0.54, 1.0)
var treeTableCustomIndentationLineColor = false
var treeTableIndentationStep = 20.0'f32
var treeTableAlternatingRowColors = true
var treeTableAlternatingColorEven = rgba(0.16, 0.17, 0.20, 1.0)
var treeTableAlternatingColorOdd = rgba(0.20, 0.21, 0.24, 1.0)
var treeTableCustomAlternatingColors = false
var treeTableHighlightHoveredRow = true
var treeTableHoverColor = rgba(0.28, 0.36, 0.48, 1.0)
var treeTableCustomHoverColor = false
var treeTableAlternatingRowHeights = false
proc buildTreeTableExample(b: var UiBuilder) =
  let parent = b.currentNode
  if demoTreeRoot == nil:
    resetDemoTree()
  b.layoutVertical:
    b.debugName("tree-table-demo")
    discard b.fillX().padding(8).gap(8)
    if FitY in parent.flags:
      discard b.height(500)
    else:
      discard b.fillY()
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)
    b.label("Tree Table"):
      discard b.fontSize(18)
    b.labelWrapped("Tree tables combine expandable hierarchy rows with aligned columns and virtualized rendering, so large nested data sets can be browsed without building every row at once."):
      discard b.fillX().fontSize(13)
        .textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    b.layoutVertical("tree-table-options"):
      discard b.fillX().fitY().gap(8)
      b.node("tree-table-options-scroll"):
        discard b.fillX().height(220).padding(4)
        b.scrollBox:
          b.tableLayout([tableColumnFit(), tableColumnFill()], 12.0'f32, 4.0'f32):
            discard b.fillX().fitY()

            template optionRow(name: string, body: untyped) =
              b.node:
                discard b.fitY().padding(4)
                discard b.text(name).fit()
              b.node:
                discard b.fillX().fitY().padding(4)
                body

            optionRow("Hide root"):
              if b.checkbox("", treeTableHideRoot, fillXInVertical = false): discard
            optionRow("Column gap"):
              discard b.dragFloat(treeTableColumnGap, 4.0'f32, 0.0'f32, 40.0'f32)
            optionRow("Show column lines"):
              if b.checkbox("", treeTableShowColumnLines, fillXInVertical = false): discard
            optionRow("Column line thickness"):
              discard b.dragFloat(treeTableColumnLineThickness, 1.0'f32, 1.0'f32, 10.0'f32)
            optionRow("Custom column line color"):
              if b.checkbox("", treeTableCustomColumnLineColor, fillXInVertical = false): discard
            optionRow("Column line color"):
              if b.colorPicker(treeTableColumnLineColor): discard
            optionRow("Show indentation lines"):
              if b.checkbox("", treeTableShowIndentationLines, fillXInVertical = false): discard
            optionRow("Indentation line thickness"):
              discard b.dragFloat(treeTableIndentationLineThickness, 1.0'f32, 1.0'f32, 10.0'f32)
            optionRow("Custom indentation line color"):
              if b.checkbox("", treeTableCustomIndentationLineColor, fillXInVertical = false): discard
            optionRow("Indentation line color"):
              if b.colorPicker(treeTableIndentationLineColor): discard
            optionRow("Indentation step"):
              discard b.dragFloat(treeTableIndentationStep, 20.0'f32, 1.0'f32, 80.0'f32)
            optionRow("Alternating background colors"):
              if b.checkbox("", treeTableAlternatingRowColors, fillXInVertical = false): discard
            optionRow("Custom alternating colors"):
              if b.checkbox("", treeTableCustomAlternatingColors, fillXInVertical = false): discard
            optionRow("Even row color"):
              if b.colorPicker(treeTableAlternatingColorEven): discard
            optionRow("Odd row color"):
              if b.colorPicker(treeTableAlternatingColorOdd): discard
            optionRow("Highlight hovered row"):
              if b.checkbox("", treeTableHighlightHoveredRow, fillXInVertical = false): discard
            optionRow("Custom hover color"):
              if b.checkbox("", treeTableCustomHoverColor, fillXInVertical = false): discard
            optionRow("Hover color"):
              if b.colorPicker(treeTableHoverColor): discard
            optionRow("Alternating row heights"):
              if b.checkbox("", treeTableAlternatingRowHeights, fillXInVertical = false): discard
      if b.button("Reset tree"):
        resetDemoTree()

    b.layoutVertical:
      b.debugName("tree-table-hosts")
      discard b.fillX().sizeToParentY().gap(12)

      block:
        b.layoutVertical:
          b.debugName("test-tree-table-host")
          discard b.fillX().sizeToParentY()
          b.label("Mutable Tree"):
            discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
          b.labelWrapped("Drag any row onto another row to make it the target's last child. Drop on the highlighted strip above or below a row to move it beside that row, reparenting it when necessary. Use Reset tree to restore the original hierarchy."):
            discard b.fillX().fontSize(13)
              .textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

          proc renderRow(b: var UiBuilder, cursor: TreeCursor, index: int) {.canRaise, nimcall.} =
            let treeCursor = DemoTreeCursor(cursor)
            b.label(cursor.fieldName & ":"):
              discard b.fitX().fitY()

              template reorderDropZone(insertAfter: bool) =
                b.node:
                  b.debugName(if insertAfter:
                    "mutable-tree-drop-after"
                  else:
                    "mutable-tree-drop-before")
                  discard b.ignoreInContentExtent()
                  if insertAfter:
                    discard b.anchors(0.0'f32, 1, 1.0'f32, 1)
                      .offsets(0.0'f32, -3, 0.0'f32, 2)
                      .finishAnchors()
                  else:
                    discard b.anchors(0.0'f32, 0, 1.0'f32, 0)
                      .offsets(0.0'f32, -2, 0.0'f32, 3)
                      .finishAnchors()
                  if b.beginDrop():
                    let userData = b.dragData.userData
                    let canDrop = userData != nil and
                      userData of DemoTreeDragUserData and
                      DemoTreeDragUserData(userData).node.canMoveDemoTreeNodeBeside(treeCursor.node)
                    if canDrop:
                      discard b.deferBuild(
                        buildDemoTreeDropGradient, if insertAfter: 1 else: 0)
                    if b.endDrop(canDrop):
                      moveDemoTreeNodeBeside(
                        DemoTreeDragUserData(userData).node,
                        treeCursor.node,
                        insertAfter)

              reorderDropZone(false)
              reorderDropZone(true)

              if b.beginDrop(includeChildren = false):
                let userData = b.dragData.userData
                let canDrop = userData != nil and
                  userData of DemoTreeDragUserData and
                  DemoTreeDragUserData(userData).node.canReparentDemoTreeNode(treeCursor.node)
                if canDrop:
                  discard b.fillBackground().backgroundColor(
                    b.themeStyle(UiStyleIndexAccent)[].fillColor)
                if b.endDrop(canDrop):
                  reparentDemoTreeNode(DemoTreeDragUserData(userData).node, treeCursor.node)
                  discard b.requestTreeTableExpand(treeCursor)

              let (dragging, began) = b.beginDrag()
              if began:
                b.setDragData(DemoTreeDragUserData(node: treeCursor.node))
                b.setDragUiCallback(buildDemoTreeDragTooltip)
              if dragging:
                discard b.fillBackground().backgroundColor(
                  b.themeStyle(UiStyleIndexAccent)[].fillColor)

            b.node:
              discard b.fit().paddingX(10)
              b.label("dummy value"):
                discard b.fitX().fitY().alignCenter()

              if treeTableAlternatingRowHeights:
                b.node:
                  discard b.size(2, (index mod 4 + 1).float32 * 15)

            b.node:
              discard b.fit().paddingX(10)
              b.label($cursor.childCount()):
                discard b.anchorsX(1, 1).pivotX(1)

            b.node:
              discard b.fit().paddingX(10)
              b.label($index):
                discard b.anchorsX(1, 1).pivotX(1)

          var opts = defaultTreeTableOptions()
          opts.columns = @[tableColumnFill(), tableColumnFill(), tableColumnFit(), tableColumnFit(), tableColumnFit()]
          opts.hideRoot = treeTableHideRoot
          opts.columnGap = treeTableColumnGap
          opts.showColumnLines = treeTableShowColumnLines
          opts.columnLineThickness = treeTableColumnLineThickness
          opts.columnLineColor = treeTableColumnLineColor
          opts.hasCustomLineColor = treeTableCustomColumnLineColor
          opts.showIndentationLines = treeTableShowIndentationLines
          opts.indentationLineThickness = treeTableIndentationLineThickness
          opts.indentationLineColor = treeTableIndentationLineColor
          opts.hasCustomIndentationLineColor = treeTableCustomIndentationLineColor
          opts.indentationStep = treeTableIndentationStep
          opts.alternatingRowBackground = treeTableAlternatingRowColors
          opts.alternatingColorEven = treeTableAlternatingColorEven
          opts.alternatingColorOdd = treeTableAlternatingColorOdd
          opts.hasCustomAlternatingColors = treeTableCustomAlternatingColors
          opts.highlightHoveredRow = treeTableHighlightHoveredRow
          opts.hoverColor = treeTableHoverColor
          opts.hasCustomHoverColor = treeTableCustomHoverColor
          let testCursor = demoTreeCursor(demoTreeRoot)
          b.treeTable(testCursor, opts, renderRow)

proc buildFileSystemTreeExample(b: var UiBuilder) =
  let parent = b.currentNode
  b.layoutVertical:
    b.debugName("file-system-tree-demo")
    discard b.fillX().padding(8).gap(8)
    if FitY in parent.flags:
      discard b.height(500)
    else:
      discard b.fillY()
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)
    b.label("File System Tree"):
      discard b.fontSize(18)
    when defined(wasm):
      b.labelWrapped("The file system tree demo is only available in native builds."):
        discard b.fillX().fontSize(13)
          .textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    else:
      b.labelWrapped("Drag a file or folder onto a folder to move it there. Invalid moves, including dropping a folder into its own descendant or onto its current parent, are rejected."):
        discard b.fillX().fontSize(13)
          .textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
      b.layoutVertical("file-system-tree-options"):
        discard b.fitX().fitY().gap(12)
        if b.checkbox("Show column lines", treeTableShowColumnLines): discard
        if b.checkbox("Show indentation lines", treeTableShowIndentationLines): discard

      block:
        b.layoutVertical:
          b.debugName("fs-tree-table-host")
          discard b.fillX().sizeToParentY()
          b.label("fs-demo"):
            discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

          proc renderRow(b: var UiBuilder, cursor: TreeCursor, index: int) {.canRaise, nimcall.} =
            b.label(cursor.fieldName & ":"):
              discard b.fitX().fitY()

              let fileCursor = FileSystemCursor(cursor)
              if b.beginDrop():
                let userData = b.dragData.userData
                let canDrop = FileDragUserData(userData).cursor.canDropOn(fileCursor)
                if canDrop:
                  discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexAccent)[].fillColor)
                if b.endDrop(canDrop):
                  if FileDragUserData(userData).cursor.moveTo(fileCursor):
                    discard b.requestTreeTableExpand(fileCursor)

              let (dragging, began) = b.beginDrag()
              if began:
                b.setDragData(FileDragUserData(cursor: FileSystemCursor(fileCursor.clone())))
                b.setDragUiCallback(buildFileDragTooltip)
              if dragging:
                discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexAccent)[].fillColor)


            b.node:
              discard b.fit().paddingX(10)
              b.label("bar"):
                discard b.fitX().fitY()

            b.node:
              discard b.fit().paddingX(10)
              b.label($cursor.childCount()):
                discard b.anchorsX(1, 1).pivotX(1)

          var opts = defaultTreeTableOptions()
          opts.columns = @[tableColumnFit(), tableColumnFill(), tableColumnFit()]
          opts.showColumnLines = treeTableShowColumnLines
          opts.showIndentationLines = treeTableShowIndentationLines
          b.treeTable(fsCursor, opts, renderRow)

# ---------------------------------------------------------------------------
# Drag & Drop — child moved between two horizontal containers
# ---------------------------------------------------------------------------

var dragDropLocation = 0 # 0 = left container, 1 = right container

proc buildDragDropTooltip(b: var UiBuilder, userData: UiDragUserData, canDrop: bool) {.nimcall.} =
  let _ = userData
  discard b.fit().padding(6).gap(4)
  discard b.fillBackground().backgroundColor(if canDrop: rgba(0.18, 0.52, 0.24, 1.0) else: rgba(0.58, 0.20, 0.20, 1.0)).cornerRadius(4)
  discard b.borderWidth(1).borderColor(rgba(1.0'f32, 1.0'f32, 1.0'f32, 0.9'f32))
  discard b.text(if canDrop: "Drop allowed" else: "Cannot drop here").fit()
  discard b.textColor(rgba(1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32))

proc buildDragDropExample*(b: var UiBuilder) =
  b.layoutVertical("drag-drop-demo"):
    discard b.fillX().fitY().padding(8).gap(8)
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("Drag & Drop — move a chip between two containers in a horizontal list"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)
    b.labelWrapped("Drag the chip from its current container and drop it onto the other. While dragging a tooltip follows the mouse and shows whether the hovered container can accept the drop."):
      discard b.fillX().fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("dnd-containers"):
      discard b.fillX().fitY().gap(12)

      # Left container
      b.node("dnd-left"):
        discard b.size(220, 180).padding(8).gap(8)
        discard b.layout(LayoutVertical)
        discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
        discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor).cornerRadius(6)

        let hoverDrop = b.beginDrop()
        let canDrop = dragDropLocation != 0

        if hoverDrop:
          if canDrop:
            discard b.borderColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HGreen, 1.0)).borderWidth(2)
          else:
            discard b.borderColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HRed, 1.0)).borderWidth(2)
          if b.endDrop(canDrop):
            dragDropLocation = 0

        b.label("Left"):
          discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

        if dragDropLocation == 0:
          b.node("dnd-chip"):
            discard b.fit().padding(8).gap(4)
            discard b.fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0)).cornerRadius(6)
            discard b.text("DragMe").fit()
            discard b.textColor(b.themeTextStyle(UiStyleIndexButtonText)[].textColor)
            let (dragging, began) = b.beginDrag()
            if began:
              b.setDragUiCallback(buildDragDropTooltip)
            if dragging:
              discard b.borderWidth(2).borderColor(rgba(1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32))
        else:
          b.node("dnd-placeholder-left"):
            discard b.fit().padding(8)
            discard b.text("drop here").fit().textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
            discard b.cornerRadius(6).borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)

      # Right container
      b.node("dnd-right"):
        discard b.size(220, 180).padding(8).gap(8)
        discard b.layout(LayoutVertical)
        discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
        discard b.borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor).cornerRadius(6)

        let hoverDrop = b.beginDrop()
        let canDrop = dragDropLocation != 1

        if hoverDrop:
          if canDrop:
            discard b.borderColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HGreen, 1.0)).borderWidth(2)
          else:
            discard b.borderColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HRed, 1.0)).borderWidth(2)
          if b.endDrop(canDrop):
            dragDropLocation = 1

        b.label("Right"):
          discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

        if dragDropLocation == 1:
          b.node("dnd-chip"):
            discard b.fit().padding(8).gap(4)
            discard b.fillBackground().backgroundColor(accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, HBlue, 1.0)).cornerRadius(6)
            discard b.text("DragMe").fit()
            discard b.textColor(b.themeTextStyle(UiStyleIndexButtonText)[].textColor)
            let (dragging, began) = b.beginDrag()
            if began:
              b.setDragUiCallback(buildDragDropTooltip)
            if dragging:
              discard b.borderWidth(2).borderColor(rgba(1.0'f32, 1.0'f32, 1.0'f32, 1.0'f32))
        else:
          b.node("dnd-placeholder-right"):
            discard b.fit().padding(8)
            discard b.text("drop here").fit().textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
            discard b.cornerRadius(6).borderWidth(1).borderColor(b.themeStyle(UiStyleIndexPanel)[].borderColor)

    b.label("Current location: " & (if dragDropLocation == 0: "Left" else: "Right")):
      discard b.fontSize(13).textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    if b.button("Reset to left"):
      dragDropLocation = 0
      b.dragData.nodeId = noneNodeId()
      b.dragData.userData = nil

proc buildAllExamples(b: var UiBuilder)

var examples = [
  (fun: buildIntroPage, scrollBox: true, title: "Intro"),
  (fun: buildFaqTreeTableExample, scrollBox: false, title: "FAQ"),
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
  (fun: buildTreeTableExample, scrollBox: false, title: "TreeTable"),
  (fun: buildFileSystemTreeExample, scrollBox: false, title: "FileSystem"),
  (fun: buildUnicodeExamples, scrollBox: true, title: "Unicode"),
  (fun: buildSubpixelExamples, scrollBox: true, title: "Subpixel"),
  (fun: buildFontAtlasExamples, scrollBox: true, title: "Atlas"),
  (fun: buildCustomRenderExamples, scrollBox: true, title: "Custom"),
  (fun: buildCustomMaterialExample, scrollBox: false, title: "CustomMat"),
  (fun: buildDragDropExample, scrollBox: true, title: "DragDrop"),
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
    discard b.dynamicVirtualList(examples.len - 1, 500, buildDemoItem)

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
            var f = b.fontScale
            b.layoutHorizontalReverse:
              discard b.fillX().fit().gap(2)
              discard b.dragFloat(f, 1, 0.1'f32, 4.0'f32)
              b.label("Font Size"):
                discard b.fitX()
            b.fontScale = f

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
