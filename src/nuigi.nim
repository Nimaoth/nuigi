## Core of nuigi's immediate-mode UI system.
##
## A `UiBuilder` rebuilds an arena-backed node tree each frame, preserves
## state through stable node IDs, resolves layout in multiple passes, and
## emits renderer-independent `UiRenderCommand`s. Higher-level controls are
## implemented in `nuigi/widgets`; this module owns their low-level building,
## layout, interaction, focus, animation, storage, and rendering primitives.

import std/[assertions]

when defined(nimony):
  import std/tables

include nuigi/util/compat2

import nuigi/core/[vecmath, arena, array_view]
import nuigi/debug/profiler
import nuigi/rendering/mesh
import nuigi/text/text
export mesh, text

from nuigi/core/hash as nui_hash import Hash, `!&`, `!$`

type
  MaterialId* = uint64
    ## Opaque handle identifying a renderer-side material/pipeline used by
    ## `CmdRawVertices` render commands. The UI does not interpret it; it is
    ## passed through to the renderer.

const
  textArrangementCacheCapacity = 512

type
  UiFlag* = enum
    ## Per-node behavior flags stored in `UiFlags`. They drive layout
    ## (sizing, anchoring, stacking), rendering, hit-testing, and animation.
    SizeXKnown
      ## Internal: the node's X size has been resolved this frame (layout bookkeeping).
    SizeYKnown
      ## Internal: the node's Y size has been resolved this frame (layout bookkeeping).
    IsPostProcessing
      ## Internal: the node is currently inside a post-processing pass, so a size change can
      ## trigger a re-pass of its parent.
    SizeDirty
      ## Internal: the node's size changed during post-processing, requiring a re-pass of descendants.
    VirtualTree
      ## Internal: the node was extracted into a virtual-node subtree (`extractVirtualTree`).
    AlignCenter
      ## Center children along the cross axis of a vertical/horizontal layout.
    FillX
      ## Child stretches to fill the remaining width of its parent's content area.
    FillY
      ## Child stretches to fill the remaining height of its parent's content area.
    FitX
      ## Node sizes to its content width (measured text or accumulated child extent).
    FitY
      ## Node sizes to its content height (measured text or accumulated child extent).
    AnchorX
      ## Position the node on the X axis via anchors (fractions of parent size + offsets).
    AnchorY
      ## Position the node on the Y axis via anchors (fractions of parent size + offsets).
    IgnoreInContentExtent
      ## Exclude this node from its parent's accumulated content extent.
    DrawText
      ## Node renders its `UiNodeText` string.
    WrapText
      ## Node text wraps within its measured width instead of staying on one line.
    FillBackground
      ## Node renders its style background fill (rect or rounded rect).
    MaskChildren
      ## Clip children to the node's bounds during rendering (pushes a clip rect).
    PostProcessChildren
      ## Node requires a layout post-processing pass over its children (anchored/fill/fit/stacking).
    LayoutVertical
      ## Stack children vertically, honoring `gap` and style padding.
    LayoutHorizontal
      ## Stack children horizontally, honoring `gap` and style padding.
    FlexLayout
      ## Lay out children with the CSS-flexbox-style engine (`nui_flex`).
    GridLayout
      ## Lay out children with the CSS-grid-style engine (`nui_grid`).
    DirectionReverse
      ## Reverse the order of children along the layout axis.
    NoHover
      ## The node itself is not hoverable; mouse hit-testing passes straight through it.
    NoChildHover
      ## Children of this node are not hoverable; hit-testing stops at this node.
    Scrollable
      ## Node can be scrolled (wheel / middle-drag) when its content exceeds its bounds.
    NodeStorageParent
      ## Node acts as a storage parent; its ID scopes child node-storage lookups.
    NodeFocusScope
      ## Node owns a logical focus scope and remembered descendant path.
    VirtualizeNode
      ## Node should be promoted to a persistent virtual node if it is absent in a future frame.

  UiTraceMode* = enum
    ## Controls which nodes have their events recorded in `UiBuilder.eventTraces`.
    TraceNone
      ## Record no events.
    TraceAll
      ## Record events for every node during the frame.
    TraceNodeId
      ## Record events only for the node selected by `UiBuilder.traceNodeId`.

  UiString* = object ## Wrapper around string which caches the hash of the string.
    valueHash: Hash
      ## Cached FNV-1a hash of `value`, used for O(1) `==` and as the basis of node-ID hashing.
    value: string
      ## The underlying string content.

  UiFlags* = set[UiFlag]
    ## Set of `UiFlag` behaviors attached to a node.

  UiNodeId* = distinct uint64
    ## Stable per-frame identifier for a node. Zero (`noneNodeId`) is the sentinel
    ## "no node"; auto-generated IDs are deterministic from the parent path, the
    ## per-parent auto counter, and any active `pushId`/`popId` ID scope.

  UiMouseButton* = enum
    ## Mouse buttons recognized by the UI input system.
    MouseLeft, MouseRight, MouseMiddle

  UiFieldAnimation* = object
    ## A single animated float field of a node. One `UiFieldAnimation` exists per
    ## animated field within a node's `UiAnimation` record.
    currentValue*: float32
      ## The currently displayed value; stepped toward `targetValue` each frame.
    targetValue*: float32
      ## The value the field eases toward.
    speed*: float32
      ## Step rate; multiplied by `animationSpeed` and `animationTick` to get the per-frame blend.
    fieldOffset*: UiNodeFloatField # Identifies field in UiNode to animate to targetValue
      ## Which node field this track animates (a `UiNodeFloatField` byte offset).
    touchedFrame*: uint64
      ## Frame index on which this track was last (re)touched via an `...Anim` mutator or `animatePos/Size`.

  UiAnimation* = object
    ## Per-node animation record keyed by node ID; holds one `UiFieldAnimation` track per animated field.
    nodeId*: UiNodeId
      ## Node this animation record belongs to.
    fields*: seq[UiFieldAnimation]
      ## The animated field tracks for this node.
    unchangedFrames*: int
      ## Number of consecutive frames with no active stepping; used to drop stale animations.

  UiNodeFloatField* = enum
    ## Each animatable field inside `UiNode` or its side data (style, gap,
    ## anchor, transform). Lets the generic animation engine animate any field without
    ## per-field code.
    UiNodeFieldPosX
      ## `UiNode.pos.x`
    UiNodeFieldPosY
      ## `UiNode.pos.y`
    UiNodeFieldSizeX
      ## `UiNode.size.x`
    UiNodeFieldSizeY
      ## `UiNode.size.y`
    UiNodeFieldMinSizeX
      ## `UiNode.minSize.x`
    UiNodeFieldMinSizeY
      ## `UiNode.minSize.y`
    UiNodeFieldMaxSizeX
      ## `UiNode.maxSize.x`
    UiNodeFieldMaxSizeY
      ## `UiNode.maxSize.y`
    UiNodeFieldCursorX
      ## `UiNode.cursor.x`
    UiNodeFieldCursorY
      ## `UiNode.cursor.y`
    UiNodeFieldContentExtentX
      ## `UiNode.contentExtent.x`
    UiNodeFieldContentExtentY
      ## `UiNode.contentExtent.y`
    UiNodeFieldStylePaddingX
      ## `UiStyle.paddingX`
    UiNodeFieldStylePaddingY
      ## `UiStyle.paddingY`
    UiNodeFieldStyleBorderWidth
      ## `UiStyle.borderWidth`
    UiNodeFieldStyleCornerRadius
      ## `UiStyle.cornerRadius`
    UiNodeFieldStyleFillColorR
      ## `UiStyle.fillColor.r`
    UiNodeFieldStyleFillColorG
      ## `UiStyle.fillColor.g`
    UiNodeFieldStyleFillColorB
      ## `UiStyle.fillColor.b`
    UiNodeFieldStyleFillColorA
      ## `UiStyle.fillColor.a`
    UiNodeFieldStyleBorderColorR
      ## `UiStyle.borderColor.r`
    UiNodeFieldStyleBorderColorG
      ## `UiStyle.borderColor.g`
    UiNodeFieldStyleBorderColorB
      ## `UiStyle.borderColor.b`
    UiNodeFieldStyleBorderColorA
      ## `UiStyle.borderColor.a`
    UiNodeFieldStyleTextColorR
      ## `UiNodeText.textColor.r`
    UiNodeFieldStyleTextColorG
      ## `UiNodeText.textColor.g`
    UiNodeFieldStyleTextColorB
      ## `UiNodeText.textColor.b`
    UiNodeFieldStyleTextColorA
      ## `UiNodeText.textColor.a`
    UiNodeFieldGap
      ## `UiFrame.gaps` entry referenced by `UiNode.gapIndex`.
    UiNodeFieldAnchorTopLeftX
      ## `UiNodeAnchor.topLeft.x`
    UiNodeFieldAnchorTopLeftY
      ## `UiNodeAnchor.topLeft.y`
    UiNodeFieldAnchorBottomRightX
      ## `UiNodeAnchor.bottomRight.x`
    UiNodeFieldAnchorBottomRightY
      ## `UiNodeAnchor.bottomRight.y`
    UiNodeFieldAnchorTopLeftOffsetX
      ## `UiNodeAnchor.topLeftOffset.x`
    UiNodeFieldAnchorTopLeftOffsetY
      ## `UiNodeAnchor.topLeftOffset.y`
    UiNodeFieldAnchorBottomRightOffsetX
      ## `UiNodeAnchor.bottomRightOffset.x`
    UiNodeFieldAnchorBottomRightOffsetY
      ## `UiNodeAnchor.bottomRightOffset.y`
    UiNodeFieldAnchorPivotX
      ## `UiNodeAnchor.pivot.x`
    UiNodeFieldAnchorPivotY
      ## `UiNodeAnchor.pivot.y`
    UiNodeFieldAnchoredOffsetX
      ## `UiNode.pos` X offset applied by the anchor blend.
    UiNodeFieldAnchoredOffsetY
      ## `UiNode.pos` Y offset applied by the anchor blend.
    UiNodeFieldTransformOffsetX
      ## `UiNodeTransform.offset.x`
    UiNodeFieldTransformOffsetY
      ## `UiNodeTransform.offset.y`
    UiNodeFieldTransformRotation
      ## `UiNodeTransform.rotation`
    UiNodeFieldTransformScaleX
      ## `UiNodeTransform.scale.x`
    UiNodeFieldTransformScaleY
      ## `UiNodeTransform.scale.y`
    UiNodeFieldTransformPivotX
      ## `UiNodeTransform.pivot.x`
    UiNodeFieldTransformPivotY
      ## `UiNodeTransform.pivot.y`

  UiMouseButtons* = set[UiMouseButton]
    ## Set of `UiMouseButton`s (used for down/pressed/released state).

  UiKey* = enum
    ## Keyboard keys recognized by the UI input system. Each field name maps directly
    ## to the physical key it represents: letters `KeyA`..`KeyZ`, digits `Key0`..`Key9`,
    ## `KeyF1`..`KeyF12` function keys, `KeyKp*` numpad keys, and `KeyWorld1`/`KeyWorld2`
    ## for locale-specific keys.
    KeyA, KeyB, KeyC, KeyD, KeyE, KeyF, KeyG, KeyH, KeyI, KeyJ, KeyK, KeyL, KeyM
    KeyN, KeyO, KeyP, KeyQ, KeyR, KeyS, KeyT, KeyU, KeyV, KeyW, KeyX, KeyY, KeyZ
    Key0, Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9
    KeySpace, KeyEnter, KeyEscape, KeyBackspace, KeyTab
    KeyLeft, KeyRight, KeyUp, KeyDown
    KeyF1, KeyF2, KeyF3, KeyF4, KeyF5, KeyF6, KeyF7, KeyF8, KeyF9, KeyF10, KeyF11, KeyF12
    KeyDelete, KeyHome, KeyEnd, KeyPageUp, KeyPageDown
    KeyShiftLeft, KeyShiftRight, KeyControlLeft, KeyControlRight
    KeyAltLeft, KeyAltRight, KeySuperLeft, KeySuperRight
    KeyCapsLock, KeyScrollLock, KeyNumLock
    KeyInsert, KeyPause, KeyMenu
    KeyKp0, KeyKp1, KeyKp2, KeyKp3, KeyKp4
    KeyKp5, KeyKp6, KeyKp7, KeyKp8, KeyKp9
    KeyKpDivide, KeyKpMultiply, KeyKpSubtract, KeyKpAdd, KeyKpDecimal, KeyKpEnter
    KeySemicolon, KeyApostrophe, KeyComma, KeyMinus, KeyPeriod, KeySlash, KeyBackslash
    KeyLeftBracket, KeyRightBracket, KeyGrave, KeyWorld1, KeyWorld2

  UiKeys* = set[UiKey]
    ## Set of `UiKey`s (used for down/pressed/released/repeated state).

  UiModifier* = enum
    ## Keyboard modifier keys.
    ModShift
      ## Shift key (left or right).
    ModControl
      ## Control key (left or right).
    ModAlt
      ## Alt key (left or right).
    ModSuper
      ## OS "super"/GUI key (left or right, e.g. Windows/Command).

  UiModifiers* = set[UiModifier]
    ## Set of `UiModifier`s currently held.

  UiNavigationDirection* = enum
    ## Logical navigation directions shared by keyboard and controller input.
    NavLeft, NavRight, NavUp, NavDown

  UiNavigationDirections* = set[UiNavigationDirection]

  UiFocusFlag* = enum
    ## Keyboard-focus behavior declared by a node for the current frame.
    FocusTabStop
      ## Include the node in Tab and Shift+Tab traversal.
    FocusActivatable
      ## Enter or Space may activate the focused node.
    FocusTextInput
      ## The focused node accepts text input.
    FocusDirectionalInput
      ## The focused node consumes arrow/controller directions itself.
    FocusDisabled
      ## Exclude the node from keyboard focus while retaining its declaration.
    FocusNoClick
      ## Pointer interaction does not move keyboard focus to this node.

  UiFocusFlags* = set[UiFocusFlag]

  UiFocusItem* = object
    ## A frame-local declaration that a node can receive keyboard focus.
    nodeId*: UiNodeId
    nodeIndex*: int
    scopeId*: UiNodeId
    flags*: UiFocusFlags
    tabOrder*: int
      ## Explicit Tab rank; equal ranks retain deterministic build order.
    navigationTargets*: array[UiNavigationDirection, UiNodeId]
      ## Explicit directional edges for arrow and controller navigation.
    shiftNavigationTargets*: array[UiNavigationDirection, UiNodeId]
      ## Optional directional edges used while Shift is held.

  UiFocusScope* = object
    ## A frame-local logical focus scope, independent of render parentage.
    nodeId*: UiNodeId
    parentScopeId*: UiNodeId

  UiInputSnapshot* = object
    ## Raw input for a single frame, fed into `beginUiFrame`. `computeFrameInteraction`
    ## uses it (against the previous frame's node positions) to produce `UiFrameOutput`.
    frameIndex*: uint64
      ## Monotonically increasing frame counter; also used as the "last access" stamp for node storage.
    mouse*: Vec2
      ## Mouse cursor position in viewport pixels.
    mouseDelta*: Vec2
      ## Mouse movement since the previous frame, in pixels.
    wheel*: Vec2
      ## Scroll wheel delta this frame.
    mouseDown*: UiMouseButtons
      ## Buttons currently held down.
    mousePressed*: UiMouseButtons
      ## Buttons that went down this frame.
    mouseReleased*: UiMouseButtons
      ## Buttons that went up this frame.
    keysDown*: UiKeys
      ## Keyboard keys currently held down.
    keysPressed*: UiKeys
      ## Keyboard keys that went down this frame.
    keysReleased*: UiKeys
      ## Keyboard keys that went up this frame.
    keysRepeated*: UiKeys
      ## Keyboard keys emitting auto-repeat this frame.
    modsDown*: UiModifiers
      ## Modifier keys currently held.
    navigationPressed*: UiNavigationDirections
      ## Logical controller/D-pad navigation pressed this frame.
    textInput*: string
      ## Committed text typed this frame (for text fields).

  UiStyle* = object
    ## Visual style for a node: padding, border, corner radius, fill/border colors,
    ## plus per-corner/per-side overrides. Any non-default value in a `*Radii`/
    ## `*Widths`/`*Colors` group activates that whole group (see `hasPerCornerRadii` etc.).
    paddingX*, paddingY*: float32
      ## Inner padding applied on each axis before laying out children / drawing content.
    borderWidth*: float32
      ## Uniform border width; fallback used when `borderWidths` is unset.
    cornerRadius*: float32
      ## Uniform corner radius; fallback used when `cornerRadii` is unset.
    fillColor*: UiColor
      ## Background fill color.
    borderColor*: UiColor
      ## Border color; fallback used when `borderColors` is unset.
    cornerRadii*: UiCornerRadii
      ## Per-corner radii (topLeft, topRight, bottomRight, bottomLeft).
    borderWidths*: UiBorderWidths
      ## Per-side border widths (left, top, right, bottom).
    borderColors*: UiBorderColors
      ## Per-side border colors (left, top, right, bottom).

  UiFontId* = int16
    ## Handle identifying a loaded font face within the font atlas.

  UiNodeText* = object
    ## Text payload attached to a node (lazily created via `ensureNodeText`).
    text*: UiString
      ## The string to render (hash-cached for fast comparison/ID derivation).
    fontSize*: float32
      ## Font size in pixels (before `UiBuilder.fontScale`).
    fontId*: UiFontId
      ## Font face used to render `text`.
    textColor*: UiColor
      ## Color of the rendered text.
    measuredTextSizeCache*: Vec2
      ## Cached measured size of the laid-out text, invalidated by `measuredTextDirty`.
    measuredTextDirty*: bool
      ## When true, `measuredTextSizeCache` must be recomputed.

  UiNodeAnchor* = object
    ## Anchor definition for a node: anchor points are fractions (0..1) of the parent
    ## size; offsets are added in pixels. Resolved during the post-processing pass when
    ## `AnchorX`/`AnchorY` flags are set.
    topLeft*: Vec2
      ## Anchor fraction for the node's top-left corner (x = left, y = top).
    bottomRight*: Vec2
      ## Anchor fraction for the node's bottom-right corner (x = right, y = bottom).
    topLeftOffset*: Vec2
      ## Pixel offset added to the top-left anchor position.
    bottomRightOffset*: Vec2
      ## Pixel offset added to the bottom-right anchor position.
    pivot*: Vec2
      ## Fraction (0..1) of the node's own size used as the anchor pivot.
    offset*: Vec2
      ## Extra pixel offset applied to the resolved anchored position.

  UiCustomLayoutProc* = proc(b: var UiBuilder, nodeIdx: int, userData: int) {.raises: [].}
    ## Callback that positions/measures the children of node `nodeIdx` during layout
    ## (custom layout / custom child layout).

  UiNodeCustomLayout* = object
    ## Pair of a custom layout callback and its user data.
    layoutProc*: UiCustomLayoutProc
      ## The layout callback (nil = no custom layout).
    userData*: int
      ## Opaque value passed back to `layoutProc`.

  UiDeferredBuildProc* = proc(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall.}
    ## Callback whose body builds a node's children; executed during `flushDeferredNodes`
    ## at `endUiFrame` (after the whole tree has been described).

  UiDragUserData* = ref object of RootObj
    ## Base type for application-defined drag payloads.

  UiDragUiCallback* = proc(b: var UiBuilder, userData: UiDragUserData, canDrop: bool) {.nimcall.}
    ## Callback that builds the contents of the tooltip shown during a drag.

  UiDeferredNode* = object
    ## A node whose child-building is deferred to `endUiFrame` (see `deferBuild`).
    nodeIdx*: int
      ## Index of the node whose children the callback builds.
    buildProc*: UiDeferredBuildProc
      ## The deferred build callback.
    userData*: int
      ## Opaque value passed back to `buildProc`.
    storageParentStack: seq[UiNodeId]
      ## Storage-parent stack to restore while running `buildProc`.
    focusScopeStack: seq[UiNodeId]
      ## Logical focus-scope stack to restore while running `buildProc`.

  UiVirtualTree* = object
    ## A buffered subtree that is inserted into the actual tree under `parent`
    ## during `endUiFrame`. `nodes` is the full flat list of `UiNode`s forming
    ## the subtree (or forest); internal `parent`/`lastChild`/`nextSibling` links
    ## are relative to this list. The side arrays (texts, styles, gaps, anchors,
    ## transforms, customCommands, customLayouts) hold the sub-data referenced by
    ## the nodes' 1-based indices; they are appended to the frame's own arrays on
    ## insertion and the node indices are remapped accordingly. `animations` holds
    ## per-field animations (by `UiNode` byte-offset) applied to this subtree.
    parent*: UiNodeId
      ## Node under which this subtree is inserted at `endUiFrame`.
    nodes*: seq[UiNode]
      ## Flat list of nodes forming the subtree (or forest).
    animations*: seq[UiFieldAnimation]
      ## Per-field animations applied to the subtree's root node.
    texts*: seq[UiNodeText]
      ## Side-array: node text data referenced by 1-based `textIndex`.
    styles*: seq[UiStyle]
      ## Side-array: node styles referenced by 1-based `styleIndex`.
    gaps*: seq[float32]
      ## Side-array: node gaps referenced by 1-based `gapIndex`.
    anchors*: seq[UiNodeAnchor]
      ## Side-array: node anchors referenced by 1-based `anchorIndex`.
    transforms*: seq[UiNodeTransform]
      ## Side-array: node transforms referenced by 1-based `transformIndex`.
    customCommands*: seq[ArrayView[UiRenderCommand]]
      ## Side-array: custom render commands referenced by 1-based `commandsIndex`.
    customLayouts*: seq[UiNodeCustomLayout]
      ## Side-array: custom layouts referenced by 1-based `customLayoutIndex`/`customChildLayoutIndex`.
    # Persistent (frame-independent) copies of custom render command data and the
    # vertex buffers they reference. Required because a virtual node outlives the
    # frame arena the original commands/vertices were allocated in; the
    # `customCommands` ArrayViews point into `commandData`, and each command's
    # `vertexData` is repointed into `commandVertices`.
    commandData*: seq[UiRenderCommand]
      ## Persistent copy of custom render command data (outlives the frame arena).
    commandVertices*: seq[UiVertex]
      ## Persistent copy of the vertex buffers referenced by `commandData`.

  UiNodeTransform* = object
    ## 2D affine transform applied to a node at render time (offset/rotation/scale about a pivot).
    offset*: Vec2
      ## Translation offset in pixels, applied about `pivot`.
    rotation*: float32
      ## Rotation in radians, applied about `pivot`.
    scale*: Vec2
      ## Scale factors, applied about `pivot`.
    pivot*: Vec2
      ## Fraction (0..1) of the node's size used as the transform origin.

  UiFrameContext* = object
    ## Per-frame environment passed to `beginUiFrame`.
    viewportSize*: Vec2
      ## Size of the render viewport in pixels (becomes the root node's size).
    animationTick*: float32
      ## Time elapsed since the previous frame, used to step animations.
    time*: float32
      ## Accumulated wall-clock time of the UI session.
    input*: UiInputSnapshot
      ## Raw input for this frame.

  UiRenderCommandKind* = enum
    ## Kind of draw operation an `UiRenderCommand` represents. The renderer interprets
    ## only the relevant payload fields for each kind.
    CmdRectFill
      ## Filled rounded rectangle (`pos`, `size`, `color`, `radius`).
    CmdRectStroke
      ## Rectangle outline (`pos`, `size`, `color`, `thickness`, `radius`).
    CmdCircleFill
      ## Filled circle (`pos` = center, `radius`).
    CmdLine
      ## Line segment (`pos` -> `pos2`, `thickness`, `color`).
    CmdText
      ## Text glyphs (`imageId` = font atlas, `textIndex`, `pos`, `color`).
    CmdImage
      ## Textured quad (`imageId`, `pos`, `size`, `uv0`, `uv1`, `samplerMode`).
    CmdClipPush
      ## Push a clip rectangle (intersected with the current clip stack).
    CmdClipPop
      ## Pop the top clip rectangle.
    CmdTransformPush
      ## Push an affine transform (`pivot`, `offset`, `scale`, `rotation`, `transformOrigin`).
    CmdTransformPop
      ## Pop the top transform.
    CmdRawVertices
      ## User-supplied vertex batch (`vertexData`, `vertexCount`, `materialId`, `materialUniform`).

  UiImageId* = distinct uint64
    ## Handle identifying a texture (image, font atlas, or render target) for `CmdImage`/`CmdText`.

  TextureSamplerMode* {.pure.} = enum
    ## Texture filtering mode for image/text render commands.
    Linear
      ## Bilinear filtering (smooth scaling).
    Nearest
      ## Nearest-neighbor filtering (crisp pixels).

  UiRenderCommand* = object
    ## A single renderer-agnostic draw command. Only the fields relevant to `kind` are used.
    kind*: UiRenderCommandKind
      ## Which draw operation this command performs.
    nodeIndex*: int32 = -1
      ## Index of the owning node (for hover/debug); -1 when not associated with a node.
    textIndex*: uint16 = 0
      ## Index into the frame's text array for `CmdText`.
    clipDepth*: uint16
      ## Clip-stack depth in effect when this command was emitted.
    color*: UiColor
      ## Primary color (fill, stroke, line, or text color).
    pos*: Vec2
      ## Primary position: rect origin, circle center, or text baseline origin.
    pos2*: Vec2
      ## Secondary position: line end point.
    size*: Vec2
      ## Size for `CmdRectFill`/`CmdRectStroke`/`CmdImage`.
    uv0*: Vec2
      ## Texture UV minimum for `CmdImage` (default (0,0)).
    uv1*: Vec2
      ## Texture UV maximum for `CmdImage` (default (1,1)).
    samplerMode*: TextureSamplerMode
      ## Texture filtering for `CmdImage`.
    radius*: float32
      ## Corner radius (`CmdRectFill`/`CmdRectStroke`) or circle radius (`CmdCircleFill`).
    thickness*: float32
      ## Line/stroke thickness (`CmdLine`/`CmdRectStroke`).
    imageId*: UiImageId
      ## Texture handle for `CmdImage` or font atlas for `CmdText`.
    vertexData*: nil ptr UncheckedArray[UiVertex]
      ## Vertex pointer for `CmdRawVertices`.
    vertexCount*: int32
      ## Number of vertices in `vertexData`.
    transformOrigin*: Vec2
      ## Transform origin used by `CmdTransformPush`.
    pivot*: Vec2
      ## Pivot (fraction of node size) for `CmdTransformPush`.
    offset*: Vec2
      ## Translation offset for `CmdTransformPush`.
    scale*: Vec2
      ## Scale for `CmdTransformPush`.
    rotation*: float32
      ## Rotation (radians) for `CmdTransformPush`.
    materialId*: MaterialId
      ## Material/pipeline for `CmdRawVertices`.
    materialUniform*: ArrayView[uint8]
      ## Material uniform data for `CmdRawVertices`.

  UiFrameOutput* = object
    ## Result of a frame's interaction + build: hover/press/scroll/drag/click state plus
    ## the emitted render commands. Queried via `wasHovered`/`wasPressed`/`wasClicked` etc.
    hoveredId*: UiNodeId
      ## Node currently under the cursor (none if nothing).
    hoveredIndex*: int
      ## Frame index of `hoveredId` (-1 if none).
    scrolledId*: UiNodeId
      ## Scrollable node currently under the cursor / being middle-drag scrolled.
    scrolledIndex*: int
      ## Frame index of `scrolledId` (-1 if none).
    hoverBeganId*: UiNodeId
      ## Node the cursor entered this frame (none if none).
    hoverEndedId*: UiNodeId
      ## Node the cursor left this frame (none if none).
    pressedId*: UiNodeId
      ## Node on which the left button was pressed this frame.
    heldId*: UiNodeId
      ## Node currently held by the left button.
    draggedId*: UiNodeId
      ## Node being dragged (held + moved, or released after a drag) this frame.
    pressedIndex*: int
      ## Frame index of `pressedId`.
    heldIndex*: int
      ## Frame index of `heldId`.
    draggedIndex*: int
      ## Frame index of `draggedId`.
    rightPressedId*: UiNodeId
      ## Node on which the right button was pressed this frame.
    rightPressedIndex*: int
      ## Frame index of `rightPressedId`.
    clickedId*: UiNodeId
      ## Node released by the left button over the node it was pressed on.
    clickedIndex*: int
      ## Frame index of `clickedId`.
    rightClickedId*: UiNodeId
      ## Node released by the right button over the node it was pressed on.
    rightClickedIndex*: int
      ## Frame index of `rightClickedId`.
    commandLayers*: seq[seq[UiRenderCommand]]
      ## Render commands grouped by layer (e.g. windows vs overlays) before flattening.
    commands*: seq[UiRenderCommand]
      ## All render commands of the frame, concatenated from `commandLayers`.

  UiNode* = object
    ## A single node in the UI tree. Stored as a flat array entry; tree structure is
    ## expressed via integer indices (not heap pointers). `-1` indices mean "none".
    id*: UiNodeId
      ## Stable per-frame identifier (see `UiNodeId`).
    parent*: int32
      ## Index of this node's parent in `UiFrame.nodes` (-1 for the root).
    lastChild*: int32
      ## Index of the last child; the child ring is traversed from `nextSibling` of the tail to the tail (-1 if no children).
    nextSibling*: int32
      ## Index of the next sibling in the child ring (-1 for the only/last child).
    flags*: UiFlags
      ## Behavior flags (see `UiFlag`).
    pos*: Vec2
      ## Position relative to the parent's content origin.
    size*: Vec2
      ## Resolved size of the node.
    minSize*: Vec2
      ## Minimum size clamp applied by `clampNodeSize`.
    maxSize*: Vec2
      ## Maximum size clamp applied by `clampNodeSize`.
    cursor*: Vec2
      ## Current layout cursor (where the next child is placed) within this node.
    contentExtent*: Vec2
      ## Accumulated extent of children/content, used by `Fit` sizing.
    renderParent*: int32
      ## Index of the node this node is drawn under in the render tree (for layering / render-under); -1 = its tree parent.
    renderChildLast*: int32
      ## Index of the last child in render order; -1 if none.
    renderSibling*: int32
      ## Index of the next sibling in render order; -1 if none.
    layerIndex*: int32 = 0
      ## Layer index inherited from the parent (determines render layer).

    # Indices into arrays in the UiBuilder
    textIndex*: uint16
      ## 1-based index into `UiFrame.texts`; 0 = no text.
    anchorIndex*: uint16
      ## 1-based index into `UiFrame.anchors`; 0 = none.
    gapIndex*: uint16
      ## 1-based index into `UiFrame.gaps`; 0 = none (gap 0).
    styleIndex*: uint16
      ## 1-based index into `UiFrame.styles` (or a theme `UiStyleIndex`); 0 = default.
    transformIndex*: uint16
      ## 1-based index into `UiFrame.transforms`; 0 = none.
    commandsIndex*: uint16
      ## 1-based index into `UiFrame.customCommands`; 0 = none.
    customLayoutIndex*: uint16
      ## 1-based index into `UiFrame.customLayouts`; 0 = none.
    customChildLayoutIndex*: uint16
      ## 1-based index into `UiFrame.customLayouts` for child layout; 0 = none.

    when defined(nuiDebug):
      debugName*: string
        ## Human-readable name for debugging/inspection.
      postProcessCounter*: int32
        ## Debug counter of how many times this node was post-processed in a frame.
    when not defined(nimony) and defined(nuiDebug):
      debugSourceFile*: string
        ## Source file where the node was created (debug only).
      debugSourceLine*: int32
        ## Source line where the node was created (debug only).
      debugSourceColumn*: int32
        ## Source column where the node was created (debug only).

  UiFrame* = object
    ## One frame's UI tree and its side data. Swapped with `previousFrame` each frame so
    ## state survives across rebuilds.
    arena*: ptr Arena
      ## Arena allocator backing this frame's transient data.
    arenaCheckpoint*: uint64
      ## Checkpoint to restore the arena at the next `beginUiFrame`.
    nodes*: seq[UiNode]
      ## Flat list of all nodes in the tree.
    nodeIdToIndex*: Table[uint64, int]
      ## Maps node ID -> index in `nodes` for fast lookup.
    duplicateNodeIds*: Table[uint64, seq[int]]
      ## Records nodes that shared an ID (duplicate ID detection).
    texts*: seq[UiNodeText]
      ## Side-array: node text data (1-based `textIndex`).
    styles*: seq[UiStyle]
      ## Side-array: node styles (1-based `styleIndex`); starts with a copy of the theme styles.
    gaps*: seq[float32]
      ## Side-array: node gaps (1-based `gapIndex`).
    anchors*: seq[UiNodeAnchor]
      ## Side-array: node anchors (1-based `anchorIndex`).
    transforms*: seq[UiNodeTransform]
      ## Side-array: node transforms (1-based `transformIndex`).
    customCommands*: seq[ArrayView[UiRenderCommand]]
      ## Side-array: custom render commands (1-based `commandsIndex`).
    customLayouts*: seq[UiNodeCustomLayout]
      ## Side-array: custom layouts (1-based `customLayoutIndex`/`customChildLayoutIndex`).
    focusItems*: seq[UiFocusItem]
      ## Focusable nodes in deterministic build order for this frame.
    focusScopes*: seq[UiFocusScope]
      ## Logical focus scopes registered in build order for this frame.

  UiNodeStorageData* = ref object of RootObj
    ## Base type for custom data for widgets. Create subtype and access using `proc nodeStorage`

  UiNodeStorage* = object
    ## Per-node storage entry; keyed by node ID in `UiBuilder.nodeStorage`.
    data*: nil UiNodeStorageData
      ## The widget's custom storage (nil if none).
    lastAccess*: uint64
      ## Frame index of last access; used by GC to drop stale entries.
    parents*: seq[UiNodeId]
      ## Storage-parent chain this entry belongs to.
    clearOldChildren*: bool
      ## When true, storage of non-rendered children is not kept alive.
    rememberedFocusChild*: UiNodeId
      ## Next scope or focusable item along this scope's last focused path.

  UiTextArrangementCacheEntry = object
    ## Cache entry mapping a (text, font, size, maxWidth) tuple to a laid-out `UiTextArrangement`.
    key*: uint64
      ## Hash key identifying the arrangement inputs.
    text*: UiString
      ## The text that was arranged.
    fontSize*: float32
      ## Font size at arrangement time.
    fontId*: UiFontId
      ## Font face used.
    lastUsedTick*: uint64
      ## Tick of last use; drives LRU eviction.
    maxWidth*: float32
      ## Wrap width used (<= 0 means no wrap).
    arrangement*: UiTextArrangement
      ## The cached text arrangement (glyph positions, no atlas UVs).

  UiMeasureTextFn* = proc(text: openArray[char], fontId: UiFontId, fontSize: float32, maxWidth: float32): UiTextArrangement {.raises: [].}
    ## Callback that shapes/wraps `text` into a cached `UiTextArrangement` (no atlas UVs).
  UiBuildTextMeshFn* = proc(arrangement: UiTextArrangement, pos: Vec2,
    screenOffset: Vec2, color: UiColor, transform: UiAffine2): tuple[data: nil ptr UncheckedArray[UiVertex], count: int] {.raises: [].}
    ## Callback that rasterizes `arrangement` into renderer-owned `UiVertex` data (runs during render-command build).
  UiOpenUrlFn* = proc(url: string): bool {.nimcall, raises: [].}
    ## Optional callback that asks the host application to open a URL.

  DragData* = object
    ## Data for the current drag operation, owned by `UiBuilder`.
    nodeId*: UiNodeId
      ## Node that is currently being dragged (`noneNodeId` if no drag).
    userData*: UiDragUserData
      ## Application-defined data associated with the drag.
    canDrop*: bool
      ## Whether the drop target processed most recently this frame accepts the drag.
    uiCallback*: UiDragUiCallback
      ## Callback that builds the drag tooltip contents.

  UiBuilder* = object
    ## The central UI object. Owns the current and previous frames, the node stack,
    ## ID scopes, theme styles, animations, node storage, and frame output. Mutators
    ## return `var UiBuilder` (`.discardable`) so calls chain.
    stack*: seq[int]
      ## Index stack of nodes currently being built (innermost last); mirrors the begin/end nesting.
    nodeIdStack*: seq[UiNodeId]
      ## Parallel stack of node IDs matching `stack`.
    # Composed ID scopes from pushId/popId; mixed into child node IDs.
    idScopeStack*: seq[uint64]
      ## Active `pushId`/`popId` ID scopes, mixed into child node IDs.
    storageParentStack: seq[UiNodeId]
      ## Stack of storage-parent node IDs for scoping child node storage.
    focusScopeStack: seq[UiNodeId]
      ## Logical focus ancestry, independent of render-tree parentage.
    # Per-parent counter used for deterministic auto-generated child IDs.
    autoChildCounter*: seq[uint32]
      ## Per-node counter producing deterministic auto-generated child IDs.
    frame*: UiFrame
      ## The frame currently being built.
    previousFrame*: UiFrame
      ## The previous frame (swapped each `beginUiFrame`); source of stable state.
    frameCtx*: UiFrameContext
      ## Per-frame environment (viewport, input, time).
    previousOutput*: UiFrameOutput
      ## Output of the previous frame; queried by `wasHovered`/`wasClicked` etc.
    frameOutput*: UiFrameOutput
      ## Output produced for the current frame.
    themeStyles*: seq[UiStyle]
      ## Named theme styles addressed by `UiStyleIndex`.
    themeTextStyles*: seq[UiNodeText]
      ## Named theme text styles addressed by `UiTextStyleIndex`.
    animations*: seq[UiAnimation]
      ## Active per-node animations.
    animationSpeed*: float32 = 1.0'f32
      ## Global multiplier applied to every animation track's speed.
    configuringAnimationStack*: seq[bool]
      ## Per-node flag: whether an `animate:` block is active (gates `...Anim` mutators).
    animationTriggerStack*: seq[bool]
      ## Per-node flag: whether new animation tracks may be created this frame.
    anythingAnimating*: bool
      ## True if any animation is actively stepping this frame.
    antialiasMeshWidth*: float32
      ## Width in pixels of alpha fringes around rectangle fill and border meshes; zero disables them.
    windows*: UiNodeId
      ## ID of the window-space root node (windows layer).
    overlays*: UiNodeId
      ## ID of the overlay root node (drawn above windows).
    focusedNode*: UiNodeId
      ## ID of the currently focused node (for keyboard/text input).
    focusNavigationHandled: bool
      ## Whether directional focus navigation moved focus at frame start.
    focusChangedByKeyboard: bool
      ## Whether Tab or directional keyboard navigation changed focus this frame.
    debugDrawGridLines*: bool
      ## When true, draw layout grid/debug guides.
    showDebugPanel*: bool = false
      ## Toggle the node-inspector debug panel.
    showDebugPanel2*: bool = false
      ## Toggle the secondary debug panel.
    showThemeEditor*: bool = false
      ## Toggle the live theme editor.
    fontAtlasImageId*: UiImageId
      ## Image ID of the font atlas texture.

    nodeStorage: Table[uint64, UiNodeStorage]
      ## Node-ID -> storage map; GC'd by `collectGarbage` at `endUiFrame`.

    currentNode: ptr UiNode
      ## Pointer to the node currently being built (innermost begin/endNode).
    currentParent: nil ptr UiNode
      ## Pointer to the parent of the current node (nil at root).
    lastNode: ptr UiNode
      ## Pointer to the node finished most recently.
    lastNodeIndex: int
      ## Index of `lastNode`.

    defaultText*: UiNodeText
      ## Default text style applied to new nodes.
    defaultStyle*: UiStyle
      ## Default visual style applied to new nodes.
    defaultAnchor*: UiNodeAnchor
      ## Default (empty) anchor returned when a node has no anchor.
    defaultTransform*: UiNodeTransform
      ## Default (identity) transform returned when a node has none.
    defaultCustomCommands*: ArrayView[UiRenderCommand]
      ## Default (empty) custom-command view returned when a node has none.
    defaultCustomLayout*: UiNodeCustomLayout
      ## Default (no-op) custom layout returned when a node has none.

    deferredNodes*: seq[UiDeferredNode]
      ## Nodes whose child-building is deferred to `flushDeferredNodes`.
    virtualNodes*: seq[UiVirtualTree]
      ## Buffered virtual subtrees to splice in at `endUiFrame`.
    virtualNodeAnimations*: Table[uint64, seq[UiFieldAnimation]]
      ## Per virtualized node ID, the animations to attach to its virtual node.

    textArrangementLookup: Table[uint64, int]
      ## Maps a text-arrangement key to its cache index.
    textArrangementEntries: seq[UiTextArrangementCacheEntry]
      ## LRU cache of text arrangements.
    textArrangementTick: uint64
      ## Monotonic tick used for LRU eviction.
    measureText*: UiMeasureTextFn
      ## Callback that lays out text (set at `newBuilder`).
    buildTextMesh*: nil UiBuildTextMeshFn
      ## Optional callback that builds text meshes (set at `newBuilder`).
    openUrlFn*: nil UiOpenUrlFn
      ## Optional callback supplied by the host application for opening URLs.
    fonts*: Table[string, UiFontId]
      ## Maps font names to loaded font IDs.
    fontScale*: float32
      ## Global scale applied to font sizes (DPI/accessibility).

    # Event tracing for debugging: maps a node id to the sequence of events
    # recorded for that node during the current frame. Cleared at frame start.
    eventTraces*: Table[uint64, seq[string]]
      ## Per-node sequence of recorded events (when tracing is enabled).
    # Controls which nodes have their events recorded. In `TraceNodeId` mode,
    # only events for `traceNodeId` are recorded.
    traceMode*: UiTraceMode
      ## Which nodes have their events recorded (see `UiTraceMode`).
    traceNodeId*: UiNodeId
      ## Node to trace when `traceMode == TraceNodeId`.

    # Middle-click drag scrolling: while the middle mouse button is held over a
    # scrollable node, the offset of the cursor from the drag start drives the
    # scroll position. `middleDragScroll` holds the per-frame scroll delta (in
    # pixels) to apply during the current frame's build.
    middleDragActive*: bool
      ## True while a middle-button drag-scroll is in progress.
    middleDragScrollStart*: Vec2
      ## Cursor position where the middle-drag scroll started.
    middleDragScroll*: Vec2
      ## Per-frame scroll delta (pixels) from the middle-drag.

    dragData*: DragData
      ## Current drag operation data (node id + user pointer).

  UiClipRect* = object
    ## An axis-aligned clipping rectangle.
    x*, y*, w*, h*: float32
      ## Top-left origin (`x`,`y`) and size (`w`,`h`), in pixels.

const
  DefaultAnimationSpeed* = 18.0'f32

type
  UiStyleIndex* = enum
    ## Named theme style slots in `UiBuilder.themeStyles`. Slots are 1-based when
    ## used as node `styleIndex` (slot 0 / `None` means "unset"). `initDefaultThemeStyles`
    ## fills these from `UiStyleIndexDefault` up to `UiStyleIndexAccent`.
    UiStyleIndexNone
      ## Sentinel: no style assigned.
    UiStyleIndexDefault
      ## Default node style; also copied into `UiBuilder.defaultStyle`.
    UiStyleIndexWindow
      ## Window frame (border + rounded corners).
    UiStyleIndexWindowTitleBar
      ## Window title bar background.
    UiStyleIndexButton
      ## Button background.
    UiStyleIndexButtonHover
      ## Button background while hovered.
    UiStyleIndexCheckbox
      ## Checkbox box background.
    UiStyleIndexCheckboxHover
      ## Checkbox box background while hovered.
    UiStyleIndexCheckboxMark
      ## Checkbox check mark fill.
    UiStyleIndexSlider
      ## Slider container.
    UiStyleIndexSliderTrack
      ## Slider track background.
    UiStyleIndexSliderTrackHover
      ## Slider track background while hovered.
    UiStyleIndexSliderFill
      ## Slider fill (selected portion).
    UiStyleIndexSliderHandle
      ## Slider handle.
    UiStyleIndexScrollBar
      ## Scrollbar background.
    UiStyleIndexScrollBarHandle
      ## Scrollbar handle.
    UiStyleIndexScrollBarHandleHover
      ## Scrollbar handle while hovered.
    UiStyleIndexWindowContent
      ## Window content area.
    UiStyleIndexWindowResizeHandle
      ## Window resize-handle grip.
    UiStyleIndexTabBarHeader
      ## Tab bar header strip.
    UiStyleIndexTabBarItem
      ## Inactive tab item.
    UiStyleIndexTabBarItemActive
      ## Active tab item.
    UiStyleIndexTabBarContent
      ## Tab content panel.
    UiStyleIndexTextField
      ## Text field background.
    UiStyleIndexTextFieldFocused
      ## Text field background while focused.
    UiStyleIndexTextFieldHint
      ## Text field placeholder/hint.
    UiStyleIndexTextCursor
      ## Text field caret.
    UiStyleIndexMenu
      ## Menu popup background.
    UiStyleIndexMenuItem
      ## Menu item background.
    UiStyleIndexMenuItemHover
      ## Menu item background while hovered.
    UiStyleIndexWindowTitleBarCollapseHover
      ## Window collapse button while hovered.
    UiStyleIndexMenuBar
      ## Menu bar background.
    UiStyleIndexPanel
      ## Generic panel/container.
    UiStyleIndexStage
      ## Top-level stage/root panel.
    UiStyleIndexCard
      ## Card container.
    UiStyleIndexHeader
      ## Section header bar.
    UiStyleIndexRow
      ## List row.
    UiStyleIndexRowAlt
      ## Alternating (zebra) list row.
    UiStyleIndexTooltip
      ## Tooltip popup.
    UiStyleIndexAccent
      ## Accent color block (base for `accentVariation`); last slot (`UiThemeStyleSlotCount`).

  UiTextStyleIndex* = enum
    ## Named theme text-style slots in `UiBuilder.themeTextStyles`. Like `UiStyleIndex`,
    ## slots are 1-based as node `textIndex` (slot 0 / `None` means "unset"). `initDefaultThemeTextStyles`
    ## fills these from `UiStyleIndexDefaultText` up to `UiStyleIndexHeaderText`.
    UiTextStyleIndexNone
      ## Sentinel: no text style assigned.
    UiStyleIndexDefaultText
      ## Default text style; also copied into `UiBuilder.defaultText`.
    UiStyleIndexSmallText
      ## Small text.
    UiStyleIndexLargeText
      ## Large text.
    UiStyleIndexExtraLargeText
      ## Extra-large text (headings/display).
    UiStyleIndexButtonText
      ## Button label.
    UiStyleIndexMenuItemHoverText
      ## Menu item label while hovered.
    UiStyleIndexMenuItemText
      ## Menu item label.
    UiStyleIndexLabelText
      ## Form label.
    UiStyleIndexWindowText
      ## Window body text.
    UiStyleIndexWindowTitleBarText
      ## Window title bar text.
    UiStyleIndexWindowContentText
      ## Window content text.
    UiStyleIndexButtonHoverText
      ## Button label while hovered.
    UiStyleIndexCheckboxText
      ## Checkbox label.
    UiStyleIndexCheckboxHoverText
      ## Checkbox label while hovered.
    UiStyleIndexCheckboxMarkText
      ## Checkbox mark text/icon.
    UiStyleIndexSliderText
      ## Slider label.
    UiStyleIndexTabBarHeaderText
      ## Tab bar header text.
    UiStyleIndexTabBarItemText
      ## Inactive tab item text.
    UiStyleIndexTabBarItemActiveText
      ## Active tab item text.
    UiStyleIndexTabBarContentText
      ## Tab content text.
    UiStyleIndexTextFieldText
      ## Text field text.
    UiStyleIndexTextFieldFocusedText
      ## Text field text while focused.
    UiStyleIndexTextFieldHintText
      ## Text field hint/placeholder text.
    UiStyleIndexHeadingText
      ## Heading text.
    UiStyleIndexMutedText
      ## De-emphasized (muted) text.
    UiStyleIndexHeaderText
      ## Header/section-title text (last slot; `UiTextStyleCount`).

const
  UiThemeStyleSlotCount* = int(UiStyleIndexAccent)
  UiTextStyleCount* = int(UiStyleIndexHeaderText)

proc accentVariation*(base: UiColor, hueShift: float32, brightness: float32): UiColor =
  ## Derive a color from `base` by rotating hue (`hueShift` in turns, 0..1)
  ## and scaling brightness (V) by `brightness`. Used to generate the varied
  ## colored blocks in the demos from a single `Accent` theme color.
  let r = base.r
  let g = base.g
  let b = base.b
  let maxc = max(r, max(g, b))
  let minc = min(r, min(g, b))
  let d = maxc - minc
  var h = 0.0'f32
  if d > 0.00001'f32:
    if maxc == r:
      h = (g - b) / d
    elif maxc == g:
      h = (b - r) / d + 2.0'f32
    else:
      h = (r - g) / d + 4.0'f32
    h = h / 6.0'f32
    if h < 0.0'f32:
      h += 1.0'f32
  let s = if maxc <= 0.00001'f32: 0.0'f32 else: d / maxc
  let v = clamp(maxc * brightness, 0.0'f32, 1.0'f32)
  let hh = h + hueShift - floor(h + hueShift)
  let i = int(hh * 6.0'f32)
  let f = hh * 6.0'f32 - i.float32
  let p = v * (1.0'f32 - s)
  let q = v * (1.0'f32 - f * s)
  let t = v * (1.0'f32 - (1.0'f32 - f) * s)
  case i mod 6
  of 0: return UiColor(r: v, g: t, b: p, a: base.a)
  of 1: return UiColor(r: q, g: v, b: p, a: base.a)
  of 2: return UiColor(r: p, g: v, b: t, a: base.a)
  of 3: return UiColor(r: p, g: q, b: v, a: base.a)
  of 4: return UiColor(r: t, g: p, b: v, a: base.a)
  else: return UiColor(r: v, g: p, b: q, a: base.a)

func uiString*(s: string): UiString =
  return UiString(valueHash: nui_hash.hash(s), value: s)

func hash*(s: UiString): Hash =
  return s.valueHash

func len*(s: UiString): int =
  return s.value.len

func value*(s: UiString): string =
  return s.value

func `==`*(a, b: UiString): bool =
  return a.valueHash == b.valueHash and a.value == b.value

func intersectClipRect*(a, b: UiClipRect): UiClipRect =
  ## Compute the intersection of two clip rectangles. Returns an empty rect if they don't overlap.
  let x1 = max(a.x, b.x)
  let y1 = max(a.y, b.y)
  let x2 = min(a.x + a.w, b.x + b.w)
  let y2 = min(a.y + a.h, b.y + b.h)
  UiClipRect(
    x: x1,
    y: y1,
    w: max(0.0'f32, x2 - x1),
    h: max(0.0'f32, y2 - y1),
  )

func isEmpty*(r: UiClipRect): bool {.inline.} =
  ## Returns true if the clip rect has zero or negative width/height.
  r.w <= 0.0'f32 or r.h <= 0.0'f32

func intersectsClipRect*(clipStack: seq[UiClipRect], cmdPos, cmdSize: Vec2): bool =
  ## Returns true if a rectangle at cmdPos with cmdSize intersects the topmost clip rect on the stack.
  if clipStack.len == 0:
    return true
  let clip = clipStack[^1]
  if isEmpty(clip):
    return false
  let cmdRight = cmdPos.x + cmdSize.x
  let cmdBottom = cmdPos.y + cmdSize.y
  cmdRight > clip.x and cmdPos.x < clip.x + clip.w and
    cmdBottom > clip.y and cmdPos.y < clip.y + clip.h

proc cachedMeasuredTextSize*(b: var UiBuilder, node: ptr UiNode): Vec2 {.raises: [].}
proc updateNodeFit*(b: var UiBuilder, n: ptr UiNode)
proc postProcessChildren*(b: var UiBuilder, idx: int): var UiBuilder {.discardable.}
proc clampNodeSize*(b: var UiBuilder, n: ptr UiNode) {.inline.}
proc updateParentAfterChildEnd(b: var UiBuilder, child: ptr UiNode)
proc removeStaleAnimations(b: var UiBuilder)
proc buildRenderCommands(b: var UiBuilder, idx: int, ox, oy: float32, inheritedLayoutIndex: int32, clipStack: var seq[UiClipRect])
proc buildMeshRenderCommands(b: var UiBuilder, idx: int, ox, oy: float32, inheritedLayoutIndex: int32, clipStack: var seq[UiClipRect])
proc absoluteNodePos*(b: UiBuilder, idx: int): Vec2
proc contentSize*(b: var UiBuilder, n: ptr UiNode): Vec2 {.raises: [].}
proc applyDeferredAnimationTracks(b: var UiBuilder, nodeIdx: int)
proc deferredAnimationBuildProc(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall.}
proc deferredPostProcessBuildProc(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall.}
proc buildDragUi(b: var UiBuilder)
proc beginAttach*(b: var UiBuilder, parentIdx: int): bool
proc endAttach*(b: var UiBuilder)
proc deferPostProcess*(b: var UiBuilder): var UiBuilder {.discardable.}
proc keepAlive*(b: var UiBuilder, nodeId: UiNodeId)
  ## Prevent node storage from being garbage-collected this frame.

proc makeTextArrangementKey(text: UiString, fontSize: float32, fontId: UiFontId, maxWidth: float32 = -1): uint64 {.inline, raises: [].} =
  let a = !$(text.valueHash !& nui_hash.hash(fontSize) !& nui_hash.hash(maxWidth) !& nui_hash.hash(fontId))
  uint64(a)

proc evictOldestTextArrangement(b: var UiBuilder) {.raises: [].} =
  prof("evictOldestTextArrangement")
  if b.textArrangementEntries.len <= 0:
    return

  var oldestIdx = 0
  var oldestTick = b.textArrangementEntries[0].lastUsedTick
  for i in 1 ..< b.textArrangementEntries.len:
    let tick = b.textArrangementEntries[i].lastUsedTick
    if tick < oldestTick:
      oldestTick = tick
      oldestIdx = i

  let oldKey = b.textArrangementEntries[oldestIdx].key
  if onRaiseQuit(b.textArrangementLookup.hasKey(oldKey)):
    del(b.textArrangementLookup, oldKey)

  let lastIdx = b.textArrangementEntries.high
  if oldestIdx != lastIdx:
    let moved = b.textArrangementEntries[lastIdx]
    b.textArrangementEntries[oldestIdx] = moved
    b.textArrangementLookup[moved.key] = oldestIdx

  b.textArrangementEntries.setLen(lastIdx)

proc buildTextArrangement(b: UiBuilder, text: ptr UiNodeText, key: uint64, maxWidth: float32 = -1): UiTextArrangementCacheEntry =
  ## Arrange text without building atlas UVs or render vertices.
  prof("buildTextArrangement")
  result = UiTextArrangementCacheEntry()
  if b.measureText != nil:
    result.arrangement = b.measureText(text.text.value, text.fontId, text.fontSize * b.fontScale, maxWidth)
  result.arrangement.fontSize = text.fontSize * b.fontScale
  result.key = key
  result.text = text.text
  result.fontSize = text.fontSize
  result.fontId = text.fontId
  result.maxWidth = maxWidth

proc getTextArrangement*(b: var UiBuilder, text: ptr UiNodeText, maxWidth: float32 = -1): ptr UiTextArrangement {.raises: [].} =
  prof("getTextArrangement")
  let key = makeTextArrangementKey(text.text, text.fontSize * b.fontScale, text.fontId, maxWidth)
  inc b.textArrangementTick

  let idx = onRaiseQuit(b.textArrangementLookup.getOrDefault(key, -1))
  if idx >= 0 and idx < b.textArrangementEntries.len:
    let entry = b.textArrangementEntries[idx].addr
    if entry.key == key and entry.text == text.text and entry.fontSize == text.fontSize and entry.fontId == text.fontId and entry.maxWidth == maxWidth:
      entry.lastUsedTick = b.textArrangementTick
      return entry.arrangement.addr

    entry[] = b.buildTextArrangement(text, key, maxWidth)
    entry.lastUsedTick = b.textArrangementTick
    return entry.arrangement.addr
  elif idx >= b.textArrangementEntries.len:
    if onRaiseQuit(b.textArrangementLookup.hasKey(key)):
      del(b.textArrangementLookup, key)

  if b.textArrangementEntries.len >= textArrangementCacheCapacity:
    b.evictOldestTextArrangement()

  let newIdx = b.textArrangementEntries.len
  b.textArrangementEntries.add(b.buildTextArrangement(text, key, maxWidth))
  b.textArrangementEntries[newIdx].lastUsedTick = b.textArrangementTick
  b.textArrangementLookup[key] = newIdx
  b.textArrangementEntries[newIdx].arrangement.addr

var sentinelNode = UiNode()

func noneNodeId*(): UiNodeId {.inline.} =
  ## Returns the sentinel "no node" ID (value 0).
  UiNodeId(0'u64)

func `==`*(a, b: UiNodeId): bool {.borrow.}

template nodes*(b: var UiBuilder): var seq[UiNode] = b.frame.nodes
  ## Access the node array of the current frame.

proc currentNode*(b: var UiBuilder): ptr UiNode =
  ## Pointer to the node currently being built (innermost begin/endNode).
  b.currentNode

proc lastNode*(b: var UiBuilder): ptr UiNode =
  ## Pointer to the node which was finished most recently (most recent endNode call)
  b.lastNode

proc lastNodeIndex*(b: var UiBuilder): int =
  ## Index of the node which was finished most recently (most recent endNode call)
  b.lastNodeIndex

proc currentParent*(b: var UiBuilder): nil ptr UiNode =
  ## Pointer to the parent of the current node, or nil if at root.
  b.currentParent

proc nodeStorageParent*(b: var UiBuilder) {.inline.} =
  ## Mark the current node as a storage parent; its ID is recorded for child storage lookup.
  b.frame.nodeIdToIndex[b.currentNode.id.uint64] = b.stack[^1]
  b.storageParentStack.add(b.currentNode.id)
  b.currentNode.flags.incl NodeStorageParent

proc focusScope*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Make the current node a logical focus scope with storage-lifetime memory.
  let nodeId = b.currentNode.id
  let parentScopeId =
    if b.focusScopeStack.len > 0: b.focusScopeStack[^1]
    else: noneNodeId()
  b.frame.focusScopes.add UiFocusScope(
    nodeId: nodeId,
    parentScopeId: parentScopeId,
  )

  var storageParents = b.storageParentStack
  if storageParents.len > 0 and storageParents[^1] == nodeId:
    storageParents.setLen(storageParents.len - 1)
  let storage = b.nodeStorage.mgetOrPut(nodeId.uint64, UiNodeStorage()).addr
  storage.parents = storageParents
  storage.lastAccess = b.frameCtx.input.frameIndex

  b.focusScopeStack.add nodeId
  b.currentNode.flags.incl NodeFocusScope
  if NodeStorageParent notin b.currentNode.flags:
    b.nodeStorageParent()
  b

proc registerFocusScope*(b: var UiBuilder, nodeId: UiNodeId,
    parentScopeId: UiNodeId = noneNodeId()) =
  ## Register a logical focus scope that does not require a rendered node.
  for scope in b.frame.focusScopes:
    if scope.nodeId == nodeId:
      return
  b.frame.focusScopes.add UiFocusScope(
    nodeId: nodeId,
    parentScopeId: parentScopeId,
  )
  let storage = b.nodeStorage.mgetOrPut(nodeId.uint64, UiNodeStorage()).addr
  storage.parents = b.storageParentStack
  storage.lastAccess = b.frameCtx.input.frameIndex

proc pushFocusScope*(b: var UiBuilder, nodeId: UiNodeId) =
  ## Enter a balanced logical focus scope without requiring a rendered node.
  let parentScopeId =
    if b.focusScopeStack.len > 0: b.focusScopeStack[^1]
    else: noneNodeId()
  b.registerFocusScope(nodeId, parentScopeId)
  b.focusScopeStack.add nodeId

proc popFocusScope*(b: var UiBuilder) =
  ## Leave the logical focus scope entered by `pushFocusScope`.
  assert b.focusScopeStack.len > 0
  discard b.focusScopeStack.pop()

proc nodeStorage*(b: var UiBuilder, node: ptr UiNode, data: UiNodeStorageData) {.inline.} =
  ## Store node storage for given node.
  let nodeId = node.id.uint64
  b.nodeStorage[nodeId] = UiNodeStorage(data: data, parents: b.storageParentStack, lastAccess: b.frameCtx.input.frameIndex)

proc nodeStorageClearOldChildren*(b: var UiBuilder, node: ptr UiNode) {.inline.} =
  ## Don't keep node storage of non-rendered children alive.
  let nodeId = node.id.uint64
  b.nodeStorage.mgetOrPut(nodeId, UiNodeStorage()).clearOldChildren = true
  b.nodeStorage.getOrQuit(nodeId).lastAccess = b.frameCtx.input.frameIndex

proc nodeStorageGet*(b: var UiBuilder, node: ptr UiNode): nil UiNodeStorageData {.inline.} =
  ## Get node storage for given node, or nil if not found.
  let nodeId = node.id.uint64
  if b.nodeStorage.hasKey(nodeId):
    var found = b.nodeStorage.getOrQuit(nodeId).addr
    found.lastAccess = b.frameCtx.input.frameIndex
    return found.data
  return nil

iterator nodeStorageParents*(b: var UiBuilder): UiNodeStorageData =
  ## Iterate active storage-parent data from innermost to outermost.
  for index in countdown(b.storageParentStack.high, 0):
    let nodeId = b.storageParentStack[index].uint64
    if b.nodeStorage.hasKey(nodeId):
      var found = b.nodeStorage.getOrQuit(nodeId).addr
      found.lastAccess = b.frameCtx.input.frameIndex
      if found.data != nil:
        yield found.data

proc ensureNodeText*(b: var UiBuilder, node: ptr UiNode): var UiNodeText {.inline.} =
  ## Lazily initialize and return a mutable reference to the node's text data.
  if node.textIndex == 0:
    node.textIndex = (b.frame.texts.len + 1).uint16
    b.frame.texts.add(UiNodeText(measuredTextDirty: true, fontSize: b.defaultText.fontSize, fontId: b.defaultText.fontId, textColor: b.defaultText.textColor))
    return b.frame.texts[^1]
  b.frame.texts[node.textIndex - 1]

proc ensureNodeStyle*(b: var UiBuilder, node: ptr UiNode): var UiStyle {.inline.} =
  ## Lazily initialize and return a mutable reference to the node's style data.
  if b.currentNode.styleIndex.int <= b.themeStyles.len:
    let currentStyle = b.frame.styles[b.currentNode.styleIndex]
    b.frame.styles.add(currentStyle)
    node.styleIndex = b.frame.styles.len.uint16
    return b.frame.styles[^1]
  if node.styleIndex == 0:
    node.styleIndex = (b.frame.styles.len + 1).uint16
    b.frame.styles.add(b.defaultStyle)
    return b.frame.styles[^1]
  b.frame.styles[node.styleIndex - 1]

proc ensureNodeGap*(b: var UiBuilder, node: ptr UiNode): var float32 {.inline.} =
  ## Lazily initialize and return a mutable reference to the node's gap value.
  if node.gapIndex == 0:
    node.gapIndex = (b.frame.gaps.len + 1).uint16
    b.frame.gaps.add(0.0'f32)
    return b.frame.gaps[^1]
  b.frame.gaps[node.gapIndex - 1]

proc ensureNodeAnchor*(b: var UiBuilder, node: ptr UiNode): var UiNodeAnchor {.inline.} =
  ## Lazily initialize and return a mutable reference to the node's anchor data.
  if node.anchorIndex == 0:
    node.anchorIndex = (b.frame.anchors.len + 1).uint16
    b.frame.anchors.add(UiNodeAnchor())
    return b.frame.anchors[^1]
  b.frame.anchors[node.anchorIndex - 1]

proc ensureNodeTransform*(b: var UiBuilder, node: ptr UiNode): var UiNodeTransform {.inline.} =
  ## Lazily initialize and return a mutable reference to the node's transform data.
  if node.transformIndex == 0:
    node.transformIndex = (b.frame.transforms.len + 1).uint16
    b.frame.transforms.add(UiNodeTransform(scale: vec2(1.0'f32, 1.0'f32), pivot: vec2(0.5'f32, 0.5'f32)))
    return b.frame.transforms[^1]
  b.frame.transforms[node.transformIndex - 1]

proc ensureNodeCustomCommands*(b: var UiBuilder, node: ptr UiNode): var ArrayView[UiRenderCommand] {.inline.} =
  ## Lazily initialize and return a mutable reference to the node's custom render commands.
  if node.commandsIndex == 0:
    node.commandsIndex = (b.frame.customCommands.len + 1).uint16
    b.frame.customCommands.add(default(ArrayView[UiRenderCommand]))
    return b.frame.customCommands[^1]
  b.frame.customCommands[node.commandsIndex - 1]

proc ensureNodeCustomLayout*(b: var UiBuilder, node: ptr UiNode): var UiNodeCustomLayout {.inline.} =
  ## Lazily initialize and return a mutable reference to the node's custom layout proc.
  if node.customLayoutIndex == 0:
    node.customLayoutIndex = (b.frame.customLayouts.len + 1).uint16
    b.frame.customLayouts.add(default(UiNodeCustomLayout))
    return b.frame.customLayouts[^1]
  b.frame.customLayouts[node.customLayoutIndex - 1]

proc ensureNodeCustomChildLayout*(b: var UiBuilder, node: ptr UiNode): var UiNodeCustomLayout {.inline.} =
  ## Lazily initialize and return a mutable reference to the node's custom child layout proc.
  if node.customChildLayoutIndex == 0:
    node.customChildLayoutIndex = (b.frame.customLayouts.len + 1).uint16
    b.frame.customLayouts.add(default(UiNodeCustomLayout))
    return b.frame.customLayouts[^1]
  b.frame.customLayouts[node.customChildLayoutIndex - 1]

proc nodeText*(b: UiBuilder, idx: int): ptr UiNodeText {.inline.} =
  ## Get the text data for node at idx, or a pointer to the default text if unset.
  let n = b.frame.nodes[idx]
  let textSlot = int(n.textIndex)
  if textSlot > 0 and textSlot <= b.frame.texts.len: addr(b.frame.texts[textSlot - 1]) else: addr(b.defaultText)

proc nodeStyle*(b: UiBuilder, idx: int): ptr UiStyle {.inline.} =
  ## Get the style for node at idx, or a pointer to the default style if unset.
  let n = b.frame.nodes[idx]
  let styleSlot = int(n.styleIndex)
  if styleSlot > 0 and styleSlot <= b.frame.styles.len: addr(b.frame.styles[styleSlot - 1]) else: addr(b.defaultStyle)

proc nodeGap*(b: UiBuilder, idx: int): float32 {.inline.} =
  ## Get the gap value for node at idx, or 0.0 if unset.
  let n = b.frame.nodes[idx]
  let gapSlot = int(n.gapIndex)
  if gapSlot > 0 and gapSlot <= b.frame.gaps.len: b.frame.gaps[gapSlot - 1] else: 0.0'f32

proc nodeAnchor*(b: UiBuilder, idx: int): ptr UiNodeAnchor {.inline.} =
  ## Get the anchor data for node at idx, or a pointer to the default anchor if unset.
  let n = b.frame.nodes[idx]
  let anchorSlot = int(n.anchorIndex)
  if anchorSlot > 0 and anchorSlot <= b.frame.anchors.len: addr(b.frame.anchors[anchorSlot - 1]) else: addr(b.defaultAnchor)

proc nodeTransform*(b: UiBuilder, idx: int): ptr UiNodeTransform {.inline.} =
  ## Get the transform for node at idx, or a pointer to the default transform if unset.
  let n = b.frame.nodes[idx]
  let transformSlot = int(n.transformIndex)
  if transformSlot > 0 and transformSlot <= b.frame.transforms.len: addr(b.frame.transforms[transformSlot - 1]) else: addr(b.defaultTransform)

proc nodeCustomCommands*(b: UiBuilder, idx: int): ptr ArrayView[UiRenderCommand] {.inline.} =
  ## Get the custom render commands for node at idx, or a pointer to the default empty view if unset.
  let n = b.frame.nodes[idx]
  let commandsSlot = int(n.commandsIndex)
  if commandsSlot > 0 and commandsSlot <= b.frame.customCommands.len: addr(b.frame.customCommands[commandsSlot - 1]) else: addr(b.defaultCustomCommands)

proc nodeCustomLayout*(b: UiBuilder, idx: int): ptr UiNodeCustomLayout {.inline.} =
  ## Get the custom layout for node at idx, or a pointer to the default (no-op) layout if unset.
  let n = b.frame.nodes[idx]
  let customLayoutSlot = int(n.customLayoutIndex)
  if customLayoutSlot > 0 and customLayoutSlot <= b.frame.customLayouts.len: addr(b.frame.customLayouts[customLayoutSlot - 1]) else: addr(b.defaultCustomLayout)

proc nodeCustomChildLayout*(b: UiBuilder, idx: int): ptr UiNodeCustomLayout {.inline.} =
  ## Get the custom child layout for node at idx, or a pointer to the default (no-op) layout if unset.
  let n = b.frame.nodes[idx]
  let customLayoutSlot = int(n.customChildLayoutIndex)
  if customLayoutSlot > 0 and customLayoutSlot <= b.frame.customLayouts.len: addr(b.frame.customLayouts[customLayoutSlot - 1]) else: addr(b.defaultCustomLayout)

proc nodeText*(b: UiBuilder, node: ptr UiNode): ptr UiNodeText {.inline.} =
  ## Get the text data for the given node, or a pointer to the default text if unset.
  let textSlot = int(node.textIndex)
  if textSlot > 0 and textSlot <= b.frame.texts.len: addr(b.frame.texts[textSlot - 1]) else: addr(b.defaultText)

proc nodeStyle*(b: UiBuilder, node: ptr UiNode): ptr UiStyle {.inline.} =
  ## Get the style for the given node, or a pointer to the default style if unset.
  let styleSlot = int(node.styleIndex)
  if styleSlot > 0 and styleSlot <= b.frame.styles.len: addr(b.frame.styles[styleSlot - 1]) else: addr(b.defaultStyle)

proc nodeGap*(b: UiBuilder, node: ptr UiNode): float32 {.inline.} =
  ## Get the gap value for the given node, or 0.0 if unset.
  let gapSlot = int(node.gapIndex)
  if gapSlot > 0 and gapSlot <= b.frame.gaps.len: b.frame.gaps[gapSlot - 1] else: 0.0'f32

proc nodeAnchor*(b: UiBuilder, node: ptr UiNode): ptr UiNodeAnchor {.inline.} =
  ## Get the anchor data for the given node, or a pointer to the default anchor if unset.
  let anchorSlot = int(node.anchorIndex)
  if anchorSlot > 0 and anchorSlot <= b.frame.anchors.len: addr(b.frame.anchors[anchorSlot - 1]) else: addr(b.defaultAnchor)

proc nodeTransform*(b: UiBuilder, node: ptr UiNode): ptr UiNodeTransform {.inline.} =
  ## Get the transform for the given node, or a pointer to the default transform if unset.
  let transformSlot = int(node.transformIndex)
  if transformSlot > 0 and transformSlot <= b.frame.transforms.len: addr(b.frame.transforms[transformSlot - 1]) else: addr(b.defaultTransform)

proc nodeCustomCommands*(b: UiBuilder, node: ptr UiNode): ptr ArrayView[UiRenderCommand] {.inline.} =
  ## Get the custom render commands for the given node, or a pointer to the default empty view if unset.
  let commandsSlot = int(node.commandsIndex)
  if commandsSlot > 0 and commandsSlot <= b.frame.customCommands.len: addr(b.frame.customCommands[commandsSlot - 1]) else: addr(b.defaultCustomCommands)

proc nodeCustomLayout*(b: UiBuilder, node: ptr UiNode): ptr UiNodeCustomLayout {.inline.} =
  ## Get the custom layout for the given node, or a pointer to the default (no-op) layout if unset.
  let customLayoutSlot = int(node.customLayoutIndex)
  if customLayoutSlot > 0 and customLayoutSlot <= b.frame.customLayouts.len: addr(b.frame.customLayouts[customLayoutSlot - 1]) else: addr(b.defaultCustomLayout)

proc nodeCustomChildLayout*(b: UiBuilder, node: ptr UiNode): ptr UiNodeCustomLayout {.inline.} =
  ## Get the custom child layout for the given node, or a pointer to the default (no-op) layout if unset.
  let customLayoutSlot = int(node.customChildLayoutIndex)
  if customLayoutSlot > 0 and customLayoutSlot <= b.frame.customLayouts.len: addr(b.frame.customLayouts[customLayoutSlot - 1]) else: addr(b.defaultCustomLayout)

proc setNodeText*(b: var UiBuilder, idx: int, value: UiNodeText) {.inline.} =
  ## Set the text data for the node at idx.
  b.ensureNodeText(b.frame.nodes[idx].addr) = value

proc setNodeStyle*(b: var UiBuilder, idx: int, value: UiStyle) {.inline.} =
  ## Set the style for the node at idx.
  b.ensureNodeStyle(b.frame.nodes[idx].addr) = value

proc setNodeStyleIndex*(b: var UiBuilder, idx: int, value: uint16) {.inline.} =
  ## Set the style index for the node at idx, referencing a theme style slot directly.
  b.frame.nodes[idx].styleIndex = value

proc setNodeStyleIndex*(b: var UiBuilder, idx: int, value: int) {.inline.} =
  ## Set the style index for the node at idx. Negative values are clamped to 0.
  b.setNodeStyleIndex(idx, max(0, value).uint16)

proc copyNodeStyleAtIndex*(b: var UiBuilder, idx: int, styleIndex: uint16) {.inline.} =
  ## Copy a theme style into the node's own style slot by theme index.
  let slot = int(styleIndex)
  if slot <= 0 or slot > b.frame.styles.len:
    return
  b.ensureNodeStyle(b.frame.nodes[idx].addr) = b.frame.styles[slot - 1]

proc copyNodeStyleAtIndex*(b: var UiBuilder, idx: int, styleIndex: int) {.inline.} =
  ## Copy a theme style into the node's own style slot by theme index (int overload).
  b.copyNodeStyleAtIndex(idx, max(0, styleIndex).uint16)

proc setNodeGap*(b: var UiBuilder, idx: int, value: float32) {.inline.} =
  ## Set the gap value for the node at idx.
  b.ensureNodeGap(b.frame.nodes[idx].addr) = value

proc setNodeAnchor*(b: var UiBuilder, idx: int, value: UiNodeAnchor) {.inline.} =
  ## Set the anchor data for the node at idx.
  b.ensureNodeAnchor(b.frame.nodes[idx].addr) = value

proc setNodeTransform*(b: var UiBuilder, idx: int, value: UiNodeTransform) {.inline.} =
  ## Set the transform for the node at idx.
  b.ensureNodeTransform(b.frame.nodes[idx].addr) = value

proc setNodeCustomCommands*(b: var UiBuilder, idx: int, value: ArrayView[UiRenderCommand]) {.inline.} =
  ## Set the custom render commands for the node at idx.
  b.ensureNodeCustomCommands(b.frame.nodes[idx].addr) = value

proc setNodeCustomChildLayout*(b: var UiBuilder, idx: int, value: UiNodeCustomLayout) {.inline.} =
  ## Set the custom child layout for the node at idx.
  b.ensureNodeCustomChildLayout(b.frame.nodes[idx].addr) = value

proc currentNodeText*(b: UiBuilder): ptr UiNodeText {.inline.} =
  ## Get the text data for the current node.
  b.nodeText(b.currentNode)

proc currentNodeStyle*(b: UiBuilder): ptr UiStyle {.inline.} =
  ## Get the style for the current node.
  b.nodeStyle(b.currentNode)

proc currentNodeGap*(b: UiBuilder): float32 {.inline.} =
  ## Get the gap value for the current node.
  b.nodeGap(b.currentNode)

proc currentNodeAnchor*(b: UiBuilder): ptr UiNodeAnchor {.inline.} =
  ## Get the anchor data for the current node.
  b.nodeAnchor(b.currentNode)

proc currentNodeTransform*(b: UiBuilder): ptr UiNodeTransform {.inline.} =
  ## Get the transform for the current node.
  b.nodeTransform(b.currentNode)

proc currentNodeCustomCommands*(b: UiBuilder): ptr ArrayView[UiRenderCommand] {.inline.} =
  ## Get the custom render commands for the current node.
  b.nodeCustomCommands(b.currentNode)

proc currentNodeCustomChildLayout*(b: UiBuilder): ptr UiNodeCustomLayout {.inline.} =
  ## Get the custom child layout for the current node.
  b.nodeCustomChildLayout(b.currentNode)

proc traceEvent*(b: var UiBuilder, nodeId: UiNodeId, event: string) {.inline, raises: [].} =
  ## Record an event string for the node with the given id. Events are cleared
  ## at the beginning of each frame (see `beginUiFrame`). Recording is gated by
  ## `traceMode`: nothing is recorded in `TraceNone`, only `traceNodeId` in
  ## `TraceNodeId`, and all nodes in `TraceAll`.
  case b.traceMode
  of TraceNone:
    return
  of TraceNodeId:
    if nodeId != b.traceNodeId:
      return
  of TraceAll:
    discard
  let key = uint64(nodeId)
  b.eventTraces.mgetOrPut(key, @[]).add(event)

proc traceEvent*(b: var UiBuilder, event: string): var UiBuilder {.discardable, inline, raises: [].} =
  ## Record an event string for the current node. Returns the builder for chaining
  ## (see `traceEvent`).
  b.traceEvent(b.currentNode.id, event)
  b

proc eventTracesFor*(b: UiBuilder, nodeId: UiNodeId): seq[string] {.inline, raises: [].} =
  ## Return the recorded event sequence for the node with the given id, or an empty seq.
  let key = uint64(nodeId)
  return b.eventTraces.getOrDefault(key, @[])

proc currentNodeEventTraces*(b: UiBuilder): seq[string] {.inline, raises: [].} =
  ## Return the recorded event sequence for the current node.
  b.eventTracesFor(b.currentNode.id)

proc setTraceMode*(b: var UiBuilder, mode: UiTraceMode): var UiBuilder {.discardable, inline, raises: [].} =
  ## Set the trace mode. For `TraceNodeId`, also set `traceNodeId` via the
  ## `nodeId` argument (defaults to none).
  b.traceMode = mode
  b

proc setTraceMode*(b: var UiBuilder, mode: UiTraceMode, nodeId: UiNodeId): var UiBuilder {.discardable, inline, raises: [].} =
  ## Set the trace mode and, for `TraceNodeId`, the specific node to trace.
  b.traceMode = mode
  b.traceNodeId = nodeId
  b

proc setCurrentNodeText*(b: var UiBuilder, value: UiNodeText) {.inline.} =
  ## Set the text data for the current node.
  b.ensureNodeText(b.currentNode) = value

proc setCurrentNodeTextIndex*(b: var UiBuilder, value: uint16) {.inline.} =
  ## Set the text index for the current node, referencing a theme text slot directly.
  b.currentNode.textIndex = value

proc setCurrentNodeTextIndex*(b: var UiBuilder, value: int) {.inline.} =
  ## Set the text index for the current node. Negative values are clamped to 0.
  b.currentNode.textIndex = max(0, value).uint16

proc copyCurrentNodeTextAtIndex*(b: var UiBuilder, textIndex: uint16) {.inline.} =
  ## Copy a theme style into the current node's own style slot by theme index.
  let slot = int(textIndex)
  if slot <= 0 or slot > b.frame.texts.len:
    return
  if b.currentNode.textIndex.int < b.themeTextStyles.len:
    b.currentNode.textIndex = 0
  let dst = b.ensureNodeText(b.currentNode).addr
  let source = b.frame.texts[slot - 1].addr
  dst.fontSize = source.fontSize
  dst.fontId = source.fontId
  dst.textColor = source.textColor
  dst.text = "".uiString
  dst.measuredTextSizeCache = vec2(0)
  dst.measuredTextDirty = false

proc copyCurrentNodeTextAtIndex*(b: var UiBuilder, textIndex: int) {.inline.} =
  ## Copy a theme style into the current node's own style slot by theme index (int overload).
  b.copyCurrentNodeTextAtIndex(max(0, textIndex).uint16)

proc ensureThemeTextStyleSlot(b: var UiBuilder, styleIndex: uint16): var UiNodeText =
  let slot = int(styleIndex)
  if slot <= 0:
    return b.defaultText
  if b.themeTextStyles.len < slot:
    let oldLen = b.themeTextStyles.len
    b.themeTextStyles.setLen(slot)
    for i in oldLen ..< b.themeTextStyles.len:
      b.themeTextStyles[i] = b.defaultText
  b.themeTextStyles[slot - 1]

proc addThemeTextStyle*(b: var UiBuilder, text: UiNodeText): uint16 =
  result = b.themeTextStyles.len.uint16 + 1
  b.ensureThemeTextStyleSlot(result) = text

proc themeTextStyle*(b: UiBuilder, textStyleIndex: uint16): ptr UiNodeText {.inline.} =
  ## Get a pointer to a theme text style slot by index.
  let slot = int(textStyleIndex)
  if slot > 0 and slot <= b.themeTextStyles.len: addr(b.themeTextStyles[slot - 1]) else: addr(b.defaultText)

proc themeTextStyle*(b: UiBuilder, textStyleIndex: int): ptr UiNodeText {.inline.} =
  ## Get a pointer to a theme text style slot by index (int overload).
  b.themeTextStyle(max(0, textStyleIndex).uint16)

proc themeTextStyle*(b: UiBuilder, textStyleIndex: UiTextStyleIndex): ptr UiNodeText {.inline.} =
  ## Get a pointer to a theme text style slot by index (int overload).
  b.themeTextStyle(textStyleIndex.uint16)

proc setThemeTextStyle*(b: var UiBuilder, textStyleIndex: uint16, value: UiNodeText): var UiBuilder {.discardable.} =
  ## Set a theme text style slot by index. Also updates defaultText if setting the default slot.
  b.ensureThemeTextStyleSlot(textStyleIndex) = value
  if textStyleIndex == UiStyleIndexDefault.uint16:
    b.defaultText = value
  b

proc setThemeTextStyle*(b: var UiBuilder, styleIndex: int, value: UiNodeText): var UiBuilder {.discardable.} =
  ## Set a theme style slot by index (int overload).
  b.setThemeTextStyle(max(0, styleIndex).uint16, value)

proc setCurrentNodeStyle*(b: var UiBuilder, value: UiStyle) {.inline.} =
  ## Set the style for the current node.
  b.ensureNodeStyle(b.currentNode) = value

proc setCurrentNodeStyleIndex*(b: var UiBuilder, value: uint16) {.inline.} =
  ## Set the style index for the current node, referencing a theme style slot directly.
  b.currentNode.styleIndex = value

proc setCurrentNodeStyleIndex*(b: var UiBuilder, value: int) {.inline.} =
  ## Set the style index for the current node. Negative values are clamped to 0.
  b.currentNode.styleIndex = max(0, value).uint16

proc copyCurrentNodeStyleAtIndex*(b: var UiBuilder, styleIndex: uint16) {.inline.} =
  ## Copy a theme style into the current node's own style slot by theme index.
  let slot = int(styleIndex)
  if slot <= 0 or slot > b.frame.styles.len:
    return
  b.ensureNodeStyle(b.currentNode) = b.frame.styles[slot - 1]

proc copyCurrentNodeStyleAtIndex*(b: var UiBuilder, styleIndex: int) {.inline.} =
  ## Copy a theme style into the current node's own style slot by theme index (int overload).
  b.copyCurrentNodeStyleAtIndex(max(0, styleIndex).uint16)

proc ensureThemeStyleSlot(b: var UiBuilder, styleIndex: uint16): var UiStyle =
  let slot = int(styleIndex)
  if slot <= 0:
    return b.defaultStyle
  if b.themeStyles.len < slot:
    let oldLen = b.themeStyles.len
    b.themeStyles.setLen(slot)
    for i in oldLen ..< b.themeStyles.len:
      b.themeStyles[i] = b.defaultStyle
  b.themeStyles[slot - 1]

proc themeStyle*(b: UiBuilder, styleIndex: uint16): ptr UiStyle {.inline.} =
  ## Get a pointer to a theme style slot by index.
  let slot = int(styleIndex)
  if slot > 0 and slot <= b.themeStyles.len: addr(b.themeStyles[slot - 1]) else: addr(b.defaultStyle)

proc themeStyle*(b: UiBuilder, styleIndex: int): ptr UiStyle {.inline.} =
  ## Get a pointer to a theme style slot by index (int overload).
  b.themeStyle(max(0, styleIndex).uint16)

proc themeStyle*(b: UiBuilder, styleIndex: UiStyleIndex): ptr UiStyle {.inline.} =
  ## Get a pointer to a theme style slot by index (int overload).
  b.themeStyle(styleIndex.uint16)

proc setThemeStyle*(b: var UiBuilder, styleIndex: uint16, value: UiStyle): var UiBuilder {.discardable.} =
  ## Set a theme style slot by index. Also updates defaultStyle if setting the default slot.
  b.ensureThemeStyleSlot(styleIndex) = value
  if styleIndex == UiStyleIndexDefault.uint16:
    b.defaultStyle = value
  b

proc setThemeStyle*(b: var UiBuilder, styleIndex: int, value: UiStyle): var UiBuilder {.discardable.} =
  ## Set a theme style slot by index (int overload).
  b.setThemeStyle(max(0, styleIndex).uint16, value)

proc virtualizeNode*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Mark the current node so that, if it is absent from a future frame, it is
  ## automatically promoted into a persistent virtual node (see `endUiFrame`).
  b.currentNode.flags.incl VirtualizeNode
  b

proc virtualizeNode*(b: var UiBuilder, animations: seq[UiFieldAnimation]): var UiBuilder {.discardable.} =
  ## Mark the current node to be virtualized (see `virtualizeNode()`) and record the
  ## given per-field `animations` to attach to the resulting virtual node.
  b.currentNode.flags.incl VirtualizeNode
  b.virtualNodeAnimations[uint64(b.currentNode.id)] = animations
  b

proc styleIndex*(b: var UiBuilder, value: uint16): var UiBuilder {.discardable.} =
  ## Fluent setter: set the current node's style index to a theme slot.
  b.setCurrentNodeStyleIndex(value)
  b

proc styleIndex*(b: var UiBuilder, value: int): var UiBuilder {.discardable.} =
  ## Fluent setter: set the current node's style index to a theme slot (int overload).
  b.setCurrentNodeStyleIndex(value)
  b

proc styleIndex*(b: var UiBuilder, value: UiStyleIndex): var UiBuilder {.discardable.} =
  ## Fluent setter: set the current node's style index to a theme slot (int overload).
  b.setCurrentNodeStyleIndex(value.uint16)
  b

proc copyStyleIndex*(b: var UiBuilder, value: uint16): var UiBuilder {.discardable.} =
  ## Fluent setter: copy a theme style into the current node's style slot.
  b.copyCurrentNodeStyleAtIndex(value)
  b

proc copyStyleIndex*(b: var UiBuilder, value: int): var UiBuilder {.discardable.} =
  ## Fluent setter: copy a theme style into the current node's style slot (int overload).
  b.copyCurrentNodeStyleAtIndex(value)
  b

proc copyStyleIndex*(b: var UiBuilder, value: UiStyleIndex): var UiBuilder {.discardable.} =
  ## Fluent setter: copy a theme style into the current node's style slot (int overload).
  b.copyCurrentNodeStyleAtIndex(value.uint16)
  b

proc textStyleIndex*(b: var UiBuilder, value: uint16): var UiBuilder {.discardable.} =
  ## Fluent setter: set the current node's text style index to a theme slot.
  b.setCurrentNodeTextIndex(value)
  b

proc textStyleIndex*(b: var UiBuilder, value: int): var UiBuilder {.discardable.} =
  ## Fluent setter: set the current node's text style index to a theme slot (int overload).
  b.setCurrentNodeTextIndex(value)
  b

proc copyTextStyleIndex*(b: var UiBuilder, value: uint16): var UiBuilder {.discardable.} =
  ## Fluent setter: copy a theme text style into the current node's text slot.
  b.copyCurrentNodeTextAtIndex(value)
  b

proc copyTextStyleIndex*(b: var UiBuilder, value: int): var UiBuilder {.discardable.} =
  ## Fluent setter: copy a theme text style into the current node's text slot (int overload).
  b.copyCurrentNodeTextAtIndex(value)
  b

proc copyTextStyleIndex*(b: var UiBuilder, value: UiTextStyleIndex): var UiBuilder {.discardable.} =
  ## Fluent setter: copy a theme text style into the current node's text slot (int overload).
  b.copyCurrentNodeTextAtIndex(value.uint16)
  b

proc setCurrentNodeGap*(b: var UiBuilder, value: float32) {.inline.} =
  ## Set the gap value for the current node.
  b.ensureNodeGap(b.currentNode) = value

proc setCurrentNodeAnchor*(b: var UiBuilder, value: UiNodeAnchor) {.inline.} =
  ## Set the anchor data for the current node.
  b.ensureNodeAnchor(b.currentNode) = value

proc setCurrentNodeTransform*(b: var UiBuilder, value: UiNodeTransform) {.inline.} =
  ## Set the transform for the current node.
  b.ensureNodeTransform(b.currentNode) = value

proc setCurrentNodeCustomCommands*(b: var UiBuilder, value: ArrayView[UiRenderCommand]) {.inline.} =
  ## Set the custom render commands for the current node.
  b.ensureNodeCustomCommands(b.currentNode) = value

proc setCurrentNodeCustomChildLayout*(b: var UiBuilder, value: UiNodeCustomLayout) {.inline.} =
  ## Set the custom child layout for the current node.
  b.ensureNodeCustomChildLayout(b.currentNode) = value

const
  UiIdOffsetBasis = 1469598103934665603'u64
  UiIdPrime = 1099511628211'u64
  UiIdRootSeed = 0xD1CE_BA5E_1234_5678'u64
  UiIdAutoSeed = 0x9E37_79B9_7F4A_7C15'u64

func mixIdByte(hash: uint64, value: uint8): uint64 {.inline.} =
  (hash xor value.uint64) * UiIdPrime

func hashUint64(value: uint64): uint64 =
  var hash = UiIdOffsetBasis
  var v = value
  for _ in 0 ..< 8:
    hash = mixIdByte(hash, (v and 0xFF'u64).uint8)
    v = v shr 8
  hash

func hashChars*(value: openArray[char]): uint64 =
  ## Hash a char sequence using FNV-1a for deterministic node ID generation.
  var hash = UiIdOffsetBasis
  for ch in value:
    hash = mixIdByte(hash, ch.uint8)
  hash

func combineIdHash(seed, part: uint64): uint64 {.inline.} =
  var hash = (seed xor UiIdOffsetBasis) * UiIdPrime
  hash = (hash xor part) * UiIdPrime
  if hash == 0'u64:
    return 1'u64
  hash

func toNodeId*(value: uint64): UiNodeId {.inline.} =
  ## Convert a uint64 to a UiNodeId. Zero is remapped to 1 (the none node is 0).
  UiNodeId(if value == 0'u64: 1'u64 else: value)

func nodeIdValue*(value: UiNodeId): uint64 {.inline.} =
  ## Extract the raw uint64 value from a UiNodeId.
  uint64(value)

func deriveNodeId*(parent: UiNodeId, value: openArray[char]): UiNodeId {.inline.} =
  ## Derive a stable logical ID from a parent ID and character key.
  toNodeId(combineIdHash(nodeIdValue(parent), hashChars(value)))

func rootNodeId*(): UiNodeId {.inline.} =
  ## Returns the deterministic ID of the root node (always created at frame start).
  toNodeId(combineIdHash(UiIdRootSeed, hashChars("root")))

iterator children*(b: UiBuilder, idx: int, frame: ptr UiFrame): int =
  ## Iterate over the child indices of the node at idx in the given frame.
  if idx >= 0 and idx < frame.nodes.len:
    let tail = frame.nodes[idx].lastChild
    if tail >= 0:
      let start = int(frame.nodes[int(tail)].nextSibling)
      var child = start
      while true:
        yield child
        if child == int(tail):
          break
        child = int(frame.nodes[child].nextSibling)

iterator children*(b: UiBuilder, node: ptr UiNode, frame: ptr UiFrame): int =
  ## Iterate over the child indices of the node in the given frame.
  let tail = node.lastChild
  if tail >= 0:
    let start = int(frame.nodes[int(tail)].nextSibling)
    var child = start
    while true:
      yield child
      if child == int(tail):
        break
      child = int(frame.nodes[child].nextSibling)

iterator children*(b: UiBuilder, idx: int): int =
  ## Iterate over the child indices of the node at idx in the current frame.
  if idx >= 0 and idx < b.frame.nodes.len:
    let tail = b.frame.nodes[idx].lastChild
    if tail >= 0:
      let start = int(b.frame.nodes[int(tail)].nextSibling)
      var child = start
      while true:
        yield child
        if child == int(tail):
          break
        child = int(b.frame.nodes[child].nextSibling)

proc childCount*(b: UiBuilder, idx: int): int =
  ## Return the number of children of the node at idx.
  result = 0
  for _ in b.children(idx):
    result.inc

proc firstChildIndex*(b: UiBuilder, idx: int): int {.inline.} =
  ## Return the index of the first child of the node at idx, or -1 if it has no children.
  if idx < 0 or idx >= b.frame.nodes.len:
    return -1

  let tail = b.frame.nodes[idx].lastChild
  if tail < 0:
    return -1

  int(b.frame.nodes[int(tail)].nextSibling)

proc hasLayout*(flags: UiFlags): bool {.inline.} =
  ## Returns true if the flags contain either LayoutVertical or LayoutHorizontal.
  LayoutVertical in flags or LayoutHorizontal in flags

proc isAnchoredLayoutX*(node: UiNode): bool {.inline.} =
  ## Returns true if the node uses anchored layout on the X axis.
  AnchorX in node.flags

proc isAnchoredLayoutY*(node: UiNode): bool {.inline.} =
  ## Returns true if the node uses anchored layout on the Y axis.
  AnchorY in node.flags

proc isAnchoredLayout*(node: UiNode): bool {.inline.} =
  ## Returns true if the node uses anchored layout on either axis.
  isAnchoredLayoutX(node) or isAnchoredLayoutY(node)

proc isHorizontalLayout*(flags: UiFlags): bool {.inline.} =
  ## Returns true if the flags indicate a horizontal layout.
  LayoutHorizontal in flags

proc isVerticalLayout*(flags: UiFlags): bool {.inline.} =
  ## Returns true if the flags indicate a vertical layout.
  LayoutVertical in flags

proc isReverseLayout*(flags: UiFlags): bool {.inline.} =
  ## Returns true if the flags indicate reverse direction layout.
  DirectionReverse in flags

proc setNodeLayoutKind*(flags: var UiFlags, value: UiFlag) {.inline.} =
  ## Set the layout kind flag, clearing both LayoutVertical and LayoutHorizontal first.
  flags.excl LayoutVertical
  flags.excl LayoutHorizontal
  flags.incl value

proc setNodeDirectionKind*(flags: var UiFlags, value: UiFlag) {.inline.} =
  ## Set the direction kind flag, clearing DirectionReverse first.
  flags.excl DirectionReverse
  if value == DirectionReverse:
    flags.incl DirectionReverse

proc nextAutoNodeKey*(b: var UiBuilder, parentIndex: int): uint64 =
  ## Return the next auto-generated child key for the given parent, incrementing its counter.
  if parentIndex < 0 or parentIndex >= b.autoChildCounter.len:
    return 1'u64

  let current = b.autoChildCounter[parentIndex]
  b.autoChildCounter[parentIndex] = current + 1
  current.uint64 + 1'u64

func noneIdScopeHash*(): uint64 {.inline.} =
  ## Returns the base hash value used when no ID scope is active.
  UiIdOffsetBasis

func currentNodePathId*(b: UiBuilder): UiNodeId {.inline.} =
  ## Returns the node ID at the top of the ID stack, or the root node ID if empty.
  if b.nodeIdStack.len > 0:
    b.nodeIdStack[^1]
  else:
    rootNodeId()

func currentIdSeed*(b: UiBuilder): uint64 {.inline.} =
  ## Compute the current ID seed by combining the node path ID with any active ID scope.
  var seed = nodeIdValue(b.currentNodePathId())
  if b.idScopeStack.len > 0:
    seed = combineIdHash(seed, b.idScopeStack[^1])
  seed

proc computeChildNodeId(b: var UiBuilder, parentIndex: int, explicitKeyHash: uint64): UiNodeId =
  let keyHash =
    if explicitKeyHash != 0'u64:
      explicitKeyHash
    else:
      combineIdHash(UiIdAutoSeed, hashUint64(b.nextAutoNodeKey(parentIndex)))
  toNodeId(combineIdHash(b.currentIdSeed(), keyHash))

proc generateId*(b: var UiBuilder): UiNodeId =
  b.computeChildNodeId(b.stack[^1], 0)

proc generateId*(b: var UiBuilder, value: uint64): UiNodeId =
  b.computeChildNodeId(b.stack[^1], hashUint64(value))

proc generateId*(b: var UiBuilder, value: string): UiNodeId =
  b.computeChildNodeId(b.stack[^1], hashChars(value))

proc pushId*(b: var UiBuilder, value: uint64): var UiBuilder {.discardable.} =
  ## Push an ID scope by hashing the given uint64 value onto the scope stack.
  let parentHash = if b.idScopeStack.len > 0: b.idScopeStack[^1] else: noneIdScopeHash()
  b.idScopeStack.add combineIdHash(parentHash, hashUint64(value))
  b

proc pushId*(b: var UiBuilder, value: openArray[char]): var UiBuilder {.discardable.} =
  ## Push an ID scope by hashing the given char array onto the scope stack.
  let parentHash = if b.idScopeStack.len > 0: b.idScopeStack[^1] else: noneIdScopeHash()
  b.idScopeStack.add combineIdHash(parentHash, hashChars(value))
  b

proc popId*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Pop the top ID scope from the stack.
  if b.idScopeStack.len > 0:
    discard b.idScopeStack.pop()
  b

proc clearFrameOutput(output: var UiFrameOutput) =
  output.hoveredId = noneNodeId()
  output.hoveredIndex = -1
  output.scrolledId = noneNodeId()
  output.scrolledIndex = -1
  output.hoverBeganId = noneNodeId()
  output.hoverEndedId = noneNodeId()
  output.pressedId = noneNodeId()
  output.pressedIndex = -1
  output.heldId = noneNodeId()
  output.heldIndex = -1
  output.draggedId = noneNodeId()
  output.draggedIndex = -1
  output.rightPressedId = noneNodeId()
  output.rightPressedIndex = -1
  output.clickedId = noneNodeId()
  output.clickedIndex = -1
  output.rightClickedId = noneNodeId()
  output.rightClickedIndex = -1
  output.commandLayers.setLen(0)
  output.commands.setLen(0)

proc initDefaultThemeStyles*(): seq[UiStyle] =
  result = newSeq[UiStyle](UiThemeStyleSlotCount)

  let grayWindow = UiColor(r: 0.07'f32, g: 0.07'f32, b: 0.08'f32, a: 1.0'f32)
  let grayBg = UiColor(r: 0.07'f32, g: 0.07'f32, b: 0.08'f32, a: 1.0'f32)
  let graySurface = UiColor(r: 0.10'f32, g: 0.10'f32, b: 0.11'f32, a: 1.0'f32)
  let grayButton = UiColor(r: 0.18'f32, g: 0.18'f32, b: 0.20'f32, a: 1.0'f32)
  let graySurfaceHi = UiColor(r: 0.15'f32, g: 0.15'f32, b: 0.16'f32, a: 1.0'f32)
  let grayHover = UiColor(r: 0.26'f32, g: 0.26'f32, b: 0.29'f32, a: 1.0'f32)
  let grayBorder = UiColor(r: 0.22'f32, g: 0.22'f32, b: 0.25'f32, a: 1.0'f32)
  let grayBorderStrong = UiColor(r: 0.32'f32, g: 0.32'f32, b: 0.36'f32, a: 1.0'f32)
  let grayScroll = UiColor(r: 0.30'f32, g: 0.30'f32, b: 0.34'f32, a: 0.95'f32)
  let accent = UiColor(r: 0.95'f32, g: 0.55'f32, b: 0.15'f32, a: 1.0'f32)

  result[int(UiStyleIndexDefault) - 1] = UiStyle(
  )
  result[int(UiStyleIndexWindow) - 1] = UiStyle(
    borderWidth: 1.0'f32,
    cornerRadius: 6.0'f32,
    fillColor: grayWindow,
    borderColor: grayBorderStrong,
  )
  result[int(UiStyleIndexWindowTitleBar) - 1] = UiStyle(
    paddingX: 4.0'f32,
    paddingY: 4.0'f32,
    fillColor: graySurface,
  )
  result[int(UiStyleIndexWindowTitleBarCollapseHover) - 1] = UiStyle(
    cornerRadius: 2.0'f32,
    fillColor: grayHover,
  )
  result[int(UiStyleIndexWindowContent) - 1] = UiStyle(
    paddingX: 0.0'f32,
    paddingY: 0.0'f32,
  )
  result[int(UiStyleIndexWindowResizeHandle) - 1] = UiStyle(
    cornerRadius: 2.0'f32,
    fillColor: grayBorderStrong,
  )
  result[int(UiStyleIndexButton) - 1] = UiStyle(
    paddingX: 4.0'f32,
    paddingY: 0.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayButton,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexButtonHover) - 1] = UiStyle(
    paddingX: 4.0'f32,
    paddingY: 0.0'f32,
    borderWidth: 1.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayHover,
    borderColor: accent,
  )
  result[int(UiStyleIndexCheckbox) - 1] = UiStyle(
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayButton,
    borderColor: grayBorderStrong,
  )
  result[int(UiStyleIndexCheckboxHover) - 1] = UiStyle(
    borderWidth: 1.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayHover,
    borderColor: accent,
  )
  result[int(UiStyleIndexCheckboxMark) - 1] = UiStyle(
    fillColor: accent,
  )
  result[int(UiStyleIndexSlider) - 1] = UiStyle(
  )
  result[int(UiStyleIndexSliderTrack) - 1] = UiStyle(
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: graySurface,
    borderColor: grayBorderStrong,
  )
  result[int(UiStyleIndexSliderTrackHover) - 1] = UiStyle(
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayHover,
    borderColor: grayBorderStrong,
  )
  result[int(UiStyleIndexSliderFill) - 1] = UiStyle(
    cornerRadius: 4.0'f32,
    fillColor: accent,
    borderColor: accent,
  )
  result[int(UiStyleIndexSliderHandle) - 1] = UiStyle(
    cornerRadius: 4.0'f32,
    fillColor: accent,
  )
  result[int(UiStyleIndexScrollBar) - 1] = UiStyle(
    cornerRadius: 4.0'f32,
    fillColor: UiColor(r: 0.10'f32, g: 0.10'f32, b: 0.11'f32, a: 0.92'f32),
  )
  result[int(UiStyleIndexScrollBarHandle) - 1] = UiStyle(
    cornerRadius: 4.0'f32,
    fillColor: grayScroll,
  )
  result[int(UiStyleIndexScrollBarHandleHover) - 1] = UiStyle(
    cornerRadius: 4.0'f32,
    fillColor: grayBorderStrong,
  )
  result[int(UiStyleIndexTabBarHeader) - 1] = UiStyle(
    paddingX: 4.0'f32,
    paddingY: 4.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 6.0'f32,
    fillColor: graySurface,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexTabBarItem) - 1] = UiStyle(
    paddingX: 6.0'f32,
    paddingY: 2.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayButton,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexTabBarItemActive) - 1] = UiStyle(
    paddingX: 6.0'f32,
    paddingY: 2.0'f32,
    borderWidth: 1.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayHover,
    borderColor: accent,
  )
  result[int(UiStyleIndexTabBarContent) - 1] = UiStyle(
    paddingX: 6.0'f32,
    paddingY: 6.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 6.0'f32,
    fillColor: grayBg,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexTextField) - 1] = UiStyle(
    paddingX: 6.0'f32,
    paddingY: 6.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayBg,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexTextFieldFocused) - 1] = UiStyle(
    paddingX: 6.0'f32,
    paddingY: 6.0'f32,
    borderWidth: 1.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: graySurface,
    borderColor: accent,
  )
  result[int(UiStyleIndexTextFieldHint) - 1] = UiStyle(
  )
  result[int(UiStyleIndexTextCursor) - 1] = UiStyle(
    fillColor: accent,
  )
  result[int(UiStyleIndexMenu) - 1] = UiStyle(
    paddingX: 4.0'f32,
    paddingY: 4.0'f32,
    borderWidth: 1.0'f32,
    cornerRadius: 6.0'f32,
    fillColor: graySurface,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexMenuItem) - 1] = UiStyle(
    paddingX: 8.0'f32,
    paddingY: 6.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: UiColor(r: 0.13'f32, g: 0.13'f32, b: 0.14'f32, a: 0.0'f32),
    borderColor: UiColor(r: 0.13'f32, g: 0.13'f32, b: 0.14'f32, a: 0.0'f32),
  )
  result[int(UiStyleIndexMenuItemHover) - 1] = UiStyle(
    paddingX: 8.0'f32,
    paddingY: 6.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayHover,
    borderColor: grayHover,
  )
  result[int(UiStyleIndexMenuBar) - 1] = UiStyle(
    paddingX: 4.0'f32,
    paddingY: 4.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 0.0'f32,
    fillColor: graySurfaceHi,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexPanel) - 1] = UiStyle(
    paddingX: 8.0'f32,
    paddingY: 8.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayWindow,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexStage) - 1] = UiStyle(
    paddingX: 8.0'f32,
    paddingY: 8.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayWindow,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexCard) - 1] = UiStyle(
    paddingX: 10.0'f32,
    paddingY: 10.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: grayWindow,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexHeader) - 1] = UiStyle(
    paddingX: 8.0'f32,
    paddingY: 6.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: graySurfaceHi,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexRow) - 1] = UiStyle(
    paddingX: 8.0'f32,
    paddingY: 6.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 3.0'f32,
    fillColor: graySurface,
    borderColor: graySurface,
  )
  result[int(UiStyleIndexRowAlt) - 1] = UiStyle(
    paddingX: 8.0'f32,
    paddingY: 6.0'f32,
    borderWidth: 0.0'f32,
    cornerRadius: 3.0'f32,
    fillColor: graySurfaceHi,
    borderColor: graySurfaceHi,
  )
  result[int(UiStyleIndexTooltip) - 1] = UiStyle(
    paddingX: 8.0'f32,
    paddingY: 6.0'f32,
    borderWidth: 1.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: graySurface,
    borderColor: grayBorder,
  )
  result[int(UiStyleIndexAccent) - 1] = UiStyle(
    paddingX: 6.0'f32,
    paddingY: 6.0'f32,
    borderWidth: 1.0'f32,
    cornerRadius: 4.0'f32,
    fillColor: accent,
    borderColor: accent,
  )



proc initDefaultThemeTextStyles*(): seq[UiNodeText] =
  result = newSeq[UiNodeText](UiTextStyleCount)

  let defaultText = UiColor(r: 0.86'f32, g: 0.86'f32, b: 0.88'f32, a: 1.0'f32)
  let accentWarm = UiColor(r: 0.95'f32, g: 0.55'f32, b: 0.15'f32, a: 1.0'f32)

  result[int(UiStyleIndexDefaultText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Default".uiString,
    textColor: defaultText,
  )
  result[int(UiStyleIndexSmallText) - 1] = UiNodeText(
    fontSize: 12,
    text: "Small".uiString,
    textColor: defaultText,
  )
  result[int(UiStyleIndexLargeText) - 1] = UiNodeText(
    fontSize: 18,
    text: "Large".uiString,
    textColor: defaultText,
  )
  result[int(UiStyleIndexExtraLargeText) - 1] = UiNodeText(
    fontSize: 50,
    text: "Extra Large".uiString,
    textColor: defaultText,
  )
  result[int(UiStyleIndexButtonText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Button".uiString,
    textColor: UiColor(r: 0.96'f32, g: 0.96'f32, b: 0.98'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexMenuItemHoverText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Menu Item Hover".uiString,
    textColor: UiColor(r: 0.98'f32, g: 0.98'f32, b: 0.99'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexMenuItemText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Menu Item".uiString,
    textColor: UiColor(r: 0.94'f32, g: 0.95'f32, b: 0.97'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexLabelText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Label".uiString,
    textColor: UiColor(r: 0.94'f32, g: 0.94'f32, b: 0.97'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexWindowText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Window".uiString,
    textColor: defaultText,
  )
  result[int(UiStyleIndexWindowTitleBarText) - 1] = UiNodeText(
    fontSize: 16,
    text: "Window Title Bar".uiString,
    textColor: UiColor(r: 0.95'f32, g: 0.96'f32, b: 0.99'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexWindowContentText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Window Content".uiString,
    textColor: UiColor(r: 0.90'f32, g: 0.92'f32, b: 0.96'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexButtonHoverText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Button Hover".uiString,
    textColor: UiColor(r: 0.96'f32, g: 0.96'f32, b: 0.98'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexCheckboxText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Checkbox".uiString,
    textColor: defaultText,
  )
  result[int(UiStyleIndexCheckboxHoverText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Checkbox Hover".uiString,
    textColor: defaultText,
  )
  result[int(UiStyleIndexCheckboxMarkText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Checkbox Mark".uiString,
    textColor: accentWarm,
  )
  result[int(UiStyleIndexSliderText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Slider".uiString,
    textColor: UiColor(r: 0.94'f32, g: 0.94'f32, b: 0.97'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexTabBarHeaderText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Tab Bar Header".uiString,
    textColor: defaultText,
  )
  result[int(UiStyleIndexTabBarItemText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Tab Bar Item".uiString,
    textColor: UiColor(r: 0.86'f32, g: 0.88'f32, b: 0.92'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexTabBarItemActiveText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Tab Bar Item Active".uiString,
    textColor: UiColor(r: 0.98'f32, g: 0.98'f32, b: 0.98'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexTabBarContentText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Tab Bar Content".uiString,
    textColor: defaultText,
  )
  result[int(UiStyleIndexTextFieldText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Text Field".uiString,
    textColor: UiColor(r: 0.94'f32, g: 0.94'f32, b: 0.97'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexTextFieldFocusedText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Text Field Focused".uiString,
    textColor: UiColor(r: 0.94'f32, g: 0.94'f32, b: 0.97'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexTextFieldHintText) - 1] = UiNodeText(
    fontSize: 14,
    text: "Text Field Hint".uiString,
    textColor: UiColor(r: 0.50'f32, g: 0.55'f32, b: 0.65'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexHeadingText) - 1] = UiNodeText(
    fontSize: 18,
    text: "Heading".uiString,
    textColor: UiColor(r: 0.95'f32, g: 0.55'f32, b: 0.15'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexMutedText) - 1] = UiNodeText(
    fontSize: 12,
    text: "Muted".uiString,
    textColor: UiColor(r: 0.84'f32, g: 0.88'f32, b: 0.94'f32, a: 1.0'f32),
  )
  result[int(UiStyleIndexHeaderText) - 1] = UiNodeText(
    fontSize: 12,
    text: "Header".uiString,
    textColor: UiColor(r: 0.95'f32, g: 0.55'f32, b: 0.15'f32, a: 1.0'f32),
  )

func rgba*[T: SomeNumber](r, g, b: T, a: T = T(1)): UiColor =
  ## Construct a UiColor from numeric values (0-1 range for float, 0-255 for int).
  UiColor(r: r.float32, g: g.float32, b: b.float32, a: a.float32)

func hasPerCornerRadii*(style: UiStyle): bool {.inline.} =
  style.cornerRadii.topLeft != 0.0'f32 or
    style.cornerRadii.topRight != 0.0'f32 or
    style.cornerRadii.bottomRight != 0.0'f32 or
    style.cornerRadii.bottomLeft != 0.0'f32

func hasPerSideBorderWidths*(style: UiStyle): bool {.inline.} =
  style.borderWidths.left != 0.0'f32 or
    style.borderWidths.top != 0.0'f32 or
    style.borderWidths.right != 0.0'f32 or
    style.borderWidths.bottom != 0.0'f32

func hasColor(color: UiColor): bool {.inline.} =
  color.r != 0.0'f32 or color.g != 0.0'f32 or
    color.b != 0.0'f32 or color.a != 0.0'f32

func hasPerSideBorderColors*(style: UiStyle): bool {.inline.} =
  style.borderColors.left.hasColor or
    style.borderColors.top.hasColor or
    style.borderColors.right.hasColor or
    style.borderColors.bottom.hasColor

func resolvedCornerRadii*(style: UiStyle): UiCornerRadii {.inline.} =
  if style.hasPerCornerRadii: style.cornerRadii
  else: uniformCornerRadii(style.cornerRadius)

func resolvedBorderWidths*(style: UiStyle): UiBorderWidths {.inline.} =
  if style.hasPerSideBorderWidths: style.borderWidths
  else: uniformBorderWidths(style.borderWidth)

func resolvedBorderColors*(style: UiStyle): UiBorderColors {.inline.} =
  if style.hasPerSideBorderColors: style.borderColors
  else: uniformBorderColors(style.borderColor)

proc fmt1*(value: float32): string =
  ## Format a float32 to 1 decimal place.
  formatFloat(value.float64, ffDecimal, 1)

proc fmt2*(value: float32): string =
  ## Format a float32 to 2 decimal places.
  formatFloat(value.float64, ffDecimal, 2)

proc nodeDebugName*(node: UiNode): string =
  ## Return the debug name of a node, or "<unnamed>" if debug names are disabled or empty.
  when defined(nuiDebug):
    if node.debugName.len <= 0:
      return "<unnamed>"
    result = node.debugName
  else:
    return "<unnamed>"

template traceUiNode*(b: UiBuilder, eventName: string, idx: int): untyped =
  ## Log node details (id, pos, size, flags) when debugLogUi is defined.
  when defined(debugLogUi) and not defined(nimony):
    if idx >= 0 and idx < b.frame.nodes.len:
      let n = b.frame.nodes[idx].addr
      debugLog(
        eventName &
        " idx=" & $idx &
        " id=" & $nodeIdValue(n.id) &
        " pos=(" & fmt1(n.pos.x) & "," & fmt1(n.pos.y) & ")" &
        " size=(" & fmt1(n.size.x) & "," & fmt1(n.size.y) & ")" &
        " flags=" & $n.flags
      )

proc newBuilder*(measureText: UiMeasureTextFn, buildTextMesh: nil UiBuildTextMeshFn = nil,
  textHeight = 16.0'f32, antialiasMeshWidth = 0.0'f32): UiBuilder =
  ## Create a new UiBuilder with default theme styles and the given text metrics.
  let frameArenaPtr = cast[ptr Arena](alloc0(sizeof(Arena)))
  let previousFrameArenaPtr = cast[ptr Arena](alloc0(sizeof(Arena)))
  frameArenaPtr[] = initArena(3 * 1024 * 1024)
  previousFrameArenaPtr[] = initArena(3 * 1024 * 1024)

  result = UiBuilder(
    frame: UiFrame(
      arena: frameArenaPtr,
      arenaCheckpoint: 0'u64,
      nodeIdToIndex: initTable[uint64, int](),
    ),
    previousFrame: UiFrame(
      arena: previousFrameArenaPtr,
      arenaCheckpoint: 0'u64,
      nodeIdToIndex: initTable[uint64, int](),
    ),
    themeStyles: initDefaultThemeStyles(),
    themeTextStyles: initDefaultThemeTextStyles(),
    animations: @[],
    animationSpeed: 1.0'f32,
    antialiasMeshWidth: max(0.0'f32, antialiasMeshWidth),
    defaultText: UiNodeText(measuredTextDirty: true, fontSize: textHeight, textColor: UiColor(r: 0.92'f32, g: 0.92'f32, b: 0.92'f32, a: 1.0'f32)),
    defaultStyle: UiStyle(),
    defaultAnchor: UiNodeAnchor(),
    defaultTransform: UiNodeTransform(scale: vec2(1.0'f32, 1.0'f32), pivot: vec2(0.5'f32, 0.5'f32)),
    currentNode: sentinelNode.addr,
    lastNode: sentinelNode.addr,
    fontScale: 1,
  )
  result.measureText = measureText
  result.buildTextMesh = buildTextMesh
  result.previousOutput.clearFrameOutput()
  result.frameOutput.clearFrameOutput()
  if result.themeStyles.len >= int(UiStyleIndexDefault):
    result.defaultStyle = result.themeStyles[int(UiStyleIndexDefault) - 1]

proc openUrl*(b: var UiBuilder, url: string): bool {.raises: [].} =
  let openUrlFn = b.openUrlFn
  if openUrlFn != nil:
    return openUrlFn(url)
  false

proc findNodeIndexById*(nodes: openArray[UiNode], id: UiNodeId, indexHint = -1): int =
  ## Find a node's index by its ID in a node array. Uses indexHint for a fast local search first.
  if id == noneNodeId():
    return -1

  prof("findNodeIndexById")
  if indexHint > 0 and nodes.len > 1:
    let clampedIndexHint = clamp(indexHint, 0, nodes.high)
    # prof("fast")
    if nodes[clampedIndexHint].id == id:
      return clampedIndexHint

    var left = clampedIndexHint - 1
    var right = clampedIndexHint + 1
    while left >= 0 or right < nodes.len:
      if right < nodes.len and nodes[right].id == id:
        return right
      if left >= 0 and nodes[left].id == id:
        return left
      dec left
      inc right

    return -1

  # prof("slow")
  for i in 0 ..< nodes.len:
    if nodes[i].id == id:
      return i
  return -1

proc indexNode*(b: var UiBuilder, nodeId: UiNodeId = noneNodeId(), nodeIdx = -1): var UiBuilder {.discardable.} =
  ## Register a node's ID-to-index mapping in the lookup table for the current frame.
  let resolvedIdx =
    if nodeIdx >= 0:
      nodeIdx
    elif b.stack.len > 0:
      b.stack[^1]
    else:
      -1

  if resolvedIdx < 0 or resolvedIdx >= b.frame.nodes.len:
    return b

  let resolvedId =
    if nodeId != noneNodeId():
      nodeId
    else:
      b.frame.nodes[resolvedIdx].id

  if resolvedId != noneNodeId():
    b.frame.nodeIdToIndex[nodeIdValue(resolvedId)] = resolvedIdx
  b

proc nodeIndex*(b: UiBuilder, nodeId: UiNodeId, indexHint: int = -1, usePreviousFrame = false): int =
  ## Look up a node's index by its ID. Uses the lookup table first, falls back to linear search.
  if nodeId == noneNodeId():
    return -1

  let key = nodeIdValue(nodeId)
  if usePreviousFrame:
    if b.previousFrame.nodeIdToIndex.hasKey(key):
      return b.previousFrame.nodeIdToIndex.getOrQuit(key)

    return findNodeIndexById(b.previousFrame.nodes, nodeId, indexHint)

  if b.frame.nodeIdToIndex.hasKey(key):
    return b.frame.nodeIdToIndex.getOrQuit(key)
  findNodeIndexById(b.frame.nodes, nodeId, indexHint)

proc previousNodeIndex*(b: UiBuilder, nodeId: UiNodeId, indexHint: int = -1): int {.inline.} =
  ## Look up a node's index in the previous frame's node array.
  prof("previousNodeIndex")
  b.nodeIndex(nodeId, indexHint, usePreviousFrame = true)

proc currentNodeIndex*(b: UiBuilder, nodeId: UiNodeId, indexHint: int = -1): int {.inline.} =
  ## Look up a node's index in the current frame's node array.
  prof("currentNodeIndex")
  b.nodeIndex(nodeId, indexHint, usePreviousFrame = false)

proc currentNodeIndex*(b: UiBuilder): int {.inline.} =
  ## Index of the current node in the current frame.
  b.stack[^1]

proc registerFocusItem*(b: var UiBuilder, nodeId: UiNodeId, nodeIndex: int,
    scopeId: UiNodeId = noneNodeId(), flags: UiFocusFlags = {FocusTabStop},
    tabOrder = 0): var UiBuilder {.discardable.} =
  ## Register a logical focus item, optionally backed by a rendered node.
  for index in 0 ..< b.frame.focusItems.len:
    if b.frame.focusItems[index].nodeId == nodeId:
      if nodeIndex >= 0 or b.frame.focusItems[index].nodeIndex < 0:
        b.frame.focusItems[index].nodeIndex = nodeIndex
      b.frame.focusItems[index].scopeId = scopeId
      b.frame.focusItems[index].flags = flags
      b.frame.focusItems[index].tabOrder = tabOrder
      return b
  b.frame.focusItems.add UiFocusItem(
    nodeId: nodeId,
    nodeIndex: nodeIndex,
    scopeId: scopeId,
    flags: flags,
    tabOrder: tabOrder,
  )
  b

proc focusable*(b: var UiBuilder, flags: UiFocusFlags = {FocusTabStop},
  tabOrder = 0): var UiBuilder {.discardable.} =
  ## Register the current node for keyboard focus in deterministic build order.
  if b.stack.len > 0:
    discard b.registerFocusItem(
      b.currentNode.id,
      b.stack[^1],
      (if b.focusScopeStack.len > 0: b.focusScopeStack[^1] else: noneNodeId()),
      flags,
      tabOrder)
  b

proc focusNavigationTarget*(b: var UiBuilder, direction: UiNavigationDirection,
    target: UiNodeId) =
  ## Set an explicit directional edge on the current node's focus declaration.
  for index in countdown(b.frame.focusItems.high, 0):
    if b.frame.focusItems[index].nodeId == b.currentNode.id:
      b.frame.focusItems[index].navigationTargets[direction] = target
      return

proc focusNavigationTarget*(b: var UiBuilder, source: UiNodeId,
    direction: UiNavigationDirection, target: UiNodeId) =
  ## Set an explicit directional edge after both custom-widget IDs are known.
  for index in countdown(b.frame.focusItems.high, 0):
    if b.frame.focusItems[index].nodeId == source:
      b.frame.focusItems[index].navigationTargets[direction] = target
      return

proc shiftFocusNavigationTarget*(b: var UiBuilder, source: UiNodeId,
    direction: UiNavigationDirection, target: UiNodeId) =
  ## Set a Shift-modified directional edge after both focus IDs are known.
  for index in countdown(b.frame.focusItems.high, 0):
    if b.frame.focusItems[index].nodeId == source:
      b.frame.focusItems[index].shiftNavigationTargets[direction] = target
      return

proc requestFocus*(b: var UiBuilder) =
  ## Focus the current node and remember its route through active focus scopes.
  b.focusedNode = b.currentNode.id
  var childId = b.currentNode.id
  for index in countdown(b.focusScopeStack.high, 0):
    let scopeId = b.focusScopeStack[index]
    let storage = b.nodeStorage.mgetOrPut(scopeId.uint64, UiNodeStorage()).addr
    storage.rememberedFocusChild = childId
    storage.lastAccess = b.frameCtx.input.frameIndex
    childId = scopeId

proc requestFocus*(b: var UiBuilder, nodeId: UiNodeId): bool =
  ## Focus a registered item by ID and remember its logical scope route.
  for item in b.frame.focusItems:
    if item.nodeId != nodeId or FocusDisabled in item.flags:
      continue
    b.focusedNode = item.nodeId
    var childId = item.nodeId
    var scopeId = item.scopeId
    while scopeId != noneNodeId():
      let storage = b.nodeStorage.mgetOrPut(scopeId.uint64, UiNodeStorage()).addr
      storage.rememberedFocusChild = childId
      storage.lastAccess = b.frameCtx.input.frameIndex
      childId = scopeId
      var parentScopeId = noneNodeId()
      for scope in b.frame.focusScopes:
        if scope.nodeId == scopeId:
          parentScopeId = scope.parentScopeId
          break
      scopeId = parentScopeId
    return true
  false

proc isFocused*(b: UiBuilder): bool {.inline.} =
  ## Whether the current node owns keyboard focus.
  b.stack.len > 0 and b.focusedNode == b.currentNode.id

proc clearFocus*(b: var UiBuilder) {.inline.} =
  ## Clear keyboard focus.
  b.focusedNode = noneNodeId()

proc wasFocusNavigationHandled*(b: UiBuilder): bool {.inline.} =
  ## Whether this frame's directional input followed an explicit focus edge.
  b.focusNavigationHandled

proc wasFocusChangedByKeyboard*(b: UiBuilder): bool {.inline.} =
  ## Whether this frame's keyboard navigation changed the focused node.
  b.focusChangedByKeyboard

proc wasFocusActivated*(b: UiBuilder): bool =
  ## Whether Enter or Space activated the current focused, activatable node.
  if not b.isFocused():
    return false
  for index in countdown(b.frame.focusItems.high, 0):
    let item = b.frame.focusItems[index]
    if item.nodeId == b.currentNode.id:
      return FocusActivatable in item.flags and
        FocusDisabled notin item.flags and
        (KeyEnter in b.frameCtx.input.keysPressed or KeySpace in b.frameCtx.input.keysPressed)
  false

proc restoreFocus*(b: var UiBuilder) =
  ## Restore the leaf remembered by the current focus scope, if one remains alive.
  var childId = b.currentNode.id
  var remaining = b.nodeStorage.len + 1
  while remaining > 0 and b.nodeStorage.hasKey(childId.uint64):
    let remembered = b.nodeStorage.getOrQuit(childId.uint64).rememberedFocusChild
    if remembered == noneNodeId():
      break
    childId = remembered
    dec remaining
  if childId != b.currentNode.id:
    b.focusedNode = childId

proc pickHoveredIndex(b: var UiBuilder, idx: int, ox, oy, mx, my: float32, transformStack: var seq[UiAffine2], inverseStack: var seq[UiAffine2]): int =
  let n = b.frame.nodes[idx].addr
  let absPos = vec2(ox + n.pos.x, oy + n.pos.y)
  let nodeStyle = b.nodeStyle(n)
  let contentOrigin = absPos + vec2(nodeStyle.paddingX, nodeStyle.paddingY)

  if n.transformIndex >= 0:
    let nodeTransform = b.nodeTransform(n)
    let pivot = absPos + vec2(n.size.x * nodeTransform.pivot.x, n.size.y * nodeTransform.pivot.y)
    let nextTransform = applyNodeRenderTransform(
      transformStack[^1],
      pivot,
      nodeTransform.offset,
      nodeTransform.rotation,
      nodeTransform.scale,
    )
    transformStack.add nextTransform
    inverseStack.add nextTransform.inverseAffine2()

  var best = -1
  let localMouse = inverseStack[^1] * vec2(mx, my)
  if localMouse.x >= absPos.x and localMouse.y >= absPos.y and localMouse.x <= absPos.x + n.size.x and localMouse.y <= absPos.y + n.size.y:
    best = idx

  if best == -1 and MaskChildren in n.flags:
    if n.transformIndex >= 0:
      if transformStack.len > 1:
        discard transformStack.pop()
        discard inverseStack.pop()
    return -1

  if NoHover in n.flags:
    best = -1

  if NoChildHover in n.flags:
    if n.transformIndex >= 0:
      if transformStack.len > 1:
        discard transformStack.pop()
        discard inverseStack.pop()
    return best

  for childIdx in b.children(idx):
    let childHit = b.pickHoveredIndex(childIdx, contentOrigin.x, contentOrigin.y, mx, my, transformStack, inverseStack)
    if childHit >= 0:
      best = childHit

  if n.transformIndex >= 0:
    if transformStack.len > 1:
      discard transformStack.pop()
      discard inverseStack.pop()

  best

proc pickScrolledIndex(b: var UiBuilder, idx: int, ox, oy, mx, my: float32, transformStack: var seq[UiAffine2], inverseStack: var seq[UiAffine2]): int =
  let n = b.frame.nodes[idx].addr
  let absPos = vec2(ox + n.pos.x, oy + n.pos.y)
  let nodeStyle = b.nodeStyle(n)
  let contentOrigin = absPos + vec2(nodeStyle.paddingX, nodeStyle.paddingY)

  if n.transformIndex >= 0:
    let nodeTransform = b.nodeTransform(n)
    let pivot = absPos + vec2(n.size.x * nodeTransform.pivot.x, n.size.y * nodeTransform.pivot.y)
    let nextTransform = applyNodeRenderTransform(
      transformStack[^1],
      pivot,
      nodeTransform.offset,
      nodeTransform.rotation,
      nodeTransform.scale,
    )
    transformStack.add nextTransform
    inverseStack.add nextTransform.inverseAffine2()

  var best = -1
  if Scrollable in n.flags:
    let localMouse = inverseStack[^1] * vec2(mx, my)
    if localMouse.x >= absPos.x and localMouse.y >= absPos.y and localMouse.x <= absPos.x + n.size.x and localMouse.y <= absPos.y + n.size.y:
      best = idx

    if best == -1 and MaskChildren in n.flags:
      if n.transformIndex >= 0:
        if transformStack.len > 1:
          discard transformStack.pop()
          discard inverseStack.pop()
      return -1

  if NoChildHover in n.flags:
    if n.transformIndex >= 0:
      if transformStack.len > 1:
        discard transformStack.pop()
        discard inverseStack.pop()
    return best

  for childIdx in b.children(idx):
    let childHit = b.pickScrolledIndex(childIdx, contentOrigin.x, contentOrigin.y, mx, my, transformStack, inverseStack)
    if childHit >= 0:
      best = childHit

  if n.transformIndex >= 0:
    if transformStack.len > 1:
      discard transformStack.pop()
      discard inverseStack.pop()

  best

proc computeFrameInteraction(b: var UiBuilder, input: UiInputSnapshot) =
  if b.frame.nodes.len == 0:
    return

  var pickTransformStack: seq[UiAffine2] = @[identityAffine2()]
  var pickInverseStack: seq[UiAffine2] = @[identityAffine2()]
  let hoverIndex = b.pickHoveredIndex(0, 0, 0, input.mouse.x, input.mouse.y, pickTransformStack, pickInverseStack)
  let hover =
    if hoverIndex >= 0 and hoverIndex < b.frame.nodes.len:
      b.frame.nodes[hoverIndex].id
    else:
      noneNodeId()
  pickTransformStack = @[identityAffine2()]
  pickInverseStack = @[identityAffine2()]
  let scrolledIndex = b.pickScrolledIndex(0, 0, 0, input.mouse.x, input.mouse.y, pickTransformStack, pickInverseStack)
  let scrolled =
    if scrolledIndex >= 0 and scrolledIndex < b.frame.nodes.len:
      b.frame.nodes[scrolledIndex].id
    else:
      noneNodeId()

  b.frameOutput.hoveredId = hover
  b.frameOutput.hoveredIndex = hoverIndex

  # Middle-click drag to scroll. When the middle button is pressed while the
  # cursor is over a scrollable node, record the start position; while held, the
  # per-frame offset of the cursor from that start becomes the scroll speed.
  if not b.middleDragActive and MouseMiddle in input.mousePressed and scrolledIndex >= 0:
    b.middleDragActive = true
    b.middleDragScrollStart = input.mouse
    b.middleDragScroll = vec2(0.0'f32, 0.0'f32)
    b.frameOutput.scrolledId = scrolled
    b.frameOutput.scrolledIndex = scrolledIndex

  if b.middleDragActive:
    if MouseMiddle in input.mouseDown:
      let offset = input.mouse - b.middleDragScrollStart
      b.middleDragScroll = offset * 0.5
    elif MouseMiddle in input.mouseReleased:
      b.middleDragActive = false
      b.middleDragScroll = vec2(0.0'f32, 0.0'f32)
    if b.frameOutput.scrolledId == noneNodeId():
      b.frameOutput.scrolledId = b.previousOutput.scrolledId
      b.frameOutput.scrolledIndex = b.currentNodeIndex(b.frameOutput.scrolledId, b.frameOutput.scrolledIndex)
  else:
    b.middleDragScroll = vec2(0.0'f32, 0.0'f32)
    b.frameOutput.scrolledId = scrolled
    b.frameOutput.scrolledIndex = scrolledIndex

  if hover != b.previousOutput.hoveredId:
    if hover != noneNodeId():
      b.frameOutput.hoverBeganId = hover
    else:
      b.frameOutput.hoverBeganId = noneNodeId()

    if b.previousOutput.hoveredId != noneNodeId():
      b.frameOutput.hoverEndedId = b.previousOutput.hoveredId
    else:
      b.frameOutput.hoverEndedId = noneNodeId()
  else:
    b.frameOutput.hoverBeganId = noneNodeId()
    b.frameOutput.hoverEndedId = noneNodeId()

  if MouseLeft in input.mousePressed:
    b.frameOutput.heldId = hover
    b.frameOutput.heldIndex = hoverIndex
    b.frameOutput.pressedId = hover
    b.frameOutput.pressedIndex = hoverIndex
  elif MouseLeft in input.mouseDown:
    b.frameOutput.heldId = b.previousOutput.heldId
    b.frameOutput.heldIndex = b.currentNodeIndex(b.previousOutput.heldId)

  if MouseRight in input.mousePressed:
    b.frameOutput.rightPressedId = hover
    b.frameOutput.rightPressedIndex = hoverIndex
  elif MouseRight in input.mouseDown:
    b.frameOutput.rightPressedId = b.previousOutput.rightPressedId
    b.frameOutput.rightPressedIndex = b.currentNodeIndex(b.previousOutput.rightPressedId)

  # Dragging starts when a node is held down and the mouse moves. The drag id is
  # reported both while the movement happens and on the release frame so callers
  # can distinguish a real drag from a click that happened in the exact same spot.
  if b.frameOutput.heldId != noneNodeId():
    if input.mouseDelta.x != 0.0'f32 or input.mouseDelta.y != 0.0'f32:
      b.frameOutput.draggedId = b.frameOutput.heldId
      b.frameOutput.draggedIndex = b.currentNodeIndex(b.frameOutput.heldId)
    elif b.previousOutput.draggedId != noneNodeId():
      b.frameOutput.draggedId = b.previousOutput.draggedId
      b.frameOutput.draggedIndex = b.currentNodeIndex(b.previousOutput.draggedId)
  elif MouseLeft in input.mouseReleased and b.previousOutput.draggedId != noneNodeId():
    b.frameOutput.draggedId = b.previousOutput.draggedId
    b.frameOutput.draggedIndex = b.currentNodeIndex(b.previousOutput.draggedId)

  if MouseLeft in input.mouseReleased and
      not (hover == noneNodeId()) and
      hover == b.previousOutput.heldId:
    b.frameOutput.clickedId = hover
    b.frameOutput.clickedIndex = hoverIndex
  else:
    b.frameOutput.clickedId = noneNodeId()
    b.frameOutput.clickedIndex = -1

  if MouseRight in input.mouseReleased and
      not (hover == noneNodeId()) and
      hover == b.previousOutput.rightPressedId:
    b.frameOutput.rightClickedId = hover
    b.frameOutput.rightClickedIndex = hoverIndex
  else:
    b.frameOutput.rightClickedId = noneNodeId()
    b.frameOutput.rightClickedIndex = -1

proc focusItemAvailable(item: UiFocusItem): bool {.inline.} =
  FocusDisabled notin item.flags

proc focusItemBefore(items: seq[UiFocusItem], left, right: int): bool {.inline.} =
  items[left].tabOrder < items[right].tabOrder or
    (items[left].tabOrder == items[right].tabOrder and left < right)

proc applyFocusedItem(b: var UiBuilder, item: UiFocusItem, frameIndex: uint64) =
  b.focusedNode = item.nodeId
  var childId = item.nodeId
  var scopeId = item.scopeId
  while scopeId != noneNodeId():
    let storage = b.nodeStorage.mgetOrPut(scopeId.uint64, UiNodeStorage()).addr
    storage.rememberedFocusChild = childId
    storage.lastAccess = frameIndex
    childId = scopeId
    var parentScopeId = noneNodeId()
    for scope in b.frame.focusScopes:
      if scope.nodeId == scopeId:
        parentScopeId = scope.parentScopeId
        break
    scopeId = parentScopeId

proc processKeyboardFocus(b: var UiBuilder, input: UiInputSnapshot) =
  if b.frame.focusItems.len == 0:
    return

  var current = -1
  for i in 0 ..< b.frame.focusItems.len:
    if b.frame.focusItems[i].nodeId == b.focusedNode:
      current = i
      break

  if (KeyTab in input.keysPressed or KeyTab in input.keysRepeated) and
      ModControl notin input.modsDown and ModAlt notin input.modsDown and
      ModSuper notin input.modsDown:
    let backwards = ModShift in input.modsDown
    var candidate = -1
    for index, item in b.frame.focusItems:
      if FocusTabStop notin item.flags or not item.focusItemAvailable():
        continue
      let followsCurrent = current < 0 or
        (if backwards: focusItemBefore(b.frame.focusItems, index, current)
        else: focusItemBefore(b.frame.focusItems, current, index))
      if followsCurrent and (candidate < 0 or
          (if backwards: focusItemBefore(b.frame.focusItems, candidate, index)
          else: focusItemBefore(b.frame.focusItems, index, candidate))):
        candidate = index
    if candidate < 0:
      for index, item in b.frame.focusItems:
        if FocusTabStop in item.flags and item.focusItemAvailable() and
            (candidate < 0 or
            (if backwards: focusItemBefore(b.frame.focusItems, candidate, index)
            else: focusItemBefore(b.frame.focusItems, index, candidate))):
          candidate = index
    if candidate >= 0:
      let previousFocusedNode = b.focusedNode
      b.applyFocusedItem(b.frame.focusItems[candidate], input.frameIndex)
      b.focusChangedByKeyboard = b.focusedNode != previousFocusedNode
    return

  if current < 0 or not b.frame.focusItems[current].focusItemAvailable():
    return
  var directionFound = false
  var direction = NavLeft
  for candidateDirection in low(UiNavigationDirection) .. high(UiNavigationDirection):
    if candidateDirection in input.navigationPressed:
      direction = candidateDirection
      directionFound = true
      break
  let itemFlags = b.frame.focusItems[current].flags
  if FocusDirectionalInput in itemFlags:
    return
  if not directionFound and FocusTextInput notin itemFlags:
    if KeyLeft in input.keysPressed or KeyLeft in input.keysRepeated:
      direction = NavLeft; directionFound = true
    elif KeyRight in input.keysPressed or KeyRight in input.keysRepeated:
      direction = NavRight; directionFound = true
    elif KeyUp in input.keysPressed or KeyUp in input.keysRepeated:
      direction = NavUp; directionFound = true
    elif KeyDown in input.keysPressed or KeyDown in input.keysRepeated:
      direction = NavDown; directionFound = true
  if not directionFound:
    return

  var target = noneNodeId()
  if ModShift in input.modsDown:
    target = b.frame.focusItems[current].shiftNavigationTargets[direction]
  if target == noneNodeId():
    target = b.frame.focusItems[current].navigationTargets[direction]
  for item in b.frame.focusItems:
    if item.nodeId == target and item.focusItemAvailable():
      let previousFocusedNode = b.focusedNode
      b.applyFocusedItem(item, input.frameIndex)
      b.focusNavigationHandled = true
      b.focusChangedByKeyboard = b.focusedNode != previousFocusedNode
      return

proc beginUiFrame*(b: var UiBuilder, ctx: UiFrameContext): var UiBuilder {.discardable.} =
  ## Start a new UI frame. Computes interactions from previous frame, resets frame state, and creates the root node.
  prof("beginUiFrame")
  b.computeFrameInteraction(ctx.input)
  b.focusNavigationHandled = false
  b.focusChangedByKeyboard = false
  b.processKeyboardFocus(ctx.input)
  b.dragData.canDrop = false

  for i in 0 ..< b.animations.len:
    inc b.animations[i].unchangedFrames

  swap(b.previousOutput, b.frameOutput)
  swap(b.previousFrame, b.frame)

  b.frameCtx = ctx
  if b.frameCtx.animationTick < 0.0'f32:
    b.frameCtx.animationTick = 0.0'f32
  b.frameOutput.clearFrameOutput()
  b.frame.arena[].restoreCheckpoint(b.frame.arenaCheckpoint)
  b.eventTraces.clear()
  b.frame.nodes.setLen(0)
  b.frame.nodeIdToIndex.clear()
  b.frame.duplicateNodeIds.clear()
  b.frame.texts.setLen(0)
  b.frame.styles.setLen(0)
  if b.themeStyles.len >= int(UiStyleIndexDefault):
    b.defaultStyle = b.themeStyles[int(UiStyleIndexDefault) - 1]
  for style in b.themeStyles:
    b.frame.styles.add style
  if b.themeTextStyles.len >= int(UiStyleIndexDefaultText):
    b.defaultText = b.themeTextStyles[int(UiStyleIndexDefaultText) - 1]
  for text in b.themeTextStyles:
    b.frame.texts.add text
  b.frame.gaps.setLen(0)
  b.frame.anchors.setLen(0)
  b.frame.transforms.setLen(0)
  b.frame.customCommands.setLen(0)
  b.frame.customLayouts.setLen(0)
  b.frame.focusItems.setLen(0)
  b.frame.focusScopes.setLen(0)
  b.deferredNodes.setLen(0)
  b.stack.setLen(0)
  b.nodeIdStack.setLen(0)
  b.idScopeStack.setLen(0)
  b.autoChildCounter.setLen(0)
  b.configuringAnimationStack.setLen(0)
  b.animationTriggerStack.setLen(0)
  b.anythingAnimating = false

  let rootId = rootNodeId()

  # Root is always created at frame start so layout can rely on viewport size immediately.
  b.frame.nodes.add UiNode(
    id: rootId,
    flags: {},
    pos: vec2(0.0'f32, 0.0'f32),
    size: vec2(max(0.0'f32, ctx.viewportSize.x), max(0.0'f32, ctx.viewportSize.y)),
    minSize: vec2(0.0'f32, 0.0'f32),
    maxSize: vec2(1.0e9'f32, 1.0e9'f32),
    cursor: vec2(0.0'f32, 0.0'f32),
    contentExtent: vec2(0.0'f32, 0.0'f32),
    lastChild: -1,
    nextSibling: -1,
    parent: -1,
    renderParent: -1,
    renderChildLast: -1,
    renderSibling: -1,
  )
  b.currentNode = b.frame.nodes[^1].addr
  b.currentParent = nil
  b.autoChildCounter.add 0'u32
  b.configuringAnimationStack.add false
  b.animationTriggerStack.add true
  b.stack.add 0
  b.nodeIdStack.add rootId
  discard b.deferPostProcess()
  b

proc beginUiFrame*(b: var UiBuilder, viewportW, viewportH: float32,
  input: UiInputSnapshot = default(UiInputSnapshot), animationTick = 1.0'f32 / 60.0'f32): var UiBuilder {.discardable.} =
  ## Convenience overload: start a new UI frame with explicit viewport dimensions and input.
  let ctx = UiFrameContext(
    viewportSize: vec2(viewportW, viewportH),
    animationTick: animationTick,
    input: input,
    time: b.frameCtx.time + animationTick,
  )
  discard b.beginUiFrame(ctx)
  b

proc beginNodeWithId*(b: var UiBuilder, nodeId: UiNodeId): var UiBuilder {.discardable.} =
  ## Begin a new node with an explicit ID. Links it as a child of the current node.
  let parentIndex = if b.stack.len > 0: b.stack[^1] else: -1
  let nodeIndex = b.frame.nodes.len
  let inheritedLayoutIndex =
    if parentIndex >= 0 and parentIndex < b.frame.nodes.len:
      b.frame.nodes[parentIndex].layerIndex
    else:
      -1'i32

  if b.frame.nodeIdToIndex.hasKey(nodeIdValue(nodeId)):
    b.frame.duplicateNodeIds.mgetOrPut(nodeIdValue(nodeId), @[]).add [nodeIndex, b.frame.nodeIdToIndex.getOrQuit(nodeIdValue(nodeId))]

  when defined(nuiDebug):
    b.frame.nodeIdToIndex[nodeIdValue(nodeId)] = nodeIndex

  b.frame.nodes.add UiNode(
    id: nodeId,
    maxSize: vec2(1.0e9'f32, 1.0e9'f32),
    lastChild: -1,
    nextSibling: -1,
    renderParent: -1,
    renderChildLast: -1,
    renderSibling: -1,
    parent: parentIndex.int32,
    layerIndex: inheritedLayoutIndex,
  )
  b.currentNode = b.frame.nodes[^1].addr

  if parentIndex >= 0:
    let parent = b.frame.nodes[parentIndex].addr
    b.currentParent = parent
    if parent.lastChild < 0:
      parent.lastChild = nodeIndex.int32
      b.currentNode.nextSibling = nodeIndex.int32
    else:
      let tail = int(parent.lastChild)
      let head = int(b.frame.nodes[tail].nextSibling)
      b.currentNode.nextSibling = head.int32
      b.frame.nodes[tail].nextSibling = nodeIndex.int32
      parent.lastChild = nodeIndex.int32
    b.currentNode.pos = parent.cursor

  b.autoChildCounter.add 0'u32
  b.configuringAnimationStack.add false
  b.animationTriggerStack.add true
  b.stack.add nodeIndex
  b.nodeIdStack.add nodeId
  b.traceEvent(nodeId, "beginNode")
  b

proc beginNodeWithKeyHash(b: var UiBuilder, explicitKeyHash: uint64): var UiBuilder {.discardable.} =
  let parentIndex = if b.stack.len > 0: b.stack[^1] else: -1
  let nodeId = b.computeChildNodeId(parentIndex, explicitKeyHash)
  b.beginNodeWithId(nodeId)

proc beginNode*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Begin a new node with an auto-generated ID.
  b.beginNodeWithKeyHash(0'u64)

proc beginNodeId*(b: var UiBuilder, key: uint64): var UiBuilder {.discardable.} =
  ## Begin a new node with a deterministic ID derived from the given uint64 key.
  b.beginNodeWithKeyHash(hashUint64(key))

proc beginNodeId*(b: var UiBuilder, key: string): var UiBuilder {.discardable.} =
  ## Begin a new node with a deterministic ID derived from the given string key.
  discard b.beginNodeWithKeyHash(hashChars(key))
  when defined(nuiDebug):
    b.currentNode.debugName = key
  b

proc debugName*(b: var UiBuilder, key: string) =
  when defined(nuiDebug):
    b.currentNode.debugName = key

proc endNode*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## End the current node. Finalizes its size, updates parent layout, and pops the stack.
  if b.stack.len > 0:
    b.traceEvent(b.currentNode.id, "endNode")
    let idx = b.stack[^1]
    b.updateNodeFit(b.currentNode)
    b.clampNodeSize(b.currentNode)
    b.updateParentAfterChildEnd(b.currentNode)
    b.traceUiNode("endNode", idx)

    if NodeStorageParent in b.currentNode.flags:
      assert b.storageParentStack.len > 0
      assert b.storageParentStack[^1] == b.currentNode.id

      discard b.storageParentStack.pop()

    if NodeFocusScope in b.currentNode.flags:
      assert b.focusScopeStack.len > 0
      assert b.focusScopeStack[^1] == b.currentNode.id
      discard b.focusScopeStack.pop()

    b.lastNode = b.currentNode
    b.lastNodeIndex = idx

    discard b.stack.pop()
    if b.stack.len > 0:
      b.currentNode = b.frame.nodes[b.stack[^1]].addr
      if b.stack.len > 1:
        b.currentParent = b.frame.nodes[b.stack[^2]].addr
      else:
        b.currentParent = nil
    else:
      b.currentNode = sentinelNode.addr
      b.currentParent = nil

    discard b.nodeIdStack.pop()
  b

proc flushDeferredNodes*(b: var UiBuilder) =
  ## Execute all deferred build procs. Each proc adds children to its designated parent node.
  prof("flushDeferredNodes")
  # Process deferred node builds; each callback uses the parent stack to add children.
  # New deferred entries added inside callbacks are picked up by the while loop.
  let storageParentStack = b.storageParentStack
  let focusScopeStack = b.focusScopeStack

  var deferredIdx = 0
  while deferredIdx < b.deferredNodes.len:
    let deferred = b.deferredNodes[deferredIdx]
    inc deferredIdx
    if deferred.buildProc != nil and deferred.nodeIdx >= 0 and deferred.nodeIdx < b.frame.nodes.len:
      let prevStackLen = b.stack.len
      let prevNodeIdStackLen = b.nodeIdStack.len
      b.stack.add deferred.nodeIdx
      b.nodeIdStack.add b.frame.nodes[deferred.nodeIdx].id
      b.storageParentStack = deferred.storageParentStack
      b.focusScopeStack = deferred.focusScopeStack
      b.currentNode = b.frame.nodes[deferred.nodeIdx].addr
      if b.currentNode.parent >= 0:
        b.currentParent = b.frame.nodes[b.currentNode.parent].addr
      else:
        b.currentParent = nil
      deferred.buildProc(b, deferred.nodeIdx, deferred.userData)
      while b.stack.len > prevStackLen:
        discard b.stack.pop()
      while b.nodeIdStack.len > prevNodeIdStackLen:
        discard b.nodeIdStack.pop()
      discard b.postProcessChildren(deferred.nodeIdx)

  if b.stack.len > 0:
    b.currentNode = b.frame.nodes[b.stack[^1]].addr
    if b.currentNode.parent >= 0:
      b.currentParent = b.frame.nodes[b.currentNode.parent].addr
    else:
      b.currentParent = nil
  else:
    b.currentNode = sentinelNode.addr
    b.currentParent = nil

  b.storageParentStack = storageParentStack
  b.focusScopeStack = focusScopeStack
  b.deferredNodes.setLen(0)

proc addVirtualTree*(b: var UiBuilder, parent: UiNodeId, nodes: seq[UiNode]): var UiBuilder {.discardable.} =
  ## Buffer a subtree (or forest) of `UiNode`s to be inserted under `parent` at `endUiFrame`.
  b.virtualNodes.add UiVirtualTree(parent: parent, nodes: nodes)
  b

proc addVirtualTree*(b: var UiBuilder, parent: UiNodeId, nodes: seq[UiNode], animations: seq[UiFieldAnimation]): var UiBuilder {.discardable.} =
  ## Buffer a subtree (or forest) of `UiNode`s to be inserted under `parent` at
  ## `endUiFrame`, carrying the given per-field `animations`.
  b.virtualNodes.add UiVirtualTree(parent: parent, nodes: nodes, animations: animations)
  b

proc setAnimatedFieldValue(b: var UiBuilder, node: var UiNode, fieldOffset: UiNodeFloatField, value: float32) {.inline.}

proc syncVirtualTreeFromFrame*(b: var UiBuilder, v: var UiVirtualTree, frameNodeIdx: int, baseStyle, baseGap, baseAnchor, baseTransform: int) {.inline.}

proc insertVirtualTrees*(b: var UiBuilder) =
  ## Splice every buffered virtual node into the actual tree under its parent.
  prof("insertVirtualTrees")
  if b.virtualNodes.len == 0:
    return

  var finishedIndices: seq[int] = @[]
  for vi, v in b.virtualNodes.mpairs:
    if v.nodes.len == 0:
      continue

    let parentIdx = b.nodeIndex(v.parent)
    let parentIndex = if parentIdx >= 0: parentIdx else: 0

    # Capture the base indices for each side array, then append this virtual node's
    # sub-data. Node indices are 1-based, so a value `t` maps to frame slot
    # `base + t` (i.e. `base + t - 1` in the 0-based array).
    let baseText = b.frame.texts.len
    let baseStyle = b.frame.styles.len
    let baseGap = b.frame.gaps.len
    let baseAnchor = b.frame.anchors.len
    let baseTransform = b.frame.transforms.len
    let baseCommands = b.frame.customCommands.len
    let baseLayouts = b.frame.customLayouts.len

    b.frame.texts.add v.texts
    b.frame.styles.add v.styles
    b.frame.gaps.add v.gaps
    b.frame.anchors.add v.anchors
    b.frame.transforms.add v.transforms
    b.frame.customCommands.add v.customCommands
    b.frame.customLayouts.add v.customLayouts

    let offset = b.frame.nodes.len
    let startIdx = offset
    let endIdx = offset + v.nodes.len - 1

    # Append the virtual node list, remapping intra-subtree structural links by the
    # append offset so the subtree's own parent/child/sibling chain stays consistent,
    # and remapping the 1-based side-array indices into the frame's arrays.
    for n in v.nodes:
      var m = n
      if m.parent >= 0:
        m.parent += offset.int32
      if m.lastChild >= 0:
        m.lastChild += offset.int32
      if m.nextSibling >= 0:
        m.nextSibling += offset.int32
      if m.renderParent >= 0:
        m.renderParent += offset.int32
      if m.renderChildLast >= 0:
        m.renderChildLast += offset.int32
      if m.renderSibling >= 0:
        m.renderSibling += offset.int32
      if m.textIndex != 0'u16:
        m.textIndex = uint16(baseText + int(m.textIndex))
      if m.styleIndex != 0'u16:
        m.styleIndex = uint16(baseStyle + int(m.styleIndex))
      if m.gapIndex != 0'u16:
        m.gapIndex = uint16(baseGap + int(m.gapIndex))
      if m.anchorIndex != 0'u16:
        m.anchorIndex = uint16(baseAnchor + int(m.anchorIndex))
      if m.transformIndex != 0'u16:
        m.transformIndex = uint16(baseTransform + int(m.transformIndex))
      if m.commandsIndex != 0'u16:
        m.commandsIndex = uint16(baseCommands + int(m.commandsIndex))
      if m.customLayoutIndex != 0'u16:
        m.customLayoutIndex = uint16(baseLayouts + int(m.customLayoutIndex))
      if m.customChildLayoutIndex != 0'u16:
        m.customChildLayoutIndex = uint16(baseLayouts + int(m.customChildLayoutIndex))
      b.frame.nodes.add m

    # A node whose (remapped) parent falls outside the appended range is a forest
    # root and is linked into the real parent as a new child.
    for i in startIdx .. endIdx:
      let p = b.frame.nodes[i].parent
      if p < startIdx or p > endIdx:
        b.frame.nodes[i].parent = parentIndex.int32
        let parent = b.frame.nodes[parentIndex].addr
        if parent.lastChild < 0:
          parent.lastChild = i.int32
          b.frame.nodes[i].nextSibling = i.int32
        else:
          let tail = int(parent.lastChild)
          let head = int(b.frame.nodes[tail].nextSibling)
          b.frame.nodes[i].nextSibling = head.int32
          b.frame.nodes[tail].nextSibling = i.int32
          parent.lastChild = i.int32

    # Register the new nodes in the id->index table for interaction lookups.
    for i in startIdx .. endIdx:
      let id = b.frame.nodes[i].id
      if id != noneNodeId():
        b.frame.nodeIdToIndex[nodeIdValue(id)] = i

    # Advance and apply any per-field animations on the now-inserted root node, then
    # write the resulting float fields and side-array data back into the stored
    # virtual node so it carries the updated values into the next frame.
    if v.animations.len > 0:
      let animationTick = max(0.0'f32, b.frameCtx.animationTick)
      let animationSpeedScale = max(0.0'f32, b.animationSpeed)
      for a in v.animations.mitems:
        let blend = clamp(a.speed * animationSpeedScale * animationTick, 0.0'f32, 1.0'f32)
        a.currentValue = a.currentValue + (a.targetValue - a.currentValue) * blend
        if abs(a.targetValue - a.currentValue) <= 0.001'f32:
          a.currentValue = a.targetValue
        setAnimatedFieldValue(b, b.frame.nodes[startIdx], a.fieldOffset, a.currentValue)
      syncVirtualTreeFromFrame(b, v, startIdx, baseStyle, baseGap, baseAnchor, baseTransform)
      var allFinished = true
      for a in v.animations:
        if a.currentValue != a.targetValue:
          allFinished = false
          break
      if allFinished:
        finishedIndices.add(vi)

  # Drop virtual nodes whose animations have all reached their target; their last
  # inserted frame node remains, but they are no longer re-spliced on future frames.
  # Removal runs afterwards (separate loop), highest index first so earlier indices
  # stay valid, and does not allocate a copy of the whole virtual-node list.
  if finishedIndices.len > 0:
    for di in countdown(finishedIndices.high, 0):
      let idx = finishedIndices[di]
      for k in idx ..< b.virtualNodes.len - 1:
        b.virtualNodes[k] = move(b.virtualNodes[k + 1])
      b.virtualNodes.setLen(b.virtualNodes.len - 1)

proc extractVirtualTree*(frame: var UiFrame, nodeIdx: int): UiVirtualTree =
  ## Inverse of `insertVirtualTrees`: extract the subtree rooted at `nodeIdx` (all
  ## descendants plus their referenced side-array data) from `frame` into a
  ## self-contained `UiVirtualTree`. Structural links are rebased to the local node
  ## list (any link leaving the subtree becomes -1), and `parent` is set to the
  ## original parent's id so re-insertion restores the node's original placement.
  result = UiVirtualTree()
  if nodeIdx < 0 or nodeIdx >= frame.nodes.len:
    return result

  let origParent = frame.nodes[nodeIdx].parent
  if origParent >= 0 and origParent < frame.nodes.len:
    result.parent = frame.nodes[origParent].id

  # Map original frame index -> local index in result.nodes.
  var indexMap = initTable[int, int]()
  var worklist = @[nodeIdx]
  while worklist.len > 0:
    let origIdx = worklist.pop()
    if indexMap.hasKey(origIdx):
      continue
    let localIdx = result.nodes.len
    indexMap[origIdx] = localIdx
    result.nodes.add frame.nodes[origIdx]
    result.nodes[^1].flags.incl VirtualTree
    result.nodes[^1].flags.excl VirtualizeNode
    let n = frame.nodes[origIdx]
    if n.lastChild >= 0:
      var child = int(frame.nodes[int(n.lastChild)].nextSibling)
      let tail = int(n.lastChild)
      while true:
        worklist.add child
        if child == tail:
          break
        child = int(frame.nodes[child].nextSibling)

  # Rebase structural links into the local list; links outside the subtree -> -1.
  for i in 0 ..< result.nodes.len:
    var n = addr result.nodes[i]
    n.parent = indexMap.getOrDefault(int(n.parent), -1).int32
    n.lastChild = indexMap.getOrDefault(int(n.lastChild), -1).int32
    n.nextSibling = indexMap.getOrDefault(int(n.nextSibling), -1).int32
    n.renderParent = indexMap.getOrDefault(int(n.renderParent), -1).int32
    n.renderChildLast = indexMap.getOrDefault(int(n.renderChildLast), -1).int32
    n.renderSibling = indexMap.getOrDefault(int(n.renderSibling), -1).int32

  # Gather referenced side-array data (deduplicated by original slot) and remap the
  # nodes' 1-based indices into the local side arrays.
  var
    textMap = initTable[int, int]()
    styleMap = initTable[int, int]()
    gapMap = initTable[int, int]()
    anchorMap = initTable[int, int]()
    transformMap = initTable[int, int]()
    commandMap = initTable[int, int]()
    layoutMap = initTable[int, int]()
  for i in 0 ..< result.nodes.len:
    var n = addr result.nodes[i]
    if n.textIndex != 0'u16:
      let slot = int(n.textIndex) - 1
      if not textMap.hasKey(slot):
        textMap[slot] = result.texts.len
        if slot < frame.texts.len:
          result.texts.add frame.texts[slot]
        else:
          result.texts.add UiNodeText()
      n.textIndex = uint16(textMap.getOrQuit(slot) + 1)
    if n.styleIndex != 0'u16:
      let slot = int(n.styleIndex) - 1
      if not styleMap.hasKey(slot):
        styleMap[slot] = result.styles.len
        if slot < frame.styles.len:
          result.styles.add frame.styles[slot]
        else:
          result.styles.add UiStyle()
      n.styleIndex = uint16(styleMap.getOrQuit(slot) + 1)
    if n.gapIndex != 0'u16:
      let slot = int(n.gapIndex) - 1
      if not gapMap.hasKey(slot):
        gapMap[slot] = result.gaps.len
        if slot < frame.gaps.len:
          result.gaps.add frame.gaps[slot]
        else:
          result.gaps.add 0.0'f32
      n.gapIndex = uint16(gapMap.getOrQuit(slot) + 1)
    if n.anchorIndex != 0'u16:
      let slot = int(n.anchorIndex) - 1
      if not anchorMap.hasKey(slot):
        anchorMap[slot] = result.anchors.len
        if slot < frame.anchors.len:
          result.anchors.add frame.anchors[slot]
        else:
          result.anchors.add UiNodeAnchor()
      n.anchorIndex = uint16(anchorMap.getOrQuit(slot) + 1)
    if n.transformIndex != 0'u16:
      let slot = int(n.transformIndex) - 1
      if not transformMap.hasKey(slot):
        transformMap[slot] = result.transforms.len
        if slot < frame.transforms.len:
          result.transforms.add frame.transforms[slot]
        else:
          result.transforms.add UiNodeTransform(scale: vec2(1.0'f32, 1.0'f32), pivot: vec2(0.5'f32, 0.5'f32))
      n.transformIndex = uint16(transformMap.getOrQuit(slot) + 1)
    if n.commandsIndex != 0'u16:
      let slot = int(n.commandsIndex) - 1
      if not commandMap.hasKey(slot):
        commandMap[slot] = result.customCommands.len
        if slot < frame.customCommands.len:
          var cmds = frame.customCommands[slot]
          let cmdCount = cmds.len
          # Deep-copy the command structs into persistent virtual-node storage, then
          # repoint each command's vertex data into the virtual node's own vertex buffer
          # so the commands stay valid after the source frame arena is reset.
          let cmdStart = result.commandData.len
          for i in 0 ..< cmdCount:
            let c = cmds[i]
            result.commandData.add c
          # Copy all referenced vertex data first so the seq cannot reallocate out
          # from under already-stored pointers, then patch the pointers afterwards.
          var vtxBase = result.commandVertices.len
          for i in 0 ..< cmdCount:
            let vc = int(result.commandData[cmdStart + i].vertexCount)
            if result.commandData[cmdStart + i].vertexData != nil and vc > 0:
              for v in 0 ..< vc:
                result.commandVertices.add result.commandData[cmdStart + i].vertexData[v]
          for i in 0 ..< cmdCount:
            let vc = int(result.commandData[cmdStart + i].vertexCount)
            if result.commandData[cmdStart + i].vertexData != nil and vc > 0:
              result.commandData[cmdStart + i].vertexData =
                cast[nil ptr UncheckedArray[UiVertex]](addr result.commandVertices[vtxBase])
              vtxBase += vc
          if result.commandData.len > cmdStart:
            let av = initArrayView(
              cast[ptr UncheckedArray[UiRenderCommand]](addr result.commandData[cmdStart]),
              result.commandData.len - cmdStart)
            result.customCommands.add av
          else:
            result.customCommands.add default(ArrayView[UiRenderCommand])
        else:
          result.customCommands.add default(ArrayView[UiRenderCommand])
      n.commandsIndex = uint16(commandMap.getOrQuit(slot) + 1)
    if n.customLayoutIndex != 0'u16:
      let slot = int(n.customLayoutIndex) - 1
      if not layoutMap.hasKey(slot):
        layoutMap[slot] = result.customLayouts.len
        if slot < frame.customLayouts.len:
          result.customLayouts.add frame.customLayouts[slot]
        else:
          result.customLayouts.add default(UiNodeCustomLayout)
      n.customLayoutIndex = uint16(layoutMap.getOrQuit(slot) + 1)
    if n.customChildLayoutIndex != 0'u16:
      let slot = int(n.customChildLayoutIndex) - 1
      if not layoutMap.hasKey(slot):
        layoutMap[slot] = result.customLayouts.len
        if slot < frame.customLayouts.len:
          result.customLayouts.add frame.customLayouts[slot]
        else:
          result.customLayouts.add default(UiNodeCustomLayout)
      n.customChildLayoutIndex = uint16(layoutMap.getOrQuit(slot) + 1)

proc virtualNodeFromNode*(b: var UiBuilder, nodeIdx: int): UiVirtualTree =
  ## Convenience wrapper around `extractVirtualTree` operating on the current frame.
  extractVirtualTree(b.frame, nodeIdx)

proc collectGarbage*(b: var UiBuilder) =
  prof("collectGarbage")

  var toRemove: seq[uint64] = @[]
  block:
    prof("mark")
    for nodeId, storage in b.nodeStorage.pairs:
      var parentAlive = false
      for i in countdown(storage.parents.high, 0):
        let parent = storage.parents[i]
        if b.nodeStorage.hasKey(parent.uint64):
          let parentStorage = b.nodeStorage.getOrQuit(parent.uint64).addr
          if parentStorage.clearOldChildren and storage.lastAccess < parentStorage.lastAccess:
            # don't keep alive even though parent is alive.
            break
        if b.frame.nodeIdToIndex.hasKey(nodeIdValue(parent)):
          parentAlive = true
          break
      if parentAlive:
        continue
      if storage.lastAccess < b.frameCtx.input.frameIndex:
        toRemove.add nodeId

  block:
    prof("sweep")
    for id in toRemove:
      b.nodeStorage.del(id)

proc updateVirtualTrees(b: var UiBuilder) =
  # Promote previous-frame nodes flagged VirtualizeNode that did not survive into the
  # current frame into persistent virtual nodes, so they keep being rendered.
  var virtualizedIds = initTable[uint64, int]()
  for v in b.virtualNodes:
    for n in v.nodes:
      virtualizedIds[nodeIdValue(n.id)] = 1
  for prevIdx in 0 ..< b.previousFrame.nodes.len:
    let prevNode = b.previousFrame.nodes[prevIdx]
    if VirtualizeNode in prevNode.flags:
      let id = nodeIdValue(prevNode.id)
      if b.currentNodeIndex(prevNode.id) < 0 and not virtualizedIds.hasKey(id):
        virtualizedIds[id] = 1
        var vn = extractVirtualTree(b.previousFrame, prevIdx)
        if b.virtualNodeAnimations.hasKey(id):
          vn.animations = b.virtualNodeAnimations.getOrQuit(id)
          b.virtualNodeAnimations.del(id)
        b.virtualNodes.add vn

  # Drop any existing virtual nodes whose nodes are present in the current frame; a
  # live node supersedes its virtual copy, and keeping both would render duplicates.
  var liveVirtualIndices: seq[int] = @[]
  for vi, v in b.virtualNodes:
    for n in v.nodes:
      if b.currentNodeIndex(n.id) >= 0:
        liveVirtualIndices.add vi
        break
  if liveVirtualIndices.len > 0:
    for di in countdown(liveVirtualIndices.high, 0):
      let idx = liveVirtualIndices[di]
      for k in idx ..< b.virtualNodes.len - 1:
        b.virtualNodes[k] = move(b.virtualNodes[k + 1])
      b.virtualNodes.setLen(b.virtualNodes.len - 1)

  b.insertVirtualTrees()

proc endUiFrame*(b: var UiBuilder, buildRenderCommands: bool = true, collectGarbage: bool = true, buildMeshRenderCommands: bool = false) =
  ## End the UI frame. Flushes deferred nodes, removes stale animations, and builds render commands.
  prof("endUiFrame")
  if b.frame.nodes.len == 0:
    b.frameOutput.clearFrameOutput()
    b.removeStaleAnimations()
    return

  discard b.endNode()
  b.flushDeferredNodes()
  b.buildDragUi()
  b.removeStaleAnimations()
  b.updateVirtualTrees()

  if MouseLeft in b.frameCtx.input.mouseReleased:
    b.dragData = DragData(nodeId: noneNodeId())

  b.frameOutput.clearFrameOutput()
  if buildRenderCommands:
    var clipStack = newSeq[UiClipRect]()
    if buildMeshRenderCommands:
      b.buildMeshRenderCommands(0, 0, 0, 0'i32, clipStack)
    else:
      b.buildRenderCommands(0, 0, 0, 0'i32, clipStack)

    prof("concatRenderCommands")
    var len = 0
    for i in 0 ..< b.frameOutput.commandLayers.len:
      len += b.frameOutput.commandLayers[i].len

    b.frameOutput.commands = newSeqOfCap[UiRenderCommand](len)
    for i in 0 ..< b.frameOutput.commandLayers.len:
      b.frameOutput.commands.add(b.frameOutput.commandLayers[i])

    when defined(nuiDebug):
      # Highlight nodes that share a duplicate id by drawing a red outline around
      # each of them on top of the frame's render commands.
      if b.frame.duplicateNodeIds.len > 0:
        let highlightColor = UiColor(r: 1.0'f32, g: 0.15'f32, b: 0.15'f32, a: 1.0'f32)
        for _, indices in b.frame.duplicateNodeIds:
          for i in 0 ..< indices.len:
            let nodeIdx = indices[i]
            if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
              continue
            let n = b.frame.nodes[nodeIdx].addr
            let absPos = b.absoluteNodePos(nodeIdx)
            let (vertexData, vertexCount) = buildRectStrokeVertices(
              b.frame.arena, absPos, n.size, highlightColor, 0.0'f32, 3.0'f32,
              b.antialiasMeshWidth)
            if vertexData != nil and vertexCount > 0:
              b.frameOutput.commands.add(UiRenderCommand(
                kind: CmdRawVertices,
                nodeIndex: nodeIdx.int32,
                vertexData: vertexData,
                vertexCount: vertexCount.int32,
              ))

  if collectGarbage:
    b.collectGarbage()

proc keepAlive*(b: var UiBuilder, nodeId: UiNodeId) =
  ## Mark a node and all its ancestors as alive, preventing their storage from being garbage-collected.
  if not b.frame.nodeIdToIndex.hasKey(nodeIdValue(nodeId)):
    b.frame.nodeIdToIndex[nodeIdValue(nodeId)] = -1

proc nodeStorageCount*(b: UiBuilder): int =
  ## Return the number of active node storage entries.
  b.nodeStorage.len

proc pushRenderCommand*(b: var UiBuilder, layerIndex: int32, command: sink UiRenderCommand, clipStack: seq[UiClipRect]) {.inline.} =
  ## Add a render command to the appropriate layer in the frame output.
  # todo: this breaks with texts right now
  # case command.kind
  # of CmdRectFill, CmdRectStroke, CmdCircleFill, CmdLine, CmdText, CmdImage:
  #   if not clipStack.intersectsClipRect(command.pos, command.size):
  #     return
  # else:
  #   discard
  let layer = max(0, layerIndex.int)
  if layer >= b.frameOutput.commandLayers.len:
    b.frameOutput.commandLayers.setLen(layer + 1)
    b.frameOutput.commandLayers[layer] = newSeq[UiRenderCommand](2048)
  b.frameOutput.commandLayers[layer].add(command)

proc buildMeshRenderCommands(b: var UiBuilder, idx: int, ox, oy: float32, inheritedLayoutIndex: int32, clipStack: var seq[UiClipRect], transformStack: var seq[UiAffine2]) =
  prof("buildMeshRenderCommands")
  let n = b.frame.nodes[idx].addr
  let layerIndex = if n.layerIndex >= 0: n.layerIndex else: inheritedLayoutIndex
  let absPos = vec2(ox + n.pos.x, oy + n.pos.y)
  let absSize = n.size
  let nodeStyle = b.nodeStyle(n)
  let contentOrigin = absPos + vec2(nodeStyle.paddingX, nodeStyle.paddingY)
  let contentSize = vec2(
    max(0.0'f32, absSize.x - nodeStyle.paddingX * 2),
    max(0.0'f32, absSize.y - nodeStyle.paddingY * 2),
  )

  if n.transformIndex >= 0:
    let nodeTransform = b.nodeTransform(n)
    let nextTransform = applyNodeRenderTransform(
      transformStack[^1],
      absPos + vec2(n.size.x * nodeTransform.pivot.x, n.size.y * nodeTransform.pivot.y),
      nodeTransform.offset,
      nodeTransform.rotation,
      nodeTransform.scale,
    )
    transformStack.add nextTransform

  let transform = transformStack[^1]

  if FillBackground in n.flags and nodeStyle.fillColor.a > 0:
    let (vertexData, vertexCount) = if nodeStyle[].hasPerCornerRadii:
      buildRectFillVertices(b.frame.arena, absPos, absSize, nodeStyle.fillColor,
        nodeStyle.cornerRadii, b.antialiasMeshWidth)
    else:
      buildRectFillVertices(b.frame.arena, absPos, absSize, nodeStyle.fillColor,
        nodeStyle.cornerRadius, b.antialiasMeshWidth)
    if not transform.isIdentity():
      for n in 0..<vertexCount:
        vertexData[n].pos = transform * vertexData[n].pos
    if vertexData != nil and vertexCount > 0:
      b.pushRenderCommand(layerIndex, UiRenderCommand(
        kind: CmdRawVertices,
        nodeIndex: idx.int32,
        vertexData: vertexData,
        vertexCount: vertexCount.int32,
      ), clipStack)

  let masksChildren = MaskChildren in n.flags
  if masksChildren:
    let clipAabb = transformedRectAabb(transform, contentOrigin, contentSize)
    var clipRect = UiClipRect(x: clipAabb.pos.x, y: clipAabb.pos.y, w: clipAabb.size.x, h: clipAabb.size.y)
    if clipStack.len > 0:
      clipRect = intersectClipRect(clipStack[^1], clipRect)
    clipStack.add clipRect
    b.pushRenderCommand(layerIndex, UiRenderCommand(
      kind: CmdClipPush,
      nodeIndex: idx.int32,
      pos: clipAabb.pos,
      size: clipAabb.size,
    ), clipStack)

  if DrawText in n.flags and n.textIndex > 0:
    let nodeText = b.nodeText(idx)
    let maxWidth = if WrapText in n.flags: contentSize.x else: -1.0'f32
    let arrangement = b.getTextArrangement(nodeText, maxWidth)
    if b.buildTextMesh != nil:
      const textTransformEpsilon = 1e-5'f32
      let snapTransformedText =
        abs(transform.m00 - 1.0'f32) <= textTransformEpsilon and
        abs(transform.m01) <= textTransformEpsilon and
        abs(transform.m10) <= textTransformEpsilon and
        abs(transform.m11 - 1.0'f32) <= textTransformEpsilon
      let screenOffset = if snapTransformedText: vec2(transform.tx, transform.ty) else: vec2(0.0'f32)
      let (vertexData, vertexCount) = b.buildTextMesh(
        arrangement[], contentOrigin, screenOffset, nodeText.textColor, transform)
      if vertexData != nil and vertexCount > 0:
        b.pushRenderCommand(layerIndex, UiRenderCommand(
          kind: CmdRawVertices,
          nodeIndex: idx.int32,
          vertexData: vertexData,
          vertexCount: vertexCount.int32,
          imageId: 1.UiImageId,
          samplerMode: TextureSamplerMode.Linear,
        ), clipStack)

  for cmd in b.nodeCustomCommands(n)[]:
    var outCmd = cmd
    if outCmd.nodeIndex < 0:
      outCmd.nodeIndex = idx.int32
    outCmd.pos += contentOrigin
    outCmd.pos2 += contentOrigin
    b.pushRenderCommand(layerIndex, outCmd, clipStack)

  for childIdx in b.children(idx):
    if b.frame.nodes[childIdx].renderParent < 0:
      b.buildMeshRenderCommands(childIdx, contentOrigin.x, contentOrigin.y, layerIndex, clipStack, transformStack)

  # Process renderChildLast chain first - these nodes render under this node.
  let renderChildLast = n.renderChildLast
  var rcIdx = renderChildLast
  if rcIdx >= 0:
    rcIdx = b.frame.nodes[rcIdx].renderSibling
    while rcIdx >= 0 and rcIdx < b.frame.nodes.len:
      let rcNode = b.frame.nodes[rcIdx].addr
      let rcAbsPos = b.absoluteNodePos(rcIdx)
      b.buildMeshRenderCommands(rcIdx, rcAbsPos.x - rcNode.pos.x, rcAbsPos.y - rcNode.pos.y, layerIndex, clipStack, transformStack)
      rcIdx = rcNode.renderSibling
      if rcIdx == renderChildLast:
        break

  if masksChildren:
    if clipStack.len > 0:
      discard clipStack.pop()
    b.pushRenderCommand(layerIndex, UiRenderCommand(
      kind: CmdClipPop,
      nodeIndex: idx.int32,
    ), clipStack)

  block:
    let (vertexData, vertexCount) = if nodeStyle[].hasPerCornerRadii or nodeStyle[].hasPerSideBorderWidths or nodeStyle[].hasPerSideBorderColors:
      buildRectStrokeVertices(b.frame.arena, absPos, absSize,
        nodeStyle[].resolvedBorderColors, nodeStyle[].resolvedCornerRadii,
        nodeStyle[].resolvedBorderWidths, b.antialiasMeshWidth)
    else:
      buildRectStrokeVertices(b.frame.arena, absPos, absSize, nodeStyle[].borderColor,
        nodeStyle[].cornerRadius, nodeStyle[].borderWidth, b.antialiasMeshWidth)
    if not transform.isIdentity():
      for n in 0..<vertexCount:
        vertexData[n].pos = transform * vertexData[n].pos
    if vertexData != nil and vertexCount > 0:
      b.pushRenderCommand(layerIndex, UiRenderCommand(
        kind: CmdRawVertices,
        nodeIndex: idx.int32,
        vertexData: vertexData,
        vertexCount: vertexCount.int32,
      ), clipStack)

  if n.transformIndex >= 0:
    if transformStack.len > 1:
      discard transformStack.pop()

proc buildMeshRenderCommands(b: var UiBuilder, idx: int, ox, oy: float32, inheritedLayoutIndex: int32, clipStack: var seq[UiClipRect]) =
  var transformStack: seq[UiAffine2] = @[identityAffine2()]
  b.buildMeshRenderCommands(idx, ox, oy, inheritedLayoutIndex, clipStack, transformStack)

proc buildRenderCommands(b: var UiBuilder, idx: int, ox, oy: float32, inheritedLayoutIndex: int32, clipStack: var seq[UiClipRect]) =
  prof("buildRenderCommands")
  let n = b.frame.nodes[idx].addr
  let layerIndex = if n.layerIndex >= 0: n.layerIndex else: inheritedLayoutIndex
  let absPos = vec2(ox + n.pos.x, oy + n.pos.y)
  let absSize = n.size
  let nodeStyle = b.nodeStyle(n)
  let contentOrigin = absPos + vec2(nodeStyle.paddingX, nodeStyle.paddingY)
  let contentSize = vec2(
    max(0.0'f32, absSize.x - nodeStyle.paddingX * 2),
    max(0.0'f32, absSize.y - nodeStyle.paddingY * 2),
  )

  if n.transformIndex >= 0:
    let nodeTransform = b.nodeTransform(n)
    b.pushRenderCommand(layerIndex, UiRenderCommand(
      kind: CmdTransformPush,
      nodeIndex: idx.int32,
      transformOrigin: absPos,
      pivot: absPos + vec2(n.size.x * nodeTransform.pivot.x, n.size.y * nodeTransform.pivot.y),
      offset: nodeTransform.offset,
      scale: nodeTransform.scale,
      rotation: nodeTransform.rotation,
    ), clipStack)

  if FillBackground in n.flags and nodeStyle.fillColor.a > 0:
    b.pushRenderCommand(layerIndex, UiRenderCommand(
      kind: CmdRectFill,
      nodeIndex: idx.int32,
      color: nodeStyle.fillColor,
      pos: absPos,
      size: absSize,
      radius: nodeStyle.cornerRadius,
    ), clipStack)

  let masksChildren = MaskChildren in n.flags
  if masksChildren:
    var clipRect = UiClipRect(x: contentOrigin.x, y: contentOrigin.y, w: contentSize.x, h: contentSize.y)
    if clipStack.len > 0:
      clipRect = intersectClipRect(clipStack[^1], clipRect)
    clipStack.add clipRect
    b.pushRenderCommand(layerIndex, UiRenderCommand(
      kind: CmdClipPush,
      nodeIndex: idx.int32,
      pos: contentOrigin,
      size: contentSize,
    ), clipStack)

  if DrawText in n.flags and n.textIndex > 0:
    b.pushRenderCommand(layerIndex, UiRenderCommand(
      kind: CmdText,
      nodeIndex: idx.int32,
      textIndex: n.textIndex,
      pos: contentOrigin,
      size: vec2(0.0'f32, 0.0'f32),
    ), clipStack)

  for cmd in b.nodeCustomCommands(n)[]:
    var outCmd = cmd
    if outCmd.nodeIndex < 0:
      outCmd.nodeIndex = idx.int32
    outCmd.pos += contentOrigin
    outCmd.pos2 += contentOrigin
    b.pushRenderCommand(layerIndex, outCmd, clipStack)

  for childIdx in b.children(idx):
    if b.frame.nodes[childIdx].renderParent < 0:
      b.buildRenderCommands(childIdx, contentOrigin.x, contentOrigin.y, layerIndex, clipStack)

  # Process renderChildLast chain first - these nodes render under this node.
  let renderChildLast = n.renderChildLast
  var rcIdx = renderChildLast
  if rcIdx >= 0:
    rcIdx = b.frame.nodes[rcIdx].renderSibling
    while rcIdx >= 0 and rcIdx < b.frame.nodes.len:
      let rcNode = b.frame.nodes[rcIdx].addr
      let rcAbsPos = b.absoluteNodePos(rcIdx)
      b.buildRenderCommands(rcIdx, rcAbsPos.x - rcNode.pos.x, rcAbsPos.y - rcNode.pos.y, layerIndex, clipStack)
      rcIdx = rcNode.renderSibling
      if rcIdx == renderChildLast:
        break

  if masksChildren:
    if clipStack.len > 0:
      discard clipStack.pop()
    b.pushRenderCommand(layerIndex, UiRenderCommand(
      kind: CmdClipPop,
      nodeIndex: idx.int32,
    ), clipStack)

  if nodeStyle.borderWidth > 0 and nodeStyle.borderColor.a > 0:
    b.pushRenderCommand(layerIndex, UiRenderCommand(
      kind: CmdRectStroke,
      nodeIndex: idx.int32,
      color: nodeStyle.borderColor,
      pos: absPos,
      size: absSize,
      radius: nodeStyle.cornerRadius,
      thickness: nodeStyle.borderWidth,
    ), clipStack)

  if n.transformIndex >= 0:
    b.pushRenderCommand(layerIndex, UiRenderCommand(
      kind: CmdTransformPop,
      nodeIndex: idx.int32,
    ), clipStack)

proc removeStaleAnimations(b: var UiBuilder) =
  var writeIdx = 0
  for readIdx in 0 ..< b.animations.len:
    if b.animations[readIdx].unchangedFrames < 2:
      if writeIdx != readIdx:
        b.animations[writeIdx] = move b.animations[readIdx]
      inc writeIdx
  b.animations.setLen(writeIdx)

proc clampNodeSize*(b: var UiBuilder, n: ptr UiNode) {.inline.} =
  ## Clamp the node's size between its minSize and maxSize constraints.
  let minV = vec2(max(0.0'f32, n.minSize.x), max(0.0'f32, n.minSize.y))
  let maxV = vec2(max(minV.x, n.maxSize.x), max(minV.y, n.maxSize.y))
  n.size = clamp(n.size, minV, maxV)

proc getAnimatedFieldValue(frame: UiFrame, node: UiNode, fieldOffset: UiNodeFloatField): float32 {.inline.} =
  proc layoutPtr(frame: UiFrame, node: UiNode): nil ptr UiStyle {.inline.} =
    if node.styleIndex > 0: addr(frame.styles[node.styleIndex - 1]) else: nil

  proc textPtr(frame: UiFrame, node: UiNode): nil ptr UiNodeText {.inline.} =
    if node.textIndex > 0: addr(frame.texts[node.textIndex - 1]) else: nil

  proc gapPtr(frame: UiFrame, node: UiNode): nil ptr float32 {.inline.} =
    if node.gapIndex > 0: addr(frame.gaps[node.gapIndex - 1]) else: nil

  proc anchorPtr(frame: UiFrame, node: UiNode): nil ptr UiNodeAnchor {.inline.} =
    if node.anchorIndex > 0: addr(frame.anchors[node.anchorIndex - 1]) else: nil

  proc transformPtr(frame: UiFrame, node: UiNode): nil ptr UiNodeTransform {.inline.} =
    if node.transformIndex > 0: addr(frame.transforms[node.transformIndex - 1]) else: nil

  case fieldOffset
  of UiNodeFieldPosX: node.pos.x
  of UiNodeFieldPosY: node.pos.y
  of UiNodeFieldSizeX: node.size.x
  of UiNodeFieldSizeY: node.size.y
  of UiNodeFieldMinSizeX: node.minSize.x
  of UiNodeFieldMinSizeY: node.minSize.y
  of UiNodeFieldMaxSizeX: node.maxSize.x
  of UiNodeFieldMaxSizeY: node.maxSize.y
  of UiNodeFieldCursorX: node.cursor.x
  of UiNodeFieldCursorY: node.cursor.y
  of UiNodeFieldContentExtentX: node.contentExtent.x
  of UiNodeFieldContentExtentY: node.contentExtent.y
  of UiNodeFieldStylePaddingX:
    let s = layoutPtr(frame, node); if s != nil: s.paddingX else: 0.0'f32
  of UiNodeFieldStylePaddingY:
    let s = layoutPtr(frame, node); if s != nil: s.paddingY else: 0.0'f32
  of UiNodeFieldStyleBorderWidth:
    let s = layoutPtr(frame, node); if s != nil: s.borderWidth else: 0.0'f32
  of UiNodeFieldStyleCornerRadius:
    let s = layoutPtr(frame, node); if s != nil: s.cornerRadius else: 0.0'f32
  of UiNodeFieldStyleFillColorR:
    let s = layoutPtr(frame, node); if s != nil: s.fillColor.r else: 0.0'f32
  of UiNodeFieldStyleFillColorG:
    let s = layoutPtr(frame, node); if s != nil: s.fillColor.g else: 0.0'f32
  of UiNodeFieldStyleFillColorB:
    let s = layoutPtr(frame, node); if s != nil: s.fillColor.b else: 0.0'f32
  of UiNodeFieldStyleFillColorA:
    let s = layoutPtr(frame, node); if s != nil: s.fillColor.a else: 0.0'f32
  of UiNodeFieldStyleBorderColorR:
    let s = layoutPtr(frame, node); if s != nil: s.borderColor.r else: 0.0'f32
  of UiNodeFieldStyleBorderColorG:
    let s = layoutPtr(frame, node); if s != nil: s.borderColor.g else: 0.0'f32
  of UiNodeFieldStyleBorderColorB:
    let s = layoutPtr(frame, node); if s != nil: s.borderColor.b else: 0.0'f32
  of UiNodeFieldStyleBorderColorA:
    let s = layoutPtr(frame, node); if s != nil: s.borderColor.a else: 0.0'f32
  of UiNodeFieldStyleTextColorR:
    let s = textPtr(frame, node); if s != nil: s.textColor.r else: 0.0'f32
  of UiNodeFieldStyleTextColorG:
    let s = textPtr(frame, node); if s != nil: s.textColor.g else: 0.0'f32
  of UiNodeFieldStyleTextColorB:
    let s = textPtr(frame, node); if s != nil: s.textColor.b else: 0.0'f32
  of UiNodeFieldStyleTextColorA:
    let s = textPtr(frame, node); if s != nil: s.textColor.a else: 0.0'f32
  of UiNodeFieldGap:
    let g = gapPtr(frame, node); if g != nil: g[] else: 0.0'f32
  of UiNodeFieldAnchorTopLeftX:
    let a = anchorPtr(frame, node); if a != nil: a.topLeft.x else: 0.0'f32
  of UiNodeFieldAnchorTopLeftY:
    let a = anchorPtr(frame, node); if a != nil: a.topLeft.y else: 0.0'f32
  of UiNodeFieldAnchorBottomRightX:
    let a = anchorPtr(frame, node); if a != nil: a.bottomRight.x else: 0.0'f32
  of UiNodeFieldAnchorBottomRightY:
    let a = anchorPtr(frame, node); if a != nil: a.bottomRight.y else: 0.0'f32
  of UiNodeFieldAnchorTopLeftOffsetX:
    let a = anchorPtr(frame, node); if a != nil: a.topLeftOffset.x else: 0.0'f32
  of UiNodeFieldAnchorTopLeftOffsetY:
    let a = anchorPtr(frame, node); if a != nil: a.topLeftOffset.y else: 0.0'f32
  of UiNodeFieldAnchorBottomRightOffsetX:
    let a = anchorPtr(frame, node); if a != nil: a.bottomRightOffset.x else: 0.0'f32
  of UiNodeFieldAnchorBottomRightOffsetY:
    let a = anchorPtr(frame, node); if a != nil: a.bottomRightOffset.y else: 0.0'f32
  of UiNodeFieldAnchorPivotX:
    let a = anchorPtr(frame, node); if a != nil: a.pivot.x else: 0.0'f32
  of UiNodeFieldAnchorPivotY:
    let a = anchorPtr(frame, node); if a != nil: a.pivot.y else: 0.0'f32
  of UiNodeFieldAnchoredOffsetX:
    let a = anchorPtr(frame, node); if a != nil: a.offset.x else: 0.0'f32
  of UiNodeFieldAnchoredOffsetY:
    let a = anchorPtr(frame, node); if a != nil: a.offset.y else: 0.0'f32
  of UiNodeFieldTransformOffsetX:
    let t = transformPtr(frame, node); if t != nil: t.offset.x else: 0.0'f32
  of UiNodeFieldTransformOffsetY:
    let t = transformPtr(frame, node); if t != nil: t.offset.y else: 0.0'f32
  of UiNodeFieldTransformRotation:
    let t = transformPtr(frame, node); if t != nil: t.rotation else: 0.0'f32
  of UiNodeFieldTransformScaleX:
    let t = transformPtr(frame, node); if t != nil: t.scale.x else: 1.0'f32
  of UiNodeFieldTransformScaleY:
    let t = transformPtr(frame, node); if t != nil: t.scale.y else: 1.0'f32
  of UiNodeFieldTransformPivotX:
    let t = transformPtr(frame, node); if t != nil: t.pivot.x else: 0.5'f32
  of UiNodeFieldTransformPivotY:
    let t = transformPtr(frame, node); if t != nil: t.pivot.y else: 0.5'f32

proc setAnimatedFieldValue(b: var UiBuilder, node: var UiNode, fieldOffset: UiNodeFloatField, value: float32) {.inline.} =
  case fieldOffset
  of UiNodeFieldPosX: node.pos.x = value
  of UiNodeFieldPosY: node.pos.y = value
  of UiNodeFieldSizeX: node.size.x = value
  of UiNodeFieldSizeY: node.size.y = value
  of UiNodeFieldMinSizeX: node.minSize.x = value
  of UiNodeFieldMinSizeY: node.minSize.y = value
  of UiNodeFieldMaxSizeX: node.maxSize.x = value
  of UiNodeFieldMaxSizeY: node.maxSize.y = value
  of UiNodeFieldCursorX: node.cursor.x = value
  of UiNodeFieldCursorY: node.cursor.y = value
  of UiNodeFieldContentExtentX: node.contentExtent.x = value
  of UiNodeFieldContentExtentY: node.contentExtent.y = value
  of UiNodeFieldStylePaddingX: b.ensureNodeStyle(node.addr).paddingX = value
  of UiNodeFieldStylePaddingY: b.ensureNodeStyle(node.addr).paddingY = value
  of UiNodeFieldStyleBorderWidth: b.ensureNodeStyle(node.addr).borderWidth = value
  of UiNodeFieldStyleCornerRadius: b.ensureNodeStyle(node.addr).cornerRadius = value
  of UiNodeFieldStyleFillColorR: b.ensureNodeStyle(node.addr).fillColor.r = value
  of UiNodeFieldStyleFillColorG: b.ensureNodeStyle(node.addr).fillColor.g = value
  of UiNodeFieldStyleFillColorB: b.ensureNodeStyle(node.addr).fillColor.b = value
  of UiNodeFieldStyleFillColorA: b.ensureNodeStyle(node.addr).fillColor.a = value
  of UiNodeFieldStyleBorderColorR: b.ensureNodeStyle(node.addr).borderColor.r = value
  of UiNodeFieldStyleBorderColorG: b.ensureNodeStyle(node.addr).borderColor.g = value
  of UiNodeFieldStyleBorderColorB: b.ensureNodeStyle(node.addr).borderColor.b = value
  of UiNodeFieldStyleBorderColorA: b.ensureNodeStyle(node.addr).borderColor.a = value
  of UiNodeFieldStyleTextColorR: b.ensureNodeText(node.addr).textColor.r = value
  of UiNodeFieldStyleTextColorG: b.ensureNodeText(node.addr).textColor.g = value
  of UiNodeFieldStyleTextColorB: b.ensureNodeText(node.addr).textColor.b = value
  of UiNodeFieldStyleTextColorA: b.ensureNodeText(node.addr).textColor.a = value
  of UiNodeFieldGap: b.ensureNodeGap(node.addr) = value
  of UiNodeFieldAnchorTopLeftX: b.ensureNodeAnchor(node.addr).topLeft.x = value
  of UiNodeFieldAnchorTopLeftY: b.ensureNodeAnchor(node.addr).topLeft.y = value
  of UiNodeFieldAnchorBottomRightX: b.ensureNodeAnchor(node.addr).bottomRight.x = value
  of UiNodeFieldAnchorBottomRightY: b.ensureNodeAnchor(node.addr).bottomRight.y = value
  of UiNodeFieldAnchorTopLeftOffsetX: b.ensureNodeAnchor(node.addr).topLeftOffset.x = value
  of UiNodeFieldAnchorTopLeftOffsetY: b.ensureNodeAnchor(node.addr).topLeftOffset.y = value
  of UiNodeFieldAnchorBottomRightOffsetX: b.ensureNodeAnchor(node.addr).bottomRightOffset.x = value
  of UiNodeFieldAnchorBottomRightOffsetY: b.ensureNodeAnchor(node.addr).bottomRightOffset.y = value
  of UiNodeFieldAnchorPivotX: b.ensureNodeAnchor(node.addr).pivot.x = value
  of UiNodeFieldAnchorPivotY: b.ensureNodeAnchor(node.addr).pivot.y = value
  of UiNodeFieldAnchoredOffsetX: b.ensureNodeAnchor(node.addr).offset.x = value
  of UiNodeFieldAnchoredOffsetY: b.ensureNodeAnchor(node.addr).offset.y = value
  of UiNodeFieldTransformOffsetX: b.ensureNodeTransform(node.addr).offset.x = value
  of UiNodeFieldTransformOffsetY: b.ensureNodeTransform(node.addr).offset.y = value
  of UiNodeFieldTransformRotation: b.ensureNodeTransform(node.addr).rotation = value
  of UiNodeFieldTransformScaleX: b.ensureNodeTransform(node.addr).scale.x = value
  of UiNodeFieldTransformScaleY: b.ensureNodeTransform(node.addr).scale.y = value
  of UiNodeFieldTransformPivotX: b.ensureNodeTransform(node.addr).pivot.x = value
  of UiNodeFieldTransformPivotY: b.ensureNodeTransform(node.addr).pivot.y = value

proc syncVirtualTreeFromFrame*(b: var UiBuilder, v: var UiVirtualTree, frameNodeIdx: int, baseStyle, baseGap, baseAnchor, baseTransform: int) {.inline.} =
  ## Copy the animated float fields and side-array data of the inserted frame node
  ## back into the stored virtual node so it carries the updated values next frame.
  if frameNodeIdx < 0 or frameNodeIdx >= b.frame.nodes.len:
    return
  let fn = b.frame.nodes[frameNodeIdx].addr
  v.nodes[0].pos = fn.pos
  v.nodes[0].size = fn.size
  v.nodes[0].minSize = fn.minSize
  v.nodes[0].maxSize = fn.maxSize
  v.nodes[0].cursor = fn.cursor
  v.nodes[0].contentExtent = fn.contentExtent
  if fn.styleIndex != 0'u16:
    let local = int(fn.styleIndex) - baseStyle
    let slot = int(fn.styleIndex) - 1
    if local >= 1:
      if v.styles.len < local: v.styles.setLen(local)
      v.styles[local - 1] = b.frame.styles[slot]
      v.nodes[0].styleIndex = uint16(local)
  if fn.gapIndex != 0'u16:
    let local = int(fn.gapIndex) - baseGap
    let slot = int(fn.gapIndex) - 1
    if local >= 1:
      if v.gaps.len < local: v.gaps.setLen(local)
      v.gaps[local - 1] = b.frame.gaps[slot]
      v.nodes[0].gapIndex = uint16(local)
  if fn.anchorIndex != 0'u16:
    let local = int(fn.anchorIndex) - baseAnchor
    let slot = int(fn.anchorIndex) - 1
    if local >= 1:
      if v.anchors.len < local: v.anchors.setLen(local)
      v.anchors[local - 1] = b.frame.anchors[slot]
      v.nodes[0].anchorIndex = uint16(local)
  if fn.transformIndex != 0'u16:
    let local = int(fn.transformIndex) - baseTransform
    let slot = int(fn.transformIndex) - 1
    if local >= 1:
      if v.transforms.len < local: v.transforms.setLen(local)
      v.transforms[local - 1] = b.frame.transforms[slot]
      v.nodes[0].transformIndex = uint16(local)

proc findAnimationIndex(b: UiBuilder, nodeId: UiNodeId): int {.inline.} =
  for i in 0 ..< b.animations.len:
    if b.animations[i].nodeId == nodeId:
      return i
  -1

proc resolveAnimationIndex(
    b: var UiBuilder,
    nodeId: UiNodeId,
    allowCreate: bool,
): int =
  let idx = b.findAnimationIndex(nodeId)
  if idx >= 0:
    return idx

  if not allowCreate:
    return -1

  b.animations.add UiAnimation(
    nodeId: nodeId,
    fields: @[],
    unchangedFrames: 0,
  )
  b.animations.high

proc nextFloatFieldOffset(baseFieldOffset: UiNodeFloatField, componentIndex: int): UiNodeFloatField {.inline.} =
  baseFieldOffset.succ(componentIndex)

proc findAnimationFieldIndex(anim: UiAnimation, fieldOffset: UiNodeFloatField): int {.inline.} =
  for i in 0 ..< anim.fields.len:
    if anim.fields[i].fieldOffset == fieldOffset:
      return i
  -1

proc animationCurrentValue(frame: UiFrame, anim: UiAnimation, node: UiNode, fieldOffset: UiNodeFloatField): float32 {.inline.} =
  let fieldIdx = findAnimationFieldIndex(anim, fieldOffset)
  if fieldIdx >= 0:
    return anim.fields[fieldIdx].currentValue
  getAnimatedFieldValue(frame, node, fieldOffset)

proc previousAnimationFieldStartValue(
    frame: UiFrame,
    anim: UiAnimation,
    nodeId: UiNodeId,
    fieldOffset: UiNodeFloatField,
): tuple[hasValue: bool, value: float32] {.inline.} =
  let prevIdx = findNodeIndexById(frame.nodes, nodeId)
  if prevIdx < 0:
    return (false, 0.0'f32)

  let _ = anim
  (true, getAnimatedFieldValue(frame, frame.nodes[prevIdx], fieldOffset))

proc applyAnimatedFieldTarget(
    anim: var UiAnimation,
    node: UiNode,
    fieldOffset: UiNodeFloatField,
    targetValue: float32,
    speed: float32,
    touchedFrame: uint64,
    initializeCurrentValue = false,
    initialCurrentValue = 0.0'f32,
): float32 =
  var fieldIdx = findAnimationFieldIndex(anim, fieldOffset)

  if fieldIdx < 0:
    let startValue = if initializeCurrentValue: initialCurrentValue else: targetValue
    anim.fields.add UiFieldAnimation(
      # First observation should not introduce a one-frame lag.
      currentValue: startValue,
      targetValue: targetValue,
      speed: max(0.0'f32, speed),
      fieldOffset: fieldOffset,
      touchedFrame: touchedFrame,
    )
    fieldIdx = anim.fields.high

  let field = anim.fields[fieldIdx].addr
  field.targetValue = targetValue
  field.speed = max(0.0'f32, speed)
  field.touchedFrame = touchedFrame

  if field.speed <= 0.0'f32:
    field.currentValue = targetValue

  field.currentValue

proc animateDelayed*(b: var UiBuilder, nodeIdx: int): var UiBuilder {.discardable.} =
  ## Schedule animation application for the node at nodeIdx to run during flushDeferredNodes.
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return b

  b.deferredNodes.add UiDeferredNode(
    nodeIdx: nodeIdx,
    buildProc: deferredAnimationBuildProc,
    userData: 0,
  )
  b

proc animateDelayed*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Schedule animation application for the current node to run during flushDeferredNodes.
  if b.stack.len <= 0:
    return b
  b.animateDelayed(b.stack[^1])

proc absoluteNodePos*(b: UiBuilder, idx: int): Vec2 =
  ## Returns the absolute position of the node at idx in the current frame.
  result = vec2(0.0'f32, 0.0'f32)
  var current = idx
  while current >= 0 and current < b.frame.nodes.len:
    let n = b.frame.nodes[current].addr
    result += n.pos
    let parentIdx = int(n.parent)
    if parentIdx >= 0 and parentIdx < b.frame.nodes.len:
      let parentNode = b.frame.nodes[parentIdx].addr
      if parentNode.styleIndex > 0:
        let si = int(parentNode.styleIndex) - 1
        if si < b.frame.styles.len:
          result += vec2(b.frame.styles[si].paddingX, b.frame.styles[si].paddingY)
    current = parentIdx

proc absoluteNodePosPrev*(b: var UiBuilder, nodeId: UiNodeId, indexHint: int = -1): Vec2 =
  ## Returns the absolute position of the node in the previous frame
  result = vec2(0.0'f32, 0.0'f32)
  var current = b.previousNodeIndex(nodeId, indexHint)
  while current >= 0 and current < b.previousFrame.nodes.len:
    let n = b.previousFrame.nodes[current].addr
    result += n.pos
    let parentIdx = int(n.parent)
    if parentIdx >= 0 and parentIdx < b.previousFrame.nodes.len:
      let parentNode = b.previousFrame.nodes[parentIdx].addr
      if parentNode.styleIndex > 0:
        let si = int(parentNode.styleIndex) - 1
        if si < b.previousFrame.styles.len:
          result += vec2(b.previousFrame.styles[si].paddingX, b.previousFrame.styles[si].paddingY)
    current = parentIdx

proc applyDeferredAnimationTracks(b: var UiBuilder, nodeIdx: int) =
  prof("applyDeferredAnimationTracks")
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return

  var node = b.frame.nodes[nodeIdx].addr
  let oldSize = node.size
  let animIdx = b.findAnimationIndex(node.id)
  if animIdx < 0:
    return

  let anim = b.animations[animIdx].addr

  let prevIdx = b.previousNodeIndex(node.id, nodeIdx)
  if prevIdx < 0:
    return

  # Detect parent change and compute recalculation for position fields.
  var parentChanged = false
  var newParentLocalOffset = vec2(0.0'f32, 0.0'f32)
  let prevParentIdx = int(b.previousFrame.nodes[prevIdx].parent)
  if node.parent >= 0 and prevParentIdx >= 0 and
      node.parent < b.frame.nodes.len and prevParentIdx < b.previousFrame.nodes.len:
    let curParentId = b.frame.nodes[node.parent].id
    let prevParentId = b.previousFrame.nodes[prevParentIdx].id
    if curParentId != prevParentId:
      parentChanged = true
      # Compute absolute position of node in previous frame.
      let nodeAbsPrev = b.absoluteNodePosPrev(node.id, nodeIdx)
      # Find new parent in the previous frame to compute its absolute position.
      let newParentPrevIdx = b.previousNodeIndex(curParentId)
      if newParentPrevIdx >= 0:
        let newParentAbsPrev = b.absoluteNodePosPrev(curParentId, newParentPrevIdx)
        # local = absolute(node) - absolute(newParent) - newParent.padding
        let newParentPrevNode = b.previousFrame.nodes[newParentPrevIdx].addr
        var newParentPadX = 0.0'f32
        var newParentPadY = 0.0'f32
        if newParentPrevNode.styleIndex > 0:
          let si = int(newParentPrevNode.styleIndex) - 1
          if si < b.previousFrame.styles.len:
            newParentPadX = b.previousFrame.styles[si].paddingX
            newParentPadY = b.previousFrame.styles[si].paddingY
        newParentLocalOffset = vec2(
          nodeAbsPrev.x - newParentAbsPrev.x - newParentPadX,
          nodeAbsPrev.y - newParentAbsPrev.y - newParentPadY,
        )
      else:
        # New parent didn't exist in previous frame; skip animation for pos fields.
        parentChanged = false

  var hasActiveField = false
  let animationTick = max(0.0'f32, b.frameCtx.animationTick)
  let animationSpeedScale = max(0.0'f32, b.animationSpeed)
  let currentFrame = b.frameCtx.input.frameIndex
  for i in 0 ..< anim.fields.len:
    let field = anim.fields[i].addr
    let nodeValue = getAnimatedFieldValue(b.frame, node[], field.fieldOffset)
    if field.touchedFrame != currentFrame:
      field.currentValue = nodeValue
      field.targetValue = nodeValue
      continue

    var previousStart = getAnimatedFieldValue(b.previousFrame, b.previousFrame.nodes[prevIdx], field.fieldOffset)
    if parentChanged:
      case field.fieldOffset
      of UiNodeFieldPosX:
        previousStart = newParentLocalOffset.x
      of UiNodeFieldPosY:
        previousStart = newParentLocalOffset.y
      else:
        discard
    let blend = clamp(field.speed * animationSpeedScale * animationTick, 0.0'f32, 1.0'f32)
    field.currentValue = previousStart + (nodeValue - previousStart) * blend
    field.targetValue = nodeValue
    if abs(nodeValue - field.currentValue) <= 0.001'f32:
      field.currentValue = nodeValue
    else:
      hasActiveField = true
    setAnimatedFieldValue(b, node[], field.fieldOffset, field.currentValue)

  if hasActiveField:
    anim[].unchangedFrames = 0
  b.clampNodeSize(node)
  if oldSize != node.size:
    discard b.postProcessChildren(nodeIdx)

proc deferredAnimationBuildProc(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall.} =
  let _ = userData
  b.applyDeferredAnimationTracks(nodeIdx)

proc deferredPostProcessBuildProc(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall.} =
  let _ = userData
  discard b.postProcessChildren(nodeIdx)

proc setAnimatedField(b: var UiBuilder, nodeIdx: int, fieldOffset: UiNodeFloatField, targetValue: float32, speed = DefaultAnimationSpeed): float32 =
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return targetValue

  let node = b.frame.nodes[nodeIdx].addr
  if not b.configuringAnimationStack[nodeIdx]:
    return targetValue

  let animIdx = b.resolveAnimationIndex(node.id, b.animationTriggerStack[nodeIdx])
  if animIdx >= 0:
    let anim = b.animations[animIdx].addr
    let nodeValueBefore = animationCurrentValue(b.frame, anim[], node[], fieldOffset)
    var initializeCurrentValue = false
    var initialCurrentValue = nodeValueBefore
    if findAnimationFieldIndex(anim[], fieldOffset) < 0:
      let previousStart = previousAnimationFieldStartValue(b.previousFrame, anim[], node.id, fieldOffset)
      if previousStart.hasValue:
        initializeCurrentValue = true
        initialCurrentValue = previousStart.value
    let animatedValue = anim[].applyAnimatedFieldTarget(
      node[],
      fieldOffset,
      targetValue,
      speed,
      b.frameCtx.input.frameIndex,
      initializeCurrentValue,
      initialCurrentValue,
    )
    when defined(debugLogUiAnimation):
      let logLine = "ui.anim.set" &
        " node='" & nodeDebugName(node[]) & "'" &
        " id=" & $nodeIdValue(node.id) &
        " field=" & $fieldOffset &
        " nodeBefore=" & fmt2(nodeValueBefore) &
        " target=" & fmt2(targetValue) &
        " current=" & fmt2(animatedValue) &
        " speed=" & fmt2(max(0.0'f32, speed))
      debugLog(logLine)
    return animatedValue

  else:
    when defined(debugLogUiAnimation):
      let logLine = "ui.anim.set.skip" &
        " node='" & nodeDebugName(node[]) & "'" &
        " id=" & $nodeIdValue(node.id) &
        " field=" & $fieldOffset &
        " reason=no-animation-state" &
        " target=" & fmt2(targetValue)
      debugLog(logLine)
    return targetValue

proc setAnimatedField[T](
    b: var UiBuilder,
    nodeIdx: int,
    firstFieldOffset: UiNodeFloatField,
    targetValue: T,
    speed = DefaultAnimationSpeed,
): T =
  if nodeIdx < 0 or nodeIdx >= b.frame.nodes.len:
    return targetValue

  let node = b.frame.nodes[nodeIdx].addr
  if not b.configuringAnimationStack[nodeIdx]:
    return targetValue

  let animIdx = b.resolveAnimationIndex(node.id, b.animationTriggerStack[nodeIdx])
  if animIdx < 0:
    return targetValue
  let anim = b.animations[animIdx].addr

  when T is Vec2:
    let xOffset = nextFloatFieldOffset(firstFieldOffset, 0)
    let yOffset = nextFloatFieldOffset(firstFieldOffset, 1)
    let xCurrentBefore = animationCurrentValue(b.frame, anim[], node[], xOffset)
    let yCurrentBefore = animationCurrentValue(b.frame, anim[], node[], yOffset)
    var initX = false
    var initY = false
    var prevX = xCurrentBefore
    var prevY = yCurrentBefore
    if findAnimationFieldIndex(anim[], xOffset) < 0:
      let previousX = previousAnimationFieldStartValue(b.previousFrame, anim[], node.id, xOffset)
      if previousX.hasValue:
        initX = true
        prevX = previousX.value
    if findAnimationFieldIndex(anim[], yOffset) < 0:
      let previousY = previousAnimationFieldStartValue(b.previousFrame, anim[], node.id, yOffset)
      if previousY.hasValue:
        initY = true
        prevY = previousY.value
    result = vec2(
      anim[].applyAnimatedFieldTarget(node[], xOffset, targetValue.x, speed, b.frameCtx.input.frameIndex, initX, prevX),
      anim[].applyAnimatedFieldTarget(node[], yOffset, targetValue.y, speed, b.frameCtx.input.frameIndex, initY, prevY),
    )
  elif T is UiColor:
    let rOffset = nextFloatFieldOffset(firstFieldOffset, 0)
    let gOffset = nextFloatFieldOffset(firstFieldOffset, 1)
    let bOffset = nextFloatFieldOffset(firstFieldOffset, 2)
    let aOffset = nextFloatFieldOffset(firstFieldOffset, 3)
    let rCurrentBefore = animationCurrentValue(b.frame, anim[], node[], rOffset)
    let gCurrentBefore = animationCurrentValue(b.frame, anim[], node[], gOffset)
    let bCurrentBefore = animationCurrentValue(b.frame, anim[], node[], bOffset)
    let aCurrentBefore = animationCurrentValue(b.frame, anim[], node[], aOffset)
    var initR = false
    var initG = false
    var initB = false
    var initA = false
    var prevR = rCurrentBefore
    var prevG = gCurrentBefore
    var prevB = bCurrentBefore
    var prevA = aCurrentBefore
    if findAnimationFieldIndex(anim[], rOffset) < 0:
      let previousR = previousAnimationFieldStartValue(b.previousFrame, anim[], node.id, rOffset)
      if previousR.hasValue:
        initR = true
        prevR = previousR.value
    if findAnimationFieldIndex(anim[], gOffset) < 0:
      let previousG = previousAnimationFieldStartValue(b.previousFrame, anim[], node.id, gOffset)
      if previousG.hasValue:
        initG = true
        prevG = previousG.value
    if findAnimationFieldIndex(anim[], bOffset) < 0:
      let previousB = previousAnimationFieldStartValue(b.previousFrame, anim[], node.id, bOffset)
      if previousB.hasValue:
        initB = true
        prevB = previousB.value
    if findAnimationFieldIndex(anim[], aOffset) < 0:
      let previousA = previousAnimationFieldStartValue(b.previousFrame, anim[], node.id, aOffset)
      if previousA.hasValue:
        initA = true
        prevA = previousA.value
    result = UiColor(
      r: anim[].applyAnimatedFieldTarget(node[], rOffset, targetValue.r, speed, b.frameCtx.input.frameIndex, initR, prevR),
      g: anim[].applyAnimatedFieldTarget(node[], gOffset, targetValue.g, speed, b.frameCtx.input.frameIndex, initG, prevG),
      b: anim[].applyAnimatedFieldTarget(node[], bOffset, targetValue.b, speed, b.frameCtx.input.frameIndex, initB, prevB),
      a: anim[].applyAnimatedFieldTarget(node[], aOffset, targetValue.a, speed, b.frameCtx.input.frameIndex, initA, prevA),
    )
  else:
    {.error: "Unsupported animated composite type".}

proc beginAnimation*(b: var UiBuilder, trigger = true) =
  ## Begin an animation block. When trigger is true, new animation tracks are created on first use.
  let idx = b.stack[^1]
  b.configuringAnimationStack[idx] = true
  b.animationTriggerStack[idx] = trigger

proc endAnimation*(b: var UiBuilder) =
  ## End an animation block. Steps all animation tracks toward their targets using the blend factor.
  let idx = b.stack[^1]
  let node = b.frame.nodes[idx].addr
  let animIdx = b.findAnimationIndex(node.id)
  if animIdx >= 0:
    let anim = b.animations[animIdx].addr
    var hasActiveField = false
    when defined(debugLogUiAnimation):
      let logLine = "ui.anim.end.begin" &
        " node='" & nodeDebugName(node[]) & "'" &
        " id=" & $nodeIdValue(node.id) &
        " fields=" & $anim.fields.len
      debugLog(logLine)
    let animationTick = max(0.0'f32, b.frameCtx.animationTick)
    let animationSpeedScale = max(0.0'f32, b.animationSpeed)
    for i in 0 ..< anim.fields.len:
      let field = anim.fields[i].addr
      let nodeValue = getAnimatedFieldValue(b.frame, node[], field.fieldOffset)
      let currentBefore = field.currentValue
      let targetBefore {.used.} = field.targetValue
      # If a non-animating field was changed externally this frame (layout/fill),
      # keep that value instead of restoring a stale target.
      if abs(nodeValue - field.currentValue) > 0.0001'f32:
        field.currentValue = nodeValue
        field.targetValue = nodeValue
        if abs(field.currentValue - currentBefore) > 0.0001'f32:
          hasActiveField = true
        when defined(debugLogUiAnimation):
          let logLine = "ui.anim.end.sync" &
            " node='" & nodeDebugName(node[]) & "'" &
            " id=" & $nodeIdValue(node.id) &
            " field=" & $field.fieldOffset &
            " nodeValue=" & fmt2(nodeValue) &
            " currentBefore=" & fmt2(currentBefore) &
            " targetBefore=" & fmt2(targetBefore) &
            " currentAfter=" & fmt2(field.currentValue)
          debugLog(logLine)
        continue

      let blend = clamp(field.speed * animationSpeedScale * animationTick, 0.0'f32, 1.0'f32)
      field.currentValue = field.currentValue + (field.targetValue - field.currentValue) * blend
      if abs(field.targetValue - field.currentValue) <= 0.001'f32:
        field.currentValue = field.targetValue
      else:
        hasActiveField = true
      setAnimatedFieldValue(b, node[], field.fieldOffset, field.currentValue)
      when defined(debugLogUiAnimation):
        let logLine = "ui.anim.end.step" &
          " node='" & nodeDebugName(node[]) & "'" &
          " id=" & $nodeIdValue(node.id) &
          " field=" & $field.fieldOffset &
          " nodeBefore=" & fmt2(nodeValue) &
          " currentBefore=" & fmt2(currentBefore) &
          " target=" & fmt2(targetBefore) &
          " blend=" & fmt2(blend) &
          " currentAfter=" & fmt2(field.currentValue)
        debugLog(logLine)
    if hasActiveField:
      anim[].unchangedFrames = 0
    b.clampNodeSize(node)

  b.configuringAnimationStack[idx] = false
  b.animationTriggerStack[idx] = true

template animate*(b: var UiBuilder, body: untyped): untyped =
  ## Shorthand for beginAnimation(true), body, endAnimation(). Animations are triggered.
  b.beginAnimation(true)
  body
  b.endAnimation()

template animate*(b: var UiBuilder, trigger: bool, body: untyped): untyped =
  ## Shorthand for beginAnimation(trigger), body, endAnimation().
  b.beginAnimation(trigger)
  body
  b.endAnimation()

proc applyAnchoredLayoutToChildX(b: var UiBuilder, parentIdx, childIdx: int) =
  if parentIdx < 0 or parentIdx >= b.frame.nodes.len:
    return
  if childIdx < 0 or childIdx >= b.frame.nodes.len:
    return

  let parent = b.frame.nodes[parentIdx].addr
  let child = b.frame.nodes[childIdx].addr
  if not isAnchoredLayoutX(child[]):
    return

  let nodeAnchor = b.nodeAnchor(child)
  let contentW = max(0.0'f32, parent.size.x - b.nodeStyle(parent).paddingX * 2)
  let anchorTopLeft = clamp(nodeAnchor.topLeft, vec2(0.0'f32, 0.0'f32), vec2(1.0'f32, 1.0'f32))
  let anchorBottomRight = clamp(nodeAnchor.bottomRight, vec2(0.0'f32, 0.0'f32), vec2(1.0'f32, 1.0'f32))
  let anchorMinPx = contentW * anchorTopLeft.x + nodeAnchor.topLeftOffset.x
  let anchorMaxPx = contentW * anchorBottomRight.x + nodeAnchor.bottomRightOffset.x
  let pivot = clamp(nodeAnchor.pivot, vec2(0.0'f32, 0.0'f32), vec2(1.0'f32, 1.0'f32))

  let anchorSpanX = max(0.0'f32, anchorMaxPx - anchorMinPx)
  if anchorSpanX != 0:
    child.size.x = anchorSpanX
    if SizeXKnown in parent.flags:
      child.flags.incl SizeXKnown
    b.clampNodeSize(child)
  child.pos.x = anchorMinPx - child.size.x * pivot.x

proc applyAnchoredLayoutToChildY(b: var UiBuilder, parentIdx, childIdx: int) =
  if parentIdx < 0 or parentIdx >= b.frame.nodes.len:
    return
  if childIdx < 0 or childIdx >= b.frame.nodes.len:
    return

  let parent = b.frame.nodes[parentIdx].addr
  let child = b.frame.nodes[childIdx].addr
  if not isAnchoredLayoutY(child[]):
    return

  let nodeAnchor = b.nodeAnchor(child)
  let contentH = max(0.0'f32, parent.size.y - b.nodeStyle(parent).paddingY * 2)
  let anchorTopLeft = clamp(nodeAnchor.topLeft, vec2(0.0'f32, 0.0'f32), vec2(1.0'f32, 1.0'f32))
  let anchorBottomRight = clamp(nodeAnchor.bottomRight, vec2(0.0'f32, 0.0'f32), vec2(1.0'f32, 1.0'f32))
  let anchorMinPx = contentH * anchorTopLeft.y + nodeAnchor.topLeftOffset.y
  let anchorMaxPx = contentH * anchorBottomRight.y + nodeAnchor.bottomRightOffset.y
  let pivot = clamp(nodeAnchor.pivot, vec2(0.0'f32, 0.0'f32), vec2(1.0'f32, 1.0'f32))

  let anchorSpanY = max(0.0'f32, anchorMaxPx - anchorMinPx)
  if anchorSpanY != 0:
    child.size.y = anchorSpanY
    if SizeYKnown in parent.flags:
      child.flags.incl SizeYKnown
    b.clampNodeSize(child)
  child.pos.y = anchorMinPx - child.size.y * pivot.y

proc applyImmediateFillFromParent(b: var UiBuilder, idx: int) =
  if idx < 0 or idx >= b.frame.nodes.len:
    return

  let parentIdx = b.frame.nodes[idx].parent
  if parentIdx < 0:
    return

  let p = b.frame.nodes[parentIdx].addr
  let n = b.frame.nodes[idx].addr
  let nodeStyle = b.nodeStyle(p)
  let contentW = max(0.0'f32, p.size.x - nodeStyle.paddingX * 2)
  let contentH = max(0.0'f32, p.size.y - nodeStyle.paddingY * 2)
  let reverseX = isReverseLayout(p.flags) and isHorizontalLayout(p.flags)
  let reverseY = isReverseLayout(p.flags) and isVerticalLayout(p.flags)
  let remainingW =
    if reverseX:
      max(0.0'f32, n.pos.x)
    else:
      max(0.0'f32, contentW - n.pos.x)
  let remainingH =
    if reverseY:
      max(0.0'f32, n.pos.y)
    else:
      max(0.0'f32, contentH - n.pos.y)

  if SizeXKnown in p.flags:
    if FillX in n.flags:
      n.size.x = remainingW
      n.flags.incl SizeXKnown
  if SizeYKnown in p.flags:
    if FillY in n.flags:
      n.size.y = remainingH
      n.flags.incl SizeYKnown

  b.clampNodeSize(n)

proc contentSize*(b: var UiBuilder, n: ptr UiNode): Vec2 {.raises: [].} =
  ## Compute the total content size of a node including text, padding, and child content extent.
  let textSize = b.cachedMeasuredTextSize(n)
  result = vec2()

  let nodeStyle = b.nodeStyle(n)
  result.x = max(textSize.x + nodeStyle.paddingX * 2, n.contentExtent.x + nodeStyle.paddingX * 2)
  result.y = max(textSize.y + nodeStyle.paddingY * 2, n.contentExtent.y + nodeStyle.paddingY * 2)

proc updateNodeFit*(b: var UiBuilder, n: ptr UiNode) =
  ## Resize the node to fit its text and child content if FitX/Y flags are set.
  if FitX in n.flags or FitY in n.flags:
    let textSize = b.cachedMeasuredTextSize(n)

    if FitX in n.flags:
      let nodeStyle = b.nodeStyle(n)
      n.size.x = max(textSize.x + nodeStyle.paddingX * 2, n.contentExtent.x + nodeStyle.paddingX * 2)

    if FitY in n.flags:
      let nodeStyle = b.nodeStyle(n)
      n.size.y = max(textSize.y + nodeStyle.paddingY * 2, n.contentExtent.y + nodeStyle.paddingY * 2)

  b.clampNodeSize(n)

proc updateNodeFit*(b: var UiBuilder, idx: int) =
  ## Resize the node at idx to fit its content if FitX/Y flags are set.
  b.updateNodeFit(b.frame.nodes[idx].addr)

proc updateParentAfterChildEnd(b: var UiBuilder, child: ptr UiNode) =
  let parentIdx = child.parent
  if parentIdx < 0:
    return

  let parent = b.frame.nodes[parentIdx].addr
  let parentFitXEnabled = FitX in parent.flags
  let parentFitYEnabled = FitY in parent.flags

  if AlignCenter in child.flags:
    parent.flags.incl PostProcessChildren
  if parentFitXEnabled and (FillX in child.flags or AlignCenter in child.flags or isAnchoredLayoutX(child[])):
    parent.flags.incl PostProcessChildren
  if parentFitYEnabled and (FillY in child.flags or AlignCenter in child.flags or isAnchoredLayoutY(child[])):
    parent.flags.incl PostProcessChildren

  if isReverseLayout(parent.flags):
    if isHorizontalLayout(parent.flags) and parentFitXEnabled and not (FillX in child.flags):
      parent.flags.incl PostProcessChildren
    if isVerticalLayout(parent.flags) and parentFitYEnabled and not (FillY in child.flags):
      parent.flags.incl PostProcessChildren
    if isHorizontalLayout(parent.flags) and FillX in child.flags:
      parent.flags.incl PostProcessChildren
    if isVerticalLayout(parent.flags) and FillY in child.flags:
      parent.flags.incl PostProcessChildren

  if isReverseLayout(parent.flags):
    if isVerticalLayout(parent.flags):
      let newCursor = max(0.0'f32, parent.cursor.y - child.size.y)
      child.pos.y = newCursor
      parent.cursor.y = max(0.0'f32, newCursor - b.nodeGap(parent))
    elif isHorizontalLayout(parent.flags):
      let newCursor = max(0.0'f32, parent.cursor.x - child.size.x)
      child.pos.x = newCursor
      parent.cursor.x = max(0.0'f32, newCursor - b.nodeGap(parent))
    else:
      discard

  let childEndX = child.pos.x + child.size.x
  let childEndY = child.pos.y + child.size.y
  if IgnoreInContentExtent notin child.flags:
    if isReverseLayout(parent.flags) and isHorizontalLayout(parent.flags) and parentFitXEnabled:
      if parent.contentExtent.x > 0:
        parent.contentExtent.x += b.nodeGap(parent)
      parent.contentExtent.x += child.size.x
    else:
      parent.contentExtent.x = max(parent.contentExtent.x, childEndX)

    if isReverseLayout(parent.flags) and isVerticalLayout(parent.flags) and parentFitYEnabled:
      if parent.contentExtent.y > 0:
        parent.contentExtent.y += b.nodeGap(parent)
      parent.contentExtent.y += child.size.y
    else:
      parent.contentExtent.y = max(parent.contentExtent.y, childEndY)

  if not isReverseLayout(parent.flags):
    if isVerticalLayout(parent.flags):
      parent.cursor.y = max(parent.cursor.y, childEndY + b.nodeGap(parent))
    elif isHorizontalLayout(parent.flags):
      parent.cursor.x = max(parent.cursor.x, childEndX + b.nodeGap(parent))
    else:
      discard

  b.updateNodeFit(parent)

  if PostProcessChildren in b.currentNode.flags:
    parent.flags.incl PostProcessChildren

proc postProcessChildren*(b: var UiBuilder, idx: int): var UiBuilder {.discardable.} =
  ## Run layout post-processing on the node at idx: applies fill, align, anchored layout, and reverse layout.
  if idx < 0 or idx >= b.frame.nodes.len:
    return b

  let n = b.frame.nodes[idx].addr
  profd("layout " & n[].nodeDebugName())
  n.flags.incl IsPostProcessing
  n.flags.incl PostProcessChildren
  for i in 0..1:
    if PostProcessChildren notin n.flags:
      break
    n.flags.excl PostProcessChildren

    when defined(nuiDebug):
      inc n.postProcessCounter

    let nodeStyle = b.nodeStyle(n)
    let customLayoutParent = n.customLayoutIndex > 0
    var hasAnchoredChildren = false

    if customLayoutParent:
      let cl = b.frame.customLayouts[n.customLayoutIndex - 1]
      cl.layoutProc(b, idx, cl.userData)
    else:
      let contentW = max(0.0'f32, n.size.x - nodeStyle.paddingX * 2)
      let contentH = max(0.0'f32, n.size.y - nodeStyle.paddingY * 2)
      var remainingW = contentW
      var remainingH = contentH

      prof("builtinLayouts")
      for childIdx in b.children(idx):
        let child = b.frame.nodes[childIdx].addr
        let oldSize = child.size
        let anchoredX = isAnchoredLayoutX(child[])
        let anchoredY = isAnchoredLayoutY(child[])
        if anchoredX:
          hasAnchoredChildren = true
          b.applyAnchoredLayoutToChildX(idx, childIdx)
        if anchoredY:
          hasAnchoredChildren = true
          b.applyAnchoredLayoutToChildY(idx, childIdx)

        var changedSize = false

        if FillX in child.flags and not anchoredX:
          if FitX in child.flags:
            child.size.x = max(remainingW, b.contentSize(child).x)
          else:
            child.size.x = remainingW
          if SizeXKnown in n.flags:
            child.flags.incl SizeXKnown
          changedSize = true
        if FillY in child.flags and not anchoredY:
          if FitY in child.flags:
            child.size.y = max(remainingH, b.contentSize(child).y)
          else:
            child.size.y = remainingH
          if SizeYKnown in n.flags:
            child.flags.incl SizeYKnown
          changedSize = true

        if changedSize:
          b.clampNodeSize(child)

        if AlignCenter in child.flags:
          if isVerticalLayout(n.flags):
            if not anchoredX:
              child.pos.x = max(0.0'f32, (contentW - child.size.x) * 0.5'f32)
          elif isHorizontalLayout(n.flags):
            if not anchoredY:
              child.pos.y = max(0.0'f32, (contentH - child.size.y) * 0.5'f32)
          elif not hasLayout(n.flags):
            if not anchoredX:
              child.pos.x = max(0.0'f32, (contentW - child.size.x) * 0.5'f32)
            if not anchoredY:
              child.pos.y = max(0.0'f32, (contentH - child.size.y) * 0.5'f32)
          else:
            discard

        if oldSize != child.size:
          child.flags.incl SizeDirty

        if isHorizontalLayout(n.flags):
          remainingW -= child.size.x + b.nodeGap(n)
        if isVerticalLayout(n.flags):
          remainingH -= child.size.y + b.nodeGap(n)

      if isReverseLayout(n.flags):
        if isVerticalLayout(n.flags):
          var cursor = contentH
          for childIdx in b.children(idx):
            let child = b.frame.nodes[childIdx].addr
            if isAnchoredLayoutY(child[]):
              continue
            cursor = max(0.0'f32, cursor - child.size.y)
            let old = child.pos.y
            child.pos.y = cursor
            if child.pos.y != old and FillY in child.flags:
              n.flags.incl PostProcessChildren
            cursor = max(0.0'f32, cursor - b.nodeGap(n))
            if IgnoreInContentExtent notin child.flags:
              n.contentExtent.x = max(n.contentExtent.x, child.pos.x + child.size.x)
              n.contentExtent.y = max(n.contentExtent.y, child.pos.y + child.size.y)
        elif isHorizontalLayout(n.flags):
          var cursor = contentW
          for childIdx in b.children(idx):
            let child = b.frame.nodes[childIdx].addr
            if isAnchoredLayoutX(child[]):
              continue
            cursor = max(0.0'f32, cursor - child.size.x)
            let old = child.pos.x
            child.pos.x = cursor
            if child.pos.x != old and FillX in child.flags:
              n.flags.incl PostProcessChildren
            cursor = max(0.0'f32, cursor - b.nodeGap(n))
            if IgnoreInContentExtent notin child.flags:
              n.contentExtent.x = max(n.contentExtent.x, child.pos.x + child.size.x)
              n.contentExtent.y = max(n.contentExtent.y, child.pos.y + child.size.y)
        else:
          discard
      else:
        if isVerticalLayout(n.flags):
          var cursor = 0.0'f32
          for childIdx in b.children(idx):
            let child = b.frame.nodes[childIdx].addr
            if isAnchoredLayoutY(child[]):
              continue
            let old = child.pos.y
            child.pos.y = cursor
            if child.pos.y != old and FillY in child.flags:
              n.flags.incl PostProcessChildren
            cursor = max(0.0'f32, child.pos.y + child.size.y + b.nodeGap(n))
        elif isHorizontalLayout(n.flags):
          var cursor = 0.0'f32
          for childIdx in b.children(idx):
            let child = b.frame.nodes[childIdx].addr
            if isAnchoredLayoutX(child[]):
              continue
            let old = child.pos.x
            child.pos.x = cursor
            if child.pos.x != old and FillX in child.flags:
              n.flags.incl PostProcessChildren
            cursor = max(0.0'f32, child.pos.x + child.size.x + b.nodeGap(n))
        else:
          discard

    let oldContentSize = n.contentExtent
    var childSizeChanged = false
    for childIdx in b.children(idx):
      let child = b.frame.nodes[childIdx].addr
      if SizeDirty in child.flags or PostProcessChildren in child.flags:
        child.flags.excl SizeDirty
        let oldSize = child.size
        discard b.postProcessChildren(childIdx)
        if oldSize != child.size:
          childSizeChanged = true
      if IgnoreInContentExtent notin child.flags:
        n.contentExtent.x = max(n.contentExtent.x, child.pos.x + child.size.x)
        n.contentExtent.y = max(n.contentExtent.y, child.pos.y + child.size.y)

    if childSizeChanged:
      n.flags.incl PostProcessChildren

    if oldContentSize != n.contentExtent or (WrapText in n.flags and SizeXKnown in n.flags):
      let oldSize = n.size
      b.updateNodeFit(n)
      if oldSize != n.size:
        let parentIdx = n.parent
        if parentIdx >= 0:
          let parent = b.frame.nodes[parentIdx].addr
          if IsPostProcessing in parent.flags:
            parent.flags.incl PostProcessChildren

  n.flags.excl IsPostProcessing
  b

proc initCursorForLayout*(frame: UiFrame, n: ptr UiNode) =
  ## Initialize the layout cursor to the content origin (or end for reverse layouts).
  if isReverseLayout(n.flags):
    let paddingX = if n.styleIndex > 0: frame.styles[n.styleIndex - 1].paddingX else: 0.0'f32
    let paddingY = if n.styleIndex > 0: frame.styles[n.styleIndex - 1].paddingY else: 0.0'f32
    let contentW = max(0.0'f32, n.size.x - paddingX * 2)
    let contentH = max(0.0'f32, n.size.y - paddingY * 2)
    if isHorizontalLayout(n.flags):
      n.cursor = vec2(contentW, 0.0'f32)
    elif isVerticalLayout(n.flags):
      n.cursor = vec2(0.0'f32, contentH)
    elif not hasLayout(n.flags):
      n.cursor = vec2(contentW, contentH)
    else:
      discard

proc markParentForPostProcess(b: var UiBuilder) =
  if b.stack.len <= 0:
    return
  let parentIdx = b.currentNode.parent
  if parentIdx >= 0:
    b.frame.nodes[parentIdx].flags.incl PostProcessChildren

proc markForPostProcess*(b: var UiBuilder) =
  b.currentNode.flags.incl PostProcessChildren

proc alignCenter*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Center the current node within its parent's content area. Marks parent for post-processing.
  b.currentNode.flags.incl AlignCenter
  b.markParentForPostProcess()
  b

proc noHover*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Disable hover detection for the current node.
  b.currentNode.flags.incl NoHover
  b

proc noChildHover*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Disable hover detection for the current nodes children.
  b.currentNode.flags.incl NoChildHover
  b

proc ignoreInContentExtent*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Exclude the current node from its parent's accumulated content extent.
  b.currentNode.flags.incl IgnoreInContentExtent
  b

proc fill*(b: var UiBuilder, value = true): var UiBuilder {.discardable.} =
  ## Make the current node fill its parent on both axes.
  let idx = b.stack[^1]
  if value:
    b.currentNode.flags.incl FillX
    b.currentNode.flags.incl FillY
    b.applyImmediateFillFromParent(idx)
  else:
    b.currentNode.flags.excl FillX
    b.currentNode.flags.excl FillY
  b

proc fillX*(b: var UiBuilder, value = true): var UiBuilder {.discardable.} =
  ## Make the current node fill its parent on the X axis.
  let idx = b.stack[^1]
  if value:
    b.currentNode.flags.incl FillX
    b.applyImmediateFillFromParent(idx)
  else:
    b.currentNode.flags.excl FillX
  b

proc fillY*(b: var UiBuilder, value = true): var UiBuilder {.discardable.} =
  ## Make the current node fill its parent on the Y axis.
  let idx = b.stack[^1]
  if value:
    b.currentNode.flags.incl FillY
    b.applyImmediateFillFromParent(idx)
  else:
    b.currentNode.flags.excl FillY
  b

proc fitX*(b: var UiBuilder, value = true): var UiBuilder {.discardable.} =
  ## Make the current node's width automatically size to its text and child content.
  if value:
    b.currentNode.flags.incl FitX
    b.updateNodeFit(b.currentNode)
  else:
    b.currentNode.flags.excl FitX
  b

proc fitY*(b: var UiBuilder, value = true): var UiBuilder {.discardable.} =
  ## Make the current node's height automatically size to its text and child content.
  if value:
    b.currentNode.flags.incl FitY
    b.updateNodeFit(b.currentNode)
  else:
    b.currentNode.flags.excl FitY
  b

proc fit*(b: var UiBuilder, x = true, y = true): var UiBuilder {.discardable.} =
  ## Make the current node automatically size to its content on the specified axes.
  if x:
    b.currentNode.flags.incl FitX
  else:
    b.currentNode.flags.excl FitX
  if y:
    b.currentNode.flags.incl FitY
  else:
    b.currentNode.flags.excl FitY
  b.updateNodeFit(b.currentNode)
  b

proc updateFit*(b: var UiBuilder, value = 1.0'f32): var UiBuilder {.discardable.} =
  ## Re-run size-to-content calculation on the current node.
  b.updateNodeFit(b.currentNode)
  b

proc sizeToParentX*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Size the current node's width to match its parent's content area.
  let idx = b.stack[^1]
  let parentIdx = b.frame.nodes[idx].parent
  if parentIdx < 0:
      return b

  let parent = b.frame.nodes[parentIdx].addr
  let nodeStyle = b.nodeStyle(parent)
  b.currentNode.minSize.x = parent.minSize.x - nodeStyle.paddingX * 2
  b.currentNode.maxSize.x = parent.maxSize.x - nodeStyle.paddingX * 2
  let parentHasFillX = FillX in parent.flags
  let parentHasFitX = FitX in parent.flags
  if parentHasFillX:
    discard b.fillX()
  if parentHasFitX:
    discard b.fitX()
  if not parentHasFillX and not parentHasFitX:
    discard b.fillX()
    if SizeXKnown in parent.flags:
      b.currentNode.flags.incl SizeXKnown
  b

proc sizeToParentXAnim*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Animated version of sizeToParentX. Smoothly transitions the node's width to match its parent.
  let idx = b.stack[^1]
  let parentIdx = b.frame.nodes[idx].parent
  if parentIdx < 0:
    return b

  let parent = b.frame.nodes[parentIdx].addr
  let nodeStyle = b.nodeStyle(parent)
  b.currentNode.minSize.x = b.setAnimatedField(idx, UiNodeFieldMinSizeX, parent.minSize.x - nodeStyle.paddingX * 2)
  b.currentNode.maxSize.x = b.setAnimatedField(idx, UiNodeFieldMaxSizeX, parent.maxSize.x - nodeStyle.paddingX * 2)
  let parentHasFillX = FillX in parent.flags
  let parentHasFitX = FitX in parent.flags
  if parentHasFillX:
    discard b.fillX()
  if parentHasFitX:
    discard b.fitX()
  if not parentHasFillX and not parentHasFitX:
    b.currentNode.size.x = b.setAnimatedField(idx, UiNodeFieldSizeX, parent.size.x - nodeStyle.paddingX * 2)
  b

proc sizeToParentY*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Size the current node's height to match its parent's content area.
  let idx = b.stack[^1]
  let parentIdx = b.frame.nodes[idx].parent
  if parentIdx < 0:
    return b

  let parent = b.frame.nodes[parentIdx].addr
  let nodeStyle = b.nodeStyle(parent)
  b.currentNode.minSize.y = parent.minSize.y - nodeStyle.paddingY * 2
  b.currentNode.maxSize.y = parent.maxSize.y - nodeStyle.paddingY * 2
  let parentHasFillY = FillY in parent.flags
  let parentHasFitY = FitY in parent.flags
  if parentHasFillY:
    discard b.fillY()
  if parentHasFitY:
    discard b.fitY()
  if not parentHasFillY and not parentHasFitY:
    discard b.fillY()
    if SizeYKnown in parent.flags:
      b.currentNode.flags.incl SizeYKnown
  b

proc sizeToParentYAnim*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Animated version of sizeToParentY. Smoothly transitions the node's height to match its parent.
  let idx = b.stack[^1]
  let parentIdx = b.frame.nodes[idx].parent
  if parentIdx < 0:
    return b

  let parent = b.frame.nodes[parentIdx].addr
  let nodeStyle = b.nodeStyle(parent)
  b.currentNode.minSize.y = b.setAnimatedField(idx, UiNodeFieldMinSizeY, parent.minSize.y - nodeStyle.paddingY * 2)
  b.currentNode.maxSize.y = b.setAnimatedField(idx, UiNodeFieldMaxSizeY, parent.maxSize.y - nodeStyle.paddingY * 2)
  let parentHasFillY = FillY in parent.flags
  let parentHasFitY = FitY in parent.flags
  if parentHasFillY:
    discard b.fillY()
  if parentHasFitY:
    discard b.fitY()
  if not parentHasFillY and not parentHasFitY:
    b.currentNode.size.y = b.setAnimatedField(idx, UiNodeFieldSizeY, parent.size.y - nodeStyle.paddingY * 2)
  b

proc sizeToParent*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Size the current node to match its parent's content area on both axes.
  let idx = b.stack[^1]
  let parentIdx = b.frame.nodes[idx].parent
  if parentIdx < 0:
    return b

  let parent = b.frame.nodes[parentIdx].addr
  let nodeStyle = b.nodeStyle(parent)
  b.currentNode.minSize.x = parent.minSize.x - nodeStyle.paddingX * 2
  b.currentNode.maxSize.x = parent.maxSize.x - nodeStyle.paddingX * 2
  b.currentNode.minSize.y = parent.minSize.y - nodeStyle.paddingY * 2
  b.currentNode.maxSize.y = parent.maxSize.y - nodeStyle.paddingY * 2
  let parentHasFillX = FillX in parent.flags
  let parentHasFillY = FillY in parent.flags
  let parentHasFitX = FitX in parent.flags
  let parentHasFitY = FitY in parent.flags
  if parentHasFillX:
    discard b.fillX()
  if parentHasFillY:
    discard b.fillY()
  if parentHasFitX:
    discard b.fitX()
  if parentHasFitY:
    discard b.fitY()
  if not parentHasFillX and not parentHasFitX:
    b.currentNode.size.x = parent.size.x - nodeStyle.paddingX * 2
  if not parentHasFillY and not parentHasFitY:
    b.currentNode.size.y = parent.size.y - nodeStyle.paddingY * 2
  b

proc sizeToParentAnim*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Animated version of sizeToParent. Smoothly transitions the node's size to match its parent.
  let idx = b.stack[^1]
  let parentIdx = b.frame.nodes[idx].parent
  if parentIdx < 0:
    return b

  let parent = b.frame.nodes[parentIdx].addr
  let nodeStyle = b.nodeStyle(parent)
  b.currentNode.minSize.x = b.setAnimatedField(idx, UiNodeFieldMinSizeX, parent.minSize.x - nodeStyle.paddingX * 2)
  b.currentNode.maxSize.x = b.setAnimatedField(idx, UiNodeFieldMaxSizeX, parent.maxSize.x - nodeStyle.paddingX * 2)
  b.currentNode.minSize.y = b.setAnimatedField(idx, UiNodeFieldMinSizeY, parent.minSize.y - nodeStyle.paddingY * 2)
  b.currentNode.maxSize.y = b.setAnimatedField(idx, UiNodeFieldMaxSizeY, parent.maxSize.y - nodeStyle.paddingY * 2)
  let parentHasFillX = FillX in parent.flags
  let parentHasFillY = FillY in parent.flags
  let parentHasFitX = FitX in parent.flags
  let parentHasFitY = FitY in parent.flags
  if parentHasFillX:
    discard b.fillX()
  if parentHasFillY:
    discard b.fillY()
  if parentHasFitX:
    discard b.fitX()
  if parentHasFitY:
    discard b.fitY()
  if not parentHasFillX and not parentHasFitX:
    b.currentNode.size.x = b.setAnimatedField(idx, UiNodeFieldSizeX, parent.size.x - nodeStyle.paddingX * 2)
  if not parentHasFillY and not parentHasFitY:
    b.currentNode.size.y = b.setAnimatedField(idx, UiNodeFieldSizeY, parent.size.y - nodeStyle.paddingY * 2)
  b

proc fillBackground*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Enable background fill rendering for the current node using its fillColor.
  b.currentNode.flags.incl FillBackground
  b

proc maskChildren*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Clip all children to the current node's content area.
  b.currentNode.flags.incl MaskChildren
  b

proc scrollable*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Current node should react to scroll events.
  b.currentNode.flags.incl Scrollable
  b

proc customRenderCommands*(b: var UiBuilder, commands: ArrayView[UiRenderCommand]): var UiBuilder {.discardable.} =
  ## Attach custom render commands to the current node (from an ArrayView).
  b.ensureNodeCustomCommands(b.currentNode) = commands
  b

proc customRenderCommands*(b: var UiBuilder, commands: openArray[UiRenderCommand]): var UiBuilder {.discardable.} =
  ## Attach custom render commands to the current node (from an openArray).
  b.ensureNodeCustomCommands(b.currentNode) = initArrayView(commands)
  b

proc backgroundColor*(b: var UiBuilder, value: UiColor): var UiBuilder {.discardable.} =
  ## Set the current node's fill color and enable background rendering.
  b.currentNode.flags.incl FillBackground
  b.ensureNodeStyle(b.currentNode).fillColor = value
  b

proc backgroundColorAnim*(b: var UiBuilder, value: UiColor): var UiBuilder {.discardable.} =
  ## Animated version of backgroundColor. Smoothly transitions the fill color.
  let idx = b.stack[^1]
  b.currentNode.flags.incl FillBackground
  b.ensureNodeStyle(b.currentNode).fillColor = b.setAnimatedField(idx, UiNodeFieldStyleFillColorR, value)
  b

proc textColor*(b: var UiBuilder, value: UiColor): var UiBuilder {.discardable.} =
  ## Set the current node's text color.
  b.ensureNodeText(b.currentNode).textColor = value
  b

proc textColorAnim*(b: var UiBuilder, value: UiColor): var UiBuilder {.discardable.} =
  ## Animated version of textColor. Smoothly transitions the text color.
  let idx = b.stack[^1]
  b.ensureNodeText(b.currentNode).textColor = b.setAnimatedField(idx, UiNodeFieldStyleTextColorR, value)
  b

proc borderColor*(b: var UiBuilder, value: UiColor): var UiBuilder {.discardable.} =
  ## Set the current node's border color.
  let style = b.ensureNodeStyle(b.currentNode).addr
  style.borderColor = value
  style.borderColors = default(UiBorderColors)
  b

proc borderColorAnim*(b: var UiBuilder, value: UiColor): var UiBuilder {.discardable.} =
  ## Animated version of borderColor. Smoothly transitions the border color.
  let idx = b.stack[^1]
  let style = b.ensureNodeStyle(b.currentNode).addr
  style.borderColor = b.setAnimatedField(idx, UiNodeFieldStyleBorderColorR, value)
  style.borderColors = default(UiBorderColors)
  b

proc borderColors*(b: var UiBuilder, left, top, right, bottom: UiColor): var UiBuilder {.discardable.} =
  ## Set independent colors for the left, top, right, and bottom borders.
  b.ensureNodeStyle(b.currentNode).borderColors = UiBorderColors(
    left: left, top: top, right: right, bottom: bottom)
  b

proc borderWidth*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set the current node's border width. Negative values are clamped to 0.
  let style = b.ensureNodeStyle(b.currentNode).addr
  style.borderWidth = max(0.0'f32, value)
  style.borderWidths = default(UiBorderWidths)
  b

proc focusHighlight*(b: var UiBuilder, width = 2.0'f32): var UiBuilder {.discardable.} =
  ## Draw the standard accent border when the current node is keyboard-focused.
  if b.isFocused():
    if b.currentNode.styleIndex > 0 and b.currentNode.styleIndex.int < b.themeStyles.len:
      discard b.copyStyleIndex(b.currentNode.styleIndex)
    discard b.borderWidth(width)
    discard b.borderColor(b.themeStyle(UiStyleIndexAccent)[].borderColor)
  b

proc borderWidthAnim*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Animated version of borderWidth. Smoothly transitions the border width.
  let idx = b.stack[^1]
  let style = b.ensureNodeStyle(b.currentNode).addr
  style.borderWidth = b.setAnimatedField(idx, UiNodeFieldStyleBorderWidth, max(0.0'f32, value))
  style.borderWidths = default(UiBorderWidths)
  b

proc borderWidths*(b: var UiBuilder, left, top, right, bottom: float32): var UiBuilder {.discardable.} =
  ## Set independent widths for the left, top, right, and bottom borders.
  b.ensureNodeStyle(b.currentNode).borderWidths = UiBorderWidths(
    left: max(0.0'f32, left),
    top: max(0.0'f32, top),
    right: max(0.0'f32, right),
    bottom: max(0.0'f32, bottom),
  )
  b

proc cornerRadius*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set the current node's corner radius. Negative values are clamped to 0.
  let style = b.ensureNodeStyle(b.currentNode).addr
  style.cornerRadius = max(0.0'f32, value)
  style.cornerRadii = default(UiCornerRadii)
  b

proc cornerRadiusAnim*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Animated version of cornerRadius. Smoothly transitions the corner radius.
  let idx = b.stack[^1]
  let style = b.ensureNodeStyle(b.currentNode).addr
  style.cornerRadius = b.setAnimatedField(idx, UiNodeFieldStyleCornerRadius, max(0.0'f32, value))
  style.cornerRadii = default(UiCornerRadii)
  b

proc cornerRadii*(b: var UiBuilder, topLeft, topRight, bottomRight, bottomLeft: float32): var UiBuilder {.discardable.} =
  ## Set independent radii for the four corners, clockwise from top-left.
  b.ensureNodeStyle(b.currentNode).cornerRadii = UiCornerRadii(
    topLeft: max(0.0'f32, topLeft),
    topRight: max(0.0'f32, topRight),
    bottomRight: max(0.0'f32, bottomRight),
    bottomLeft: max(0.0'f32, bottomLeft),
  )
  b

proc text*(b: var UiBuilder, value: string): var UiBuilder {.discardable.} =
  ## Set the current node's text content. Enables DrawText and triggers size-to-content recalculation.
  b.currentNode.flags.incl DrawText
  var t = addr(b.ensureNodeText(b.currentNode))
  if t.text.value != value:
    t.text = value.uiString
    t.measuredTextDirty = true
  b.updateNodeFit(b.currentNode)
  b

proc wrapText*(b: var UiBuilder, value = true): var UiBuilder {.discardable.} =
  ## Enable or disable wrapping text to the current node's content width.
  if value:
    b.currentNode.flags.incl WrapText
  else:
    b.currentNode.flags.excl WrapText
  if b.currentNode.textIndex > 0:
    b.nodeText(b.currentNode).measuredTextDirty = true
    b.updateNodeFit(b.currentNode)
  b

proc fontSize*(b: var UiBuilder, size: float32): var UiBuilder {.discardable.} =
  ## Set the current node's font size. Triggers text measurement and size-to-content recalculation.
  b.currentNode.flags.incl DrawText
  var t = addr(b.ensureNodeText(b.currentNode))
  if t.fontSize != size:
    t.fontSize = size
    t.measuredTextDirty = true
    b.updateNodeFit(b.currentNode)
  b

proc fontId*(b: var UiBuilder, fontId: UiFontId): var UiBuilder {.discardable.} =
  ## Set the current node's font. Triggers text measurement and size-to-content recalculation.
  var t = addr(b.ensureNodeText(b.currentNode))
  if t.fontId != fontId:
    t.fontId = fontId
    t.measuredTextDirty = true
    b.updateNodeFit(b.currentNode)
  b

proc minSize*(b: var UiBuilder, w, h: float32): var UiBuilder {.discardable.} =
  ## Set the minimum size constraint for the current node. Clamps the current size immediately.
  let target = vec2(max(0.0'f32, w), max(0.0'f32, h))
  b.currentNode.minSize = target
  if b.currentNode.maxSize.x < b.currentNode.minSize.x:
    b.currentNode.maxSize.x = b.currentNode.minSize.x
  if b.currentNode.maxSize.y < b.currentNode.minSize.y:
    b.currentNode.maxSize.y = b.currentNode.minSize.y
  b.clampNodeSize(b.currentNode)
  b

proc minSizeAnim*(b: var UiBuilder, w, h: float32): var UiBuilder {.discardable.} =
  ## Animated version of minSize. Smoothly transitions the minimum size constraint.
  let idx = b.stack[^1]
  let target = vec2(max(0.0'f32, w), max(0.0'f32, h))
  b.currentNode.minSize = b.setAnimatedField(idx, UiNodeFieldMinSizeX, target)
  if b.currentNode.maxSize.x < b.currentNode.minSize.x:
    b.currentNode.maxSize.x = b.currentNode.minSize.x
  if b.currentNode.maxSize.y < b.currentNode.minSize.y:
    b.currentNode.maxSize.y = b.currentNode.minSize.y
  b.clampNodeSize(b.currentNode)
  b

proc maxSize*(b: var UiBuilder, w, h: float32): var UiBuilder {.discardable.} =
  ## Set the maximum size constraint for the current node. Clamps the current size immediately.
  let target = vec2(max(0.0'f32, w), max(0.0'f32, h))
  b.currentNode.maxSize = target
  if b.currentNode.maxSize.x < b.currentNode.minSize.x:
    b.currentNode.maxSize.x = b.currentNode.minSize.x
  if b.currentNode.maxSize.y < b.currentNode.minSize.y:
    b.currentNode.maxSize.y = b.currentNode.minSize.y
  b.clampNodeSize(b.currentNode)
  b

proc maxSizeAnim*(b: var UiBuilder, w, h: float32): var UiBuilder {.discardable.} =
  ## Animated version of maxSize. Smoothly transitions the maximum size constraint.
  let idx = b.stack[^1]
  let target = vec2(max(0.0'f32, w), max(0.0'f32, h))
  b.currentNode.maxSize = b.setAnimatedField(idx, UiNodeFieldMaxSizeX, target)
  if b.currentNode.maxSize.x < b.currentNode.minSize.x:
    b.currentNode.maxSize.x = b.currentNode.minSize.x
  if b.currentNode.maxSize.y < b.currentNode.minSize.y:
    b.currentNode.maxSize.y = b.currentNode.minSize.y
  b.clampNodeSize(b.currentNode)
  b

proc minWidth*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set the minimum width constraint for the current node.
  discard b.minSize(value, b.currentNode.minSize.y)
  b

proc minWidthAnim*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Animated version of minWidth.
  discard b.minSizeAnim(value, b.currentNode.minSize.y)
  b

proc minHeight*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set the minimum height constraint for the current node.
  discard b.minSize(b.currentNode.minSize.x, value)
  b

proc minHeightAnim*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Animated version of minHeight.
  discard b.minSizeAnim(b.currentNode.minSize.x, value)
  b

proc maxWidth*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set the maximum width constraint for the current node.
  discard b.maxSize(value, b.currentNode.maxSize.y)
  b

proc maxWidthAnim*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Animated version of maxWidth.
  discard b.maxSizeAnim(value, b.currentNode.maxSize.y)
  b

proc maxHeight*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set the maximum height constraint for the current node.
  discard b.maxSize(b.currentNode.maxSize.x, value)
  b

proc maxHeightAnim*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Animated version of maxHeight.
  discard b.maxSizeAnim(b.currentNode.maxSize.x, value)
  b

proc anchorBlend*(b: var UiBuilder, blend = true): var UiBuilder {.discardable.} =
  ## Enable or disable anchored layout on both axes for the current node.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  if blend:
    b.currentNode.flags.incl AnchorX
    b.currentNode.flags.incl AnchorY
  else:
    b.currentNode.flags.excl AnchorX
    b.currentNode.flags.excl AnchorY
  b.markParentForPostProcess()
  b

proc anchorBlendX*(b: var UiBuilder, blend = true): var UiBuilder {.discardable.} =
  ## Enable or disable anchored layout on the X axis for the current node.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  if blend:
    b.currentNode.flags.incl AnchorX
  else:
    b.currentNode.flags.excl AnchorX
  b.markParentForPostProcess()
  b

proc anchorBlendY*(b: var UiBuilder, blend = true): var UiBuilder {.discardable.} =
  ## Enable or disable anchored layout on the Y axis for the current node.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  if blend:
    b.currentNode.flags.incl AnchorY
  else:
    b.currentNode.flags.excl AnchorY
  b.markParentForPostProcess()
  b

proc anchors*(b: var UiBuilder, topLeft, bottomRight: Vec2): var UiBuilder {.discardable.} =
  ## Set anchor positions (0-1 range) for both axes. Enables anchored layout.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  b.currentNode.flags.incl AnchorX
  b.currentNode.flags.incl AnchorY
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeft = topLeft
  nodeAnchor.bottomRight = bottomRight
  b.markParentForPostProcess()
  b

proc anchorsAnim*(b: var UiBuilder, topLeft, bottomRight: Vec2): var UiBuilder {.discardable.} =
  ## Animated version of anchors. Smoothly transitions anchor positions.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  let idx = b.stack[^1]
  b.currentNode.flags.incl AnchorX
  b.currentNode.flags.incl AnchorY
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeft = b.setAnimatedField(idx, UiNodeFieldAnchorTopLeftX, topLeft)
  nodeAnchor.bottomRight = b.setAnimatedField(idx, UiNodeFieldAnchorBottomRightX, bottomRight)
  b.markParentForPostProcess()
  b

proc anchorsX*(b: var UiBuilder, topLeftX, bottomRightX: float32): var UiBuilder {.discardable.} =
  ## Set X-axis anchor positions. Enables anchored layout on X.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  b.currentNode.flags.incl AnchorX
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeft.x = topLeftX
  nodeAnchor.bottomRight.x = bottomRightX
  b.markParentForPostProcess()
  b

proc anchorsXAnim*(b: var UiBuilder, topLeftX, bottomRightX: float32): var UiBuilder {.discardable.} =
  ## Animated version of anchorsX. Smoothly transitions X-axis anchor positions.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  let idx = b.stack[^1]
  b.currentNode.flags.incl AnchorX
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeft.x = b.setAnimatedField(idx, UiNodeFieldAnchorTopLeftX, topLeftX)
  nodeAnchor.bottomRight.x = b.setAnimatedField(idx, UiNodeFieldAnchorBottomRightX, bottomRightX)
  b.markParentForPostProcess()
  b

proc anchorsY*(b: var UiBuilder, topLeftY, bottomRightY: float32): var UiBuilder {.discardable.} =
  ## Set Y-axis anchor positions. Enables anchored layout on Y.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  b.currentNode.flags.incl AnchorY
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeft.y = topLeftY
  nodeAnchor.bottomRight.y = bottomRightY
  b.markParentForPostProcess()
  b

proc anchorsYAnim*(b: var UiBuilder, topLeftY, bottomRightY: float32): var UiBuilder {.discardable.} =
  ## Animated version of anchorsY. Smoothly transitions Y-axis anchor positions.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  let idx = b.stack[^1]
  b.currentNode.flags.incl AnchorY
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeft.y = b.setAnimatedField(idx, UiNodeFieldAnchorTopLeftY, topLeftY)
  nodeAnchor.bottomRight.y = b.setAnimatedField(idx, UiNodeFieldAnchorBottomRightY, bottomRightY)
  b.markParentForPostProcess()
  b

proc anchors*(b: var UiBuilder, topLeftX, topLeftY, bottomRightX, bottomRightY: float32): var UiBuilder {.discardable.} =
  ## Set anchor positions for both axes from individual floats.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  discard b.anchors(vec2(topLeftX, topLeftY), vec2(bottomRightX, bottomRightY))
  b

proc anchorsAnim*(b: var UiBuilder, topLeftX, topLeftY, bottomRightX, bottomRightY: float32): var UiBuilder {.discardable.} =
  ## Animated version of anchors (float overload). Smoothly transitions anchor positions.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  discard b.anchorsAnim(vec2(topLeftX, topLeftY), vec2(bottomRightX, bottomRightY))
  b

proc finishAnchors*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Apply anchored layout to the current node relative to its parent.
  ## Must be called after configuring anchor properties (anchors, offsets, pivot) for them to take effect.
  let childIdx = b.stack[^1]
  let parentIdx = b.frame.nodes[childIdx].parent
  if parentIdx < 0:
    return b
  b.applyAnchoredLayoutToChildX(parentIdx, childIdx)
  b.applyAnchoredLayoutToChildY(parentIdx, childIdx)
  b

proc offsets*(b: var UiBuilder, topLeft, bottomRight: Vec2): var UiBuilder {.discardable.} =
  ## Set pixel offsets for anchored layout. Enables anchored layout on both axes.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  b.currentNode.flags.incl AnchorX
  b.currentNode.flags.incl AnchorY
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeftOffset = topLeft
  nodeAnchor.bottomRightOffset = bottomRight
  b.markParentForPostProcess()
  b

proc offsetsAnim*(b: var UiBuilder, topLeft, bottomRight: Vec2): var UiBuilder {.discardable.} =
  ## Animated version of offsets. Smoothly transitions pixel offsets.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  let idx = b.stack[^1]
  b.currentNode.flags.incl AnchorX
  b.currentNode.flags.incl AnchorY
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeftOffset = b.setAnimatedField(idx, UiNodeFieldAnchorTopLeftOffsetX, topLeft)
  nodeAnchor.bottomRightOffset = b.setAnimatedField(idx, UiNodeFieldAnchorBottomRightOffsetX, bottomRight)
  b.markParentForPostProcess()
  b

proc offsetsX*(b: var UiBuilder, left, right: float32): var UiBuilder {.discardable.} =
  ## Set X-axis pixel offsets for anchored layout.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  b.currentNode.flags.incl AnchorX
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeftOffset.x = left
  nodeAnchor.bottomRightOffset.x = right
  b.markParentForPostProcess()
  b

proc offsetsXAnim*(b: var UiBuilder, left, right: float32): var UiBuilder {.discardable.} =
  ## Animated version of offsetsX. Smoothly transitions X-axis pixel offsets.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  let idx = b.stack[^1]
  b.currentNode.flags.incl AnchorX
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeftOffset.x = b.setAnimatedField(idx, UiNodeFieldAnchorTopLeftOffsetX, left)
  nodeAnchor.bottomRightOffset.x = b.setAnimatedField(idx, UiNodeFieldAnchorBottomRightOffsetX, right)
  b.markParentForPostProcess()
  b

proc offsetsY*(b: var UiBuilder, top, bottom: float32): var UiBuilder {.discardable.} =
  ## Set Y-axis pixel offsets for anchored layout.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  b.currentNode.flags.incl AnchorY
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeftOffset.y = top
  nodeAnchor.bottomRightOffset.y = bottom
  b.markParentForPostProcess()
  b

proc offsetsYAnim*(b: var UiBuilder, top, bottom: float32): var UiBuilder {.discardable.} =
  ## Animated version of offsetsY. Smoothly transitions Y-axis pixel offsets.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  let idx = b.stack[^1]
  b.currentNode.flags.incl AnchorY
  let nodeAnchor = b.ensureNodeAnchor(b.currentNode).addr
  nodeAnchor.topLeftOffset.y = b.setAnimatedField(idx, UiNodeFieldAnchorTopLeftOffsetY, top)
  nodeAnchor.bottomRightOffset.y = b.setAnimatedField(idx, UiNodeFieldAnchorBottomRightOffsetY, bottom)
  b.markParentForPostProcess()
  b

proc offsets*(b: var UiBuilder, left, top, right, bottom: float32): var UiBuilder {.discardable.} =
  ## Set pixel offsets for anchored layout from individual floats.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  discard b.offsets(vec2(left, top), vec2(right, bottom))
  b

proc offsetsAnim*(b: var UiBuilder, left, top, right, bottom: float32): var UiBuilder {.discardable.} =
  ## Animated version of offsets (float overload). Smoothly transitions pixel offsets.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  discard b.offsetsAnim(vec2(left, top), vec2(right, bottom))
  b

proc pivot*(b: var UiBuilder, value: Vec2): var UiBuilder {.discardable.} =
  ## Set the anchor pivot point (0-1 range). Enables anchored layout.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  b.currentNode.flags.incl AnchorX
  b.currentNode.flags.incl AnchorY
  b.ensureNodeAnchor(b.currentNode).pivot = value
  b.markParentForPostProcess()
  b

proc pivotAnim*(b: var UiBuilder, value: Vec2): var UiBuilder {.discardable.} =
  ## Animated version of pivot. Smoothly transitions the anchor pivot point.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  let idx = b.stack[^1]
  b.currentNode.flags.incl AnchorX
  b.currentNode.flags.incl AnchorY
  b.ensureNodeAnchor(b.currentNode).pivot = b.setAnimatedField(idx, UiNodeFieldAnchorPivotX, value)
  b.markParentForPostProcess()
  b

proc pivotX*(b: var UiBuilder, x: float32): var UiBuilder {.discardable.} =
  ## Set the X component of the anchor pivot point.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  b.currentNode.flags.incl AnchorX
  b.ensureNodeAnchor(b.currentNode).pivot.x = x
  b.markParentForPostProcess()
  b

proc pivotXAnim*(b: var UiBuilder, x: float32): var UiBuilder {.discardable.} =
  ## Animated version of pivotX.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  let idx = b.stack[^1]
  b.currentNode.flags.incl AnchorX
  b.ensureNodeAnchor(b.currentNode).pivot.x = b.setAnimatedField(idx, UiNodeFieldAnchorPivotX, x)
  b.markParentForPostProcess()
  b

proc pivotY*(b: var UiBuilder, y: float32): var UiBuilder {.discardable.} =
  ## Set the Y component of the anchor pivot point.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  b.currentNode.flags.incl AnchorY
  b.ensureNodeAnchor(b.currentNode).pivot.y = y
  b.markParentForPostProcess()
  b

proc pivotYAnim*(b: var UiBuilder, y: float32): var UiBuilder {.discardable.} =
  ## Animated version of pivotY.
  ## Call `finishAnchors` after configuring anchor properties for them to take effect.
  let idx = b.stack[^1]
  b.currentNode.flags.incl AnchorY
  b.ensureNodeAnchor(b.currentNode).pivot.y = b.setAnimatedField(idx, UiNodeFieldAnchorPivotY, y)
  b.markParentForPostProcess()
  b

proc pivot*(b: var UiBuilder, x, y: float32): var UiBuilder {.discardable.} =
  ## Set the anchor pivot point from individual floats.
  discard b.pivot(vec2(x, y))
  b

proc pivotAnim*(b: var UiBuilder, x, y: float32): var UiBuilder {.discardable.} =
  ## Animated version of pivot (float overload).
  discard b.pivotAnim(vec2(x, y))
  b

proc position*(b: var UiBuilder, x, y: float32): var UiBuilder {.discardable.} =
  ## Set the position of the current node, relative to its parent's content origin.
  b.currentNode.pos = vec2(x, y)
  b

proc positionAnim*(b: var UiBuilder, x, y: float32): var UiBuilder {.discardable.} =
  ## Animated version of position. Position is relative to parent. Smoothly transitions the node's position.
  let idx = b.stack[^1]
  b.currentNode.pos = b.setAnimatedField(idx, UiNodeFieldPosX, vec2(x, y))
  b

proc animatePos*(b: var UiBuilder, speed = DefaultAnimationSpeed): var UiBuilder {.discardable.} =
  ## Enable animation for the current node's position (relative to parent) using its previously set value as the start.
  let previousX = previousAnimationFieldStartValue(b.previousFrame, UiAnimation(), b.currentNode.id, UiNodeFieldPosX)
  let previousY = previousAnimationFieldStartValue(b.previousFrame, UiAnimation(), b.currentNode.id, UiNodeFieldPosY)
  if previousX.hasValue and previousY.hasValue:
    let animIdx = b.resolveAnimationIndex(b.currentNode.id, true)
    let anim = b.animations[animIdx].addr
    let initializeX = findAnimationFieldIndex(anim[], UiNodeFieldPosX) < 0 and previousX.hasValue
    let initializeY = findAnimationFieldIndex(anim[], UiNodeFieldPosY) < 0 and previousY.hasValue
    discard anim[].applyAnimatedFieldTarget(b.currentNode[], UiNodeFieldPosX, b.currentNode.pos.x, speed, b.frameCtx.input.frameIndex, initializeX, previousX.value)
    discard anim[].applyAnimatedFieldTarget(b.currentNode[], UiNodeFieldPosY, b.currentNode.pos.y, speed, b.frameCtx.input.frameIndex, initializeY, previousY.value)
  b

proc position*(b: var UiBuilder, pos: Vec2): var UiBuilder {.discardable.} =
  ## Set the position of the current node, relative to its parent's content origin (Vec2 overload).
  discard b.position(pos.x, pos.y)
  b

proc positionAnim*(b: var UiBuilder, pos: Vec2): var UiBuilder {.discardable.} =
  ## Animated version of position (Vec2 overload). Position is relative to parent.
  discard b.positionAnim(pos.x, pos.y)
  b

proc transformOffset*(b: var UiBuilder, value: Vec2): var UiBuilder {.discardable.} =
  ## Set the transform offset applied to the current node after layout.
  b.ensureNodeTransform(b.currentNode).offset = value
  b

proc transformOffsetAnim*(b: var UiBuilder, value: Vec2): var UiBuilder {.discardable.} =
  ## Animated version of transformOffset. Smoothly transitions the offset.
  let idx = b.stack[^1]
  b.ensureNodeTransform(b.currentNode).offset = b.setAnimatedField(idx, UiNodeFieldTransformOffsetX, value)
  b

proc transformOffset*(b: var UiBuilder, x, y: float32): var UiBuilder {.discardable.} =
  ## Set the transform offset from individual floats.
  discard b.transformOffset(vec2(x, y))
  b

proc transformOffsetAnim*(b: var UiBuilder, x, y: float32): var UiBuilder {.discardable.} =
  ## Animated version of transformOffset (float overload).
  discard b.transformOffsetAnim(vec2(x, y))
  b

proc transformRotation*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set the rotation (in radians) of the current node's transform.
  b.ensureNodeTransform(b.currentNode).rotation = value
  b

proc transformRotationAnim*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Animated version of transformRotation. Smoothly transitions the rotation.
  let idx = b.stack[^1]
  b.ensureNodeTransform(b.currentNode).rotation = b.setAnimatedField(idx, UiNodeFieldTransformRotation, value)
  b

proc transformScale*(b: var UiBuilder, value: Vec2): var UiBuilder {.discardable.} =
  ## Set the scale of the current node's transform.
  b.ensureNodeTransform(b.currentNode).scale = value
  b

proc transformScaleAnim*(b: var UiBuilder, value: Vec2): var UiBuilder {.discardable.} =
  ## Animated version of transformScale. Smoothly transitions the scale.
  let idx = b.stack[^1]
  b.ensureNodeTransform(b.currentNode).scale = b.setAnimatedField(idx, UiNodeFieldTransformScaleX, value)
  b

proc transformScale*(b: var UiBuilder, x, y: float32): var UiBuilder {.discardable.} =
  ## Set the scale from individual floats.
  discard b.transformScale(vec2(x, y))
  b

proc transformScaleAnim*(b: var UiBuilder, x, y: float32): var UiBuilder {.discardable.} =
  ## Animated version of transformScale (float overload).
  discard b.transformScaleAnim(vec2(x, y))
  b

proc transformScale*(b: var UiBuilder, uniform: float32): var UiBuilder {.discardable.} =
  ## Set a uniform scale on both axes.
  discard b.transformScale(vec2(uniform, uniform))
  b

proc transformScaleAnim*(b: var UiBuilder, uniform: float32): var UiBuilder {.discardable.} =
  ## Animated version of transformScale (uniform overload).
  discard b.transformScaleAnim(vec2(uniform, uniform))
  b

proc transformPivot*(b: var UiBuilder, value: Vec2): var UiBuilder {.discardable.} =
  ## Set the pivot point for the transform (0-1 range, default 0.5,0.5).
  b.ensureNodeTransform(b.currentNode).pivot = value
  b

proc transformPivotAnim*(b: var UiBuilder, value: Vec2): var UiBuilder {.discardable.} =
  ## Animated version of transformPivot. Smoothly transitions the pivot point.
  let idx = b.stack[^1]
  b.ensureNodeTransform(b.currentNode).pivot = b.setAnimatedField(idx, UiNodeFieldTransformPivotX, value)
  b

proc transformPivot*(b: var UiBuilder, x, y: float32): var UiBuilder {.discardable.} =
  ## Set the transform pivot point from individual floats.
  discard b.transformPivot(vec2(x, y))
  b

proc transformPivotAnim*(b: var UiBuilder, x, y: float32): var UiBuilder {.discardable.} =
  ## Animated version of transformPivot (float overload).
  discard b.transformPivotAnim(vec2(x, y))
  b

proc width*(b: var UiBuilder, w: float32): var UiBuilder {.discardable.} =
  ## Set the width of the current node. Clamps to min/max size constraints.
  b.currentNode.size.x = w
  b.currentNode.flags.incl SizeXKnown
  b.clampNodeSize(b.currentNode)
  b

proc widthAnim*(b: var UiBuilder, w: float32): var UiBuilder {.discardable.} =
  ## Animated version of width. Smoothly transitions the node's width.
  let idx = b.stack[^1]
  b.currentNode.size.x = b.setAnimatedField(idx, UiNodeFieldSizeX, w)
  b.currentNode.flags.incl SizeXKnown
  b.clampNodeSize(b.currentNode)
  b

proc height*(b: var UiBuilder, h: float32): var UiBuilder {.discardable.} =
  ## Set the height of the current node. Clamps to min/max size constraints.
  b.currentNode.size.y = h
  b.currentNode.flags.incl SizeYKnown
  b.clampNodeSize(b.currentNode)
  b

proc heightAnim*(b: var UiBuilder, h: float32): var UiBuilder {.discardable.} =
  ## Animated version of height. Smoothly transitions the node's height.
  let idx = b.stack[^1]
  b.currentNode.size.y = b.setAnimatedField(idx, UiNodeFieldSizeY, h)
  b.currentNode.flags.incl SizeYKnown
  b.clampNodeSize(b.currentNode)
  b

proc size*(b: var UiBuilder, w, h: float32): var UiBuilder {.discardable.} =
  ## Set the size of the current node. Clamps to min/max size constraints.
  b.currentNode.size = vec2(w, h)
  b.currentNode.flags.incl SizeXKnown
  b.currentNode.flags.incl SizeYKnown
  b.clampNodeSize(b.currentNode)
  b

proc sizeAnim*(b: var UiBuilder, w, h: float32): var UiBuilder {.discardable.} =
  ## Animated version of size. Smoothly transitions the node's size.
  let idx = b.stack[^1]
  b.currentNode.size = b.setAnimatedField(idx, UiNodeFieldSizeX, vec2(w, h))
  b.currentNode.flags.incl SizeXKnown
  b.currentNode.flags.incl SizeYKnown
  b.clampNodeSize(b.currentNode)
  b

proc animateSize*(b: var UiBuilder, speed = DefaultAnimationSpeed): var UiBuilder {.discardable.} =
  ## Enable animation for the current node's size using its previously set value as the start.
  let previousX = previousAnimationFieldStartValue(b.previousFrame, UiAnimation(), b.currentNode.id, UiNodeFieldSizeX)
  let previousY = previousAnimationFieldStartValue(b.previousFrame, UiAnimation(), b.currentNode.id, UiNodeFieldSizeY)
  if previousX.hasValue and previousY.hasValue:
    let animIdx = b.resolveAnimationIndex(b.currentNode.id, true)
    let anim = b.animations[animIdx].addr
    let initializeX = findAnimationFieldIndex(anim[], UiNodeFieldSizeX) < 0 and previousX.hasValue
    let initializeY = findAnimationFieldIndex(anim[], UiNodeFieldSizeY) < 0 and previousY.hasValue
    discard anim[].applyAnimatedFieldTarget(b.currentNode[], UiNodeFieldSizeX, b.currentNode.size.x, speed, b.frameCtx.input.frameIndex, initializeX, previousX.value)
    discard anim[].applyAnimatedFieldTarget(b.currentNode[], UiNodeFieldSizeY, b.currentNode.size.y, speed, b.frameCtx.input.frameIndex, initializeY, previousY.value)
  b

proc animateWidth*(b: var UiBuilder, speed = DefaultAnimationSpeed): var UiBuilder {.discardable.} =
  ## Enable animation for the current node's width using its previously set value as the start.
  let previousX = previousAnimationFieldStartValue(b.previousFrame, UiAnimation(), b.currentNode.id, UiNodeFieldSizeX)
  if previousX.hasValue:
    let animIdx = b.resolveAnimationIndex(b.currentNode.id, true)
    let anim = b.animations[animIdx].addr
    let initializeX = findAnimationFieldIndex(anim[], UiNodeFieldSizeX) < 0 and previousX.hasValue
    discard anim[].applyAnimatedFieldTarget(b.currentNode[], UiNodeFieldSizeX, b.currentNode.size.x, speed, b.frameCtx.input.frameIndex, initializeX, previousX.value)
  b

proc animateHeight*(b: var UiBuilder, speed = DefaultAnimationSpeed): var UiBuilder {.discardable.} =
  ## Enable animation for the current node's height using its previously set value as the start.
  let previousY = previousAnimationFieldStartValue(b.previousFrame, UiAnimation(), b.currentNode.id, UiNodeFieldSizeY)
  if previousY.hasValue:
    let animIdx = b.resolveAnimationIndex(b.currentNode.id, true)
    let anim = b.animations[animIdx].addr
    let initializeY = findAnimationFieldIndex(anim[], UiNodeFieldSizeY) < 0 and previousY.hasValue
    discard anim[].applyAnimatedFieldTarget(b.currentNode[], UiNodeFieldSizeY, b.currentNode.size.y, speed, b.frameCtx.input.frameIndex, initializeY, previousY.value)
  b

proc size*(b: var UiBuilder, wh: Vec2): var UiBuilder {.discardable.} =
  ## Set the size of the current node (Vec2 overload).
  discard b.size(wh.x, wh.y)
  b

proc sizeAnim*(b: var UiBuilder, wh: Vec2): var UiBuilder {.discardable.} =
  ## Animated version of size (Vec2 overload).
  discard b.sizeAnim(wh.x, wh.y)
  b

proc padding*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set uniform padding on all sides. Triggers size-to-content and layout cursor update.
  let nodeStyle = b.ensureNodeStyle(b.currentNode).addr
  nodeStyle.paddingX = value
  nodeStyle.paddingY = value
  b.updateNodeFit(b.currentNode)
  b.frame.initCursorForLayout(b.currentNode)
  b

proc paddingX*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set horizontal padding. Triggers size-to-content and layout cursor update.
  let nodeStyle = b.ensureNodeStyle(b.currentNode).addr
  nodeStyle.paddingX = value
  b.updateNodeFit(b.currentNode)
  b.frame.initCursorForLayout(b.currentNode)
  b

proc paddingY*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set vertical padding. Triggers size-to-content and layout cursor update.
  let nodeStyle = b.ensureNodeStyle(b.currentNode).addr
  nodeStyle.paddingY = value
  b.updateNodeFit(b.currentNode)
  b.frame.initCursorForLayout(b.currentNode)
  b

proc paddingAnim*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Animated version of padding. Smoothly transitions the padding value.
  let idx = b.stack[^1]
  let nodeStyle = b.ensureNodeStyle(b.currentNode).addr
  nodeStyle.paddingX = b.setAnimatedField(idx, UiNodeFieldStylePaddingX, value)
  nodeStyle.paddingY = b.setAnimatedField(idx, UiNodeFieldStylePaddingY, value)
  b.updateNodeFit(b.currentNode)
  b.frame.initCursorForLayout(b.currentNode)
  b

proc gap*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Set the spacing between child nodes in a layout.
  b.ensureNodeGap(b.currentNode) = value
  b

proc gapAnim*(b: var UiBuilder, value: float32): var UiBuilder {.discardable.} =
  ## Animated version of gap. Smoothly transitions the gap value.
  let idx = b.stack[^1]
  b.ensureNodeGap(b.currentNode) = b.setAnimatedField(idx, UiNodeFieldGap, value)
  b

proc layout*(b: var UiBuilder, value: UiFlag): var UiBuilder {.discardable.} =
  ## Set the layout kind for the current node (LayoutVertical or LayoutHorizontal).
  b.currentNode.flags.setNodeLayoutKind(value)
  b.frame.initCursorForLayout(b.currentNode)
  b

proc customLayout*(b: var UiBuilder, layoutProc: UiCustomLayoutProc, userData: int = 0): var UiBuilder {.discardable.} =
  ## Assign a custom layout callback for the current node.
  let cl = b.ensureNodeCustomLayout(b.currentNode).addr
  cl.layoutProc = layoutProc
  cl.userData = userData
  b.currentNode.flags.incl PostProcessChildren
  b

proc deferBuild*(b: var UiBuilder, buildProc: UiDeferredBuildProc, userData: int = 0): var UiBuilder {.discardable.} =
  ## Schedule a build callback to run during flushDeferredNodes for the current node.
  if b.stack.len == 0:
    return b
  let idx = b.stack[^1]
  b.deferredNodes.add default(UiDeferredNode)
  b.deferredNodes[^1].nodeIdx = idx
  b.deferredNodes[^1].buildProc = buildProc
  b.deferredNodes[^1].userData = userData
  b.deferredNodes[^1].storageParentStack = b.storageParentStack
  b.deferredNodes[^1].focusScopeStack = b.focusScopeStack
  b

proc deferPostProcess*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Schedule postProcessChildren to run during flushDeferredNodes for the current node.
  b.deferBuild(deferredPostProcessBuildProc)

proc forwardLayout*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Set the current node's layout direction to forward (default).
  b.currentNode.flags.excl DirectionReverse
  b

proc reverseLayout*(b: var UiBuilder): var UiBuilder {.discardable.} =
  ## Set the current node's layout direction to reverse.
  b.currentNode.flags.setNodeDirectionKind(DirectionReverse)
  b.frame.initCursorForLayout(b.currentNode)
  b

proc layerIndex*(b: var UiBuilder, value: int32): var UiBuilder {.discardable.} =
  ## Set the render command layer index for the current node.
  b.currentNode.layerIndex = value
  b

proc measuredTextSize*(b: var UiBuilder, text: ptr UiNodeText, maxWidth: float32 = -1): Vec2 =
  ## Measure the pixel size of the text using the frame's measureText callback.
  if text.text.value.len == 0:
    return vec2(0.0'f32, 0.0'f32)
  let arrangement = b.getTextArrangement(text, maxWidth)
  return arrangement.size

proc cachedMeasuredTextSize*(b: var UiBuilder, node: ptr UiNode): Vec2 {.raises: [].} =
  ## Return the cached measured text size for a node, re-measuring only if the text is dirty.
  let textSlot = int(node.textIndex)
  if textSlot <= 0 or textSlot > b.frame.texts.len:
    return vec2(0)

  let nodeText = addr(b.frame.texts[textSlot - 1])

  if nodeText.text.value.len == 0:
    nodeText.measuredTextSizeCache = vec2(0.0'f32, 0.0'f32)
    nodeText.measuredTextDirty = false
    return nodeText.measuredTextSizeCache

  if WrapText in node.flags and b.currentParent != nil:
    if SizeXKnown notin node.flags or node.size.x <= 0:
      b.traceEvent(node.id, "skip measure parent size unknown")
      return vec2(0)

  if nodeText.measuredTextDirty:
    try:
      let nodeStyle = b.nodeStyle(node)
      let maxWidth =
        if WrapText in node.flags:
          max(0.0'f32, node.size.x - nodeStyle.paddingX * 2)
        else:
          -1.0'f32
      nodeText.measuredTextSizeCache = b.measuredTextSize(nodeText, maxWidth)
      b.traceEvent(node.id, "measure size")
      nodeText.measuredTextDirty = false
    except:
      nodeText.measuredTextDirty = false

  nodeText.measuredTextSizeCache

proc isHovered(b: UiBuilder, frame: ptr UiFrame, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx (in the given frame) is currently hovered by the mouse.
  let n = frame.nodes[idx].addr
  if n.id == b.previousOutput.hoveredId:
    return true
  if not includeChildren:
    return false
  for c in b.children(idx, frame):
    if b.isHovered(frame, c, includeChildren):
      return true
  return false

proc isClicked(b: UiBuilder, frame: ptr UiFrame, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx (in the given frame) was clicked this frame.
  let n = frame.nodes[idx].addr
  if n.id == b.previousOutput.clickedId:
    return true
  if not includeChildren:
    return false
  for c in b.children(idx, frame):
    if b.isClicked(frame, c, includeChildren):
      return true
  return false

proc isRightClicked(b: UiBuilder, frame: ptr UiFrame, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx (in the given frame) was right clicked this frame.
  let n = frame.nodes[idx].addr
  if n.id == b.previousOutput.rightClickedId:
    return true
  if not includeChildren:
    return false
  for c in b.children(idx, frame):
    if b.isRightClicked(frame, c, includeChildren):
      return true
  return false

proc isDragged(b: UiBuilder, frame: ptr UiFrame, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx (in the given frame) was dragged this frame.
  let n = frame.nodes[idx].addr
  if n.id == b.previousOutput.draggedId:
    return true
  if not includeChildren:
    return false
  for c in b.children(idx, frame):
    if b.isDragged(frame, c, includeChildren):
      return true
  return false

proc isHeld(b: UiBuilder, frame: ptr UiFrame, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx (in the given frame) was pressed this frame.
  let n = frame.nodes[idx].addr
  if n.id == b.previousOutput.heldId:
    return true
  if not includeChildren:
    return false
  for c in b.children(idx, frame):
    if b.isHeld(frame, c, includeChildren):
      return true
  return false

proc isPressed(b: UiBuilder, frame: ptr UiFrame, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx (in the given frame) was pressed this frame.
  let n = frame.nodes[idx].addr
  if n.id == b.previousOutput.pressedId:
    return true
  if not includeChildren:
    return false
  for c in b.children(idx, frame):
    if b.isPressed(frame, c, includeChildren):
      return true
  return false

proc wasHovered*(b: UiBuilder, nodeId: UiNodeId, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was hovered.
  if nodeId == b.previousOutput.hoveredId:
    return true
  let prevIndex = b.previousNodeIndex(nodeId, indexHint)
  if prevIndex >= 0:
    return b.isHovered(b.previousFrame.addr, prevIndex, includeChildren)
  return false

proc wasHovered*(b: UiBuilder, n: ptr UiNode, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was hovered.
  return b.wasHovered(n.id, includeChildren, indexHint)

proc wasHovered*(b: UiBuilder, includeChildren: bool = false): bool =
  ## Check if the current node was hovered.
  return b.wasHovered(b.currentNode, includeChildren, b.currentNodeIndex)

proc wasHovered*(b: UiBuilder, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx was hovered.
  return b.wasHovered(b.frame.nodes[idx].addr, includeChildren, idx)

proc wasHeld*(b: UiBuilder, nodeId: UiNodeId, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was pressed.
  if nodeId == b.previousOutput.heldId:
    return true
  let prevIndex = b.previousNodeIndex(nodeId, indexHint)
  if prevIndex >= 0:
    return b.isHeld(b.previousFrame.addr, prevIndex, includeChildren)
  return false

proc wasHeld*(b: UiBuilder, n: ptr UiNode, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was pressed.
  return b.wasHeld(n.id, includeChildren, indexHint)

proc wasHeld*(b: UiBuilder, includeChildren: bool = false): bool =
  ## Check if the current node was pressed.
  return b.wasHeld(b.currentNode, includeChildren, b.currentNodeIndex)

proc wasHeld*(b: UiBuilder, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx was pressed.
  return b.wasHeld(b.frame.nodes[idx].addr, includeChildren, idx)

proc wasPressed*(b: UiBuilder, nodeId: UiNodeId, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was pressed.
  if nodeId == b.previousOutput.pressedId:
    return true
  let prevIndex = b.previousNodeIndex(nodeId, indexHint)
  if prevIndex >= 0:
    return b.isPressed(b.previousFrame.addr, prevIndex, includeChildren)
  return false

proc wasPressed*(b: UiBuilder, n: ptr UiNode, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was pressed.
  return b.wasPressed(n.id, includeChildren, indexHint)

proc wasPressed*(b: UiBuilder, includeChildren: bool = false): bool =
  ## Check if the current node was pressed.
  return b.wasPressed(b.currentNode, includeChildren, b.currentNodeIndex)

proc wasPressed*(b: UiBuilder, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx was pressed.
  return b.wasPressed(b.frame.nodes[idx].addr, includeChildren, idx)

proc wasClicked*(b: UiBuilder, nodeId: UiNodeId, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was clicked.
  if nodeId == b.previousOutput.clickedId:
    return true
  let prevIndex = b.previousNodeIndex(nodeId, indexHint)
  if prevIndex >= 0:
    return b.isClicked(b.previousFrame.addr, prevIndex, includeChildren)
  return false

proc wasClicked*(b: UiBuilder, n: ptr UiNode, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was clicked.
  return b.wasClicked(n.id, includeChildren, indexHint)

proc wasClicked*(b: UiBuilder, includeChildren: bool = false): bool =
  ## Check if the current node was clicked.
  return b.wasClicked(b.currentNode, includeChildren, b.currentNodeIndex)

proc wasClicked*(b: UiBuilder, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx was clicked.
  return b.wasClicked(b.frame.nodes[idx].addr, includeChildren, idx)

proc wasDragged*(b: UiBuilder, nodeId: UiNodeId, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was dragged (held and moved).
  if nodeId == b.previousOutput.draggedId:
    return true
  let prevIndex = b.previousNodeIndex(nodeId, indexHint)
  if prevIndex >= 0:
    return b.isDragged(b.previousFrame.addr, prevIndex, includeChildren)
  return false

proc wasDragged*(b: UiBuilder, n: ptr UiNode, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was dragged.
  return b.wasDragged(n.id, includeChildren, indexHint)

proc wasDragged*(b: UiBuilder, includeChildren: bool = false): bool =
  ## Check if the current node was dragged.
  return b.wasDragged(b.currentNode, includeChildren, b.currentNodeIndex)

proc wasDragged*(b: UiBuilder, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx was dragged.
  return b.wasDragged(b.frame.nodes[idx].addr, includeChildren, idx)

proc wasRightClicked*(b: UiBuilder, nodeId: UiNodeId, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was right clicked.
  if nodeId == b.previousOutput.rightClickedId:
    return true
  let prevIndex = b.previousNodeIndex(nodeId, indexHint)
  if prevIndex >= 0:
    return b.isRightClicked(b.previousFrame.addr, prevIndex, includeChildren)
  return false

proc wasRightClicked*(b: UiBuilder, n: ptr UiNode, includeChildren: bool = false, indexHint: int = -1): bool =
  ## Check if the given node was right clicked.
  return b.wasRightClicked(n.id, includeChildren, indexHint)

proc wasRightClicked*(b: UiBuilder, includeChildren: bool = false): bool =
  ## Check if the current node was right clicked.
  return b.wasRightClicked(b.currentNode, includeChildren, b.currentNodeIndex)

proc wasRightClicked*(b: UiBuilder, idx: int, includeChildren: bool = false): bool =
  ## Check if the node at idx was right-clicked.
  return b.wasRightClicked(b.frame.nodes[idx].addr, includeChildren, idx)

proc beginDrag*(b: var UiBuilder): tuple[dragging: bool, began: bool] =
  ## Begin dragging for the current node if no drag is active.
  ## Returns (dragging, began) where `dragging` is true when the current node
  ## is the dragged node, and `began` is true only on the frame dragging started.
  if b.stack.len == 0:
    return (false, false)
  if b.dragData.nodeId != noneNodeId():
    let isDragging = b.dragData.nodeId == b.currentNode.id
    return (isDragging, false)
  # No drag active — start drag for current node if it is interacted and left button is down.
  # Require hover/held/pressed/dragged to avoid auto-starting drag without user interaction.
  let interacted = b.wasDragged()
  if interacted and MouseLeft in b.frameCtx.input.mouseDown:
    b.dragData = DragData(nodeId: b.currentNode.id)
    return (true, true)
  return (false, false)

proc setDragData*(b: var UiBuilder, userData: UiDragUserData) =
  ## Set the application-defined data for the current drag.
  if b.dragData.nodeId != noneNodeId():
    b.dragData.userData = userData

proc setDragUiCallback*(b: var UiBuilder, cb: UiDragUiCallback) =
  ## Set the callback that builds tooltip contents for the current drag.
  if b.dragData.nodeId != noneNodeId():
    b.dragData.uiCallback = cb

proc beginDrop*(b: var UiBuilder, includeChildren = true): bool =
  ## Returns true when the mouse is hovered over the current node while drag data exists.
  if b.dragData.nodeId == noneNodeId():
    return false
  return b.wasHovered(includeChildren)

proc endDrop*(b: var UiBuilder, canDrop: bool): bool =
  ## Store target acceptance even while dragging, and report a successful release.
  b.dragData.canDrop = canDrop
  return canDrop and MouseLeft in b.frameCtx.input.mouseReleased

proc buildDragUi(b: var UiBuilder) =
  if b.dragData.nodeId == noneNodeId():
    return

  let overlayIdx = b.currentNodeIndex(b.overlays)
  let attached = b.beginAttach(overlayIdx)
  try:
    discard b.beginNodeId("drag-tooltip")
    if b.dragData.uiCallback != nil:
      b.dragData.uiCallback(b, b.dragData.userData, b.dragData.canDrop)
    let input = b.frameCtx.input
    discard b.offsets(input.mouse.x, input.mouse.y, 0, 0).pivot(0, 1).finishAnchors().noHover()
    discard b.endNode()
  finally:
    if attached:
      b.endAttach()

template node*(b: var UiBuilder, body: untyped): untyped =
  ## Create an anonymous child node, execute body in its context, then close it.
  block:
    prof("node")
    discard b.beginNode()
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

proc beginAttach*(b: var UiBuilder, parentIdx: int): bool =
  ## Pushes the existing node at parentIdx as the current node. Use `endAttach` to pop it and restore the previous current node.
  if parentIdx >= 0 and parentIdx < b.frame.nodes.len:
    b.stack.add parentIdx
    b.nodeIdStack.add b.frame.nodes[parentIdx].id
    b.currentNode = b.frame.nodes[parentIdx].addr
    if b.currentNode.parent >= 0:
      b.currentParent = b.frame.nodes[b.currentNode.parent].addr
    else:
      b.currentParent = nil
    return true
  return false

proc endAttach*(b: var UiBuilder) =
  ## Restores the previous current node.
  discard b.stack.pop()
  discard b.nodeIdStack.pop()
  if b.stack.len > 0:
    b.currentNode = b.frame.nodes[b.stack[^1]].addr
  else:
    b.currentNode = sentinelNode.addr
  if b.currentNode.parent >= 0:
    b.currentParent = b.frame.nodes[b.currentNode.parent].addr
  else:
    b.currentParent = nil

template withParent*(b: var UiBuilder, parentIdx: int, body: untyped): untyped =
  ## Execute body with parentIdx as the current parent. Restores the previous parent afterwards.
  block:
    let attached = b.beginAttach(parentIdx)
    try:
      body
    finally:
      if attached:
        b.endAttach()

template withParent*(b: var UiBuilder, parentId: UiNodeId, body: untyped): untyped =
  ## Execute body with the node identified by parentId as the current parent.
  let parentIdx = b.currentNodeIndex(parentId)
  b.withParent(parentIdx):
    body

template withLast*(b: var UiBuilder, body: untyped): untyped =
  ## Execute body with the node last ended node as the current parent.
  b.withParent(b.lastNodeIndex):
    body

proc renderUnder*(b: var UiBuilder, parentIdx: int) =
  ## Cause the current node to render under the node at parentIdx.
  ## The node is added to the parent's render child chain (renderChildLast/renderSibling linked list).
  if parentIdx < 0 or parentIdx >= b.frame.nodes.len:
    return
  if b.stack.len <= 0:
    return
  let currentIdx = b.stack[^1]
  if currentIdx < 0 or currentIdx >= b.frame.nodes.len:
    return
  var currentNode = b.frame.nodes[currentIdx].addr
  currentNode.renderParent = parentIdx.int32
  var parentNode = b.frame.nodes[parentIdx].addr
  if parentNode.renderChildLast >= 0:
    currentNode.renderSibling = b.frame.nodes[parentNode.renderChildLast].renderSibling
    b.frame.nodes[parentNode.renderChildLast].renderSibling = currentIdx.int32
  else:
    currentNode.renderSibling = currentIdx.int32
  parentNode.renderChildLast = currentIdx.int32

template nodeWithId*(b: var UiBuilder, id: UiNodeId, body: untyped): untyped =
  ## Create a child node with a deterministic ID derived from the string key.
  block:
    prof("node")
    discard b.beginNodeWithId(id)
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

template node*(b: var UiBuilder, key: string, body: untyped): untyped =
  ## Create a child node with a deterministic ID derived from the string key.
  block:
    prof("node")
    discard b.beginNodeId(key)
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

template node*(b: var UiBuilder, key: uint64, body: untyped): untyped =
  ## Create a child node with a deterministic ID derived from the uint64 key.
  block:
    prof("node")
    discard b.beginNodeId(key)
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

template layoutVertical*(b: var UiBuilder, body: untyped): untyped =
  ## Create an anonymous vertical layout node.
  block:
    prof("layoutVertical")
    discard b.beginNode().layout(LayoutVertical)
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

template layoutHorizontal*(b: var UiBuilder, body: untyped): untyped =
  ## Create an anonymous horizontal layout node.
  block:
    prof("layoutHorizontal")
    discard b.beginNode().layout(LayoutHorizontal)
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

template layoutVerticalReverse*(b: var UiBuilder, body: untyped): untyped =
  ## Create an anonymous vertical reverse layout node.
  block:
    prof("layoutVerticalReverse")
    discard b.beginNode().layout(LayoutVertical).reverseLayout()
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

template layoutHorizontalReverse*(b: var UiBuilder, body: untyped): untyped =
  ## Create an anonymous horizontal reverse layout node.
  block:
    prof("layoutHorizontalReverse")
    discard b.beginNode().layout(LayoutHorizontal).reverseLayout()
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

template layoutVertical*(b: var UiBuilder, key: string, body: untyped): untyped =
  ## Create a vertical layout node with a deterministic ID from the string key.
  block:
    prof("layoutVertical")
    discard b.beginNodeId(key).layout(LayoutVertical)
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

template layoutHorizontal*(b: var UiBuilder, key: string, body: untyped): untyped =
  ## Create a horizontal layout node with a deterministic ID from the string key.
  block:
    prof("layoutHorizontal")
    discard b.beginNodeId(key).layout(LayoutHorizontal)
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

template layoutVerticalReverse*(b: var UiBuilder, key: string, body: untyped): untyped =
  ## Create a vertical reverse layout node with a deterministic ID from the string key.
  block:
    prof("layoutVerticalReverse")
    discard b.beginNodeId(key).layout(LayoutVertical).reverseLayout()
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()

template layoutHorizontalReverse*(b: var UiBuilder, key: string, body: untyped): untyped =
  ## Create a horizontal reverse layout node with a deterministic ID from the string key.
  block:
    prof("layoutHorizontalReverse")
    discard b.beginNodeId(key).layout(LayoutHorizontal).reverseLayout()
    when not defined(nimony) and defined(nuiDebug):
      let info = instantiationInfo(-1, fullPaths = true)
      b.currentNode.debugSourceFile = info.filename
      b.currentNode.debugSourceLine = info.line.int32
      b.currentNode.debugSourceColumn = info.column.int32
    body
    discard b.endNode()
