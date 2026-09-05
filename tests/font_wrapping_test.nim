import nuigi/text/fonts

proc lineCount(arrangement: UiTextArrangement): int =
  var baselines: seq[float32] = @[]
  for glyph in arrangement.glyphs:
    var found = false
    for baseline in baselines:
      if abs(baseline - glyph.pos.y) < 0.001'f32:
        found = true
        break
    if not found:
      baselines.add(glyph.pos.y)
  baselines.len

proc requireWithinWidth(arrangement: UiTextArrangement, maxWidth: float32) =
  doAssert arrangement.size.x <= maxWidth + 0.01'f32

proc main() =
  var renderer = FontRender()
  doAssert renderer.init(flags = {})
  defer: renderer.deinit()

  let fontId = renderer.addFontFace("assets/dontuse/fonts/DejaVuSansMono.ttf")
  doAssert fontId >= 0

  let fontSize = 20.0'f32
  let unlimited = renderer.arrangeText("hello world", fontSize, fontId)
  let prefix = renderer.arrangeText("hello ", fontSize, fontId)
  let suffix = renderer.arrangeText("world", fontSize, fontId)
  let wrapWidth = max(prefix.size.x, suffix.size.x) + 0.1'f32
  let wrapped = renderer.arrangeText("hello world", fontSize, fontId, wrapWidth)
  doAssert unlimited.lineCount == 1
  doAssert wrapped.lineCount == 2
  doAssert wrapped.size.y > unlimited.size.y
  wrapped.requireWithinWidth(wrapWidth)

  for text in [
      "one two three four five",
      "one  two   three",
      "a bb ccc dddd eeeee",
      "word word word word word word",
    ]:
    for width in [40.0'f32, 60.0'f32, 80.0'f32, 100.0'f32]:
      let stressed = renderer.arrangeText(text, fontSize, fontId, width)
      stressed.requireWithinWidth(width)
      doAssert stressed.lineCount > 1

  let exactWord = renderer.arrangeText("exact", fontSize, fontId)
  let separatorOverflow = renderer.arrangeText(
    "exact next", fontSize, fontId, exactWord.size.x + 0.01'f32)
  separatorOverflow.requireWithinWidth(exactWord.size.x + 0.01'f32)
  doAssert separatorOverflow.lineCount == 2

  let oneWideGlyph = renderer.arrangeText("W", fontSize, fontId)
  let hardWrapped = renderer.arrangeText("WWW", fontSize, fontId, oneWideGlyph.size.x + 0.1'f32)
  doAssert hardWrapped.lineCount == 3

  let explicitLines = renderer.arrangeText("one\ntwo", fontSize, fontId)
  doAssert explicitLines.lineCount == 2

  echo "font fallback wrapping tests passed"

main()