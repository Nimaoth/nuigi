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
- ANSI true-color terminal backend with Unicode cell-aware text

## Examples

Build the SDL demo with `./build.exe demo`, or the terminal demo with `./build.exe terminal-demo`.

### Setup

```nim
import nuigi
# create the builder once, at startup
# (arrangeText / buildTextMesh are supplied by your font + text layer)
proc arrangeText(text: openArray[char], fontId: int16, fontSize: float32, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.gcsafe, raises: [].} =
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

#### Docking

Pass a `DockSpace` to `windowSpace` to let windows dock. The `window` calls
stay the same; the dock layout decides whether each window floats or is docked.
Windows that are not in the layout float at the geometry given to `window`.

```nim
var layout = initDockLayout()
layout.dockWindow("Scene")                          # fills the space
layout.dockWindow("Outline", "", DockLeft, 0.25)    # left quarter of the space
layout.dockWindow("Log", "Scene", DockBottom, 0.3)  # split below Scene
layout.dockWindow("Console", "Log", DockCenter)     # tab next to Log
let dock = newDockSpace(layout)

# every frame
ui.windowSpace(dock)
ui.window("Scene", 0, 0, 400, 300):
  ui.label("docked")
```

Users can rearrange the layout:

- Drag the gap between docked windows to resize them.
- Click a tab to switch to it, and drag a tab out to make its window float.
- Drag a floating window by its title bar. A highlight previews the drop:
  a 100-pixel square at another window's center adds a tab, and bands extending
  100 pixels inward from its edges create splits. The gap around the center
  square is not a drop target: release there to leave the window floating,
  including when dragging a tab out. On small panes these zones shrink to
  preserve the gap; terminal backends use cell-sized zones.
  While dragging over a pane, dark accent guides show its available drop areas,
  leaving the floating gap clear. The brighter highlight previews the selected
  docking result. Guides disappear on release, outside the dock space, or while
  holding Shift.
  The outer 32-pixel edge of the window space docks along that side (two cells
  in terminals, shrinking for small spaces). An empty dock space accepts a drop
  only in its center square.
  Hold shift to keep the window floating anywhere.

Docked windows in inactive tabs are hidden, and windows that are not
submitted in a frame give their space to the rest of the layout. `dock.layout`
is plain data keyed by window title. Save it with `serialize` and restore it
with `parseDockLayout(text, layout)`, which returns false for malformed text.
With `Sdl3App`, assign `app.dockSpace` before `run`.
