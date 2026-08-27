import std/math
import nuigi
import colorpicker

proc themeTint(baseH, hueShift, sat, val, a: float32): UiColor =
  ## Build a color from `baseH` (the primary hue, 0..1) shifted by `hueShift`
  ## turns, with the given saturation/value/brightness and alpha.
  let hh = baseH + hueShift
  let f = hh - floor(hh)
  hsvToRgb(f, sat, val, a)

proc createThemeFromColor*(primary: UiColor): (seq[UiStyle], seq[UiNodeText]) =
  ## Build a complete theme from a single primary/accent color. The accent
  ## color is the primary itself; all accent variations (warm/hover/active
  ## highlights) and every surface/text color are derived from `primary`'s hue
  ## via HSV manipulation so the whole UI stays color-cohesive.
  let (h, s, v) = rgbToHsv(primary)
  var styles = initDefaultThemeStyles()
  var texts = initDefaultThemeTextStyles()

  # Shared palette pieces derived from the primary hue.
  let panelFill = themeTint(h, 0.0'f32, 0.25'f32, 0.18'f32, 1.0'f32)
  let softFill = themeTint(h, 0.0'f32, 0.30'f32, 0.13'f32, 0.96'f32)
  let panelBorder = themeTint(h, 0.0'f32, 0.30'f32, 0.42'f32, 1.0'f32)
  let accentWarm = themeTint(h, 0.15'f32, 0.75'f32, 0.92'f32, 1.0'f32)
  let redAccent = themeTint(h, 0.11'f32, 0.62'f32, 0.90'f32, 1.0'f32)
  let accentBright = themeTint(h, 0.0'f32, 0.55'f32, 0.95'f32, 1.0'f32)

  # --- surface / widget styles ---
  styles[int(UiStyleIndexWindow) - 1].fillColor = softFill
  styles[int(UiStyleIndexWindow) - 1].borderColor = panelBorder
  styles[int(UiStyleIndexWindowTitleBar) - 1].fillColor = themeTint(h, 0.0'f32, 0.25'f32, 0.24'f32, 1.0'f32)
  styles[int(UiStyleIndexWindowTitleBarCollapseHover) - 1].fillColor = themeTint(h, 0.0'f32, 0.25'f32, 0.34'f32, 1.0'f32)
  styles[int(UiStyleIndexWindowResizeHandle) - 1].fillColor = themeTint(h, 0.0'f32, 0.22'f32, 0.56'f32, 1.0'f32)
  styles[int(UiStyleIndexButton) - 1].fillColor = themeTint(h, 0.0'f32, 0.18'f32, 0.27'f32, 1.0'f32)
  styles[int(UiStyleIndexButton) - 1].borderColor = themeTint(h, 0.0'f32, 0.16'f32, 0.64'f32, 1.0'f32)
  styles[int(UiStyleIndexButtonHover) - 1].fillColor = redAccent
  styles[int(UiStyleIndexButtonHover) - 1].borderColor = themeTint(h, 0.0'f32, 0.16'f32, 0.64'f32, 1.0'f32)
  styles[int(UiStyleIndexCheckbox) - 1].fillColor = panelFill
  styles[int(UiStyleIndexCheckbox) - 1].borderColor = themeTint(h, 0.0'f32, 0.16'f32, 0.66'f32, 1.0'f32)
  styles[int(UiStyleIndexCheckboxHover) - 1].fillColor = themeTint(h, 0.0'f32, 0.18'f32, 0.24'f32, 1.0'f32)
  styles[int(UiStyleIndexCheckboxHover) - 1].borderColor = themeTint(h, 0.0'f32, 0.05'f32, 0.92'f32, 1.0'f32)
  styles[int(UiStyleIndexCheckboxMark) - 1].fillColor = accentWarm
  styles[int(UiStyleIndexSliderTrack) - 1].fillColor = panelFill
  styles[int(UiStyleIndexSliderTrack) - 1].borderColor = themeTint(h, 0.0'f32, 0.16'f32, 0.66'f32, 1.0'f32)
  styles[int(UiStyleIndexSliderTrackHover) - 1].fillColor = themeTint(h, 0.0'f32, 0.18'f32, 0.24'f32, 1.0'f32)
  styles[int(UiStyleIndexSliderTrackHover) - 1].borderColor = themeTint(h, 0.0'f32, 0.16'f32, 0.66'f32, 1.0'f32)
  styles[int(UiStyleIndexSliderFill) - 1].fillColor = primary
  styles[int(UiStyleIndexSliderFill) - 1].borderColor = primary
  styles[int(UiStyleIndexSliderHandle) - 1].fillColor = accentWarm
  styles[int(UiStyleIndexScrollBar) - 1].fillColor = themeTint(h, 0.0'f32, 0.20'f32, 0.16'f32, 0.92'f32)
  styles[int(UiStyleIndexScrollBarHandle) - 1].fillColor = themeTint(h, 0.0'f32, 0.18'f32, 0.56'f32, 1.0'f32)
  styles[int(UiStyleIndexScrollBarHandleHover) - 1].fillColor = themeTint(h, 0.0'f32, 0.12'f32, 0.72'f32, 1.0'f32)
  styles[int(UiStyleIndexTabBarHeader) - 1].fillColor = themeTint(h, 0.0'f32, 0.24'f32, 0.18'f32, 1.0'f32)
  styles[int(UiStyleIndexTabBarHeader) - 1].borderColor = themeTint(h, 0.0'f32, 0.26'f32, 0.40'f32, 1.0'f32)
  styles[int(UiStyleIndexTabBarItem) - 1].fillColor = themeTint(h, 0.0'f32, 0.18'f32, 0.24'f32, 1.0'f32)
  styles[int(UiStyleIndexTabBarItem) - 1].borderColor = themeTint(h, 0.0'f32, 0.18'f32, 0.50'f32, 1.0'f32)
  styles[int(UiStyleIndexTabBarItemActive) - 1].fillColor = themeTint(h, 0.0'f32, 0.16'f32, 0.40'f32, 1.0'f32)
  styles[int(UiStyleIndexTabBarItemActive) - 1].borderColor = accentWarm
  styles[int(UiStyleIndexTabBarContent) - 1].fillColor = themeTint(h, 0.0'f32, 0.20'f32, 0.14'f32, 1.0'f32)
  styles[int(UiStyleIndexTabBarContent) - 1].borderColor = themeTint(h, 0.0'f32, 0.24'f32, 0.32'f32, 1.0'f32)
  styles[int(UiStyleIndexTextField) - 1].fillColor = themeTint(h, 0.0'f32, 0.20'f32, 0.14'f32, 1.0'f32)
  styles[int(UiStyleIndexTextField) - 1].borderColor = themeTint(h, 0.0'f32, 0.18'f32, 0.48'f32, 1.0'f32)
  styles[int(UiStyleIndexTextFieldFocused) - 1].fillColor = themeTint(h, 0.0'f32, 0.18'f32, 0.18'f32, 1.0'f32)
  styles[int(UiStyleIndexTextFieldFocused) - 1].borderColor = accentBright
  styles[int(UiStyleIndexTextCursor) - 1].fillColor = themeTint(h, 0.0'f32, 0.03'f32, 0.95'f32, 1.0'f32)
  styles[int(UiStyleIndexMenu) - 1].fillColor = softFill
  styles[int(UiStyleIndexMenu) - 1].borderColor = themeTint(h, 0.0'f32, 0.24'f32, 0.34'f32, 1.0'f32)
  styles[int(UiStyleIndexMenuItem) - 1].fillColor = themeTint(h, 0.0'f32, 0.20'f32, 0.18'f32, 0.0'f32)
  styles[int(UiStyleIndexMenuItem) - 1].borderColor = themeTint(h, 0.0'f32, 0.20'f32, 0.18'f32, 0.0'f32)
  styles[int(UiStyleIndexMenuItemHover) - 1].fillColor = themeTint(h, 0.0'f32, 0.18'f32, 0.30'f32, 1.0'f32)
  styles[int(UiStyleIndexMenuItemHover) - 1].borderColor = themeTint(h, 0.0'f32, 0.18'f32, 0.30'f32, 1.0'f32)
  styles[int(UiStyleIndexMenuBar) - 1].fillColor = themeTint(h, 0.0'f32, 0.28'f32, 0.24'f32, 1.0'f32)
  styles[int(UiStyleIndexMenuBar) - 1].borderColor = panelBorder
  styles[int(UiStyleIndexPanel) - 1].fillColor = panelFill
  styles[int(UiStyleIndexPanel) - 1].borderColor = panelBorder
  styles[int(UiStyleIndexStage) - 1].fillColor = themeTint(h, 0.0'f32, 0.22'f32, 0.18'f32, 1.0'f32)
  styles[int(UiStyleIndexStage) - 1].borderColor = themeTint(h, 0.0'f32, 0.26'f32, 0.32'f32, 1.0'f32)
  styles[int(UiStyleIndexCard) - 1].fillColor = themeTint(h, 0.0'f32, 0.22'f32, 0.20'f32, 1.0'f32)
  styles[int(UiStyleIndexCard) - 1].borderColor = panelBorder
  styles[int(UiStyleIndexHeader) - 1].fillColor = themeTint(h, 0.0'f32, 0.24'f32, 0.26'f32, 1.0'f32)
  styles[int(UiStyleIndexHeader) - 1].borderColor = themeTint(h, 0.0'f32, 0.24'f32, 0.36'f32, 1.0'f32)
  styles[int(UiStyleIndexRow) - 1].fillColor = themeTint(h, 0.0'f32, 0.20'f32, 0.14'f32, 1.0'f32)
  styles[int(UiStyleIndexRow) - 1].borderColor = themeTint(h, 0.0'f32, 0.20'f32, 0.14'f32, 1.0'f32)
  styles[int(UiStyleIndexRowAlt) - 1].fillColor = themeTint(h, 0.0'f32, 0.20'f32, 0.18'f32, 1.0'f32)
  styles[int(UiStyleIndexRowAlt) - 1].borderColor = themeTint(h, 0.0'f32, 0.20'f32, 0.18'f32, 1.0'f32)
  styles[int(UiStyleIndexTooltip) - 1].fillColor = themeTint(h, 0.0'f32, 0.22'f32, 0.12'f32, 0.98'f32)
  styles[int(UiStyleIndexTooltip) - 1].borderColor = themeTint(h, 0.0'f32, 0.28'f32, 0.44'f32, 1.0'f32)
  styles[int(UiStyleIndexAccent) - 1].fillColor = primary
  styles[int(UiStyleIndexAccent) - 1].borderColor = primary

  # --- text styles ---
  let defaultText = themeTint(h, 0.0'f32, 0.05'f32, 0.92'f32, 1.0'f32)
  let whiteText = themeTint(h, 0.0'f32, 0.03'f32, 0.96'f32, 1.0'f32)
  let mutedText = themeTint(h, 0.0'f32, 0.10'f32, 0.86'f32, 1.0'f32)
  let headingText = themeTint(h, 0.08'f32, 0.25'f32, 0.95'f32, 1.0'f32)
  let goldText = themeTint(h, 0.45'f32, 0.70'f32, 0.88'f32, 1.0'f32)
  let hintText = themeTint(h, 0.0'f32, 0.10'f32, 0.50'f32, 1.0'f32)

  texts[int(UiStyleIndexDefaultText) - 1].textColor = defaultText
  texts[int(UiStyleIndexSmallText) - 1].textColor = defaultText
  texts[int(UiStyleIndexLargeText) - 1].textColor = defaultText
  texts[int(UiStyleIndexExtraLargeText) - 1].textColor = defaultText
  texts[int(UiStyleIndexButtonText) - 1].textColor = whiteText
  texts[int(UiStyleIndexMenuItemHoverText) - 1].textColor = whiteText
  texts[int(UiStyleIndexMenuItemText) - 1].textColor = whiteText
  texts[int(UiStyleIndexLabelText) - 1].textColor = whiteText
  texts[int(UiStyleIndexWindowText) - 1].textColor = defaultText
  texts[int(UiStyleIndexWindowTitleBarText) - 1].textColor = whiteText
  texts[int(UiStyleIndexWindowContentText) - 1].textColor = defaultText
  texts[int(UiStyleIndexButtonHoverText) - 1].textColor = whiteText
  texts[int(UiStyleIndexCheckboxText) - 1].textColor = defaultText
  texts[int(UiStyleIndexCheckboxHoverText) - 1].textColor = defaultText
  texts[int(UiStyleIndexCheckboxMarkText) - 1].textColor = goldText
  texts[int(UiStyleIndexSliderText) - 1].textColor = whiteText
  texts[int(UiStyleIndexTabBarHeaderText) - 1].textColor = defaultText
  texts[int(UiStyleIndexTabBarItemText) - 1].textColor = whiteText
  texts[int(UiStyleIndexTabBarItemActiveText) - 1].textColor = whiteText
  texts[int(UiStyleIndexTabBarContentText) - 1].textColor = defaultText
  texts[int(UiStyleIndexTextFieldText) - 1].textColor = whiteText
  texts[int(UiStyleIndexTextFieldFocusedText) - 1].textColor = whiteText
  texts[int(UiStyleIndexTextFieldHintText) - 1].textColor = hintText
  texts[int(UiStyleIndexHeadingText) - 1].textColor = headingText
  texts[int(UiStyleIndexMutedText) - 1].textColor = mutedText
  texts[int(UiStyleIndexHeaderText) - 1].textColor = goldText

  (styles, texts)
