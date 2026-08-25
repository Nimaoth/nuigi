import std/[math, assertions]
import "../nuigi", "../widgets", "../flex", "../grid"
import "../mymath", "../arena", "../array_view"
import "../profiler"

# ---------------------------------------------------------------------------
# Shared flex/grid option tables and helpers (mirrors ui_example.nim)
# ---------------------------------------------------------------------------

const flexJustifyOptions = [
  FlexJustifyStart,
  FlexJustifyEnd,
  FlexJustifyCenter,
  FlexJustifySpaceBetween,
  FlexJustifySpaceAround,
  FlexJustifySpaceEvenly,
]

const flexAlignItemsOptions = [
  FlexAlignStart,
  FlexAlignCenter,
  FlexAlignEnd,
  FlexAlignStretch,
  FlexAlignBaseline,
]

const flexAlignSelfOptions = [
  FlexAlignAuto,
  FlexAlignStart,
  FlexAlignCenter,
  FlexAlignEnd,
  FlexAlignStretch,
  FlexAlignBaseline,
]

const flexAlignContentOptions = [
  FlexContentStart,
  FlexContentEnd,
  FlexContentCenter,
  FlexContentStretch,
  FlexContentSpaceBetween,
  FlexContentSpaceAround,
  FlexContentSpaceEvenly,
]

var flexDirectionCurrentJustify = FlexJustifyStart
var flexDirectionCurrentAlignItems = FlexAlignCenter
var flexDirectionCurrentChildAlignSelf = FlexAlignAuto

var flexWrapCurrentJustify = FlexJustifyCenter
var flexWrapCurrentAlignContent = FlexContentStart
var flexWrapCurrentChildAlignSelf = FlexAlignAuto

var flexJustifyCurrentJustify = FlexJustifyStart
var flexJustifyCurrentAlignItems = FlexAlignCenter
var flexJustifyCurrentChildAlignSelf = FlexAlignAuto

var flexAlignCurrentAlignItems = FlexAlignEnd
var flexAlignCurrentChildAlignSelf = FlexAlignAuto

var flexChildPropsCurrentJustify = FlexJustifyStart
var flexChildPropsCurrentAlignItems = FlexAlignCenter
var flexChildPropsCurrentChildAlignSelf = FlexAlignAuto

var flexAnchorIgnoredCurrentJustify = FlexJustifyStart
var flexAnchorIgnoredCurrentAlignItems = FlexAlignCenter
var flexAnchorIgnoredCurrentChildAlignSelf = FlexAlignAuto

var gridFixedCurrentJustifyItems = FlexAlignStretch
var gridFixedCurrentAlignItems = FlexAlignStretch
var gridFixedCurrentJustifyContent = FlexContentStart
var gridFixedCurrentAlignContent = FlexContentStart
var gridFixedCurrentJustifySelf = FlexAlignAuto
var gridFixedCurrentAlignSelf = FlexAlignAuto

var gridFrCurrentJustifyItems = FlexAlignStretch
var gridFrCurrentAlignItems = FlexAlignStretch
var gridFrCurrentJustifyContent = FlexContentStart
var gridFrCurrentAlignContent = FlexContentStart
var gridFrCurrentJustifySelf = FlexAlignAuto
var gridFrCurrentAlignSelf = FlexAlignAuto

var gridSelfCurrentJustifyItems = FlexAlignStretch
var gridSelfCurrentAlignItems = FlexAlignStretch
var gridSelfCurrentJustifyContent = FlexContentStart
var gridSelfCurrentAlignContent = FlexContentStart
var gridSelfCurrentJustifySelf = FlexAlignCenter
var gridSelfCurrentAlignSelf = FlexAlignCenter

var gridContentCurrentJustifyItems = FlexAlignStretch
var gridContentCurrentAlignItems = FlexAlignStretch
var gridContentCurrentJustifyContent = FlexContentStretch
var gridContentCurrentAlignContent = FlexContentStretch
var gridContentCurrentJustifySelf = FlexAlignAuto
var gridContentCurrentAlignSelf = FlexAlignAuto

proc cycleFlexOption[T: enum](current: var T, options: openArray[T]) =
  for i in 0 ..< options.len:
    if options[i].ord == current.ord:
      current = options[(i + 1) mod options.len]
      return
  current = options[0]

proc flexJustifyName(value: UiFlexJustify): string =
  case value
  of FlexJustifyStart: "start"
  of FlexJustifyEnd: "end"
  of FlexJustifyCenter: "center"
  of FlexJustifySpaceBetween: "space-between"
  of FlexJustifySpaceAround: "space-around"
  of FlexJustifySpaceEvenly: "space-evenly"

proc flexAlignName(value: UiFlexAlign): string =
  case value
  of FlexAlignAuto: "auto"
  of FlexAlignStart: "start"
  of FlexAlignCenter: "center"
  of FlexAlignEnd: "end"
  of FlexAlignStretch: "stretch"
  of FlexAlignBaseline: "baseline"

proc flexAlignContentName(value: UiFlexAlignContent): string =
  case value
  of FlexContentStart: "start"
  of FlexContentEnd: "end"
  of FlexContentCenter: "center"
  of FlexContentStretch: "stretch"
  of FlexContentSpaceBetween: "space-between"
  of FlexContentSpaceAround: "space-around"
  of FlexContentSpaceEvenly: "space-evenly"

# Hue shifts (in turns) applied to the single theme `Accent` color to derive the
# varied colored blocks below. Keeps the demo themeable from one accent slot.
const
  HGreen* = -0.26'f32
  HBlue* = 0.0'f32
  HRed* = 0.41'f32
  HOrange* = 0.45'f32
  HYellow* = -0.46'f32
  HPurple* = 0.19'f32
  HTeal* = -0.09'f32

# ---------------------------------------------------------------------------
# Type 4 #1 — Flex layout showcase
# ---------------------------------------------------------------------------

proc buildFlexLayoutExamples*(b: var UiBuilder) =
  let accent = b.themeStyle(UiStyleIndexAccent)[].fillColor
  b.layoutVertical("flex-demos"):
    discard b.fillX().fitY().padding(6).gap(6)
    discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("Flex Layout Examples (Parent + Children)"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.layoutHorizontal("flex-controls-anchor-ignored"):
      discard b.fillX().fitY().gap(4)
      if b.button("Parent justify: " & flexJustifyName(flexAnchorIgnoredCurrentJustify)):
        cycleFlexOption(flexAnchorIgnoredCurrentJustify, flexJustifyOptions)
      if b.button("Parent align-items: " & flexAlignName(flexAnchorIgnoredCurrentAlignItems)):
        cycleFlexOption(flexAnchorIgnoredCurrentAlignItems, flexAlignItemsOptions)
      if b.button("Child align-self: " & flexAlignName(flexAnchorIgnoredCurrentChildAlignSelf)):
        cycleFlexOption(flexAnchorIgnoredCurrentChildAlignSelf, flexAlignSelfOptions)

    b.node("flex-anchor-ignored"):
      discard b.height(280).padding(4).fillX()
      discard b.flexLayout().flexDirection(FlexDirectionRow).justifyContent(flexAnchorIgnoredCurrentJustify).alignItems(flexAnchorIgnoredCurrentAlignItems).columnGap(6)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)

      b.node:
        discard b.fit().padding(3).fontSize(12.0).flex(1.0, 1.0, 56.0).flexAlignSelf(flexAnchorIgnoredCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HGreen, 1.0))
        discard b.text("left")
        b.node:
          discard b.fillX().fitY().padding(2).gap(2).alignCenter()
          discard b.flexLayout().flexWrap(FlexWrap).justifyContent(FlexJustifyStart).alignItems(FlexAlignStart).alignContent(FlexContentStart).flexGaps(2, 2)
          discard b.fillBackground().backgroundColor(accentVariation(accent, HGreen, 0.72))
          for chip in ["Left1", "Left2", "Left3", "Left4", "Left5", "Left6", "Left7", "Left8", "Left9", "Left10", "Left11", "Left12"]:
            b.node:
              discard b.fit().padding(2).flex(0.0, 0.0, -1.0)
              discard b.fillBackground().backgroundColor(accentVariation(accent, HGreen, 0.62))
              discard b.text(chip)

      b.node:
        discard b.fit().padding(3).fontSize(15.0).anchorsX(0.5, 0.5).offsetsX(0, 0).pivotX(0.5).flexAlignSelf(flexAnchorIgnoredCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HYellow, 1.0))
        discard b.text("anchor ignored in flex")

      b.node:
        discard b.fit().padding(3).fontSize(10.0).flex(1.0, 1.0, 64.0).flexAlignSelf(flexAnchorIgnoredCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HBlue, 1.0))
        discard b.text("right")
        b.node:
          discard b.fillX().fitY().padding(2).gap(2)
          discard b.flexLayout().flexWrap(FlexWrap).justifyContent(FlexJustifyStart).alignItems(FlexAlignAuto).alignContent(FlexContentStart).flexGaps(2, 2)
          discard b.fillBackground().backgroundColor(accentVariation(accent, HBlue, 0.72))
          for chip in ["Right1", "Right2", "Right3", "Right4", "Right5", "Right6", "Right7", "Right8", "Right9", "Right10", "Right11", "Right12"]:
            b.node:
              discard b.fit().padding(2).flex(0.0, 0.0, -1.0)
              discard b.fillBackground().backgroundColor(accentVariation(accent, HBlue, 0.62))
              discard b.text(chip)

    b.node("flex-anchor-ignored2"):
      discard b.height(280).padding(4).fillX()
      discard b.flexLayout().flexDirection(FlexDirectionRow).justifyContent(flexAnchorIgnoredCurrentJustify).alignItems(flexAnchorIgnoredCurrentAlignItems).columnGap(6)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)

      b.node:
        discard b.fitY().padding(3).flex(1.0, 1.0, 56.0).flexAlignSelf(flexAnchorIgnoredCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HGreen, 0.62))
        b.node:
          discard b.fillX().fitY()
          discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor).wrapText()
          discard b.text("this is a very long sentence that the will wrap around")

      b.node:
        discard b.fit().padding(3).fontSize(15.0).anchorsX(0.5, 0.5).offsetsX(0, 0).pivotX(0.5).flexAlignSelf(flexAnchorIgnoredCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HYellow, 1.0))
        discard b.text("anchor ignored in flex")

      b.node:
        discard b.fitY().padding(3).flex(1.0, 1.0, 64.0).flexAlignSelf(flexAnchorIgnoredCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HBlue, 0.62))
        b.node:
          discard b.fillX().fitY()
          discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor).wrapText()
          discard b.text("this is a very long sentence that the will wrap around")

    b.label("Direction: row / row-reverse / column / column-reverse"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("flex-controls-direction"):
      discard b.fillX().fitY().gap(4)
      if b.button("Parent justify: " & flexJustifyName(flexDirectionCurrentJustify)):
        cycleFlexOption(flexDirectionCurrentJustify, flexJustifyOptions)
      if b.button("Parent align-items: " & flexAlignName(flexDirectionCurrentAlignItems)):
        cycleFlexOption(flexDirectionCurrentAlignItems, flexAlignItemsOptions)
      if b.button("Child align-self: " & flexAlignName(flexDirectionCurrentChildAlignSelf)):
        cycleFlexOption(flexDirectionCurrentChildAlignSelf, flexAlignSelfOptions)

    b.layoutHorizontal("flex-direction-row"):
      discard b.size(280, 34).padding(3).fillX()
      discard b.flexLayout().flexDirection(FlexDirectionRow).justifyContent(flexDirectionCurrentJustify).alignItems(flexDirectionCurrentAlignItems).columnGap(4)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      b.node:
        discard b.fit().padding(3).fontSize(11.0).flex(0.0, 1.0, 44.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
        discard b.backgroundColor(accentVariation(accent, HRed, 1.0))
        discard b.text("row sm")
      b.node:
        discard b.fit().padding(3).fontSize(16.0).flex(0.0, 1.0, 44.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
        discard b.backgroundColor(accentVariation(accent, HBlue, 1.0))
        discard b.text("row LG")
      b.node:
        discard b.fit().padding(3).fontSize(13.0).flex(0.0, 1.0, 44.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
        discard b.backgroundColor(accentVariation(accent, HGreen, 1.0))
        discard b.text("row md")

    b.layoutHorizontal("flex-direction-row-reverse"):
      discard b.size(280, 34).padding(3).fillX()
      discard b.flexLayout().flexDirection(FlexDirectionRowReverse).justifyContent(flexDirectionCurrentJustify).alignItems(flexDirectionCurrentAlignItems).columnGap(4)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      b.node:
        discard b.fit().padding(3).fontSize(14.0).flex(0.0, 1.0, 44.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
        discard b.backgroundColor(accentVariation(accent, HOrange, 1.0))
        discard b.text("rev a")
      b.node:
        discard b.fit().padding(3).fontSize(10.0).flex(0.0, 1.0, 44.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
        discard b.backgroundColor(accentVariation(accent, HBlue, 1.0))
        discard b.text("rev b")
      b.node:
        discard b.fit().padding(3).fontSize(17.0).flex(0.0, 1.0, 44.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
        discard b.backgroundColor(accentVariation(accent, HGreen, 1.0))
        discard b.text("rev c")

    b.layoutHorizontal:
      discard b.fillX().fitY().gap(8)

      b.node("flex-direction-column"):
        discard b.size(136, 86).padding(3)
        discard b.flexLayout().flexDirection(FlexDirectionColumn).justifyContent(flexDirectionCurrentJustify).alignItems(flexDirectionCurrentAlignItems).rowGap(3)
        discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
        b.node:
          discard b.fit().padding(3).fontSize(10.0).flex(0.0, 1.0, 18.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
          discard b.backgroundColor(accentVariation(accent, HOrange, 1.0))
          discard b.text("col s")
        b.node:
          discard b.fit().padding(3).fontSize(15.0).flex(0.0, 1.0, 18.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
          discard b.backgroundColor(accentVariation(accent, HBlue, 1.0))
          discard b.text("col L")
        b.node:
          discard b.fit().padding(3).fontSize(12.0).flex(0.0, 1.0, 18.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
          discard b.backgroundColor(accentVariation(accent, HGreen, 1.0))
          discard b.text("col m")

      b.node("flex-direction-column-reverse"):
        discard b.size(136, 86).padding(3)
        discard b.flexLayout().flexDirection(FlexDirectionColumnReverse).justifyContent(flexDirectionCurrentJustify).alignItems(flexDirectionCurrentAlignItems).rowGap(3)
        discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
        b.node:
          discard b.fit().padding(3).fontSize(16.0).flex(0.0, 1.0, 18.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
          discard b.backgroundColor(accentVariation(accent, HRed, 1.0))
          discard b.text("rev L")
        b.node:
          discard b.fit().padding(3).fontSize(11.0).flex(0.0, 1.0, 18.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
          discard b.backgroundColor(accentVariation(accent, HBlue, 1.0))
          discard b.text("rev s")
        b.node:
          discard b.fit().padding(3).fontSize(13.0).flex(0.0, 1.0, 18.0).flexAlignSelf(flexDirectionCurrentChildAlignSelf).fillBackground()
          discard b.backgroundColor(accentVariation(accent, HGreen, 1.0))
          discard b.text("rev m")

    b.label("Wrap + align-content + row/column gaps"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("flex-controls-wrap"):
      discard b.fillX().fitY().gap(4)
      if b.button("Parent justify: " & flexJustifyName(flexWrapCurrentJustify)):
        cycleFlexOption(flexWrapCurrentJustify, flexJustifyOptions)
      if b.button("Parent align-content: " & flexAlignContentName(flexWrapCurrentAlignContent)):
        cycleFlexOption(flexWrapCurrentAlignContent, flexAlignContentOptions)
      if b.button("Child align-self: " & flexAlignName(flexWrapCurrentChildAlignSelf)):
        cycleFlexOption(flexWrapCurrentChildAlignSelf, flexAlignSelfOptions)

    b.layoutHorizontal("flex-wrap-align-content"):
      discard b.size(280, 110).padding(4).fillX()
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexWrap(FlexWrap).alignContent(flexWrapCurrentAlignContent)
      discard b.justifyContent(flexWrapCurrentJustify).flexGaps(6, 5)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      for i in 0 .. 8:
        b.node:
          let basis = if i mod 3 == 0: 74.0'f32 elif i mod 3 == 1: 56.0'f32 else: 48.0'f32
          let itemFont = if i mod 3 == 0: 10.0'f32 elif i mod 3 == 1: 13.0'f32 else: 16.0'f32
          discard b.fit().padding(3).fontSize(itemFont).flex(0.0, 1.0, basis).flexAlignSelf(flexWrapCurrentChildAlignSelf).fillBackground()
          discard b.backgroundColor(accentVariation(accent, HBlue, 0.72 + i.float32 * 0.03'f32))
          discard b.text("wrap " & $i)

    b.layoutHorizontal("flex-wrap-reverse"):
      discard b.size(280, 96).padding(4).fillX()
      discard b.flexLayout().flexDirection(FlexDirectionRow).flexWrap(FlexWrapReverse).alignContent(flexWrapCurrentAlignContent)
      discard b.justifyContent(flexWrapCurrentJustify).flexGaps(4, 4)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      for i in 0 .. 6:
        b.node:
          let itemFont = if i mod 2 == 0: 11.0'f32 else: 15.0'f32
          discard b.fit().padding(3).fontSize(itemFont).flex(0.0, 1.0, 66.0 - (i mod 3).float32 * 10.0'f32).flexAlignSelf(flexWrapCurrentChildAlignSelf).fillBackground()
          discard b.backgroundColor(accentVariation(accent, HOrange, 0.95 - i.float32 * 0.05'f32))
          discard b.text("rev " & $i)

    b.label("justify-content interactive"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("flex-controls-justify"):
      discard b.fillX().fitY().gap(4)
      if b.button("Parent justify: " & flexJustifyName(flexJustifyCurrentJustify)):
        cycleFlexOption(flexJustifyCurrentJustify, flexJustifyOptions)
      if b.button("Parent align-items: " & flexAlignName(flexJustifyCurrentAlignItems)):
        cycleFlexOption(flexJustifyCurrentAlignItems, flexAlignItemsOptions)
      if b.button("Child align-self: " & flexAlignName(flexJustifyCurrentChildAlignSelf)):
        cycleFlexOption(flexJustifyCurrentChildAlignSelf, flexAlignSelfOptions)

    b.layoutHorizontal("flex-justify-interactive"):
      discard b.size(280, 34).padding(3).fillX()
      discard b.flexLayout().flexDirection(FlexDirectionRow).justifyContent(flexJustifyCurrentJustify).alignItems(flexJustifyCurrentAlignItems).columnGap(4)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      b.node:
        discard b.fit().padding(3).fontSize(10.0).flex(0.0, 1.0, 38.0).flexAlignSelf(flexJustifyCurrentChildAlignSelf).fillBackground()
        discard b.backgroundColor(accentVariation(accent, HOrange, 1.0))
        discard b.text("J1")
      b.node:
        discard b.fit().padding(3).fontSize(14.0).flex(0.0, 1.0, 38.0).flexAlignSelf(flexJustifyCurrentChildAlignSelf).fillBackground()
        discard b.backgroundColor(accentVariation(accent, HBlue, 1.0))
        discard b.text("J2")
      b.node:
        discard b.fit().padding(3).fontSize(18.0).flex(0.0, 1.0, 38.0).flexAlignSelf(flexJustifyCurrentChildAlignSelf).fillBackground()
        discard b.backgroundColor(accentVariation(accent, HGreen, 1.0))
        discard b.text("J3")

    b.label("align-items + align-self + baseline"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("flex-controls-align"):
      discard b.fillX().fitY().gap(4)
      if b.button("Parent align-items: " & flexAlignName(flexAlignCurrentAlignItems)):
        cycleFlexOption(flexAlignCurrentAlignItems, flexAlignItemsOptions)
      if b.button("Child align-self: " & flexAlignName(flexAlignCurrentChildAlignSelf)):
        cycleFlexOption(flexAlignCurrentChildAlignSelf, flexAlignSelfOptions)

    b.layoutHorizontal("flex-align-items"):
      discard b.size(280, 78).padding(4).fillX()
      discard b.flexLayout().flexDirection(FlexDirectionRow).alignItems(flexAlignCurrentAlignItems).columnGap(5)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)

      b.node:
        discard b.fit().padding(3).fontSize(10.0).flex(0.0, 1.0, 36.0).flexAlignSelf(flexAlignCurrentChildAlignSelf).fillBackground().backgroundColor(accentVariation(accent, HYellow, 1.0))
        discard b.text("A")

      b.node:
        discard b.fit().padding(3).fontSize(13.0).flex(0.0, 1.0, 36.0).flexAlignSelf(flexAlignCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HRed, 1.0))
        discard b.text("Align")

      b.node:
        discard b.fit().padding(3).fontSize(16.0).flex(0.0, 1.0, 36.0).flexAlignSelf(flexAlignCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HBlue, 1.0))
        discard b.text("Tall")

      b.node:
        discard b.fit().padding(3).fontSize(11.0).flex(0.0, 1.0, 36.0).flexAlignSelf(flexAlignCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HGreen, 1.0))
        discard b.text("S")

      b.node:
        discard b.fit().padding(3).fontSize(15.0).flex(0.0, 1.0, 36.0).flexAlignSelf(flexAlignCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HPurple, 1.0))
        discard b.text("Base")

    b.label("Children: order + grow/shrink/basis"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("flex-controls-child-props"):
      discard b.fillX().fitY().gap(4)
      if b.button("Parent justify: " & flexJustifyName(flexChildPropsCurrentJustify)):
        cycleFlexOption(flexChildPropsCurrentJustify, flexJustifyOptions)
      if b.button("Parent align-items: " & flexAlignName(flexChildPropsCurrentAlignItems)):
        cycleFlexOption(flexChildPropsCurrentAlignItems, flexAlignItemsOptions)
      if b.button("Child align-self: " & flexAlignName(flexChildPropsCurrentChildAlignSelf)):
        cycleFlexOption(flexChildPropsCurrentChildAlignSelf, flexAlignSelfOptions)

    b.layoutHorizontal("flex-child-props"):
      discard b.size(280, 58).padding(4).fillX()
      discard b.flexLayout().flexDirection(FlexDirectionRow).justifyContent(flexChildPropsCurrentJustify).alignItems(flexChildPropsCurrentAlignItems).columnGap(4)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)

      b.node:
        discard b.fit().padding(3).fontSize(11.0).flex(1.0, 1.0, 38.0).flexOrder(2).flexAlignSelf(flexChildPropsCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HRed, 1.0))
        discard b.text("grow1")

      b.node:
        discard b.fit().padding(3).fontSize(16.0).flex(2.0, 1.0, 52.0).flexOrder(0).flexAlignSelf(flexChildPropsCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HBlue, 1.0))
        discard b.text("grow2")

      b.node:
        discard b.fit().padding(3).fontSize(13.0).flex(0.0, 3.0, 86.0).flexOrder(1).flexAlignSelf(flexChildPropsCurrentChildAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HGreen, 1.0))
        discard b.text("shrink3")

# ---------------------------------------------------------------------------
# Type 4 #2 — Grid layout showcase
# ---------------------------------------------------------------------------

proc buildGridLayoutExamples*(b: var UiBuilder) =
  let accent = b.themeStyle(UiStyleIndexAccent)[].fillColor
  b.layoutVertical("grid-demos"):
    discard b.fillX().fitY().padding(6).gap(6)
    discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("Grid Layout Examples"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

    b.label("Fixed tracks + explicit areas"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("grid-controls-fixed"):
      discard b.fillX().fitY().gap(4)
      if b.button("Parent justify-items: " & flexAlignName(gridFixedCurrentJustifyItems)):
        cycleFlexOption(gridFixedCurrentJustifyItems, flexAlignItemsOptions)
      if b.button("Parent align-items: " & flexAlignName(gridFixedCurrentAlignItems)):
        cycleFlexOption(gridFixedCurrentAlignItems, flexAlignItemsOptions)
      if b.button("Parent justify-content: " & flexAlignContentName(gridFixedCurrentJustifyContent)):
        cycleFlexOption(gridFixedCurrentJustifyContent, flexAlignContentOptions)
      if b.button("Parent align-content: " & flexAlignContentName(gridFixedCurrentAlignContent)):
        cycleFlexOption(gridFixedCurrentAlignContent, flexAlignContentOptions)
      if b.button("Child justify-self: " & flexAlignName(gridFixedCurrentJustifySelf)):
        cycleFlexOption(gridFixedCurrentJustifySelf, flexAlignSelfOptions)
      if b.button("Child align-self: " & flexAlignName(gridFixedCurrentAlignSelf)):
        cycleFlexOption(gridFixedCurrentAlignSelf, flexAlignSelfOptions)

    b.node("grid-fixed-area"):
      discard b.size(280, 110).padding(4).fillX()
      discard b.gridLayout().gridTemplateColumns([gridPx(56.0), gridPx(74.0), gridPx(92.0)])
      discard b.gridTemplateRows([gridPx(26.0), gridPx(42.0)])
      discard b.gridGaps(6.0, 6.0)
      discard b.gridJustifyItems(gridFixedCurrentJustifyItems).gridAlignItems(gridFixedCurrentAlignItems)
      discard b.gridJustifyContent(gridFixedCurrentJustifyContent).gridAlignContent(gridFixedCurrentAlignContent)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)

      b.node:
        discard b.gridJustifySelf(gridFixedCurrentJustifySelf).gridAlignSelf(gridFixedCurrentAlignSelf)
        discard b.gridArea(1, 1).fillBackground().backgroundColor(accentVariation(accent, HRed, 1.0))
        discard b.text("A").fit()

      b.node:
        discard b.gridJustifySelf(gridFixedCurrentJustifySelf).gridAlignSelf(gridFixedCurrentAlignSelf)
        discard b.gridArea(2, 1, 2, 1).fillBackground().backgroundColor(accentVariation(accent, HBlue, 1.0))
        discard b.text("B span 2 cols").fit()

      b.node:
        discard b.gridJustifySelf(gridFixedCurrentJustifySelf).gridAlignSelf(gridFixedCurrentAlignSelf)
        discard b.gridArea(1, 2, 1, 1).fillBackground().backgroundColor(accentVariation(accent, HGreen, 1.0))
        discard b.text("C").fit()

      b.node:
        discard b.gridJustifySelf(gridFixedCurrentJustifySelf).gridAlignSelf(gridFixedCurrentAlignSelf)
        discard b.gridArea(2, 2, 2, 1).fillBackground().backgroundColor(accentVariation(accent, HPurple, 1.0))
        discard b.text("D span 2 cols").fit()

    b.label("Fraction tracks + auto placement"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("grid-controls-fr"):
      discard b.fillX().fitY().gap(4)
      if b.button("Parent justify-items: " & flexAlignName(gridFrCurrentJustifyItems)):
        cycleFlexOption(gridFrCurrentJustifyItems, flexAlignItemsOptions)
      if b.button("Parent align-items: " & flexAlignName(gridFrCurrentAlignItems)):
        cycleFlexOption(gridFrCurrentAlignItems, flexAlignItemsOptions)
      if b.button("Parent justify-content: " & flexAlignContentName(gridFrCurrentJustifyContent)):
        cycleFlexOption(gridFrCurrentJustifyContent, flexAlignContentOptions)
      if b.button("Parent align-content: " & flexAlignContentName(gridFrCurrentAlignContent)):
        cycleFlexOption(gridFrCurrentAlignContent, flexAlignContentOptions)
      if b.button("Child justify-self: " & flexAlignName(gridFrCurrentJustifySelf)):
        cycleFlexOption(gridFrCurrentJustifySelf, flexAlignSelfOptions)
      if b.button("Child align-self: " & flexAlignName(gridFrCurrentAlignSelf)):
        cycleFlexOption(gridFrCurrentAlignSelf, flexAlignSelfOptions)

    b.node("grid-fr-auto"):
      discard b.size(280, 126).padding(4).fillX()
      discard b.gridLayout().gridTemplateColumns([gridFr(1.0), gridFr(2.0), gridFr(1.0)])
      discard b.gridTemplateRows([gridPx(28.0), gridPx(28.0), gridPx(28.0)])
      discard b.gridGaps(5.0, 6.0)
      discard b.gridJustifyItems(gridFrCurrentJustifyItems).gridAlignItems(gridFrCurrentAlignItems)
      discard b.gridJustifyContent(gridFrCurrentJustifyContent).gridAlignContent(gridFrCurrentAlignContent)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
      for labelText in ["one", "two wide", "three", "four", "five", "six"]:
        b.node:
          discard b.gridJustifySelf(gridFrCurrentJustifySelf).gridAlignSelf(gridFrCurrentAlignSelf)
          discard b.fillBackground().backgroundColor(accentVariation(accent, HBlue, 0.85))
          discard b.text(labelText).fit()

    b.label("Self alignment inside cells"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("grid-controls-self"):
      discard b.fillX().fitY().gap(4)
      if b.button("Parent justify-items: " & flexAlignName(gridSelfCurrentJustifyItems)):
        cycleFlexOption(gridSelfCurrentJustifyItems, flexAlignItemsOptions)
      if b.button("Parent align-items: " & flexAlignName(gridSelfCurrentAlignItems)):
        cycleFlexOption(gridSelfCurrentAlignItems, flexAlignItemsOptions)
      if b.button("Parent justify-content: " & flexAlignContentName(gridSelfCurrentJustifyContent)):
        cycleFlexOption(gridSelfCurrentJustifyContent, flexAlignContentOptions)
      if b.button("Parent align-content: " & flexAlignContentName(gridSelfCurrentAlignContent)):
        cycleFlexOption(gridSelfCurrentAlignContent, flexAlignContentOptions)
      if b.button("Child justify-self: " & flexAlignName(gridSelfCurrentJustifySelf)):
        cycleFlexOption(gridSelfCurrentJustifySelf, flexAlignSelfOptions)
      if b.button("Child align-self: " & flexAlignName(gridSelfCurrentAlignSelf)):
        cycleFlexOption(gridSelfCurrentAlignSelf, flexAlignSelfOptions)

    b.node("grid-self-align"):
      discard b.size(280, 112).padding(4).fillX()
      discard b.gridLayout().gridTemplateColumns([gridPx(84.0), gridPx(84.0), gridPx(84.0)])
      discard b.gridTemplateRows([gridPx(44.0), gridPx(44.0)])
      discard b.gridGaps(8.0, 8.0)
      discard b.gridJustifyItems(gridSelfCurrentJustifyItems).gridAlignItems(gridSelfCurrentAlignItems)
      discard b.gridJustifyContent(gridSelfCurrentJustifyContent).gridAlignContent(gridSelfCurrentAlignContent)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)

      b.node:
        discard b.gridArea(1, 1).gridJustifySelf(FlexAlignStart).gridAlignSelf(FlexAlignStart)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HOrange, 1.0))
        discard b.text("start")

      b.node:
        discard b.gridArea(2, 1).gridJustifySelf(FlexAlignCenter).gridAlignSelf(FlexAlignCenter)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HBlue, 1.0))
        discard b.text("center")

      b.node:
        discard b.gridArea(3, 1).gridJustifySelf(FlexAlignEnd).gridAlignSelf(FlexAlignEnd)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HGreen, 1.0))
        discard b.text("end")

      b.node:
        discard b.gridJustifySelf(FlexAlignStretch).gridAlignSelf(FlexAlignStretch)
        discard b.gridArea(1, 2).fillBackground().backgroundColor(accentVariation(accent, HYellow, 1.0))
        discard b.text("stretch")

      b.node:
        discard b.gridArea(3, 2, 1, 1).gridJustifySelf(gridSelfCurrentJustifySelf).gridAlignSelf(gridSelfCurrentAlignSelf)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HTeal, 1.0))
        discard b.text("mix")

    b.label("Content distribution + spans"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutHorizontal("grid-controls-content"):
      discard b.fillX().fitY().gap(4)
      if b.button("Parent justify-items: " & flexAlignName(gridContentCurrentJustifyItems)):
        cycleFlexOption(gridContentCurrentJustifyItems, flexAlignItemsOptions)
      if b.button("Parent align-items: " & flexAlignName(gridContentCurrentAlignItems)):
        cycleFlexOption(gridContentCurrentAlignItems, flexAlignItemsOptions)
      if b.button("Parent justify-content: " & flexAlignContentName(gridContentCurrentJustifyContent)):
        cycleFlexOption(gridContentCurrentJustifyContent, flexAlignContentOptions)
      if b.button("Parent align-content: " & flexAlignContentName(gridContentCurrentAlignContent)):
        cycleFlexOption(gridContentCurrentAlignContent, flexAlignContentOptions)
      if b.button("Child justify-self: " & flexAlignName(gridContentCurrentJustifySelf)):
        cycleFlexOption(gridContentCurrentJustifySelf, flexAlignSelfOptions)
      if b.button("Child align-self: " & flexAlignName(gridContentCurrentAlignSelf)):
        cycleFlexOption(gridContentCurrentAlignSelf, flexAlignSelfOptions)

    b.node("grid-content-distribution"):
      discard b.height(220).fillX().padding(4)
      discard b.gridLayout().gridTemplateColumns([gridAuto(), gridPx(100.0), gridAuto()])
      discard b.gridTemplateRows([gridPx(70.0), gridPx(70.0), gridPx(70.0)])
      discard b.gridGaps(6.0, 6.0)
      discard b.gridJustifyItems(gridContentCurrentJustifyItems).gridAlignItems(gridContentCurrentAlignItems)
      discard b.gridJustifyContent(gridContentCurrentJustifyContent).gridAlignContent(gridContentCurrentAlignContent)
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)

      b.node:
        discard b.gridJustifySelf(gridContentCurrentJustifySelf).gridAlignSelf(gridContentCurrentAlignSelf)
        discard b.gridArea(1, 1, 2, 1).fontSize(13.0)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HRed, 1.0)).padding(5)
        discard b.text("span 2")
      b.node:
        discard b.gridJustifySelf(gridContentCurrentJustifySelf).gridAlignSelf(gridContentCurrentAlignSelf)
        discard b.gridArea(3, 1).fontSize(15.0)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HBlue, 1.0)).padding(5)
        discard b.text("top")
      b.node:
        discard b.gridJustifySelf(gridContentCurrentJustifySelf).gridAlignSelf(gridContentCurrentAlignSelf)
        discard b.gridArea(1, 2, 3, 2)
        discard b.fillBackground().backgroundColor(accentVariation(accent, HGreen, 1.0)).padding(5)
        discard b.text("span 3 x 2")

# ---------------------------------------------------------------------------
# Type 4 #3 — Table layout showcase
# ---------------------------------------------------------------------------

proc buildTableLayoutExamples*(b: var UiBuilder) =
  let accent = b.themeStyle(UiStyleIndexAccent)[].fillColor
  b.layoutVertical("table-examples"):
    discard b.sizeToParentX().fitY().padding(8).gap(10)
    discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("3-column property table"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.tableLayout([tableColumnFit(), tableColumnProportional(5), tableColumnProportional(1)], 4.0, 2.0):
      discard b.fillX().fitY()
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)

      for h in ["Property", "Value", "Type"]:
        b.node:
          discard b.fitY().padding(5)
          discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexHeader)[].fillColor)
          discard b.text(h).fit()
          discard b.textColor(b.themeTextStyle(UiStyleIndexHeaderText)[].textColor)

      let rowNames  = ["pos.x",  "pos.y",  "size.x",  "size.y",  "layoutIdx"]
      let rowValues = ["42.50",  "88.00",  "200.00",  "120.00",  "0"        ]
      let rowTypes  = ["float32","float32","float32","float32",  "int32"    ]
      let rowBg0 = b.themeStyle(UiStyleIndexRow)[].fillColor
      let rowBg1 = b.themeStyle(UiStyleIndexRowAlt)[].fillColor
      for rowIdx in 0 ..< rowNames.len:
        let bg = if rowIdx mod 2 == 0: rowBg0 else: rowBg1
        b.node:
          discard b.fitY().padding(4)
          discard b.fillBackground().backgroundColor(bg)
          discard b.text(rowNames[rowIdx]).fit()
          discard b.textColor(b.themeTextStyle(UiStyleIndexLabelText)[].textColor)
        b.node:
          discard b.fitY().padding(4)
          discard b.fillBackground().backgroundColor(bg)
          discard b.text(rowValues[rowIdx]).fit()
          discard b.textColor(accentVariation(accent, HGreen, 1.0))
        b.node:
          discard b.fitY().padding(4)
          discard b.fillBackground().backgroundColor(bg)
          discard b.text(rowTypes[rowIdx]).fit()
          discard b.textColor(accentVariation(accent, HBlue, 1.0))

    b.label("2-column key-value list"):
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.tableLayout([tableColumnFit(), tableColumnFill()], 6.0, 3.0):
      discard b.fillX().fitY()
      discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)

      for h in ["Key", "Value"]:
        b.node:
          discard b.fitY().padding(5)
          discard b.fillBackground().backgroundColor(b.themeStyle(UiStyleIndexHeader)[].fillColor)
          discard b.text(h).fit()
          discard b.textColor(b.themeTextStyle(UiStyleIndexHeaderText)[].textColor)

      let kvKeys   = ["width",  "height", "refresh", "format"]
      let kvValues = ["1920 px","1080 px","60 Hz",   "RGBA8"  ]
      let kvBg0 = b.themeStyle(UiStyleIndexRow)[].fillColor
      let kvBg1 = b.themeStyle(UiStyleIndexRowAlt)[].fillColor
      for i in 0 ..< kvKeys.len:
        let bg = if i mod 2 == 0: kvBg0 else: kvBg1
        b.node:
          discard b.fitY().padding(5)
          discard b.fillBackground().backgroundColor(bg)
          discard b.text(kvKeys[i]).fit()
          discard b.textColor(b.themeTextStyle(UiStyleIndexLabelText)[].textColor)
        b.node:
          discard b.fitY().padding(5)
          discard b.fillBackground().backgroundColor(bg)
          discard b.text(kvValues[i]).fit()
          discard b.textColor(accentVariation(accent, HGreen, 1.0))
