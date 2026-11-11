## Debug captures of the terminal backend's last rendered cell grid.
##
## - `captureText`: character grid with row/column rulers and right edge markers.
## - `captureColorMaps`: one symbol per distinct background/foreground color, plus legends.
## - `captureHtml`: colored HTML page which can be viewed or screenshotted in a browser.

import std/[hashes, strutils, tables]
import ./terminal

const ColorSymbols = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

proc hash(color: TerminalColor): Hash =
  hash((color.r, color.g, color.b))

proc hex(color: TerminalColor): string =
  "#" & color.r.toHex(2) & color.g.toHex(2) & color.b.toHex(2)

proc isBlank(cell: TerminalCell): bool =
  cell.grapheme.len == 0 or cell.grapheme == " "

proc appendColumnRulers(output: var string, width: int, prefix: int) =
  if width > 100:
    output.add repeat(' ', prefix)
    for x in 0 ..< width:
      output.add(if x mod 100 == 0: char(ord('0') + (x div 100) mod 10) else: ' ')
    output.add '\n'
  output.add repeat(' ', prefix)
  for x in 0 ..< width:
    output.add(if x mod 10 == 0: char(ord('0') + (x div 10) mod 10) else: ' ')
  output.add '\n'
  output.add repeat(' ', prefix)
  for x in 0 ..< width:
    output.add char(ord('0') + x mod 10)
  output.add '\n'

proc captureText*(backend: TerminalBackend): string =
  ## Character grid. Each row is `NNN|<cells>|`; wide graphemes occupy their
  ## first cell and the continuation cell is omitted.
  result = "size " & $backend.width & "x" & $backend.height & "\n"
  result.appendColumnRulers(backend.width, 4)
  for y in 0 ..< backend.height:
    result.add align($y, 3)
    result.add '|'
    for x in 0 ..< backend.width:
      let cell = backend.cell(x, y)
      if cell.continuation:
        continue
      result.add(if cell.grapheme.len == 0: " " else: cell.grapheme)
    result.add "|\n"

proc captureColorMaps*(backend: TerminalBackend): string =
  ## Background map (every cell) and foreground map (only cells with visible
  ## glyphs; blank cells are `.`), with legends mapping symbols to colors.
  var bgSymbols, fgSymbols: Table[TerminalColor, int]
  var bgOrder, fgOrder: seq[TerminalColor]
  var bgCounts, fgCounts: seq[int]

  proc symbolFor(symbols: var Table[TerminalColor, int], order: var seq[TerminalColor],
      counts: var seq[int], color: TerminalColor): char =
    var index = symbols.getOrDefault(color, -1)
    if index < 0:
      index = order.len
      symbols[color] = index
      order.add color
      counts.add 0
    inc counts[index]
    if index < ColorSymbols.len: ColorSymbols[index] else: '?'

  var bgMap, fgMap = ""
  for y in 0 ..< backend.height:
    bgMap.add align($y, 3)
    bgMap.add '|'
    fgMap.add align($y, 3)
    fgMap.add '|'
    for x in 0 ..< backend.width:
      let cell = backend.cell(x, y)
      bgMap.add symbolFor(bgSymbols, bgOrder, bgCounts, cell.background)
      if cell.continuation:
        fgMap.add '+'
      elif cell.isBlank:
        fgMap.add '.'
      else:
        fgMap.add symbolFor(fgSymbols, fgOrder, fgCounts, cell.foreground)
    bgMap.add "|\n"
    fgMap.add "|\n"

  result = "size " & $backend.width & "x" & $backend.height & "\n\n"
  result.add "background legend:\n"
  for index, color in bgOrder:
    let symbol = if index < ColorSymbols.len: ColorSymbols[index] else: '?'
    result.add "  " & symbol & " = " & color.hex & " (" & $bgCounts[index] & " cells)\n"
  result.add "\nbackground map:\n"
  result.appendColumnRulers(backend.width, 4)
  result.add bgMap
  result.add "\nforeground legend ('.' = blank cell, '+' = wide glyph continuation):\n"
  for index, color in fgOrder:
    let symbol = if index < ColorSymbols.len: ColorSymbols[index] else: '?'
    result.add "  " & symbol & " = " & color.hex & " (" & $fgCounts[index] & " cells)\n"
  result.add "\nforeground map:\n"
  result.appendColumnRulers(backend.width, 4)
  result.add fgMap

proc addEscapedHtml(output: var string, text: string) =
  for c in text:
    case c
    of '&': output.add "&amp;"
    of '<': output.add "&lt;"
    of '>': output.add "&gt;"
    else: output.add c

proc captureHtml*(backend: TerminalBackend, title = "terminal capture"): string =
  ## Standalone HTML page rendering the cell grid with its colors. Every cell is
  ## a fixed-width inline block so wide glyphs and box drawing stay aligned.
  result = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>"""
  result.addEscapedHtml(title)
  result.add """</title>
<style>
body { background: #202020; color: #ddd; margin: 8px; font-family: sans-serif; font-size: 12px; }
.grid { font-family: 'Cascadia Mono', Consolas, 'DejaVu Sans Mono', monospace; font-size: 12px;
  line-height: 15px; display: inline-block; outline: 1px solid #f0f; }
.row { height: 15px; display: flex; }
.row > span { width: 1ch; height: 15px; white-space: pre; overflow: visible; }
.row > span.w2 { width: 2ch; }
</style></head><body>
<div>"""
  result.addEscapedHtml(title)
  result.add " &mdash; " & $backend.width & "x" & $backend.height & " cells</div>\n<div class=\"grid\">\n"
  for y in 0 ..< backend.height:
    result.add "<div class=\"row\">"
    var x = 0
    while x < backend.width:
      let cell = backend.cell(x, y)
      if cell.continuation:
        inc x
        continue
      let wide = x + 1 < backend.width and backend.cell(x + 1, y).continuation
      result.add "<span"
      if wide:
        result.add " class=\"w2\""
      result.add " style=\"background:" & cell.background.hex & ";color:" & cell.foreground.hex & "\">"
      result.addEscapedHtml(if cell.grapheme.len == 0: " " else: cell.grapheme)
      result.add "</span>"
      inc x
    result.add "</div>\n"
  result.add "</div></body></html>\n"
