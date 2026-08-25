include "../compat2"
import "../nuigi", "../widgets"

when not defined(nimony):
  proc forceNim2ToIncludeUiBuilderInTheGeneratedCFileIntro*(): UiBuilder {.exportc.} = UiBuilder()

# ---------------------------------------------------------------------------
# Type 0 — Intro page
# ---------------------------------------------------------------------------

proc buildIntroPage*(b: var UiBuilder) =
  b.layoutVertical("intro-page"):
    discard b.fillX().fitY().padding(12).gap(10)
    discard b.fillBackground().styleIndex(UiStyleIndexWindow)

    b.label("nuigi Demo"):
      discard b.copyTextStyleIndex(UiStyleIndexHeadingText).fontSize(28)

    b.labelWrapped("This window is a self-contained tour of nuigi. Each tab above demonstrates one feature, or a small composition of features."):
      discard b.fillX().copyTextStyleIndex(UiStyleIndexMutedText).fontSize(14)

    b.label("Use the tabs to explore:"):
      discard b.copyTextStyleIndex(UiStyleIndexHeadingText).fontSize(15)

    b.layoutVertical("intro-list"):
      discard b.fillX().fitY().padding(8).gap(4)
      discard b.fillBackground().styleIndex(UiStyleIndexPanel)
      for line in [
        "Fill / Fit — how a node claims space from its parent",
        "Anchors — position relative to the parent using 0..1 fractions",
        "Layout direction — vertical / horizontal + reverse",
        "Align — centering and vertical alignment",
        "Gap & Padding, Styles, Text, Transforms, Animations ...",
        "Combined layouts, widgets, flex / grid / table, virtual lists",
      ]:
        b.label(line):
          discard b.fillX().fitY().copyTextStyleIndex(UiStyleIndexMutedText).fontSize(13)
