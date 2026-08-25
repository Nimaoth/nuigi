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
    discard b.backgroundColor(rgba(0.09, 0.11, 0.16, 1.0))

    b.label("nuigi Demo"):
      discard b.fontSize(28).textColor(rgba(0.98, 0.92, 0.70, 1.0))

    b.labelWrapped("This window is a self-contained tour of nuigi. Each tab above demonstrates one feature, or a small composition of features."):
      discard b.fillX().textColor(rgba(0.84, 0.88, 0.94, 1.0)).fontSize(14)

    b.label("Use the tabs to explore:"):
      discard b.textColor(rgba(0.96, 0.92, 0.78, 1.0)).fontSize(15)

    b.layoutVertical("intro-list"):
      discard b.fillX().fitY().padding(8).gap(4)
      discard b.backgroundColor(rgba(0.13, 0.16, 0.22, 1.0))
      for line in [
        "Fill / Fit — how a node claims space from its parent",
        "Anchors — position relative to the parent using 0..1 fractions",
        "Layout direction — vertical / horizontal + reverse",
        "Align — centering and vertical alignment",
        "Gap & Padding, Styles, Text, Transforms, Animations ...",
        "Combined layouts, widgets, flex / grid / table, virtual lists",
      ]:
        b.label(line):
          discard b.fillX().fitY().textColor(rgba(0.86, 0.90, 0.96, 1.0)).fontSize(13)

