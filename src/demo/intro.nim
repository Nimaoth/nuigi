include "../compat2"
import sdl3
import "../nuigi", "../widgets"

when not defined(nimony):
  proc forceNim2ToIncludeUiBuilderInTheGeneratedCFileIntro*(): UiBuilder {.exportc.} = UiBuilder()

# ---------------------------------------------------------------------------
# Type 0 — Intro page
# ---------------------------------------------------------------------------

proc buildIntroPage*(b: var UiBuilder) =
  b.layoutVertical("intro-page"):
    discard b.fillX().fitY().padding(12).gap(10)

    b.label("nuigi demo"):
      discard b.copyTextStyleIndex(UiStyleIndexHeadingText).fontSize(28)

    b.labelWrapped("This window is a demo of nuigi. In the settings window on the left you can toggle different windows."):
      discard b.fillX().copyTextStyleIndex(UiStyleIndexMutedText).fontSize(14)

    if b.button("Open GitHub repository"):
      discard openURL("https://github.com/Nimaoth/nuigi")
