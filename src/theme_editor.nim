import nuigi
import mymath
import profiler

import widgets, windows
import dynamic_virtuallist
import theme

include compat2

const
  ThemeEditorItemHeight = 150.0'f32
  ThemeTextEditorItemHeight = 120.0'f32

type
  ListFontsFun* = proc(): seq[(string, UiFontId)] {.raises: [], gcsafe.}
  ResolveFontFun* = proc(name: string): UiFontId {.raises: [], gcsafe.}

  ThemeEditor* = object
    highlightedStyleIndex*: int
    lastHighlightedStyleIndex*: int
    activeTabIndex*: int
    primaryColor*: UiColor
    cornerRadiusDisabled*: bool
    listStorage: UiDynamicVirtualListStorage
    listFonts*: nil ListFontsFun
    resolveFont*: nil ResolveFontFun

func themeStyleName(styleIndex: int): string =
  if styleIndex <= 0 or styleIndex > UiThemeStyleSlotCount:
    return "Unknown"
  for e in low(UiStyleIndex) .. high(UiStyleIndex):
    if int(e) == styleIndex:
      let name = $e
      const prefix = "UiStyleIndex"
      if name.len > prefix.len and name[0 .. prefix.len - 1] == prefix:
        return name[prefix.len .. ^1]
      return name
  "Style " & $styleIndex

proc editFloatSlider(b: var UiBuilder, labelText: string, value: var float32, minValue, maxValue: float32) =
  discard b.pushId(labelText)
  discard b.slider(labelText, value, minValue, maxValue, value)
  discard b.popId()

proc editFloatRow4(b: var UiBuilder,
    rowId: string,
    aLabel: string, aValue: var float32, aMin, aMax: float32,
    bLabel: string, bValue: var float32, bMin, bMax: float32,
    cLabel: string, cValue: var float32, cMin, cMax: float32,
    dLabel: string, dValue: var float32, dMin, dMax: float32) =
  b.layoutHorizontal(rowId):
    discard b.fillX().fitY().gap(8)
    editFloatSlider(b, aLabel, aValue, aMin, aMax)
    editFloatSlider(b, bLabel, bValue, bMin, bMax)
    editFloatSlider(b, cLabel, cValue, cMin, cMax)
    editFloatSlider(b, dLabel, dValue, dMin, dMax)

proc labeledColorPicker(b: var UiBuilder, labelText: string, value: var UiColor) =
  discard b.pushId(labelText)
  b.layoutHorizontal("theme-editor-labeled-color-picker"):
    discard b.fitX().fitY().gap(4)
    b.node("theme-editor-labeled-color-picker-label"):
      discard b.fitX().fitY().alignCenter()
      discard b.text(labelText)
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
    discard b.colorPicker(value)
  discard b.popId()

proc buildThemeStyleEntry(b: var UiBuilder, itemIndex: int, userData: int) {.nimcall.} =
  prof("buildThemeStyleEntry")
  if userData == 0:
    return
  let themeEditor = cast[ptr ThemeEditor](userData)
  let styleIndex = itemIndex + 1
  if styleIndex <= 0 or styleIndex > UiThemeStyleSlotCount:
    return

  var styleValue = b.themeStyle(styleIndex)[]
  let styleName = themeStyleName(styleIndex)
  let isHighlighted = themeEditor.highlightedStyleIndex == styleIndex
  let rowBackground =
    if isHighlighted:
      accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, 0.0'f32, 0.5'f32)
    elif itemIndex mod 2 == 0:
      b.themeStyle(UiStyleIndexRow)[].fillColor
    else:
      b.themeStyle(UiStyleIndexRowAlt)[].fillColor

  discard b.layout(LayoutVertical)
  discard b.padding(8).fitY()
  discard b.gap(6)
  discard b.fillBackground()
  discard b.backgroundColor(rowBackground)
  discard b.borderWidth(if isHighlighted: 2.0'f32 else: 1.0'f32)
  discard b.borderColor(if isHighlighted: accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, -0.46'f32, 1.0) else: b.themeStyle(UiStyleIndexStage)[].borderColor)
  discard b.cornerRadius(6)

  b.node("theme-editor-style-title"):
    discard b.fitX().fitY()
    discard b.text($styleIndex & ". " & styleName)
    discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

  b.layoutHorizontal("theme-editor-style-preview-row"):
    discard b.fillX().fitY().gap(12)

    discard b.setThemeStyle(styleIndex, styleValue)
    b.node("theme-editor-style-preview"):
      discard b.styleIndex(styleIndex)
      discard b.fillX().fitY()
      discard b.fillBackground()
      discard b.text("Preview Text")

  editFloatRow4(
    b,
    "theme-editor-style-layout-row",
    "paddingX", styleValue.paddingX, 0.0'f32, 32.0'f32,
    "paddingY", styleValue.paddingY, 0.0'f32, 32.0'f32,
    "borderWidth", styleValue.borderWidth, 0.0'f32, 8.0'f32,
    "cornerRadius", styleValue.cornerRadius, 0.0'f32, 16.0'f32,
  )

  editFloatRow4(
    b,
    "theme-editor-corner-radii-row",
    "cornerTL", styleValue.cornerRadii.topLeft, 0.0'f32, 32.0'f32,
    "cornerTR", styleValue.cornerRadii.topRight, 0.0'f32, 32.0'f32,
    "cornerBR", styleValue.cornerRadii.bottomRight, 0.0'f32, 32.0'f32,
    "cornerBL", styleValue.cornerRadii.bottomLeft, 0.0'f32, 32.0'f32,
  )

  editFloatRow4(
    b,
    "theme-editor-border-widths-row",
    "borderLeft", styleValue.borderWidths.left, 0.0'f32, 8.0'f32,
    "borderTop", styleValue.borderWidths.top, 0.0'f32, 8.0'f32,
    "borderRight", styleValue.borderWidths.right, 0.0'f32, 8.0'f32,
    "borderBottom", styleValue.borderWidths.bottom, 0.0'f32, 8.0'f32,
  )

  b.layoutHorizontal("theme-editor-style-colors-row"):
    discard b.fillX().fitY().gap(12)
    labeledColorPicker(b, "Fill", styleValue.fillColor)
    labeledColorPicker(b, "Border", styleValue.borderColor)

  b.layoutHorizontal("theme-editor-border-colors-row"):
    discard b.fillX().fitY().gap(12)
    labeledColorPicker(b, "Border Left", styleValue.borderColors.left)
    labeledColorPicker(b, "Border Top", styleValue.borderColors.top)
    labeledColorPicker(b, "Border Right", styleValue.borderColors.right)
    labeledColorPicker(b, "Border Bottom", styleValue.borderColors.bottom)

  discard b.setThemeStyle(styleIndex, styleValue)

proc buildThemeTextStyleEntry(b: var UiBuilder, itemIndex: int, userData: int) {.nimcall.} =
  prof("buildThemeTextStyleEntry")
  if userData == 0:
    return
  let themeEditor = cast[ptr ThemeEditor](userData)
  if itemIndex < 0 or itemIndex > b.themeTextStyles.len:
    return

  var textStyleValue = if itemIndex == 0: b.defaultText.addr else: b.themeTextStyles[itemIndex - 1].addr

  let fonts = if themeEditor.listFonts != nil: themeEditor.listFonts() else: newSeq[(string, UiFontId)]()
  var fontNames = newSeq[string](fonts.len)
  for fi in 0 ..< fonts.len:
    fontNames[fi] = fonts[fi][0]
  var selectedFontIdx = 0
  for fi in 0 ..< fonts.len:
    if fonts[fi][1] == textStyleValue.fontId:
      selectedFontIdx = fi
      break

  let isHighlighted = false
  let rowBackground =
    if isHighlighted:
      accentVariation(b.themeStyle(UiStyleIndexAccent)[].fillColor, 0.0'f32, 0.5'f32)
    elif itemIndex mod 2 == 0:
      b.themeStyle(UiStyleIndexRow)[].fillColor
    else:
      b.themeStyle(UiStyleIndexRowAlt)[].fillColor

  discard b.layout(LayoutVertical)
  discard b.padding(8).fitY()
  discard b.gap(6)
  discard b.fillBackground()
  discard b.backgroundColor(rowBackground)
  discard b.borderWidth(1.0'f32)
  discard b.borderColor(b.themeStyle(UiStyleIndexStage)[].borderColor)
  discard b.cornerRadius(6)

  b.node("theme-editor-text-style-title"):
    discard b.fitX().fitY()
    discard b.text($itemIndex & ". Text Style")
    discard b.textColor(b.themeTextStyle(UiStyleIndexHeadingText)[].textColor)

  b.layoutHorizontal("theme-editor-text-style-row"):
    discard b.fillX().fitY().gap(12)

    b.node("theme-editor-text-style-meta"):
      discard b.fitX().fitY()
      discard b.text("fontId: " & $textStyleValue.fontId)
      discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.node("theme-editor-text-style-preview"):
      discard b.fillX().fitY()
      discard b.fillBackground()
      discard b.text(textStyleValue.text.value)
      discard b.fontSize(textStyleValue.fontSize)
      discard b.fontId(textStyleValue.fontId)

  b.layoutHorizontal("theme-editor-text-style-edit-row"):
    discard b.fillX().fitY().gap(12)

    discard slider(b, "fontSize", textStyleValue.fontSize, 4.0'f32, 128.0'f32, 16)

    if fonts.len > 0:
      b.layoutHorizontal("theme-editor-text-style-font-row"):
        discard b.fillX().fitY().gap(12)
        if dropdown(b, fontNames, selectedFontIdx, "Font"):
          textStyleValue.fontId = fonts[selectedFontIdx][1]

const ThemeTitle = "Theme Editor"

let themeEditorId* = ThemeTitle.hashChars.UiNodeId

proc rebuildTheme(themeEditor: var ThemeEditor, b: var UiBuilder) =
  ## Rebuild the active theme from the editor's primary color (or the built-in
  ## default when none is chosen) and optionally strip all corner radii.
  var styles: seq[UiStyle]
  var texts: seq[UiNodeText]
  if themeEditor.primaryColor.a > 0.0'f32:
    (styles, texts) = createThemeFromColor(themeEditor.primaryColor)
  else:
    styles = initDefaultThemeStyles()
    texts = initDefaultThemeTextStyles()
  if themeEditor.cornerRadiusDisabled:
    for i in 0 ..< styles.len:
      styles[i].cornerRadius = 0.0'f32
      styles[i].cornerRadii = UiCornerRadii()
  b.themeStyles = styles
  b.themeTextStyles = texts

proc themeEditor*(b: var UiBuilder, themeEditor: var ThemeEditor): var UiBuilder {.discardable.} =
  prof("themeEditor")

  let cutoff = b.nodes.len
  let trackHoveredStyle = ModAlt in b.frameCtx.input.modsDown
  themeEditor.highlightedStyleIndex = 0
  let hoveredIdx = b.currentNodeIndex(b.previousOutput.hoveredId)
  if hoveredIdx >= 0 and hoveredIdx < cutoff:
    let hoveredNode = b.nodes[hoveredIdx]
    themeEditor.highlightedStyleIndex =
      if hoveredNode.styleIndex > 0:
        int(hoveredNode.styleIndex)
      else:
        int(UiStyleIndexDefault)

  b.window(ThemeTitle, 170, 180, 900.0'f32, 800.0'f32):
    b.layoutVertical("theme-editor-root"):
      discard b.fillX().fillY().gap(6)

      b.node("theme-editor-header"):
        discard b.fitX().fitY()
        discard b.text("Adjust shared theme slots. Preview nodes below use the edited style directly.")
        discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

      b.layoutHorizontal("theme-editor-primary-color"):
        discard b.fitX().fitY().gap(8)
        b.node("theme-editor-primary-color-label"):
          discard b.fitX().fitY().alignCenter()
          discard b.text("Primary / Accent Color")
          discard b.textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
        if b.colorPicker(themeEditor.primaryColor):
          rebuildTheme(themeEditor, b)
        if b.button("Restore Defaults"):
          themeEditor.primaryColor = UiColor()
          rebuildTheme(themeEditor, b)
        var cornerEnabled = not themeEditor.cornerRadiusDisabled
        if b.checkbox("Corner Radius", cornerEnabled):
          themeEditor.cornerRadiusDisabled = not cornerEnabled
          rebuildTheme(themeEditor, b)

      b.tabBar(["Styles", "Other"], themeEditor.activeTabIndex):
        case themeEditor.activeTabIndex
        of 0:
          b.node("theme-editor-list"):
            discard b.fillX().fillY()
            let listIdx = b.stack[^1]
            let listViewportHeight =
              if listIdx >= 0 and listIdx < b.nodes.len:
                max(0.0'f32, b.nodes[listIdx].size.y)
              else:
                0.0'f32

            if themeEditor.highlightedStyleIndex > 0 and themeEditor.highlightedStyleIndex <= UiThemeStyleSlotCount:
              if trackHoveredStyle and
                  themeEditor.highlightedStyleIndex != themeEditor.lastHighlightedStyleIndex and
                  themeEditor.listStorage != nil:
                themeEditor.listStorage.centerItem(
                  themeEditor.highlightedStyleIndex - 1,
                  listViewportHeight)
              themeEditor.lastHighlightedStyleIndex = themeEditor.highlightedStyleIndex
            else:
              themeEditor.lastHighlightedStyleIndex = 0

            themeEditor.listStorage = b.dynamicVirtualList(
              UiThemeStyleSlotCount,
              ThemeEditorItemHeight,
              buildThemeStyleEntry,
              cast[int](themeEditor.addr))
        else:
          b.node("theme-editor-text-style-list"):
            discard b.fillX().fillY()
            let textStyleListCount = b.themeTextStyles.len + 1
            if textStyleListCount > 0:
              discard b.dynamicVirtualList(
                textStyleListCount,
                ThemeTextEditorItemHeight,
                buildThemeTextStyleEntry,
                cast[int](themeEditor.addr))

  b