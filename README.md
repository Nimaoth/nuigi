# Nuigi

Nuigi is a backend agnostic, immediate mode UI library written in Nim.

It is not ready for usage yet.

[Check out the online demo](https://nimaoth.github.io/nuigi/nuigi-demo.html)

## Features

- Immediate mode (build ui every frame or on events)
- Backend agnostic (emits draw commands, bring your own renderer)
- Automatic node ids with manual overrides
- Stable state across frames (hover, press, storage, animation)
- Very little heap alloc per frame (arena used for most stuff)
- Simple builtin layouts, optional complex layouts (flex, css grid, table)
- Content driven sizing (fill, fit, min/max, grow to text)
- Field animation (pos, size, color, transform) immediate or delayed
- Theme slots you can override (with live editor)
- Builtin widgets (window, button, slider, textfield, tabs, menu)
- Optional per widget storage, auto garbage collected
- Virtual lists for big ui
- Debug panel and event tracing

## Examples

### Setup

```nim
import nuigi
# create the builder once, at startup
# (arrangeText / buildTextMesh are supplied by your font + text layer)
proc arrangeText(text: openArray[char], fontId: int16, fontSize: float32, maxWidth: float32): UiTextArrangement {.gcsafe, raises: [].} =
  discard # implemented by you, but you can use fonts.nim if you want
proc buildTextMesh(arrangement: UiTextArrangement, pos, screenOffset: Vec2, color: UiColor, transform: UiAffine2): tuple[data: nil ptr UncheckedArray[UiVertex], count: int] =
  discard # implemented by you, but you can use fonts.nim if you want

var ui = newBuilder(arrangeText, buildTextMesh, 16)

# build the ui once per frame
ui.beginUiFrame(viewW, viewH, input)
# ... build nodes and widgets here ...
ui.endUiFrame()
```

### Nodes

```nim
ui.beginUiFrame(viewW, viewH, input)
ui.layoutVertical:
  ui.node("header"):
    discard ui.fit().text("hello")
  ui.node("box"):
    discard ui.fillX().size(200, 100)
    discard ui.text("a sized box")
ui.endUiFrame()
```

### Widgets

```nim
ui.layoutVertical:
  if ui.button("click me"):
    echo "clicked"
  discard ui.checkbox("enable", enabled)
  discard ui.slider(value, 0, 1)
  discard ui.textField(text, "type here...")
  ui.label("just text")
```

### Windows

```nim
ui.windowSpace() # creates root node for windows
ui.window("Settings", 100, 100, 400, 300):
  ui.layoutVertical:
    ui.label("a window with widgets")
    if ui.button("ok"):
      echo "ok"
ui.endUiFrame()
```
