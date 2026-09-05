# Common immediate-mode concerns

## Doesn't rebuilding the interface every frame make immediate-mode UI slow?

Rebuilding does not mean allocating and rendering every possible element. nuigi uses frame arenas to keep per-frame allocation low, caches text arrangements and meshes, and emits a flat, backend-agnostic command list. Applications may build the UI every frame, as games usually do, or only in response to events. Animations and incremental work can request further frames, while an otherwise idle application can stop redrawing.

## Aren't immediate-mode interfaces difficult to theme consistently?

nuigi has shared style and text-style slots for controls and their states, including hover, focus, and selection variants. Applications can replace theme slots globally, assign them by index, and inspect or edit them with the live theme editor. A copied style is only needed for a genuine one-off variation, so most widget code does not hard-code colors, padding, borders, or fonts.

## Can an immediate-mode layout handle content-driven and responsive interfaces?

Yes. Nodes can fit their content, fill available space, use min/max constraints, stack children, or use anchors and offsets. More structured interfaces can use flex, CSS-style grid, tables, or custom layout callbacks. Layout is resolved in deferred passes, so text measurement, wrapping, fill, and nested content can affect final sizes rather than requiring the application to calculate rectangles up front.

## Do layout changes jump because the final position is not known while building the UI?

nuigi supports delayed animation specifically for layout-computed values. It resolves the new layout first, then interpolates position and size from the previous frame. This works with fill, anchors, flex, grid, content changes, and even reparenting, while immediate animation remains available when the target value is already known.

## How can a removed widget fade or animate out if it no longer exists next frame?

A node can be marked for virtualization before it disappears. nuigi promotes the previous subtree into a persistent virtual node, keeps rendering it, and applies exit animations such as opacity, color, or transform scale. The virtual node is discarded when its animation reaches the target. Menus and windows use this mechanism for close animations.

## Does immediate mode require building thousands of offscreen rows?

No. `virtualList` builds only visible fixed-height rows. `dynamicVirtualList` supports variable-height rows by starting with a height hint, measuring rendered rows, caching their heights, and maintaining scroll anchoring as estimates are corrected. It does not build arbitrary offscreen rows just to measure them.

## What about large expandable trees and tables?

`treeTable` combines cursor-based tree traversal with variable-height virtualization. The FAQ itself is displayed using this widget. It keeps stable expansion and focus identity, caches offscreen branch counts, refreshes visible ancestry incrementally, and supports wrapped, width-dependent columns. Expand-all work is time-budgeted across frames so a large hierarchy does not have to block one frame.

## Isn't text rendering and wrapping too stateful for immediate mode?

Text is measured through a cached arrangement API and turned into a mesh only when render commands are built. The supplied renderer uses FreeType and optional HarfBuzz shaping, caches bounded least-recently-used meshes, grows or resets its glyph atlas safely, and budgets new glyph packing across frames. The fallback path still wraps at whitespace, hyphens, CJK boundaries, and finally glyph boundaries.

## Where does interaction state live if widgets are recreated every frame?

Application state remains in application objects or module variables. Small widget-owned state, such as focus, scrolling, editing, animation, and window ordering, is retained by stable node ID and garbage-collected when it is no longer used. Rebuilding a control therefore does not mean losing its interaction state.

## Is nuigi accessible to screen readers?

Not yet. Built-in controls already support keyboard focus and activation, and the builder has enough stable identity and hierarchy to form the basis of a semantic tree, but nuigi does not currently expose platform accessibility APIs. The plan is to add roles, names, values, actions, and focus synchronization and bridge that tree through [AccessKit](https://accesskit.dev/).

## Does immediate mode lock the application to one renderer or platform?

No. nuigi emits a flat list of rendering commands for rectangles, text, images, clipping, transforms, and custom vertices. The host supplies input, text callbacks, and the renderer, so the same UI model can be integrated with a game renderer, a desktop backend, or WebAssembly without putting backend objects in widget code.

# Platform support

## Which platforms does nuigi support?

The core nuigi library is platform independent: it consumes host-provided input and text callbacks and emits backend-agnostic rendering commands. The built-in SDL3 backend currently supports Windows and the web through WebAssembly. Linux support for that backend is planned.

# Compilers and languages

## Which compilers and languages does nuigi support?

nuigi is written for Nim and supports both the Nim compiler and Nimony. It does not currently provide a C API, so using the library directly from C or other languages is not supported.

# AI

## Is AI used to develop nuigi?

Yes. I use agents during development, but a decent amount of the code is handwritten. Most of the decisions about why things are the way they are are made by me (a human)
