import nuigi, widgets, mymath, arena, array_view
import std/monotimes, std/strutils, std/math, std/syncio

{.passL: "-Lbuild".}

when defined(nimony):
  import std/assertions

const NumNodes = 10_000
const WarmupIters = 3
const BenchIters = 100

proc fixedMeasureText(text: openArray[char], fontId: int16, fontSize: float32, maxWidth: float32): UiTextArrangement {.gcsafe, raises: [].} =
  let _ = fontId
  let naturalWidth = text.len.float32 * 10.0'f32
  let lineCount =
    if maxWidth > 0.0'f32 and naturalWidth > maxWidth:
      int((naturalWidth + maxWidth - 1.0'f32) / maxWidth)
    else:
      1
  result = UiTextArrangement()
  result.fontSize = fontSize
  result.size = vec2(if maxWidth >= 0.0'f32: min(naturalWidth, maxWidth) else: naturalWidth, lineCount.float32 * 20.0'f32)

proc stats(samples: openArray[float64], label: string) =
  if samples.len == 0:
    echo label & ": no valid samples"
    return

  var sum = 0.0'f64
  var minVal = samples[0]
  var maxVal = samples[0]
  for s in samples:
    sum += s
    if s < minVal: minVal = s
    if s > maxVal: maxVal = s
  let mean = sum / samples.len.float64

  var varianceSum = 0.0'f64
  for s in samples:
    let diff = s - mean
    varianceSum += diff * diff
  let stddev = sqrt(varianceSum / samples.len.float64)

  var filtered = newSeq[float64]()
  for s in samples:
    if abs(s - mean) <= 2.0 * stddev:
      filtered.add s
  let outliers = samples.len - filtered.len

  if filtered.len > 0:
    var fSum = 0.0'f64
    var fMin = filtered[0]
    var fMax = filtered[0]
    for s in filtered:
      fSum += s
      if s < fMin: fMin = s
      if s > fMax: fMax = s
    let fMean = fSum / filtered.len.float64
    var fVarSum = 0.0'f64
    for s in filtered:
      let d = s - fMean
      fVarSum += d * d
    let fStddev = sqrt(fVarSum / filtered.len.float64)

    let rawRate = (NumNodes.float64 * 1000.0 / mean).int
    let rawFrame = int(NumNodes.float64 * 16.0 / mean)
    let rawPerNode = mean * 1000.0 / NumNodes.float64
    let rate = (NumNodes.float64 * 1000.0 / fMean).int
    let perFrame = int(NumNodes.float64 * 16.0 / fMean)
    let perNode = fMean * 1000.0 / NumNodes.float64

    echo label
    echo "  samples: " & $samples.len & " (" & $outliers & " outliers removed)"
    echo "  raw:      " & mean.formatFloat(ffDecimal, 1) & " ms ± " & stddev.formatFloat(ffDecimal, 1) & " ms  [" & minVal.formatFloat(ffDecimal, 1) & ".." & maxVal.formatFloat(ffDecimal, 1) & "]  (" & $rawRate & " nodes/sec, " & $rawFrame & " nodes/16ms, " & rawPerNode.formatFloat(ffDecimal, 2) & " µs/node)"
    echo "  filtered: " & fMean.formatFloat(ffDecimal, 1) & " ms ± " & fStddev.formatFloat(ffDecimal, 1) & " ms  [" & fMin.formatFloat(ffDecimal, 1) & ".." & fMax.formatFloat(ffDecimal, 1) & "]  (" & $rate & " nodes/sec, " & $perFrame & " nodes/16ms, " & perNode.formatFloat(ffDecimal, 2) & " µs/node)"
  else:
    echo label & ": all samples were outliers"

template benchReused(b: var UiBuilder, label: string, iter: untyped): untyped =
  block:
    for w in 0 ..< WarmupIters:
      discard b.beginUiFrame(800.0, 600.0)
      iter
      b.endUiFrame(false)
    var samples = newSeq[float64](BenchIters)
    for i in 0 ..< BenchIters:
      let start = getMonoTime()
      discard b.beginUiFrame(800.0, 600.0)
      iter
      b.endUiFrame(false)
      let stop = getMonoTime()
      let elapsedNs = ticks(stop) - ticks(start)
      samples[i] = elapsedNs.float64 / 1_000_000.0
    stats(samples, label)
    # echo "num frame.texts: ", b.frame.texts.len
    # echo "num frame.styles: ", b.frame.styles.len
    # echo "num frame.gaps: ", b.frame.gaps.len
    # echo "num frame.anchors: ", b.frame.anchors.len
    # echo "num frame.transforms: ", b.frame.transforms.len
    # echo "num frame.customCommands: ", b.frame.customCommands.len

proc runNoSideData() =
  var b = newBuilder(fixedMeasureText)
  benchReused(b, "no-side-data"):
    for i in 0 ..< NumNodes:
      discard b.beginNode().endNode()

proc runSomeSideData() =
  var b = newBuilder(fixedMeasureText)
  benchReused(b, "some-side-data"):
    for i in 0 ..< NumNodes:
      discard b.beginNode()
      discard b.text("hello").fillBackground().backgroundColor(rgba(0.2, 0.3, 0.4, 1.0))
      discard b.endNode()

proc runAllSideData() =
  var b = newBuilder(fixedMeasureText)
  benchReused(b, "all-side-data"):
    for i in 0 ..< NumNodes:
      discard b.beginNode()
      discard b.text("hello")
      discard b.fillBackground().backgroundColor(rgba(0.2, 0.3, 0.4, 1.0))
      discard b.borderWidth(2.0).cornerRadius(4.0)
      discard b.gap(8.0)
      discard b.anchors(vec2(0, 0), vec2(1, 1))
      discard b.transformOffset(10.0, 20.0).transformScale(1.5, 1.5)
      discard b.endNode()

proc runMixedSizes() =
  var b = newBuilder(fixedMeasureText)
  benchReused(b, "mixed-sizes (25% each)"):
    for i in 0 ..< NumNodes:
      discard b.beginNode()
      let category = i mod 4
      if category == 0:
        discard b.text("item").fillBackground()
      elif category == 1:
        discard b.text("wide").fillBackground()
        discard b.anchors(vec2(0, 0), vec2(1, 1))
      elif category == 2:
        discard b.fillBackground().backgroundColor(rgba(0.5, 0.5, 0.5, 1.0))
        discard b.transformOffset(5.0, 5.0)
      discard b.endNode()

proc runLabelBench() =
  var b = newBuilder(fixedMeasureText)
  benchReused(b, "label"):
    for i in 0 ..< NumNodes:
      b.label("x"):
        discard b.fillBackground().backgroundColor(rgba(0.2, 0.3, 0.4, 1.0))

proc runButtonBench() =
  var b = newBuilder(fixedMeasureText)
  benchReused(b, "button"):
    for i in 0 ..< NumNodes:
      discard b.button("x")

proc runCheckboxBench() =
  var b = newBuilder(fixedMeasureText)
  benchReused(b, "checkbox"):
    for i in 0 ..< NumNodes:
      var v = false
      discard b.checkbox("x", v)

proc runSliderBench() =
  var b = newBuilder(fixedMeasureText)
  benchReused(b, "slider"):
    for i in 0 ..< NumNodes:
      var v = 0.5'f32
      discard b.slider("x", v, 0.0'f32, 1.0'f32)

when isMainModule:
  echo "UiNode creation benchmark (" & $NumNodes & " nodes per frame, " & $WarmupIters & " warmup, " & $BenchIters & " iterations, b reused, 16ms frame budget)"
  echo ""
  runNoSideData()
  echo ""
  runSomeSideData()
  echo ""
  runAllSideData()
  echo ""
  runMixedSizes()
  echo ""
  runLabelBench()
  echo ""
  runButtonBench()
  echo ""
  runCheckboxBench()
  echo ""
  runSliderBench()
  echo ""
  echo "done."
