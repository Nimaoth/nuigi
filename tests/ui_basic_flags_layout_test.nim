import std/[os, math]
when defined(nimony):
  import std/dirs
import nuigi, nuigi/widgets, nuigi/layout/[flex, grid], nuigi/core/[vecmath, arena, array_view]
import nuigi/widgets/[tree_table, file_system_cursor]
import nuigi/widgets/plot
import nuigi/widgets/collapsing_header
import nuigi/demo/demo_window
import nuigi/styling/theme
when defined(nuigiProfiler):
  import nuigi/debug/[profiler, profiler_ui]

include nuigi/util/compat2

{.passL: "-Lbuild".}

when defined(nimony):
  import std/assertions

proc approxEq(a, b: float32, eps = 0.001'f32): bool =
  abs(a - b) <= eps

proc require(cond: bool, msg: string) =
  when defined(nimony):
    assert cond, msg
  else:
    doAssert(cond, msg)

proc createTestDir(directory: string) =
  when defined(nimony):
    onRaiseQuit(createDir(path(directory)))
  else:
    createDir(directory)

proc removeTestDir(directory: string) =
  when defined(nimony):
    try:
      for kind, entryPath in walkDir(path(directory)):
        if kind == pcDir or kind == pcLinkToDir:
          removeTestDir($entryPath)
        else:
          removeFile(entryPath)
      removeDir(path(directory))
    except:
      quit "FAILURE: removeTestDir(" & directory & ")"
  else:
    removeDir(directory)

proc fixedMeasureText(text: openArray[char], fontId: int16, fontSize: float32, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.gcsafe, raises: [].} =
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

proc fixedTerminalMeasureText(text: openArray[char], fontId: int16, fontSize: float32, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.gcsafe, raises: [].} =
  let _ = fontId
  let naturalWidth = text.len.float32
  let lineCount =
    if maxWidth > 0.0'f32 and naturalWidth > maxWidth:
      int((naturalWidth + maxWidth - 1.0'f32) / maxWidth)
    else:
      1
  result = UiTextArrangement()
  result.fontSize = fontSize
  result.size = vec2(if maxWidth >= 0.0'f32: min(naturalWidth, maxWidth) else: naturalWidth, lineCount.float32)

proc newTestBuilder(viewW = 200.0'f32, viewH = 120.0'f32): UiBuilder =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(viewW, viewH)
  b

type CacheTestState = object
  created, freed: int
  width, height: int

proc createTestCache(context: pointer, width, height: int): UiImageId {.nimcall, gcsafe, raises: [].} =
  let state = cast[ptr CacheTestState](context)
  inc state.created
  state.width = width
  state.height = height
  UiImageId(100 + state.created)

proc freeTestCache(context: pointer, image: UiImageId) {.nimcall, gcsafe, raises: [].} =
  inc cast[ptr CacheTestState](context).freed

block widgetCaching:
  for mesh in [false, true]:
    var state = CacheTestState()
    var b = newBuilder(fixedMeasureText)
    b.createCacheTextureFn = createTestCache
    b.freeCacheTextureFn = freeTestCache
    b.cacheTextureUserData = state.addr
    var widgetId = noneNodeId()
    var childId = noneNodeId()
    for frame in 0 ..< 6:
      discard b.beginUiFrame(200, 120)
      b.node:
        discard b.size(if frame == 4: 60.0'f32 else: 50.0'f32, 40).position(float32(frame), 0)
        widgetId = b.currentNode.id
        let hit = b.reuseCachedNode(dirty = frame == 3)
        require(hit == (frame == 1 or frame == 2),
          "cache should hit until dirty or resized")
        if not hit:
          b.node:
            discard b.size(20, 20).backgroundColor(rgba(1.0, 0.0, 0.0, 0.5))
            discard b.text("cached")
            discard b.focusable()
            childId = b.currentNode.id
            var vertices = b.frame.arena[].allocArray(3, UiVertex)
            vertices[0] = UiVertex(pos: vec2(2, 3))
            vertices[1] = UiVertex(pos: vec2(4, 5))
            vertices[2] = UiVertex(pos: vec2(6, 7))
            var commands = b.frame.arena[].allocArray(1, UiRenderCommand)
            commands[0] = UiRenderCommand(kind: CmdRawVertices,
              vertexData: vertices.data, vertexCount: 3)
            discard b.customRenderCommands(commands)
        else:
          require(CopiedFromPreviousFrame in b.currentNode.flags,
            "cache hit should mark copied root")
          let child = b.currentNodeIndex(childId)
          require(child >= 0 and b.frame.nodes[child].parent == b.currentNodeIndex(widgetId),
            "cache hit should preserve child IDs and remap links")
          var commands = b.frame.customCommands[int(b.frame.nodes[child].commandsIndex) - 1]
          require(commands[0].vertexData[2].pos == vec2(6, 7),
            "copied arena vertices should survive repeated frame swaps")
      b.endUiFrame(buildMeshRenderCommands = mesh)
      require(b.frame.focusItems.len == 1, "cached subtree should preserve focus declarations")
      var targetCount = 0
      var cachedDraws = 0
      var widgetCommandCount = 0
      for command in b.frameOutput.commands:
        if command.kind == CmdRenderTarget: inc targetCount
        if command.premultipliedAlpha: inc cachedDraws
        if command.nodeIndex == b.currentNodeIndex(widgetId):
          inc widgetCommandCount
      require(targetCount == (if frame == 1 or frame == 2: 0 else: 2),
        "miss should render into texture; hit should not regenerate subtree commands")
      require(cachedDraws == 1, "subtree should be composed with exactly one cached draw")
      if frame == 1 or frame == 2:
        require(widgetCommandCount == 1,
          "an untransformed cached root should emit exactly one command")
    require(state.created == 3 and state.freed == 2,
      "dirty should reuse allocation; resizing should free and recreate textures")
    discard b.beginUiFrame(200, 120)
    b.endUiFrame()
    require(state.freed == state.created, "absent widgets should release cache textures")
    b.clearWidgetCaches()
    require(state.freed == state.created, "cache teardown should be idempotent")

block widgetCachingDisabled:
  var b = newTestBuilder()
  b.node:
    require(not b.reuseCachedNode(), "nil texture callbacks should disable caching")
  var state = CacheTestState()
  b.createCacheTextureFn = createTestCache
  b.cacheTextureUserData = state.addr
  b.node:
    require(not b.reuseCachedNode(), "both texture callbacks are required")
  b.endUiFrame()
  require(state.created == 0, "disabled caching should allocate no textures")

block widgetCachingToggle:
  for mesh in [false, true]:
    var state = CacheTestState()
    var b = newBuilder(fixedMeasureText)
    require(b.cachingEnabled, "subtree caching should default to enabled")
    b.createCacheTextureFn = createTestCache
    b.freeCacheTextureFn = freeTestCache
    b.cacheTextureUserData = state.addr
    var builds = 0
    for frame in 0 ..< 7:
      b.cachingEnabled = frame != 2 and frame != 3
      discard b.beginUiFrame(200, 120)
      b.node:
        discard b.size(50, 40)
        let hit = b.reuseCachedNode()
        require(hit == (frame == 1 or frame == 5 or frame == 6),
          "disabled caching must rebuild, and re-enabling must start with a miss")
        if not hit:
          inc builds
          b.node:
            discard b.size(20, 20).text("cached")
      # Settings may toggle caching after earlier widgets have already reused it.
      if frame == 6: b.cachingEnabled = false
      b.endUiFrame(buildMeshRenderCommands = mesh)
      var targets = 0
      var cachedDraws = 0
      for command in b.frameOutput.commands:
        if command.kind == CmdRenderTarget: inc targets
        if command.premultipliedAlpha: inc cachedDraws
      if not b.cachingEnabled:
        require(targets == 0 and cachedDraws == 0,
          "disabled frames must use ordinary render commands even after a cache hit")
        require(state.freed == state.created, "disabled rendering must release cache textures")
        require(UseCachedTexture notin b.frame.nodes[1].flags,
          "disabled rendering must clear cached texture flags")
      else:
        require(cachedDraws == 1, "enabled frames should draw the cached image")
        require(targets == (if frame == 0 or frame == 4: 2 else: 0),
          "only enabled misses should capture a texture")
    require(builds == 4, "disabled frames should build widget children normally")
    require(state.created == 2 and state.freed == 2,
      "re-enabling must allocate a fresh cache and disabling must free it")

block widgetCachingNested:
  var state = CacheTestState()
  var b = newBuilder(fixedMeasureText)
  b.createCacheTextureFn = createTestCache
  b.freeCacheTextureFn = freeTestCache
  b.cacheTextureUserData = state.addr
  for frame in 0 ..< 3:
    discard b.beginUiFrame(if frame == 2: 250.0'f32 else: 200.0'f32, 120)
    b.node:
      discard b.fit()
      let hit = b.reuseCachedNode()
      require(hit == (frame == 1), "viewport changes should invalidate a cached subtree")
      if not hit:
        b.node:
          discard b.size(30.25'f32, 20.5'f32)
          if not b.reuseCachedNode():
            b.node:
              discard b.size(15, 10).backgroundColor(rgba(1, 0, 0, 1))
    b.endUiFrame()
    var targetCount = 0
    for command in b.frameOutput.commands:
      if command.kind == CmdRenderTarget: inc targetCount
    require(targetCount == (if frame == 1: 0 else: 4),
      "nested hits must not render either subtree into a texture again")
    require(approxEq(b.frame.nodes[1].size.x, 30.25'f32),
      "fit sizing must survive cached subtree copying")
    require(state.width == 31 and state.height == 21,
      "texture allocation should round fractional bounds upwards")
  b.createCacheTextureFn = nil
  b.freeCacheTextureFn = nil
  discard b.beginUiFrame(200, 120)
  b.endUiFrame()
  require(state.freed == state.created,
    "disabling callbacks should release textures through their original owner")

proc buildExternalCachePopup(b: var UiBuilder, nodeIdx, userData: int)
    {.nimcall, gcsafe, raises: [].} =
  b.withParent(userData):
    b.node("cache-popup"):
      discard b.size(80, 30).position(120, 20).text("popup")

block widgetCachingExternalParent:
  for mesh in [false, true]:
    for deferred in [false, true]:
      var state = CacheTestState()
      var b = newBuilder(fixedMeasureText)
      b.createCacheTextureFn = createTestCache
      b.freeCacheTextureFn = freeTestCache
      b.cacheTextureUserData = state.addr
      var popupId = noneNodeId()
      for frame in 0 ..< 9:
        let popupOpen = frame >= 2 and frame <= 6
        let mouse = if popupOpen: vec2(125 + frame.float32, 25) else: vec2(220, 140)
        discard b.beginUiFrame(240, 160, UiInputSnapshot(mouse: mouse, mouseDelta: vec2(1, 0)))
        var externalParent = -1
        b.node("cache-overlay-root"):
          externalParent = b.currentNodeIndex
          discard b.size(240, 160)
        b.node("cache-editor"):
          discard b.size(100, 100)
          let outerHit = b.reuseCachedNode(dirty = frame == 2)
          require(outerHit == (frame == 1 or frame == 8),
            "external popup builds must invalidate every cached ancestor until closed")
          if not outerHit:
            b.node("cache-editor-body"):
              discard b.size(100, 100)
              let innerHit = b.reuseCachedNode(dirty = frame == 2)
              require(not innerHit, "inner cached roots must also rebuild external popups")
              if not innerHit:
                b.node:
                  discard b.size(20, 20).text("editor")
                  if popupOpen:
                    if deferred:
                      discard b.deferBuild(buildExternalCachePopup, externalParent)
                    else:
                      b.buildExternalCachePopup(b.currentNodeIndex, externalParent)
        b.endUiFrame(buildMeshRenderCommands = mesh)
        var popupIndex = -1
        for i in 0 ..< b.frame.nodes.len:
          if b.nodeText(i).text == "popup".uiString: popupIndex = i
        require((popupIndex >= 0) == popupOpen,
          "the popup must appear on every open frame, including repeated mouse movement")
        if popupOpen:
          popupId = b.frame.nodes[popupIndex].id
          if frame > 2:
            require(b.previousOutput.hoveredId == popupId,
              "external popup must stay available to hover hit testing")
          require(state.freed == state.created,
            "external builds must release originating cache textures")
      b.clearWidgetCaches()

block widgetCachingInternalParent:
  var state = CacheTestState()
  var b = newBuilder(fixedMeasureText)
  b.createCacheTextureFn = createTestCache
  b.freeCacheTextureFn = freeTestCache
  b.cacheTextureUserData = state.addr
  for frame in 0 ..< 2:
    discard b.beginUiFrame(200, 120)
    b.node:
      discard b.size(100, 100)
      let hit = b.reuseCachedNode()
      require(hit == (frame == 1), "attaching within a cache must not disable reuse")
      if not hit:
        var childIndex = -1
        b.node:
          childIndex = b.currentNodeIndex
          discard b.size(80, 80)
        b.withParent(childIndex):
          b.node:
            discard b.size(20, 20).text("internal")
    b.endUiFrame()
  require(state.created == 1, "internal attaches should retain the existing texture")
  b.clearWidgetCaches()

proc shiftChevronParent(b: var UiBuilder, nodeIdx, userData: int)
    {.nimcall, gcsafe, raises: [].} =
  b.frame.nodes[userData].pos.y += 11.0'f32

block collapsingHeaderCachedCoordinates:
  for mesh in [false, true]:
    var state = CacheTestState()
    var b = newBuilder(fixedMeasureText)
    b.createCacheTextureFn = createTestCache
    b.freeCacheTextureFn = freeTestCache
    b.cacheTextureUserData = state.addr
    var expanded = false
    for frame in 0 ..< 12:
      b.cachingEnabled = frame mod 2 == 0
      discard b.beginUiFrame(400, 300)
      var rootIndex = -1
      b.node:
        rootIndex = b.currentNodeIndex
        discard b.size(180, 160).position(40, 30 + frame.float32)
        require(not b.reuseCachedNode(dirty = true), "dirty chevron frame must rebuild")
        b.collapsingHeader("Changes", expanded):
          b.node:
            discard b.size(100, 30)
        b.node:
          discard b.size(0, 0).deferBuild(shiftChevronParent, rootIndex)
      b.endUiFrame(buildMeshRenderCommands = mesh)
      var iconIndex = -1
      for i in 0 ..< b.frame.nodes.len:
        if b.nodeCustomCommands(i)[].len == 1 and
            b.nodeCustomCommands(i)[][0].vertexCoordinatesLocal:
          iconIndex = i
      require(iconIndex >= 0, "collapsing header must build its chevron")
      var custom = b.nodeCustomCommands(iconIndex)[]
      require(custom.len == 1 and custom[0].vertexCoordinatesLocal,
        "chevron geometry must stay node-local until rendering")
      let origin = b.absoluteNodePos(iconIndex) +
        vec2(b.nodeStyle(iconIndex)[].paddingX, b.nodeStyle(iconIndex)[].paddingY)
      var captureOffset = vec2(0.0'f32)
      var rendered = 0
      for command in b.frameOutput.commands:
        if command.kind == CmdRenderTarget:
          captureOffset = if command.imageId.uint64 == 0: vec2(0.0'f32)
            else: b.absoluteNodePos(command.nodeIndex.int)
        elif command.kind == CmdRawVertices and command.nodeIndex == iconIndex.int32:
          inc rendered
          require(not command.vertexCoordinatesLocal, "renderers must receive resolved vertices")
          require(command.vertexCount == custom[0].vertexCount,
            "rendering must preserve chevron geometry")
          for i in 0 ..< command.vertexCount.int:
            let expected = custom[0].vertexData[i].pos + origin - captureOffset
            require(approxEq(command.vertexData[i].pos.x, expected.x) and
              approxEq(command.vertexData[i].pos.y, expected.y),
              "icon position must follow final layout in ordinary and cache-capture frames")
      require(rendered == 1, "each frame must emit exactly one correctly positioned chevron")
    require(state.created > 0, "chevron regression must exercise real cache captures")
    b.clearWidgetCaches()

block customLocalMeshTransforms:
  for local in [false, true]:
    var b = newBuilder(fixedMeasureText)
    discard b.beginUiFrame(300, 200)
    var index = -1
    b.node:
      index = b.currentNodeIndex
      discard b.size(40, 40).position(30, 20).padding(2)
        .transformPivot(0, 0).transformScale(2)
      var vertices = b.frame.arena[].allocArray(3, UiVertex)
      for i in 0 ..< vertices.len:
        vertices[i] = UiVertex(pos: vec2(1 + i.float32, 3))
      var commands = b.frame.arena[].allocArray(1, UiRenderCommand)
      commands[0] = UiRenderCommand(kind: CmdRawVertices, vertexData: vertices.data,
        vertexCount: 3, vertexCoordinatesLocal: local)
      discard b.customRenderCommands(commands)
    b.endUiFrame(buildMeshRenderCommands = true)
    var found = false
    for command in b.frameOutput.commands:
      if command.kind == CmdRawVertices and command.nodeIndex == index.int32:
        found = true
        let expected = if local: vec2(36, 30) else: vec2(1, 3)
        require(approxEq(command.vertexData[0].pos.x, expected.x) and
          approxEq(command.vertexData[0].pos.y, expected.y),
          "local raw meshes must follow node transforms without changing legacy absolute meshes")
        require(b.nodeCustomCommands(index)[][0].vertexData[0].pos == vec2(1, 3),
          "rendering must not mutate stored custom vertices")
    require(found, "custom raw mesh must be emitted")

block widgetCachingNonRenderingFrame:
  var state = CacheTestState()
  var b = newBuilder(fixedMeasureText)
  b.createCacheTextureFn = createTestCache
  b.freeCacheTextureFn = freeTestCache
  b.cacheTextureUserData = state.addr
  for frame in 0 ..< 3:
    discard b.beginUiFrame(200, 120)
    b.node:
      discard b.size(50, 40)
      let hit = b.reuseCachedNode(dirty = frame == 1)
      require(not hit, "a non-rendered dirty frame must not leave a valid texture")
      if not hit:
        b.node:
          discard b.size(20, 20).backgroundColor(rgba(1, 0, 0, 1))
    b.endUiFrame(buildRenderCommands = frame != 1)
  b.clearWidgetCaches()

block widgetCachingUnsupported:
  var state = CacheTestState()
  var b = newBuilder(fixedMeasureText)
  b.createCacheTextureFn = createTestCache
  b.freeCacheTextureFn = freeTestCache
  b.cacheTextureUserData = state.addr
  for frame in 0 ..< 2:
    discard b.beginUiFrame(200, 120)
    b.node:
      discard b.size(50, 40)
      require(not b.reuseCachedNode(), "cross-layer subtrees must not be cached")
      b.node:
        discard b.size(20, 20).backgroundColor(rgba(1, 0, 0, 1))
        b.currentNode.layerIndex = 1
    b.endUiFrame()
  require(state.created == 0, "unsupported render trees should allocate no textures")

when not defined(nuiNoSemantics):
  block widgetCachingDemoControls:
    var state = CacheTestState()
    var b = newBuilder(fixedMeasureText)
    b.createCacheTextureFn = createTestCache
    b.freeCacheTextureFn = freeTestCache
    b.cacheTextureUserData = state.addr
    template drawCacheDemo() =
      discard b.beginUiFrame(1200, 900)
      b.buildCacheExamples()
      b.endUiFrame()
    template activateCacheControl(label: string, requestedAction: UiSemanticAction = SemanticActivate) =
      var target = noneNodeId()
      for i in 0 ..< b.frame.nodes.len:
        let node = b.frame.nodes[i]
        if node.textIndex > 0 and b.frame.texts[int(node.textIndex) - 1].text.value == label:
          target = node.id
          if node.parent >= 0:
            let parentSemantics = b.nodeSemantics(int(node.parent))
            if parentSemantics != nil and parentSemantics.role == SemanticCheckBox:
              target = b.frame.nodes[node.parent].id
          break
      require(target != noneNodeId(), "cache demo control should exist: " & label)
      b.enqueueSemanticRequest(UiSemanticRequest(target: target, action: requestedAction))
      drawCacheDemo()
    template demoRoot(): untyped =
      block:
        var root = -1
        for i in 0 ..< b.frame.nodes.len:
          if CacheSubtree in b.frame.nodes[i].flags:
            root = i
            break
        require(root >= 0, "cache demo root should exist")
        root
    template expectDemoHit(expected: bool) =
      require((CopiedFromPreviousFrame in b.frame.nodes[demoRoot()].flags) == expected,
        "cache demo should have the expected hit/rebuild state")

    drawCacheDemo()
    expectDemoHit(false)
    drawCacheDemo()
    expectDemoHit(true)
    activateCacheControl("Change data only")
    expectDemoHit(true)
    activateCacheControl("Mark widget dirty")
    expectDemoHit(false)
    drawCacheDemo()
    expectDemoHit(true)
    activateCacheControl("Move (no dirty)")
    expectDemoHit(true)
    activateCacheControl("Rotate (no dirty)")
    expectDemoHit(true)
    let oldSize = b.frame.nodes[demoRoot()].size
    activateCacheControl("Resize width")
    expectDemoHit(false)
    require(b.frame.nodes[demoRoot()].size.x > oldSize.x, "width control should resize the widget")
    drawCacheDemo()
    activateCacheControl("Resize height")
    expectDemoHit(false)
    require(b.frame.nodes[demoRoot()].size.y > oldSize.y, "height control should resize the widget")
    drawCacheDemo()
    activateCacheControl("Fractional size")
    expectDemoHit(false)
    activateCacheControl("Mark nested dirty")
    expectDemoHit(false)
    activateCacheControl("Overflow child")
    expectDemoHit(false)
    drawCacheDemo()
    expectDemoHit(true)
    activateCacheControl("Clip stage")
    expectDemoHit(true)
    activateCacheControl("Nested cache")
    expectDemoHit(false)
    drawCacheDemo()
    expectDemoHit(true)
    activateCacheControl("Nested cache")
    activateCacheControl("Animate child (cache fallback)")
    require(UseCachedTexture notin b.frame.nodes[demoRoot()].flags,
      "animated demo subtree should use ordinary rendering")
    drawCacheDemo()
    expectDemoHit(false)
    activateCacheControl("Animate child (cache fallback)")
    for frame in 0 ..< 4:
      drawCacheDemo()
    expectDemoHit(true)
    activateCacheControl("Zero size")
    require(UseCachedTexture notin b.frame.nodes[demoRoot()].flags and
      b.frame.nodes[demoRoot()].size == vec2(0),
      "zero-size control should disable texture rendering")
    activateCacheControl("Zero size")
    activateCacheControl("Hide widget")
    require(state.created == state.freed, "hiding the demo widget should free both caches")
    activateCacheControl("Hide widget")
    expectDemoHit(false)
    b.clearWidgetCaches()

block virtualTreeOwnership:
  var source = newTestBuilder()
  let nodeIndex = source.nodes.len
  source.node:
    discard source.size(20.0'f32, 20.0'f32)
  var tree = extractVirtualTree(source.frame, nodeIndex)
  tree.animations.add UiFieldAnimation(
    currentValue: 0, targetValue: 10, speed: 30, fieldOffset: UiNodeFieldPosX)
  let nodesAddress = tree.nodes[0].addr
  var b = newTestBuilder()
  b.virtualNodes.add UiVirtualTree()
  b.virtualNodes.add move(tree)
  b.insertVirtualTrees()
  require(b.virtualNodes.len == 2 and b.virtualNodes[0].nodes.len == 0,
    "inserting virtual trees should preserve empty entries")
  require(b.virtualNodes[1].nodes[0].addr == nodesAddress,
    "inserting virtual trees should retain node storage without copying")
  require(approxEq(b.virtualNodes[1].animations[0].currentValue, 5) and
    approxEq(b.virtualNodes[1].nodes[0].pos.x, 5),
    "virtual tree animation progress should survive ownership transfer")
  b.insertVirtualTrees()
  require(approxEq(b.virtualNodes[1].animations[0].currentValue, 7.5),
    "virtual tree animation should continue from its retained state")
  b.frameCtx.animationTick = 1
  b.insertVirtualTrees()
  require(b.virtualNodes.len == 1,
    "finished virtual trees should retire after ownership is restored")
  require(approxEq(b.frame.nodes[^1].pos.x, 10),
    "retiring virtual trees should leave the completed frame node")

block nullableDefaults:
  let drag = DragData()
  require(drag.userData == nil and drag.uiCallback == nil,
    "default drag payload and callback should be nil")
  require(UiDeferredNode().buildProc == nil and UiNodeCustomLayout().layoutProc == nil,
    "default deferred and custom layout callbacks should be nil")
  require(UiRenderCommand().vertexData == nil and PlotSeries().fn == nil,
    "default render data and plot callback should be nil")
  let empty = ArrayView[int]()
  require(empty.first() == nil and empty.last() == nil,
    "empty array views should return nil pointers")
  var payload: UiDragUserData = UiDragUserData()
  require(payload != nil, "constructed drag payload should not be nil")
  payload = nil
  require(payload == nil, "ordinary ref types should accept nil")
  let builder = newBuilder(fixedMeasureText)
  require(builder.buildTextMesh == nil and builder.openUrlFn == nil and
    builder.readClipboardFn == nil and builder.writeClipboardFn == nil,
    "omitted platform callbacks should remain nil")

var dragUiCallbackCalls = 0
var dragUiCallbackUserData: UiDragUserData = nil
var dragUiCallbackCanDrop = false

proc buildTestDragUi(b: var UiBuilder, userData: UiDragUserData, canDrop: bool) {.nimcall, gcsafe.} =
  gcsafeb:
    assumeSyncBlock:
      inc dragUiCallbackCalls
      dragUiCallbackUserData = userData
      dragUiCallbackCanDrop = canDrop
      b.node:
        discard b.fit().text("drag")

proc resetDragUiCallbackState() =
  assumeSyncBlock:
    dragUiCallbackCalls = 0
    dragUiCallbackUserData = nil
    dragUiCallbackCanDrop = false

proc dragUiCallbackCallCount(): int =
  assumeSyncBlock:
    result = dragUiCallbackCalls

proc dragUiCallbackData(): UiDragUserData =
  assumeSyncBlock:
    result = dragUiCallbackUserData

proc dragUiCallbackAcceptsDrop(): bool =
  assumeSyncBlock:
    result = dragUiCallbackCanDrop

# --- property editor test scaffolding ---------------------------------------

# A deterministic tree cursor: every non-leaf node has `childrenPerNode`
# children, down to `maxDepth` levels. Used to verify the property editor
# renders the expected property name labels for a known tree shape.
type
  TestTreeCursor* = ref object of TreeCursor
    maxDepth*: int
    childrenPerNode*: int

proc treeName(path: seq[int]): string =
  if path.len == 0:
    return "root"
  result = "n"
  for p in path:
    result.add("_")
    result.add($p)

method clone*(c: TestTreeCursor): TreeCursor =
  let r = TestTreeCursor()
  r.fieldName = c.fieldName
  r.index = c.index
  r.path = c.path
  r.maxDepth = c.maxDepth
  r.childrenPerNode = c.childrenPerNode
  return r

method childCount*(c: TestTreeCursor): int =
  if c.path.len < c.maxDepth:
    return c.childrenPerNode
  return 0

method enterChild*(c: TestTreeCursor): bool =
  if c.path.len >= c.maxDepth:
    return false
  c.path.add(0)
  c.index = 0
  c.fieldName = treeName(c.path)
  return true

method moveNext*(c: TestTreeCursor, count: int = 1): bool =
  if c.path.len == 0:
    return false
  # Advance among siblings: the parent's child count, not this node's own.
  let parentChildCount = if (c.path.len - 1) < c.maxDepth: c.childrenPerNode else: 0
  if c.index + count < parentChildCount:
    c.index += count
    c.path[c.path.high] = c.index
    c.fieldName = treeName(c.path)
    return true
  return false

method exitChild*(c: TestTreeCursor): bool =
  if c.path.len == 0:
    return false
  c.path.setLen(c.path.len - 1)
  c.index = if c.path.len > 0: c.path[^1] else: 0
  c.fieldName = treeName(c.path)
  return true

proc newTreeCursor*(maxDepth, childrenPerNode: int): TestTreeCursor =
  result = TestTreeCursor(maxDepth: maxDepth, childrenPerNode: childrenPerNode)
  result.path = @[]
  result.index = 0
  result.fieldName = treeName(result.path)

proc expectedTreeNamesRec(result: var seq[string], prefix: seq[int], depth, maxDepth, childrenPerNode: int) =
  if depth > maxDepth:
    return
  for i in 0 ..< childrenPerNode:
    var p = newSeqOfCap[int](prefix.len + 1)
    for value in prefix:
      p.add(value)
    p.add(i)
    var name = "n"
    for x in p:
      name.add("_")
      name.add($x)
    result.add(name)
    expectedTreeNamesRec(result, p, depth + 1, maxDepth, childrenPerNode)

proc expectedTreeNames(maxDepth, childrenPerNode: int): seq[string] =
  result = @[]
  result.add("root")
  expectedTreeNamesRec(result, @[], 1, maxDepth, childrenPerNode)

var plotTransformCalls = 0

proc plotTestValue(x: float32, userData: int): float32 {.gcsafe, raises: [].} =
  x + userData.float32

proc plotTestTransform(x: float32): float32 {.gcsafe, raises: [].} =
  assumeSyncBlock:
    inc plotTransformCalls
    result = 100.0'f32 * pow(100.0'f32, x)

proc resetPlotTransformCalls() =
  assumeSyncBlock:
    plotTransformCalls = 0

proc plotTransformCallCount(): int =
  assumeSyncBlock:
    result = plotTransformCalls

proc testPlotHoverLabels() =
  let series = [
    PlotSeries(fn: plotTestValue, label: uiString("Tone")),
    PlotSeries(fn: plotTestValue, userData: 1)]
  for mode in 0 .. 3:
    var b = newTestBuilder()
    resetPlotTransformCalls()
    let before = b.frame.texts.len
    let mouse = if mode == 3: vec2(-1.0'f32, -1.0'f32) else: vec2(50.0'f32, 50.0'f32)
    var callback: PlotXTransformFn = plotTestTransform
    if mode == 0:
      callback = nil
    let commands = b.buildPlotVertices(vec2(0.0'f32, 0.0'f32),
      vec2(100.0'f32, 100.0'f32), vec2(0.0'f32, 1.0'f32),
      vec2(0.0'f32, 2.0'f32), series, resolution = 16, mousePos = mouse,
      showHoverX = mode != 2, transformHoverX = callback)
    require(commands.len > 0, "plot should produce geometry")
    if mode == 3:
      require(b.frame.texts.len == before, "unhovered plot should not produce labels")
    else:
      require(b.frame.texts.len == before + 2, "each series should have a hover label")
      let suffix = if mode == 0: " (x: 0.50)"
        elif mode == 1: " (x: 1000.00)" else: ""
      require(b.frame.texts[before].text.value == "Tone: 0.50" & suffix,
        "named series should display hovered values")
      require(b.frame.texts[before + 1].text.value == "1.50" & suffix,
        "unnamed series should display hovered values")
    require(plotTransformCallCount() == (if mode == 1: 1 else: 0),
      "X transform should run once only when enabled and hovered")

proc testFlagsAndMutators() =
  var b = newTestBuilder()

  discard b.text("abc")
  discard b.fillBackground()
  discard b.backgroundColor(rgba(0.2, 0.3, 0.4, 1.0))
  discard b.textColor(rgba(0.9, 0.8, 0.7, 1.0))

  let n = b.nodes[0]
  require(FillBackground in n.flags, "FillBackground flag missing")
  require(DrawText in n.flags, "DrawText flag missing")
  require(b.frame.texts[n.textIndex - 1].text.value == "abc", "text mutator mismatch")
  require(approxEq(b.frame.styles[n.styleIndex - 1].fillColor.r, 0.2'f32), "fillColor.r mismatch")
  require(approxEq(b.frame.texts[n.textIndex - 1].textColor.g, 0.8'f32), "textColor.g mismatch")

proc testHighlightedText() =
  let normalColor = rgba(0.2, 0.3, 0.4, 1.0)
  let highlightColor = rgba(0.9, 0.8, 0.1, 1.0)

  var b = newTestBuilder()
  let initialNodeCount = b.nodes.len
  let unicodeHighlights = @[2]
  b.highlightedText("abédefgh", unicodeHighlights, normalColor, highlightColor,
    maxWidth = 7, fontScale = 1.5'f32)

  var textIndices: seq[int] = @[]
  for i in initialNodeCount ..< b.nodes.len:
    if b.nodes[i].textIndex > 0:
      textIndices.add(b.nodes[i].textIndex.int - 1)
  require(textIndices.len == 5,
    "highlighted text should create five visible spans, got " & $textIndices.len &
      " text nodes from " & $(b.nodes.len - initialNodeCount) & " added nodes (" &
      $initialNodeCount & " -> " & $b.nodes.len & ")")
  require(b.frame.texts[textIndices[0]].text.value == "ab", "ordinary prefix mismatch")
  require(b.frame.texts[textIndices[1]].text.value == "é", "UTF-8 byte-offset highlight mismatch")
  require(b.frame.texts[textIndices[2]].text.value == "de", "abbreviated prefix mismatch")
  require(b.frame.texts[textIndices[3]].text.value == "…", "ellipsis mismatch")
  require(b.frame.texts[textIndices[4]].text.value == "h", "abbreviated suffix mismatch")
  require(approxEq(b.frame.texts[textIndices[0]].textColor.r, normalColor.r),
    "ordinary span color mismatch")
  require(approxEq(b.frame.texts[textIndices[1]].textColor.r, highlightColor.r),
    "highlight span color mismatch")
  require(approxEq(b.frame.texts[textIndices[1]].fontSize,
    b.themeTextStyle(UiStyleIndexLabelText)[].fontSize * 1.5'f32),
    "highlighted text font scale mismatch")

  var plain = newTestBuilder()
  let plainInitialNodeCount = plain.nodes.len
  let noHighlights: seq[int] = @[]
  plain.highlightedText("abcdefghi", noHighlights, normalColor, highlightColor, maxWidth = 6)
  textIndices.setLen(0)
  for i in plainInitialNodeCount ..< plain.nodes.len:
    if plain.nodes[i].textIndex > 0:
      textIndices.add(plain.nodes[i].textIndex.int - 1)
  require(textIndices.len == 3, "plain abbreviation should create three spans")
  require(plain.frame.texts[textIndices[0]].text.value == "abc", "plain abbreviation prefix mismatch")
  require(plain.frame.texts[textIndices[1]].text.value == "…", "plain abbreviation ellipsis mismatch")
  require(plain.frame.texts[textIndices[2]].text.value == "hi", "plain abbreviation suffix mismatch")

  var unsorted = newTestBuilder()
  let unsortedInitialNodeCount = unsorted.nodes.len
  let unsortedHighlights = @[4, 0, 0, 99]
  unsorted.highlightedText("aébc", unsortedHighlights, normalColor, highlightColor)
  textIndices.setLen(0)
  for i in unsortedInitialNodeCount ..< unsorted.nodes.len:
    if unsorted.nodes[i].textIndex > 0:
      textIndices.add(unsorted.nodes[i].textIndex.int - 1)
  require(textIndices.len == 3,
    "unsorted and duplicate highlight offsets should produce rune spans")
  require(approxEq(unsorted.frame.texts[textIndices[0]].textColor.r, highlightColor.r),
    "first unsorted highlight mismatch")
  require(approxEq(unsorted.frame.texts[textIndices[2]].textColor.r, highlightColor.r),
    "last unsorted highlight mismatch")

proc testTextWrappingUsesNodeWidthOnlyWhenEnabled() =
  var b = newTestBuilder()

  let unwrappedIdx = b.nodes.len
  b.node:
    discard b.width(30.0'f32).fitY().text("abcdefghij")

  let wrappedIdx = b.nodes.len
  b.node:
    discard b.width(30.0'f32).fitY().wrapText().text("abcdefghij")

  require(approxEq(b.nodes[unwrappedIdx].size.y, 20.0'f32), "unwrapped text should use an unlimited arrangement width")
  require(approxEq(b.nodes[wrappedIdx].size.y, 80.0'f32), "wrapped text should use the node content width")

proc testPositionAndSizeScalars() =
  var b = newTestBuilder()

  let idx = b.nodes.len
  b.node:
    discard b.position(12.0'f32, 34.0'f32)
    discard b.size(56.0'f32, 78.0'f32)
  discard b.postProcessChildren(0)

  let n = b.nodes[idx]
  require(approxEq(n.pos.x, 12.0), "position.x mismatch")
  require(approxEq(n.pos.y, 34.0), "position.y mismatch")
  require(approxEq(n.size.x, 56.0), "size.x mismatch")
  require(approxEq(n.size.y, 78.0), "size.y mismatch")

proc testBaseFontRelativePadding() =
  var graphical = newBuilder(fixedMeasureText)
  graphical.fontScale = 1.5'f32
  discard graphical.beginUiFrame(200.0'f32, 120.0'f32)
  graphical.defaultText.fontSize = 10.0'f32

  let uniformIndex = graphical.nodes.len
  graphical.node:
    discard graphical.paddingRelative(1.0'f32)
  let uniformStyle = graphical.nodeStyle(uniformIndex)
  require(approxEq(uniformStyle.paddingX, 15.0'f32) and
      approxEq(uniformStyle.paddingY, 15.0'f32),
    "relative padding of one should equal the effective base font size")

  let axisIndex = graphical.nodes.len
  graphical.node:
    discard graphical.padding(2.0'f32)
    discard graphical.paddingXRelative(0.5'f32)
    discard graphical.paddingYRelative(0.25'f32)
    discard graphical.gapRelative(0.5'f32)
  let axisStyle = graphical.nodeStyle(axisIndex)
  require(approxEq(axisStyle.paddingX, 7.5'f32),
    "relative horizontal padding should preserve graphical fractions")
  require(approxEq(axisStyle.paddingY, 3.75'f32),
    "relative vertical padding should preserve graphical fractions")
  require(approxEq(graphical.nodeGap(axisIndex), 7.5'f32),
    "relative gap should preserve graphical fractions")

  var terminal = newBuilder(fixedMeasureText, backendType = UiBackendType.Terminal)
  terminal.fontScale = 1.5'f32
  discard terminal.beginUiFrame(80.0'f32, 24.0'f32)
  terminal.defaultText.fontSize = 3.0'f32
  let terminalIndex = terminal.nodes.len
  terminal.node:
    discard terminal.paddingRelative(0.75'f32)
    discard terminal.gapRelative(0.75'f32)
  let terminalStyle = terminal.nodeStyle(terminalIndex)
  require(terminalStyle.paddingX == 3.0'f32 and terminalStyle.paddingY == 3.0'f32,
    "terminal relative padding should round down to whole cells")
  require(terminal.nodeGap(terminalIndex) == 3.0'f32,
    "terminal relative gap should round down to whole cells")

proc testBaseFontRelativeSize() =
  var b = newBuilder(fixedMeasureText)
  b.fontScale = 1.5'f32
  discard b.beginUiFrame(200.0'f32, 120.0'f32)
  b.defaultText.fontSize = 10.0'f32

  let sizeIndex = b.nodes.len
  b.node:
    discard b.sizeRelative(0.5'f32, 0.25'f32)
  require(b.nodes[sizeIndex].size == vec2(8.0'f32, 4.0'f32),
    "relative size should scale by the effective base font and round")

  let axisIndex = b.nodes.len
  b.node:
    discard b.widthRelative(1.1'f32)
    discard b.heightRelative(0.6'f32)
  require(b.nodes[axisIndex].size == vec2(17.0'f32, 9.0'f32),
    "relative width and height should round to whole layout units")

proc testTerminalCatalogWidgetsAreOneRowHigh() =
  var b = newBuilder(fixedTerminalMeasureText, backendType = UiBackendType.Terminal)
  for styleIndex in low(UiStyleIndex) .. high(UiStyleIndex):
    b.themeStyle(styleIndex).paddingY = 0.0'f32
  for styleIndex in low(UiTextStyleIndex) .. high(UiTextStyleIndex):
    b.themeTextStyle(styleIndex).fontSize = 1.0'f32
  discard b.beginUiFrame(200.0'f32, 120.0'f32)
  b.defaultText.fontSize = 1.0'f32

  var checked = false
  var sliderValue = 0.5'f32
  var dragValue = 0.5'f32
  var dragVec2 = vec2(0.5'f32)
  var dragVec3 = vec3(0.5'f32)
  var dragVec4 = vec4(0.5'f32)
  var color = rgba(1.0'f32, 0.0'f32, 0.0'f32, 1.0'f32)
  var selected = 0
  var menuOpen = false
  let options = ["One", "Two"]
  var widgetNodes: seq[(string, int)] = @[]

  template capture(name: string, body: untyped) =
    block:
      let nodeIndex = b.nodes.len
      body
      widgetNodes.add((name, nodeIndex))

  capture("label"):
    b.label("Label")
  capture("labelWrapped"):
    b.labelWrapped("Wrapped"):
      discard b.width(20.0'f32)
  capture("button"):
    discard b.button("Button")
  capture("checkbox"):
    discard b.checkbox("Checkbox", checked)
  capture("slider"):
    discard b.slider(sliderValue)
  capture("dragFloat"):
    discard b.dragFloat(dragValue, 0.5'f32)
  capture("dragFloat2"):
    discard b.dragFloat2(dragVec2, 0.5'f32)
  capture("dragFloat3"):
    discard b.dragFloat3(dragVec3, 0.5'f32)
  capture("dragFloat4"):
    discard b.dragFloat4(dragVec4, 0.5'f32)
  capture("colorPicker"):
    discard b.colorPicker(color)
  capture("dropdown"):
    discard b.dropdown(options, selected)
  capture("tooltip button"):
    discard b.button("Hover me")
  capture("menuBar"):
    b.menuBar:
      b.menuBarItem(menuOpen):
        b.label("Menu")
      do:
        discard
      do:
        discard
      do:
        discard

  discard b.postProcessChildren(0)
  for widget in widgetNodes:
    require(approxEq(b.nodes[widget[1]].size.y, 1.0'f32),
      widget[0] & " should be exactly one terminal row high, got " & $b.nodes[widget[1]].size.y)

proc testVerticalLayoutTextSizing() =
  var b = newTestBuilder(200.0, 120.0)

  discard b.layout(LayoutVertical).padding(5.0).gap(3.0)

  let firstIdx = b.nodes.len
  b.node:
    discard b.fitX().fitY()
    discard b.text("abcd")

  let secondIdx = b.nodes.len
  b.node:
    discard b.size(10.0, 20.0)
    discard b.fillX()
  discard b.postProcessChildren(0)

  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]

  # fixedMeasureText: 4 chars => 40x20
  require(approxEq(first.size.x, 40.0), "vertical first size.x mismatch")
  require(approxEq(first.size.y, 20.0), "vertical first size.y mismatch")
  require(approxEq(first.pos.x, 0.0), "vertical first pos.x mismatch")
  require(approxEq(first.pos.y, 0.0), "vertical first pos.y mismatch")

  require(approxEq(second.size.x, 190.0), "vertical second size.x mismatch") # root width 200 - padding*2
  require(approxEq(second.size.y, 20.0), "vertical second size.y mismatch")
  require(approxEq(second.pos.x, 0.0), "vertical second pos.x mismatch")
  require(approxEq(second.pos.y, 23.0), "vertical second pos.y mismatch") # 20 + 3

proc testHorizontalLayoutTextSizing() =
  var b = newTestBuilder(300.0, 90.0)

  discard b.layout(LayoutHorizontal).padding(4.0).gap(2.0)

  let firstIdx = b.nodes.len
  b.node:
    discard b.size(30.0, 1.0)
    discard b.fillY()

  let secondIdx = b.nodes.len
  b.node:
    discard b.fitX().fitY()
    discard b.text("xy")
  discard b.postProcessChildren(0)

  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]

  require(approxEq(first.pos.x, 0.0), "horizontal first pos.x mismatch")
  require(approxEq(first.pos.y, 0.0), "horizontal first pos.y mismatch")
  require(approxEq(first.size.x, 30.0), "horizontal first size.x mismatch")
  require(approxEq(first.size.y, 82.0), "horizontal first size.y mismatch") # root height 90 - padding*2

  require(approxEq(second.pos.x, 32.0), "horizontal second pos.x mismatch") # 30 + 2
  require(approxEq(second.pos.y, 0.0), "horizontal second pos.y mismatch")
  require(approxEq(second.size.x, 20.0), "horizontal second size.x mismatch") # 2 chars * 10
  require(approxEq(second.size.y, 20.0), "horizontal second size.y mismatch")

proc testAlignCenterVerticalCrossAxis() =
  var b = newTestBuilder(200.0, 120.0)
  var idx = -1

  b.node:
    discard b.fillX().fillY()
    discard b.layout(LayoutVertical)

    idx = b.nodes.len
    b.node:
      discard b.alignCenter()
      discard b.size(40.0, 10.0)
  discard b.postProcessChildren(0)

  let n = b.nodes[idx]
  require(approxEq(n.pos.x, 80.0), "vertical AlignCenter should center child on X")
  require(approxEq(n.pos.y, 0.0), "vertical AlignCenter should not move child on Y")

proc testAlignCenterHorizontalCrossAxis() =
  var b = newTestBuilder(300.0, 90.0)
  var idx = -1

  b.node:
    discard b.fillX().fillY()
    discard b.layout(LayoutHorizontal)

    idx = b.nodes.len
    b.node:
      discard b.alignCenter()
      discard b.size(20.0, 10.0)
  discard b.postProcessChildren(0)

  let n = b.nodes[idx]
  require(approxEq(n.pos.x, 0.0), "horizontal AlignCenter should not move child on X")
  require(approxEq(n.pos.y, 40.0), "horizontal AlignCenter should center child on Y")

proc testAlignCenterWithoutLayout() =
  var b = newTestBuilder(200.0, 120.0)

  let idx = b.nodes.len
  b.node:
    discard b.alignCenter()
    discard b.size(40.0, 10.0)
  discard b.postProcessChildren(0)

  b.endUiFrame()

  let n = b.nodes[idx]
  require(approxEq(n.pos.x, 80.0), "layout-none AlignCenter should center child on X")
  require(approxEq(n.pos.y, 55.0), "layout-none AlignCenter should center child on Y")

proc testStandaloneFitOnEndNode() =
  var b = newTestBuilder(200.0, 120.0)

  let idx = b.nodes.len
  b.node:
    discard b.padding(3.0)
    discard b.fitX().fitY()
    discard b.text("abc")
  discard b.postProcessChildren(0)

  let n = b.nodes[idx]
  # fixedMeasureText: 3 chars => 30x20, plus padding 3 on each side.
  require(approxEq(n.size.x, 36.0), "standalone size-to-content width mismatch")
  require(approxEq(n.size.y, 26.0), "standalone size-to-content height mismatch")

proc testParentFitIncludesChildren() =
  var b = newTestBuilder(200.0, 120.0)

  let parentIdx = b.nodes.len
  b.node:
    discard b.padding(2.0)
    discard b.fitX().fitY()
    b.node:
      discard b.fitX().fitY()
      discard b.text("abcd")
      discard b.position(5.0, 7.0)
  discard b.postProcessChildren(0)

  let parent = b.nodes[parentIdx]
  # Child intrinsic is 40x20 (4 chars * 10 x 20), positioned at (5,7), plus parent leading/trailing padding.
  require(approxEq(parent.size.x, 49.0), "parent size-to-content width should include child extent")
  require(approxEq(parent.size.y, 31.0), "parent size-to-content height should include child extent")

proc testParentFitIgnoresFlaggedChildExtent() =
  var b = newTestBuilder(200.0, 120.0)

  let parentIdx = b.nodes.len
  var overlayIdx = -1
  b.node:
    discard b.fitX().fitY()
    b.node:
      discard b.size(20.0, 30.0)
    overlayIdx = b.nodes.len
    b.node:
      discard b.size(80.0, 90.0).ignoreInContentExtent()
      discard b.anchors(0.0, 0.0, 1.0, 0.0)
        .offsets(0.0, -10.0, 0.0, 10.0)
        .finishAnchors()
  discard b.postProcessChildren(0)

  require(IgnoreInContentExtent in b.nodes[overlayIdx].flags,
    "ignoreInContentExtent should set the node flag")
  require(approxEq(b.nodes[parentIdx].size.x, 20.0),
    "flagged overlay should not affect fitted parent width")
  require(approxEq(b.nodes[parentIdx].size.y, 30.0),
    "flagged overlay should not affect fitted parent height")

proc testParentFitIncludesChildren2() =
  var b = newTestBuilder(200.0, 120.0)

  let parentIdx = b.nodes.len
  b.node: # 1
    discard b.fillX().fitY()

    b.node: # 2
      discard b.padding(50).gap(6)
      discard b.fillX().fitY()
      discard b.layout(LayoutHorizontal)

      b.node: # 3
        discard b.fitX().fitY()
        discard b.text("abc")

      b.node: # 4
        discard b.size(80, 50)

      b.node: # 5
        discard b.fitX().fitY()
        discard b.text("abc")
  discard b.postProcessChildren(0)

  let parent = b.nodes[parentIdx]
  require(approxEq(parent.size.x, 200.0), "parent size-to-content width should include child extent")
  require(approxEq(parent.size.y, 50.0'f32 * 2.0'f32 + 50.0'f32), "parent size-to-content height should include child extent")

proc testHorizontalFitYWithNestedFillYPropagation() =
  var b = newTestBuilder(300.0, 160.0)

  var firstIdx = -1
  var firstChildIdx = -1
  var secondIdx = -1

  b.node:
    discard b.layout(LayoutHorizontal)
    discard b.fitY()
    discard b.gap(0.0)

    firstIdx = b.nodes.len
    b.node:
      discard b.fillY().fitX()

      firstChildIdx = b.nodes.len
      b.node:
        discard b.size(30.0, 0.0)
        discard b.fillY()

    secondIdx = b.nodes.len
    b.node:
      discard b.size(40.0, 50.0)
  discard b.postProcessChildren(0)

  let first = b.nodes[firstIdx]
  let firstChild = b.nodes[firstChildIdx]
  let second = b.nodes[secondIdx]

  require(approxEq(second.size.y, 50.0), "setup failed: second child fixed height mismatch")
  require(approxEq(first.size.y, second.size.y), "first child should match second child height after FitY post-process")
  require(approxEq(firstChild.size.y, second.size.y), "nested FillY child should recursively match propagated height")

proc testImmediateFillXAndFillY() =
  var b = newTestBuilder(220.0, 140.0)

  b.node:
    discard b.padding(10.0)
    discard b.size(100.0, 80.0)
    let childIdx = b.nodes.len
    b.node:
      discard b.size(1.0, 1.0)
      discard b.fillX().fillY()

    let child = b.nodes[childIdx]
    require(approxEq(child.size.x, 80.0), "fillX should resolve immediately from parent content width")
    require(approxEq(child.size.y, 60.0), "fillY should resolve immediately from parent content height")

proc testImmediateFillRespectsChildPosition() =
  var b = newTestBuilder(220.0, 140.0)

  b.node:
    discard b.size(100.0, 80.0)
    let childIdx = b.nodes.len
    b.node:
      discard b.size(1.0, 1.0)
      discard b.position(10.0, 15.0)
      discard b.fillX().fillY()

    let child = b.nodes[childIdx]
    require(approxEq(child.size.x, 90.0), "fillX should use remaining width after child x position")
    require(approxEq(child.size.y, 65.0), "fillY should use remaining height after child y position")

proc testPostProcessFillRespectsChildPosition() =
  var b = newTestBuilder(220.0, 140.0)

  b.node:
    discard b.size(100.0, 80.0)

    let fillChildIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 1.0)
      discard b.position(5.0, 12.0)
      discard b.fillY()

    # This sibling marks the parent for child post-processing.
    b.node:
      discard b.size(10.0, 10.0)
      discard b.alignCenter()

    let fillChild = b.nodes[fillChildIdx]
    require(approxEq(fillChild.size.y, 68.0), "post-process FillY should use remaining height after child y position")

proc testPostProcessFillPropagatesKnownParentAxes() =
  var b = newTestBuilder(220.0, 140.0)
  var parentIdx = -1
  var childIdx = -1

  b.node:
    parentIdx = b.nodes.len
    b.node:
      discard b.width(100.0'f32)
      childIdx = b.nodes.len
      b.node:
        discard b.fillX().fillY()

      b.node:
        discard b.alignCenter()

  discard b.postProcessChildren(parentIdx)
  let child = b.nodes[childIdx]
  require(SizeXKnown in child.flags, "post-process FillX should inherit a known parent width")
  require(SizeYKnown notin child.flags, "post-process FillY should remain unknown when the parent height is unknown")

proc testReverseVerticalFillXUsesContentWidth() =
  var b = newTestBuilder(220.0, 140.0)

  b.node:
    discard b.size(100.0, 80.0)
    discard b.layout(LayoutVertical)
    discard b.reverseLayout()

    let childIdx = b.nodes.len
    b.node:
      discard b.size(1.0, 10.0)
      discard b.fillX()

    let child = b.nodes[childIdx]
    require(approxEq(child.size.x, 100.0), "reverse vertical FillX should use full parent content width")

proc testMinMaxSizeClamping() =
  var b = newTestBuilder()

  let idx = b.nodes.len
  b.node:
    discard b.fitX().fitY()
    discard b.text("abcdefghij") # fixedMeasureText => 100 x 20
    discard b.minSize(120.0, 30.0)
    discard b.maxSize(90.0, 25.0)
  discard b.postProcessChildren(0)

  let n = b.nodes[idx]
  require(approxEq(n.size.x, 120.0), "width should clamp to effective min when max < min")
  require(approxEq(n.size.y, 30.0), "height should clamp to effective min when max < min")

proc testPaddingOffsetsChildWithoutLayout() =
  ## Parent padding should offset child placement during traversal/render command generation,
  ## while child.pos remains in parent content-space.
  var b = newTestBuilder(200.0, 120.0)

  var childIdx = -1
  b.node:
    discard b.padding(12.0)
    childIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 8.0)
      discard b.fillBackground()
      discard b.backgroundColor(rgba(0.4, 0.5, 0.6, 1.0))

  let child = b.nodes[childIdx]
  require(approxEq(child.pos.x, 0.0), "child pos.x should remain content-relative")
  require(approxEq(child.pos.y, 0.0), "child pos.y should remain content-relative")

  b.endUiFrame()
  var found = false
  for cmd in b.frameOutput.commands:
    if cmd.nodeIndex == childIdx and cmd.kind == CmdRectFill:
      found = true
      require(approxEq(cmd.pos.x, 12.0), "rendered child x should include parent padding")
      require(approxEq(cmd.pos.y, 12.0), "rendered child y should include parent padding")
  require(found, "expected a fill command for child node")

proc testCustomRenderCommandsInjection() =
  var b = newTestBuilder(220.0, 140.0)

  var custom = [
    UiRenderCommand(
      kind: CmdLine,
      nodeIndex: -1,
      pos: vec2(2.0'f32, 3.0'f32),
      size: vec2(11.0'f32, 7.0'f32),
      color: rgba(0.8, 0.2, 0.1, 1.0),
    ),
    UiRenderCommand(
      kind: CmdCircleFill,
      nodeIndex: 0,
      pos: vec2(9.0'f32, 5.0'f32),
      radius: 4.0'f32,
      color: rgba(0.2, 0.7, 0.4, 1.0),
    ),
  ]

  var customNodeIdx = -1
  b.node("custom-cmd-node"):
    customNodeIdx = b.stack[^1]
    discard b.customRenderCommands(custom)

  b.endUiFrame()

  var sawLine = false
  var sawCircle = false
  for cmd in b.frameOutput.commands:
    if cmd.kind == CmdLine:
      sawLine = true
      require(cmd.nodeIndex == customNodeIdx, "custom command without node index should inherit current node index")
      require(approxEq(cmd.pos.x, 2.0'f32), "custom line command x mismatch")
    if cmd.kind == CmdCircleFill:
      sawCircle = true
      require(cmd.nodeIndex == 0, "custom command with explicit node index should be preserved")

  require(sawLine, "expected custom line command in frame output")
  require(sawCircle, "expected custom circle command in frame output")

proc testCustomRenderCommandsSupportsTwoFrameLifetime() =
  var b = newBuilder(fixedMeasureText)
  var custom = [
    UiRenderCommand(
      kind: CmdLine,
      nodeIndex: -1,
      pos: vec2(1.0'f32, 1.0'f32),
      size: vec2(5.0'f32, 5.0'f32),
      color: rgba(0.1, 0.2, 0.3, 1.0),
    ),
  ]

  discard b.beginUiFrame(220.0, 140.0)
  b.node("persist-custom"):
    discard b.customRenderCommands(custom)
  b.endUiFrame()

  custom[0].pos = vec2(23.0'f32, 19.0'f32)

  discard b.beginUiFrame(220.0, 140.0)
  b.node("persist-custom"):
    discard b.customRenderCommands(custom)
  b.endUiFrame()

  var sawUpdated = false
  for cmd in b.frameOutput.commands:
    if cmd.kind == CmdLine:
      sawUpdated = true
      require(approxEq(cmd.pos.x, 23.0'f32), "second-frame custom command should read external storage")
      require(approxEq(cmd.pos.y, 19.0'f32), "second-frame custom command should read external storage")
      break

  require(sawUpdated, "expected custom line command in second frame output")

proc testArenaResizeArrayView() =
  var a = initArena(256)
  var cmds = a.allocEmptyArray(2, UiRenderCommand)

  cmds.add UiRenderCommand(kind: CmdRectFill, pos: vec2(1.0'f32, 2.0'f32), size: vec2(3.0'f32, 4.0'f32))
  require(cmds.len == 1, "setup failed: expected one command")
  require(cmds.cap == 2, "setup failed: expected initial capacity 2")

  a.resize(cmds, 4)
  require(cmds.cap == 4, "resize should grow capacity")
  require(cmds.len == 1, "resize should preserve logical length when growing")
  require(approxEq(cmds[0].pos.x, 1.0'f32), "resize should preserve existing command data")

  cmds.add UiRenderCommand(kind: CmdRectFill, pos: vec2(5.0'f32, 6.0'f32), size: vec2(1.0'f32, 1.0'f32))
  cmds.add UiRenderCommand(kind: CmdRectFill, pos: vec2(7.0'f32, 8.0'f32), size: vec2(1.0'f32, 1.0'f32))
  require(cmds.len == 3, "expected three commands after appends")

  a.resize(cmds, 2)
  require(cmds.cap == 2, "resize should shrink capacity")
  require(cmds.len == 2, "resize should clamp logical length when shrinking")
  require(approxEq(cmds[1].pos.x, 5.0'f32), "shrink should preserve prefix data")

proc testStableExplicitIdsAcrossFrames() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(200.0, 120.0)
  let a1Idx = b.nodes.len
  b.node("animated-A"):
    discard
  let idA1 = b.nodes[a1Idx].id

  let b1Idx = b.nodes.len
  b.node("animated-B"):
    discard
  let idB1 = b.nodes[b1Idx].id

  discard b.beginUiFrame(200.0, 120.0)
  # Insert an unrelated auto-id node before explicit IDs.
  b.node:
    discard

  let a2Idx = b.nodes.len
  b.node("animated-A"):
    discard
  let idA2 = b.nodes[a2Idx].id

  let b2Idx = b.nodes.len
  b.node("animated-B"):
    discard
  let idB2 = b.nodes[b2Idx].id

  require(idA1 == idA2, "explicit node id A must remain stable")
  require(idB1 == idB2, "explicit node id B must remain stable")
  require(not (idA1 == idB1), "different explicit keys must generate different ids")

proc testPushPopIdScopes() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(240.0, 120.0)
  discard b.pushId("left-column")
  let left1Idx = b.nodes.len
  b.node("button"):
    discard
  let left1 = b.nodes[left1Idx].id
  discard b.popId()

  discard b.pushId("right-column")
  let right1Idx = b.nodes.len
  b.node("button"):
    discard
  let right1 = b.nodes[right1Idx].id
  discard b.popId()

  discard b.beginUiFrame(240.0, 120.0)
  discard b.pushId("left-column")
  let left2Idx = b.nodes.len
  b.node("button"):
    discard
  let left2 = b.nodes[left2Idx].id
  discard b.popId()

  discard b.pushId("right-column")
  let right2Idx = b.nodes.len
  b.node("button"):
    discard
  let right2 = b.nodes[right2Idx].id
  discard b.popId()

  require(left1 == left2, "left scoped id must remain stable")
  require(right1 == right2, "right scoped id must remain stable")
  require(not (left1 == right1), "same node key in different scopes must not collide")

proc testButtonHoverAndPressed() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(260.0, 120.0)
  let firstIdx = b.nodes.len
  let firstPressed = b.button("Play")
  let firstFill = b.frame.styles[b.nodes[firstIdx].styleIndex - 1].fillColor

  require(not firstPressed, "button should not report pressed without prior click")
  require(approxEq(firstFill.r, 0.22'f32), "button default fill should be non-hover color")

  let pressInput = UiInputSnapshot(
    mouse: vec2(8.0'f32),
    mousePressed: {MouseLeft},
  )
  discard b.beginUiFrame(260.0, 120.0, input = pressInput)
  discard b.button("Play")

  let releaseInput = UiInputSnapshot(
    mouse: vec2(8.0'f32),
    mouseReleased: {MouseLeft},
  )
  discard b.beginUiFrame(260.0, 120.0, input = releaseInput)
  let secondIdx = b.nodes.len
  let secondPressed = b.button("Play")
  let secondFill = b.frame.styles[b.nodes[secondIdx].styleIndex - 1].fillColor

  require(secondPressed, "button should report pressed when previous frame clicked id matches")
  require(secondFill.r > firstFill.r, "button hover fill should animate toward hover color when previously hovered")
  require(secondFill.r < 0.96'f32 + 0.0001'f32, "button hover fill should remain below click highlight color")

proc buildMouseClickTargets(b: var UiBuilder): tuple[first, second: UiNodeId] =
  result = (first: noneNodeId(), second: noneNodeId())
  b.node(1'u64):
    discard b.position(0, 0).size(40, 40)
    result.first = b.currentNode.id
  b.node(2'u64):
    discard b.position(60, 0).size(40, 40)
    result.second = b.currentNode.id
  b.endUiFrame(buildRenderCommands = false)

proc mouseClickFrame(b: var UiBuilder, input: UiInputSnapshot): tuple[first, second: UiNodeId] =
  discard b.beginUiFrame(120.0'f32, 60.0'f32, input = input)
  return b.buildMouseClickTargets()

proc testPressAndReleaseWithinOneFrame() =
  for button in [MouseLeft, MouseRight]:
    var b = newBuilder(fixedMeasureText)
    let targets = b.mouseClickFrame(UiInputSnapshot())
    for click in 1..3:
      let input = UiInputSnapshot(mouse: vec2(70.0'f32, 10.0'f32),
        mousePressed: {button}, mouseReleased: {button},
        mouseClickCount: click.uint8)
      discard b.mouseClickFrame(input)
      if button == MouseLeft:
        require(b.wasPressed(targets.second), "same-frame left click must report its press")
        require(b.wasClicked(targets.second), "same-frame left click must report its click")
        require(b.previousOutput.clickedIndex >= 0, "same-frame click must report its node index")
        require(not b.wasHeld(targets.second), "released same-frame click must not remain held")
        require(b.previousOutput.heldIndex == -1, "released same-frame click must clear its held index")
      else:
        require(b.previousOutput.rightPressedId == targets.second,
          "same-frame right click must report its press")
        require(b.wasRightClicked(targets.second), "same-frame right click must report its click")
        require(b.previousOutput.rightClickedIndex >= 0,
          "same-frame right click must report its node index")
      discard b.mouseClickFrame(UiInputSnapshot(mouse: input.mouse))
      require(not b.wasClicked(targets.second) and not b.wasRightClicked(targets.second),
        "click must not repeat in the following frame")

proc testSameFrameClickUsesCurrentPressTarget() =
  for button in [MouseLeft, MouseRight]:
    var b = newBuilder(fixedMeasureText)
    let targets = b.mouseClickFrame(UiInputSnapshot())
    discard b.mouseClickFrame(UiInputSnapshot(mouse: vec2(10.0'f32),
      mousePressed: {button}, mouseDown: {button}))
    discard b.mouseClickFrame(UiInputSnapshot(mouse: vec2(70.0'f32, 10.0'f32),
      mousePressed: {button}, mouseReleased: {button}))
    if button == MouseLeft:
      require(b.wasClicked(targets.second) and not b.wasClicked(targets.first),
        "same-frame left click must use the new press target, not the previous held node")
    else:
      require(b.wasRightClicked(targets.second) and not b.wasRightClicked(targets.first),
        "same-frame right click must use the new press target, not the previous pressed node")

proc testSeparateFrameMouseClickTargets() =
  for button in [MouseLeft, MouseRight]:
    for releaseOverTarget in [false, true]:
      var b = newBuilder(fixedMeasureText)
      let targets = b.mouseClickFrame(UiInputSnapshot())
      discard b.mouseClickFrame(UiInputSnapshot(mouse: vec2(10.0'f32),
        mousePressed: {button}, mouseDown: {button}))
      discard b.mouseClickFrame(UiInputSnapshot(
        mouse: vec2(if releaseOverTarget: 10.0'f32 else: 70.0'f32, 10.0'f32),
        mouseReleased: {button}))
      let clicked = if button == MouseLeft:
          b.wasClicked(targets.first)
        else:
          b.wasRightClicked(targets.first)
      require(clicked == releaseOverTarget,
        "separate-frame clicks must still require release over the original press target")

proc testSameFrameClickPreservesFinalDownState() =
  var b = newBuilder(fixedMeasureText)
  let targets = b.mouseClickFrame(UiInputSnapshot())
  discard b.mouseClickFrame(UiInputSnapshot(mouse: vec2(10.0'f32),
    mousePressed: {MouseLeft, MouseRight}, mouseReleased: {MouseLeft, MouseRight},
    mouseDown: {MouseLeft, MouseRight}))
  require(b.wasClicked(targets.first) and b.wasRightClicked(targets.first),
    "both buttons must detect a click when both transitions are present")
  require(b.wasHeld(targets.first), "final mouseDown state must keep the left button held")

proc testSameFrameClickOutsideUi() =
  var b = newBuilder(fixedMeasureText)
  let targets = b.mouseClickFrame(UiInputSnapshot())
  discard b.mouseClickFrame(UiInputSnapshot(mouse: vec2(200.0'f32),
    mousePressed: {MouseLeft, MouseRight}, mouseReleased: {MouseLeft, MouseRight}))
  require(b.previousOutput.clickedId == noneNodeId() and
      b.previousOutput.rightClickedId == noneNodeId(),
    "same-frame clicks outside the UI must not report a clicked target")
  require(b.previousOutput.clickedIndex == -1 and b.previousOutput.rightClickedIndex == -1,
    "same-frame clicks outside the UI must not report a clicked index")
  require(not b.wasPressed(targets.first) and not b.wasHeld(targets.first),
    "same-frame clicks outside the UI must not press or hold an existing node")

proc testMouseDragReleaseStillReported() =
  var b = newBuilder(fixedMeasureText)
  let targets = b.mouseClickFrame(UiInputSnapshot())
  discard b.mouseClickFrame(UiInputSnapshot(mouse: vec2(10.0'f32),
    mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
  discard b.mouseClickFrame(UiInputSnapshot(mouse: vec2(20.0'f32, 10.0'f32),
    mouseDelta: vec2(10.0'f32, 0.0'f32), mouseDown: {MouseLeft}))
  require(b.previousOutput.draggedId == targets.first, "moving a held node must report dragging")
  discard b.mouseClickFrame(UiInputSnapshot(mouse: vec2(70.0'f32, 10.0'f32),
    mouseDelta: vec2(50.0'f32, 0.0'f32), mouseReleased: {MouseLeft}))
  require(b.previousOutput.draggedId == targets.first,
    "release must still report the previously dragged node")
  require(b.previousOutput.draggedIndex >= 0, "drag release must report its node index")
  require(not b.wasHeld(targets.first), "drag release must clear held state")
  require(b.previousOutput.clickedId == noneNodeId(),
    "drag release over a different node must not report a click")

proc testHitBoundsExcludeBottomEdge() =
  var b = newBuilder(fixedMeasureText, textHeight = 1.0'f32,
    backendType = UiBackendType.Terminal)

  discard b.beginUiFrame(20.0'f32, 10.0'f32)
  let nodeIndex = b.nodes.len
  b.node("one-row-target"):
    discard b.size(10.0'f32, 1.0'f32)
  let nodeId = b.nodes[nodeIndex].id

  discard b.beginUiFrame(20.0'f32, 10.0'f32,
    input = UiInputSnapshot(mouse: vec2(5.0'f32, 1.0'f32)))
  b.node("one-row-target"):
    discard b.size(10.0'f32, 1.0'f32)

  require(b.previousOutput.hoveredId != nodeId,
    "the terminal row immediately below a node must not hover it")

proc testTerminalScrollBoxContentHasNoPadding() =
  var b = newBuilder(fixedMeasureText, textHeight = 1.0'f32,
    backendType = UiBackendType.Terminal)
  b.defaultStyle.paddingX = 3.0'f32
  b.defaultStyle.paddingY = 3.0'f32
  discard b.beginUiFrame(40.0'f32, 12.0'f32)

  let scrollBoxIndex = b.nodes.len
  var contentIndex = -1
  b.scrollBox:
    contentIndex = b.stack[^1]

  require(scrollBoxIndex >= 0 and contentIndex >= 0,
    "terminal scroll box should contain a content node")
  let scrollBoxStyle = b.nodeStyle(scrollBoxIndex)
  let contentStyle = b.nodeStyle(contentIndex)
  require(scrollBoxStyle.paddingX == 0.0'f32 and scrollBoxStyle.paddingY == 0.0'f32,
    "terminal scroll box should not have padding")
  require(contentStyle.paddingX == 0.0'f32 and contentStyle.paddingY == 0.0'f32,
    "terminal scroll box content should not have padding")

proc testTerminalScrollBoxUsesCellScrollbar() =
  var b = newBuilder(fixedMeasureText, textHeight = 1.0'f32,
    backendType = UiBackendType.Terminal)
  discard b.beginUiFrame(40.0'f32, 12.0'f32)

  let scrollBoxIndex = b.nodes.len
  b.scrollBox:
    discard b.fillX().height(40.0'f32)
  b.endUiFrame(buildRenderCommands = false)

  let contentIndex = b.firstChildIndex(scrollBoxIndex)
  var trackIndex = -1
  for childIndex in b.children(scrollBoxIndex):
    if childIndex != contentIndex:
      trackIndex = childIndex
      break
  let thumbIndex = b.firstChildIndex(trackIndex)

  require(trackIndex >= 0 and thumbIndex >= 0,
    "overflowing terminal scroll box should build a scrollbar")
  require(b.nodes[trackIndex].size.x == 1.0'f32,
    "terminal scroll box track should be one cell wide")
  require(b.nodes[thumbIndex].pos.x == 0.0'f32 and
      b.nodes[thumbIndex].size.x == 1.0'f32,
    "terminal scroll box thumb should fill its one-cell track")
  require(b.nodes[thumbIndex].size.y >= 1.0'f32,
    "terminal scroll box thumb should be at least one row high")

proc buildHoverInspectorFrame(b: var UiBuilder) =
  b.node("hover-target"):
    discard b.position(4.0'f32, 3.0'f32).size(20.0'f32, 10.0'f32)
    discard b.padding(2.0'f32).fillBackground().text("inspect me")
  b.node("overlays"):
    discard b.fill().noHover()
    b.overlays = b.currentNode.id

proc frameContainsText(b: UiBuilder, needle: string): bool =
  for nodeText in b.frame.texts:
    if needle in nodeText.text.value:
      return true
  return false

proc testHoveredNodeIndexAndDebugTooltip() =
  var b = newBuilder(fixedMeasureText)
  discard b.beginUiFrame(200.0'f32, 120.0'f32)
  let targetIndex = b.nodes.len
  b.buildHoverInspectorFrame()
  let targetId = b.nodes[targetIndex].id
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(200.0'f32, 120.0'f32,
    input = UiInputSnapshot(mouse: vec2(6.0'f32, 5.0'f32), modsDown: {ModAlt}))
  require(b.hoveredNodeIndex() == targetIndex,
    "hoveredNodeIndex should identify the directly hovered previous-frame node")
  require(b.previousFrame.nodes[b.hoveredNodeIndex()].id == targetId,
    "hoveredNodeIndex should reference the matching previous-frame node")
  b.buildHoverInspectorFrame()
  b.endUiFrame(buildRenderCommands = false)

  when defined(nuiDebug):
    require(b.frameContainsText("index=" & $targetIndex),
      "Alt-hover should build a tooltip containing the hovered node index")
    require(b.frameContainsText("inspect me"),
      "Alt-hover tooltip should include node text details")

    b.showDebugPanel = true
    discard b.beginUiFrame(200.0'f32, 120.0'f32,
      input = UiInputSnapshot(mouse: vec2(6.0'f32, 5.0'f32), modsDown: {ModAlt}))
    b.buildHoverInspectorFrame()
    b.endUiFrame(buildRenderCommands = false)
    require(not b.frameContainsText("index=" & $targetIndex),
      "the hover tooltip should be hidden while the debug panel is visible")

proc testSliderClickUpdatesValue() =
  var b = newBuilder(fixedMeasureText)
  var value = 0.0'f32

  discard b.beginUiFrame(300.0, 120.0)
  let sliderIdx = b.nodes.len
  discard b.slider(value, 0.0'f32, 100.0'f32)

  require(b.childCount(sliderIdx) >= 2, "slider should create label and track children")
  let pressInput = UiInputSnapshot(
    mouse: vec2(84, 12),
    mousePressed: {MouseLeft},
  )
  discard b.beginUiFrame(300.0, 120.0, input = pressInput)
  discard b.slider(value, 0.0'f32, 100.0'f32)

  let releaseInput = UiInputSnapshot(
    mouse: vec2(84, 12),
    mouseReleased: {MouseLeft},
  )
  discard b.beginUiFrame(300.0, 120.0, input = releaseInput)
  let changed = b.slider(value, 0.0'f32, 100.0'f32)

  require(changed, "slider should report changed after click on track")
  require(approxEq(value, 50.0'f32), "slider click should map pointer x to range value")

proc buildOffsetDropdownFrame(b: var UiBuilder, selected: var int,
    overlayIndex: var int, hostIndex: var int) =
  overlayIndex = b.nodes.len
  b.node("dropdown-overlays"):
    discard b.position(0.0'f32, 0.0'f32).size(80.0'f32, 24.0'f32).noHover()
    b.overlays = b.currentNode.id
  hostIndex = b.nodes.len
  b.node("dropdown-host"):
    discard b.position(20.0'f32, 8.0'f32).fit()
    discard b.dropdown(["One", "Two", "Three", "Four"], selected)

proc testTerminalDropdownPopupAnchorsBelowButton() =
  var b = newBuilder(fixedTerminalMeasureText, backendType = UiBackendType.Terminal)
  var selected = 0
  var overlayIndex = -1
  var hostIndex = -1

  discard b.beginUiFrame(80.0'f32, 24.0'f32)
  b.buildOffsetDropdownFrame(selected, overlayIndex, hostIndex)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(80.0'f32, 24.0'f32, input = UiInputSnapshot(
    mouse: vec2(21.0'f32, 8.0'f32),
    mousePressed: {MouseLeft},
  ))
  b.buildOffsetDropdownFrame(selected, overlayIndex, hostIndex)
  b.endUiFrame(buildRenderCommands = false)

  discard b.beginUiFrame(80.0'f32, 24.0'f32, input = UiInputSnapshot(
    mouse: vec2(21.0'f32, 8.0'f32),
    mouseReleased: {MouseLeft},
  ))
  b.buildOffsetDropdownFrame(selected, overlayIndex, hostIndex)
  b.endUiFrame(buildRenderCommands = false)

  let dropdownIndex = b.firstChildIndex(hostIndex)
  let buttonIndex = b.firstChildIndex(dropdownIndex)
  let popupIndex = b.firstChildIndex(overlayIndex)
  require(buttonIndex >= 0, "open dropdown should contain its button")
  require(popupIndex >= 0, "clicked dropdown should build its popup")
  let buttonPos = b.absoluteNodePos(buttonIndex)
  let popupPos = b.absoluteNodePos(popupIndex)
  require(approxEq(popupPos.x, buttonPos.x),
    "dropdown popup should align with the button x position")
  require(approxEq(popupPos.y, buttonPos.y + b.nodes[buttonIndex].size.y + 2.0'f32),
    "dropdown popup should be positioned below the button: button=" & $buttonPos &
      " buttonHeight=" & $b.nodes[buttonIndex].size.y & " popup=" & $popupPos &
      " popupSize=" & $b.nodes[popupIndex].size)

proc testPreviousNodesAndIndicesDoubleBuffered() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(220.0, 120.0)
  let firstIdx = b.nodes.len
  b.node("persisted"):
    discard b.size(20.0, 10.0)
  let firstId = b.nodes[firstIdx].id

  let pressInput = UiInputSnapshot(
    mouse: vec2(5),
    mousePressed: {MouseLeft},
  )
  discard b.beginUiFrame(220.0, 120.0, input = pressInput)
  b.node("persisted"):
    discard b.size(20.0, 10.0)

  let releaseInput = UiInputSnapshot(
    mouse: vec2(5),
    mouseReleased: {MouseLeft},
  )
  discard b.beginUiFrame(220.0, 120.0, input = releaseInput)

  require(b.previousFrame.nodes.len > firstIdx, "previousFrame.nodes should retain prior frame tree after swap")
  require(b.previousOutput.hoveredIndex == firstIdx, "hoveredIndex should point into previousFrame.nodes")
  require(b.previousOutput.clickedIndex == firstIdx, "clickedIndex should point into previousFrame.nodes")
  require(b.previousFrame.nodes[b.previousOutput.hoveredIndex].id == firstId, "hoveredIndex should resolve to previous frame node id")
  require(b.previousFrame.nodes[b.previousOutput.clickedIndex].id == firstId, "clickedIndex should resolve to previous frame node id")

proc testDragUiCallbackAndDropState() =
  var b = newBuilder(fixedMeasureText)
  resetDragUiCallbackState()
  let testUserData = UiDragUserData()

  discard b.beginUiFrame(220.0, 120.0, input = UiInputSnapshot(mouse: vec2(30.0'f32, 40.0'f32)))
  b.dragData.nodeId = b.nodes[0].id
  b.setDragData(testUserData)
  b.setDragUiCallback(buildTestDragUi)
  require(not b.endDrop(true), "accepted target should not drop before release")
  require(b.dragData.canDrop, "endDrop should store acceptance while the mouse remains down")
  b.endUiFrame(buildRenderCommands = false)

  require(dragUiCallbackCallCount() == 1, "endUiFrame should invoke the drag UI callback")
  require(dragUiCallbackData() == testUserData, "drag UI callback user data mismatch")
  require(dragUiCallbackAcceptsDrop(), "drag UI callback should receive current target acceptance")
  require(b.nodes.len == 3, "drag tooltip and callback content should be added to the frame")
  require(b.dragData.nodeId != noneNodeId(), "drag should remain active before release")

  let releaseInput = UiInputSnapshot(
    mouse: vec2(30.0'f32, 40.0'f32),
    mouseReleased: {MouseLeft},
  )
  discard b.beginUiFrame(220.0, 120.0, input = releaseInput)
  require(not b.dragData.canDrop, "drop acceptance should reset at the start of each frame")
  require(not b.endDrop(false), "rejected target should not drop on release")
  b.endUiFrame(buildRenderCommands = false)

  require(dragUiCallbackCallCount() == 2, "drag UI callback should run on the release frame")
  require(not dragUiCallbackAcceptsDrop(), "release-frame callback should receive rejected target state")
  require(b.dragData.nodeId == noneNodeId(), "drag data should clear after release-frame UI is built")
  require(b.dragData.uiCallback == nil, "drag UI callback should clear with released drag data")

proc buildExternalDropTarget(b: var UiBuilder): tuple[hovered: bool, dropped: bool] =
  result = (false, false)
  b.node:
    discard b.size(100.0, 50.0)
    result.hovered = b.beginDrop()
    if result.hovered:
      result.dropped = b.endDrop(b.externalDragData() != nil)

proc testExternalDragAndDrop() =
  var b = newBuilder(fixedMeasureText)

  discard b.beginUiFrame(220.0, 120.0, input = UiInputSnapshot(mouse: vec2(10)))
  discard buildExternalDropTarget(b)
  b.endUiFrame(buildRenderCommands = false)
  require(not b.isExternalDrag(), "no external drag without OS drag input")

  discard b.beginUiFrame(220.0, 120.0,
    input = UiInputSnapshot(mouse: vec2(10), externalDragActive: true))
  require(b.isExternalDrag(), "OS drag should create external drag data")
  require(b.dragData.nodeId == externalDragNodeId(), "external drag uses sentinel node id")
  let pending = b.externalDragData()
  require(pending != nil, "external drag should expose its payload")
  if pending != nil:
    require(not pending.dropped, "payload should be pending before drop")
  let (beginDragActive, beginDragStarted) = b.beginDrag()
  require(not beginDragActive and not beginDragStarted, "in-app drag must not start during external drag")
  let hoverFrame = buildExternalDropTarget(b)
  require(hoverFrame.hovered and not hoverFrame.dropped, "target should be hovered but not dropped")
  b.endUiFrame(buildRenderCommands = false)
  require(b.isExternalDrag(), "external drag should persist while active")

  discard b.beginUiFrame(220.0, 120.0, input = UiInputSnapshot(mouse: vec2(10),
    externalDropped: true, droppedFiles: @["C:/a.txt"], droppedTexts: @["hello"]))
  let dropped = b.externalDragData()
  require(dropped != nil, "external drop should expose its payload")
  if dropped != nil:
    require(dropped.dropped, "payload should be marked dropped")
    require(dropped.files == @["C:/a.txt"] and dropped.texts == @["hello"], "payload mismatch")
  let dropFrame = buildExternalDropTarget(b)
  require(dropFrame.dropped, "accepting target should receive the external drop")
  b.endUiFrame(buildRenderCommands = false)
  require(b.dragData.nodeId == noneNodeId(), "external drag should clear after drop")

  # Leaving the window without dropping cancels the drag.
  discard b.beginUiFrame(220.0, 120.0,
    input = UiInputSnapshot(mouse: vec2(10), externalDragActive: true))
  b.endUiFrame(buildRenderCommands = false)
  discard b.beginUiFrame(220.0, 120.0, input = UiInputSnapshot(mouse: vec2(10)))
  require(not b.isExternalDrag(), "cancelled external drag should clear")
  let cancelFrame = buildExternalDropTarget(b)
  require(not cancelFrame.hovered, "no drop hover after external drag cancelled")
  b.endUiFrame(buildRenderCommands = false)

  # A mouse release must not end an external drag.
  discard b.beginUiFrame(220.0, 120.0, input = UiInputSnapshot(mouse: vec2(10),
    externalDragActive: true, mouseReleased: {MouseLeft}))
  let releaseFrame = buildExternalDropTarget(b)
  require(not releaseFrame.dropped, "mouse release should not drop an external drag")
  b.endUiFrame(buildRenderCommands = false)
  require(b.isExternalDrag(), "external drag should survive mouse release")

proc testFileSystemCursorDragAndDrop() =
  let root = getTempDir() / "nuigi-file-drag-test"
  if dirExists(root):
    removeTestDir(root)
  createTestDir(root)
  try:
    let sourceParentPath = root / "source"
    let sourceFolderPath = sourceParentPath / "folder"
    let sourceChildPath = sourceFolderPath / "child"
    let sourceFilePath = sourceParentPath / "item.txt"
    let targetPath = root / "target"
    let unrelatedPath = root / "unrelated"
    let cachedKindPath = root / "cached-kind"
    createTestDir(sourceParentPath)
    createTestDir(sourceFolderPath)
    createTestDir(sourceChildPath)
    createTestDir(targetPath)
    createTestDir(unrelatedPath)
    createTestDir(cachedKindPath)
    onRaiseQuit(writeFile(sourceFilePath, "drag"))

    let cache = newFileSystemCache()
    require(fileSystemCursor(cachedKindPath, cache).kind == Folder, "initial directory kind should be Folder")
    removeTestDir(cachedKindPath)
    require(fileSystemCursor(cachedKindPath, cache).kind == Folder, "shared cache should serve entry kind without rechecking the filesystem")
    let rootCursor = fileSystemCursor(root, cache)
    let sourceParent = fileSystemCursor(sourceParentPath, cache)
    let sourceFolder = fileSystemCursor(sourceFolderPath, cache)
    let sourceChild = fileSystemCursor(sourceChildPath, cache)
    let sourceFile = fileSystemCursor(sourceFilePath, cache)
    let target = fileSystemCursor(targetPath, cache)
    let unrelated = fileSystemCursor(unrelatedPath, cache)

    require(sourceFolder.kind == Folder, "directory cursor should have Folder kind")
    require(sourceFile.kind == File, "file cursor should have File kind")
    require(FileSystemCursor(sourceFolder.clone()).kind == Folder, "cloned cursor should preserve entry kind")
    require(not sourceFile.canDropOn(sourceFile), "file target should reject a drop")
    require(not sourceFolder.canDropOn(sourceFolder), "folder should not drop onto itself")
    require(not sourceFolder.canDropOn(sourceChild), "folder should not drop onto its child")
    require(not sourceFile.canDropOn(sourceParent), "entry should not drop onto its direct parent")
    require(sourceFolder.canDropOn(target), "sibling folder should accept the dragged folder")

    require(sourceParent.childCount() == 2, "source listing should be cached before the move")
    require(target.childCount() == 0, "target listing should be empty before the move")
    require(unrelated.childCount() == 0, "unrelated listing should be cached before the move")
    onRaiseQuit(writeFile(unrelatedPath / "late.txt", "cached"))

    var sourceNav = FileSystemCursor(rootCursor.clone())
    require(sourceNav.enterChild(), "source folder should be reachable from root")
    var sourceFolderNav = FileSystemCursor(sourceNav.clone())
    require(sourceFolderNav.enterChild(), "dragged folder should be reachable from source")
    let sourceFolderNavPath = sourceFolderNav.fullPath
    var sourceFolderParent = FileSystemCursor(sourceFolderNav.clone())
    require(sourceFolderParent.exitChild(), "cloned child cursor should restore its parent")
    require(sourceFolderParent.fullPath == sourceParentPath,
      "restored filesystem parent should retain its cached full path")
    require(sourceFolderNav.parentPath == sourceParentPath,
      "filesystem child should expose its parent location path")
    require(sourceFolderNav.rootPath == root,
      "filesystem child should derive its original root from its location chain")
    require(sourceFolderParent.fieldName == extractFilename(sourceParentPath),
      "restored filesystem parent should retain its cached name")
    require(sourceFolderNav.fullPath == sourceFolderNavPath,
      "ascending a clone should not mutate the original cursor")
    var targetNav = FileSystemCursor(rootCursor.clone())
    require(targetNav.enterChild() and targetNav.moveNext(), "target folder should be reachable from root")

    var tree = newTreeTable(rootCursor)
    tree.toggleNode(rootCursor)
    tree.toggleNode(sourceNav)
    tree.toggleNode(sourceFolderNav)
    tree.toggleNode(targetNav)

    proc expandedIndex(tree: TreeTable, key: string): int =
      for i in 0 .. tree.nodes.high:
        let cursor = tree.nodes[i].cursor
        if cursor != nil and cursor.cursorKey() == key:
          return i
      return -1

    let targetExpandedIndex = expandedIndex(tree, targetPath)
    require(targetExpandedIndex >= 0 and tree.nodes[targetExpandedIndex].childCount == 0,
      "target expansion should begin with a cached zero child count")

    require(sourceFolder.moveTo(target), "eligible folder move should succeed")
    require(dirExists(targetPath / "folder"), "moved folder should exist under target")
    require(not dirExists(sourceFolderPath), "moved folder should leave its source path")
    require(unrelated.childCount() == 0, "moving should not invalidate an unrelated listing")

    tree.refreshRenderedNode(sourceNav)
    require(expandedIndex(tree, sourceFolderPath) < 0, "rendered source should remove its missing expanded child")
    let sourceExpandedIndex = expandedIndex(tree, sourceParentPath)
    require(sourceExpandedIndex >= 0 and tree.nodes[sourceExpandedIndex].childCount == 1,
      "rendered source should refresh its cached child count")
    require(tree.nodes[expandedIndex(tree, targetPath)].childCount == 0,
      "non-rendered target should retain its cached child count")

    tree.refreshRenderedNode(targetNav)
    require(tree.nodes[expandedIndex(tree, targetPath)].childCount == 1,
      "rendered target should refresh its cached child count")

    require(sourceFile.moveTo(target), "eligible file move should succeed")
    require(fileExists(targetPath / "item.txt"), "moved file should exist under target")
    require(not fileExists(sourceFilePath), "moved file should leave its source path")
    require(sourceParent.childCount() == 0, "source cache should refresh after both moves")
    require(target.childCount() == 2, "target cache should refresh after both moves")
  finally:
    if dirExists(root):
      removeTestDir(root)

type
  ReverseChildMode = enum
    ReverseFixed, ReverseContent, ReverseFill

const
  reverseChildModes = [ReverseFixed, ReverseContent, ReverseFill]

proc configureReverseChild(b: var UiBuilder, mode: ReverseChildMode, horizontalAxis: bool, label: string) =
  case mode
  of ReverseFixed:
    if horizontalAxis:
      discard b.size(20.0, 10.0)
    else:
      discard b.size(10.0, 20.0)
  of ReverseContent:
    if horizontalAxis:
      discard b.fitX()
    else:
      discard b.fitY()
    discard b.text(label)
  of ReverseFill:
    if horizontalAxis:
      discard b.size(1.0, 10.0)
      discard b.fillX()
    else:
      discard b.size(10.0, 1.0)
      discard b.fillY()

proc reverseAxisExpectedSize(mode: ReverseChildMode, cursorAtBegin: float32): float32 =
  case mode
  of ReverseFixed, ReverseContent:
    20.0'f32
  of ReverseFill:
    max(0.0'f32, cursorAtBegin)

proc testReverseVerticalLayoutAllCombinations() =
  for firstMode in reverseChildModes:
    for secondMode in reverseChildModes:
      var b = newTestBuilder(240.0, 180.0)

      var firstIdx = -1
      var secondIdx = -1
      b.node:
        discard b.size(100.0, 100.0)
        discard b.layout(LayoutVertical)
        discard b.reverseLayout()

        firstIdx = b.nodes.len
        b.node:
          b.configureReverseChild(firstMode, false, "aa")

        secondIdx = b.nodes.len
        b.node:
          b.configureReverseChild(secondMode, false, "bb")

      discard b.postProcessChildren(firstIdx)

      let first = b.nodes[firstIdx]
      let second = b.nodes[secondIdx]
      let firstSize = reverseAxisExpectedSize(firstMode, 100.0'f32)
      let firstPos = max(0.0'f32, 100.0'f32 - firstSize)
      let secondSize = reverseAxisExpectedSize(secondMode, firstPos)
      let secondPos = max(0.0'f32, firstPos - secondSize)

      require(approxEq(first.size.y, firstSize), "reverse vertical first size.y mismatch")
      require(approxEq(first.pos.y, firstPos), "reverse vertical first pos.y mismatch")
      require(approxEq(second.size.y, secondSize), "reverse vertical second size.y mismatch")
      require(approxEq(second.pos.y, secondPos), "reverse vertical second pos.y mismatch")

proc testReverseHorizontalLayoutAllCombinations() =
  for firstMode in reverseChildModes:
    for secondMode in reverseChildModes:
      var b = newTestBuilder(260.0, 180.0)

      var firstIdx = -1
      var secondIdx = -1
      b.node:
        discard b.size(100.0, 100.0)
        discard b.layout(LayoutHorizontal)
        discard b.reverseLayout()

        firstIdx = b.nodes.len
        b.node:
          b.configureReverseChild(firstMode, true, "aa")

        secondIdx = b.nodes.len
        b.node:
          b.configureReverseChild(secondMode, true, "bb")

      discard b.postProcessChildren(firstIdx)

      let first = b.nodes[firstIdx]
      let second = b.nodes[secondIdx]
      let firstSize = reverseAxisExpectedSize(firstMode, 100.0'f32)
      let firstPos = max(0.0'f32, 100.0'f32 - firstSize)
      let secondSize = reverseAxisExpectedSize(secondMode, firstPos)
      let secondPos = max(0.0'f32, firstPos - secondSize)

      require(approxEq(first.size.x, firstSize), "reverse horizontal first size.x mismatch")
      require(approxEq(first.pos.x, firstPos), "reverse horizontal first pos.x mismatch")
      require(approxEq(second.size.x, secondSize), "reverse horizontal second size.x mismatch")
      require(approxEq(second.pos.x, secondPos), "reverse horizontal second pos.x mismatch")

proc testReverseVerticalParentFitRepositions() =
  var b = newTestBuilder(240.0, 180.0)
  var parentIdx = -1
  var firstIdx = -1
  var secondIdx = -1

  b.node:
    parentIdx = b.nodes.len
    b.node:
      discard b.layout(LayoutVertical)
      discard b.reverseLayout()
      discard b.fitY()

      firstIdx = b.nodes.len
      b.node:
        discard b.fitY()
        discard b.text("aa")

      secondIdx = b.nodes.len
      b.node:
        discard b.size(10.0, 20.0)
  discard b.postProcessChildren(0)
  let parent = b.nodes[parentIdx]
  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]
  require(approxEq(parent.size.y, 40.0), "reverse vertical size-to-content parent height mismatch")
  require(approxEq(first.pos.y, 20.0), "reverse vertical size-to-content first child position mismatch")
  require(approxEq(second.pos.y, 0.0), "reverse vertical size-to-content second child position mismatch")

proc testReverseHorizontalParentFitRepositions() =
  var b = newTestBuilder(260.0, 180.0)
  var parentIdx = -1
  var firstIdx = -1
  var secondIdx = -1

  b.node:
    parentIdx = b.nodes.len
    b.node:
      discard b.layout(LayoutHorizontal)
      discard b.reverseLayout()
      discard b.fitX()

      firstIdx = b.nodes.len
      b.node:
        discard b.fitX()
        discard b.text("aa")

      secondIdx = b.nodes.len
      b.node:
        discard b.size(20.0, 10.0)
  discard b.postProcessChildren(0)

  let parent = b.nodes[parentIdx]
  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]
  require(approxEq(parent.size.x, 40.0), "reverse horizontal size-to-content parent width mismatch")
  require(approxEq(first.pos.x, 20.0), "reverse horizontal size-to-content first child position mismatch")
  require(approxEq(second.pos.x, 0.0), "reverse horizontal size-to-content second child position mismatch")

proc testAnchoredLayoutPivotPositioning() =
  var b = newTestBuilder(200.0, 100.0)

  let childIdx = b.nodes.len
  b.node:
    discard b.size(40.0, 20.0)
    discard b.anchors(0.5, 0.5, 0.5, 0.5)
    discard b.offsets(10.0, -5.0, 10.0, -5.0)
    discard b.pivot(0.5, 0.5)

  b.endUiFrame()

  let child = b.nodes[childIdx]
  require(approxEq(child.size.x, 40.0), "point-anchored child should keep explicit width when anchors are equal")
  require(approxEq(child.size.y, 20.0), "point-anchored child should keep explicit height when anchors are equal")
  require(approxEq(child.pos.x, 90.0), "anchored layout should resolve expected x from anchor/pivot/offset")
  require(approxEq(child.pos.y, 35.0), "anchored layout should resolve expected y from anchor/pivot/offset")

proc testAnchoredLayoutStretchUsesAnchorOffsets() =
  var b = newTestBuilder(200.0, 100.0)

  let childIdx = b.nodes.len
  b.node:
    discard b.size(10.0, 12.0)
    discard b.minSize(0.0, 0.0)
    discard b.maxSize(10000.0, 10000.0)
    discard b.anchors(0.0, 0.0, 1.0, 1.0)
    discard b.offsets(5.0, 7.0, -9.0, -11.0)
    discard b.pivot(0.0, 0.0)

  b.endUiFrame()

  let child = b.nodes[childIdx]
  require(not approxEq(child.size.x, 10.0), "stretched anchored child should override explicit width when anchors differ")
  require(not approxEq(child.size.y, 12.0), "stretched anchored child should override explicit height when anchors differ")
  require(approxEq(child.pos.x, 5.0), "stretched anchored child x should include top-left offset")
  require(approxEq(child.pos.y, 7.0), "stretched anchored child y should include top-left offset")
  require(approxEq(child.size.x, 186.0), "stretched anchored child width should honor right offset")
  require(approxEq(child.size.y, 82.0), "stretched anchored child height should honor bottom offset")

proc testAnchoredLayoutTriggersParentPostProcessForFit() =
  var b = newTestBuilder(240.0, 140.0)

  let parentIdx = b.nodes.len
  b.node:
    discard b.fitX().fitY()

    b.node:
      discard b.size(20.0, 10.0)
      discard b.anchors(0.0, 0.0, 1.0, 1.0)
      discard b.pivot(0.5, 0.5)

  let parent = b.nodes[parentIdx]
  require(PostProcessChildren in parent.flags, "anchored child should mark size-to-content parent for post-processing")

proc testAnchoredLayoutAxisSpecificMutators() =
  var b = newTestBuilder(200.0, 100.0)

  let xOnlyIdx = b.nodes.len
  b.node:
    discard b.size(40.0, 20.0)
    discard b.anchorsX(0.5, 0.5)
    discard b.offsetsX(10.0, 10.0)
    discard b.pivotX(0.5)

  let yOnlyIdx = b.nodes.len
  b.node:
    discard b.size(30.0, 10.0)
    discard b.anchorsY(0.0, 1.0)
    discard b.offsetsY(3.0, -7.0)
    discard b.pivotY(0.0)

  b.endUiFrame()

  let xOnly = b.nodes[xOnlyIdx]
  require(AnchorX in xOnly.flags, "anchorsX should set AnchorX flag")
  require(not (AnchorY in xOnly.flags), "anchorsX should not set AnchorY flag")
  require(approxEq(xOnly.pos.x, 90.0), "x-only anchoring should resolve x")
  require(approxEq(xOnly.pos.y, 0.0), "x-only anchoring should not change y")
  require(approxEq(xOnly.size.x, 40.0), "x-only point anchors should keep explicit width")
  require(approxEq(xOnly.size.y, 20.0), "x-only anchoring should not change height")

  let yOnly = b.nodes[yOnlyIdx]
  require(AnchorY in yOnly.flags, "anchorsY should set AnchorY flag")
  require(not (AnchorX in yOnly.flags), "anchorsY should not set AnchorX flag")
  require(approxEq(yOnly.pos.x, 0.0), "y-only anchoring should not change x")
  require(approxEq(yOnly.pos.y, 3.0), "y-only anchoring should resolve y")
  require(approxEq(yOnly.size.x, 30.0), "y-only anchoring should not change width")
  require(approxEq(yOnly.size.y, 90.0), "y-only stretch anchors should override explicit height")

proc testFlexHorizontalGrowDistribution() =
  var b = newTestBuilder(260.0, 120.0)

  var firstIdx = -1
  var secondIdx = -1
  var thirdIdx = -1
  b.node:
    discard b.size(200.0, 80.0)
    discard b.layout(LayoutHorizontal)
    discard b.flexLayout()
    discard b.gap(10.0)

    firstIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 20.0)
      discard b.flex(1.0, 1.0, 50.0)

    secondIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 20.0)
      discard b.flex(1.0, 1.0, 50.0)

    thirdIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 20.0)
      discard b.flex(1.0, 1.0, 50.0)
  discard b.postProcessChildren(0)

  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]
  let third = b.nodes[thirdIdx]

  require(approxEq(first.size.x, 60.0), "flex grow should distribute extra main-axis space")
  require(approxEq(second.size.x, 60.0), "flex grow should distribute extra main-axis space equally")
  require(approxEq(third.size.x, 60.0), "flex grow should distribute extra main-axis space equally")
  require(approxEq(first.pos.x, 0.0), "first flex child x mismatch")
  require(approxEq(second.pos.x, 70.0), "second flex child x mismatch")
  require(approxEq(third.pos.x, 140.0), "third flex child x mismatch")

proc testFlexHorizontalShrinkDistribution() =
  var b = newTestBuilder(260.0, 120.0)

  var firstIdx = -1
  var secondIdx = -1
  b.node:
    discard b.size(120.0, 70.0)
    discard b.layout(LayoutHorizontal)
    discard b.flexLayout()
    discard b.gap(10.0)

    firstIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 20.0)
      discard b.flex(0.0, 1.0, 80.0)

    secondIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 20.0)
      discard b.flex(0.0, 1.0, 80.0)

  discard b.postProcessChildren(0)
  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]

  require(approxEq(first.size.x, 55.0), "flex shrink should reduce width proportionally")
  require(approxEq(second.size.x, 55.0), "flex shrink should reduce width proportionally")
  require(approxEq(first.pos.x, 0.0), "first shrink child x mismatch")
  require(approxEq(second.pos.x, 65.0), "second shrink child x mismatch")

proc testFlexAlignSelfAndStretch() =
  var b = newTestBuilder(260.0, 120.0)

  var startIdx = -1
  var centerIdx = -1
  var endIdx = -1
  var stretchIdx = -1
  var autoFillIdx = -1
  b.node:
    discard b.size(120.0, 60.0)
    discard b.layout(LayoutHorizontal)
    discard b.flexLayout()

    startIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 10.0)
      discard b.flexAlignSelf(FlexAlignStart)

    centerIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 20.0)
      discard b.flex(0.0, 1.0, 10.0)
      discard b.flexAlignSelf(FlexAlignCenter)

    endIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 15.0)
      discard b.flex(0.0, 1.0, 10.0)
      discard b.flexAlignSelf(FlexAlignEnd)

    stretchIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 5.0)
      discard b.flex(0.0, 1.0, 10.0)
      discard b.flexAlignSelf(FlexAlignStretch)

    autoFillIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 5.0)
      discard b.fillY()
      discard b.flex(0.0, 1.0, 10.0)

  discard b.postProcessChildren(0)
  let startNode = b.nodes[startIdx]
  let centerNode = b.nodes[centerIdx]
  let endNode = b.nodes[endIdx]
  let stretchNode = b.nodes[stretchIdx]
  let autoFillNode = b.nodes[autoFillIdx]

  require(approxEq(startNode.pos.y, 0.0), "flex align-self start should pin to top")
  require(approxEq(centerNode.pos.y, 20.0), "flex align-self center should center on cross-axis")
  require(approxEq(endNode.pos.y, 45.0), "flex align-self end should pin to bottom")
  require(approxEq(stretchNode.pos.y, 0.0), "flex align-self stretch should pin to top")
  require(approxEq(stretchNode.size.y, 60.0), "flex align-self stretch should expand cross-axis size")
  require(approxEq(autoFillNode.pos.y, 0.0), "flex auto align should place FillY child at cross start")
  require(approxEq(autoFillNode.size.y, 60.0), "flex auto align should expand FillY child on cross-axis")

proc testFlexReverseHorizontalPositions() =
  var b = newTestBuilder(260.0, 120.0)

  var firstIdx = -1
  var secondIdx = -1
  var thirdIdx = -1
  b.node:
    discard b.size(100.0, 50.0)
    discard b.layout(LayoutHorizontal)
    discard b.reverseLayout()
    discard b.flexLayout()
    discard b.gap(5.0)

    firstIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 20.0)

    secondIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 20.0)

    thirdIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 20.0)

  discard b.postProcessChildren(0)
  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]
  let third = b.nodes[thirdIdx]
  require(approxEq(first.pos.x, 80.0), "reverse flex first child x mismatch")
  require(approxEq(second.pos.x, 55.0), "reverse flex second child x mismatch")
  require(approxEq(third.pos.x, 30.0), "reverse flex third child x mismatch")

proc testFlexIgnoresAnchorLayoutOnChildren() =
  var b = newTestBuilder(260.0, 120.0)

  var firstIdx = -1
  var anchoredIdx = -1
  var thirdIdx = -1
  b.node:
    discard b.size(100.0, 50.0)
    discard b.layout(LayoutHorizontal)
    discard b.flexLayout()

    firstIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 30.0)

    anchoredIdx = b.nodes.len
    b.node:
      discard b.size(20.0, 10.0)
      discard b.anchorsX(0.5, 0.5)
      discard b.offsetsX(0.0, 0.0)
      discard b.pivotX(0.5)

    thirdIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 10.0)
      discard b.flex(0.0, 1.0, 30.0)

  discard b.postProcessChildren(0)

  let first = b.nodes[firstIdx]
  let anchored = b.nodes[anchoredIdx]
  let third = b.nodes[thirdIdx]

  require(approxEq(first.pos.x, 0.0), "first flex item should start at x=0")
  require(approxEq(anchored.pos.x, 30.0), "anchored flags should be ignored under flex parent")
  require(approxEq(third.pos.x, 50.0), "third child should follow normal flex flow including anchored node")

proc testGridFixedTracksAndPlacement() =
  var b = newTestBuilder(320.0, 180.0)

  var aIdx = -1
  var bIdx = -1
  var cIdx = -1
  b.node:
    discard b.size(200.0, 120.0)
    discard b.gridLayout()
    discard b.gridTemplateColumns([gridPx(40.0), gridPx(50.0), gridPx(60.0)])
    discard b.gridTemplateRows([gridPx(20.0), gridPx(30.0)])
    discard b.gridGaps(5.0, 10.0)

    aIdx = b.nodes.len
    b.node:
      discard b.gridArea(1, 1)

    bIdx = b.nodes.len
    b.node:
      discard b.gridArea(2, 1, 2, 1)

    cIdx = b.nodes.len
    b.node:
      discard b.gridArea(1, 2)

  discard b.postProcessChildren(0)
  let a = b.nodes[aIdx]
  let bb = b.nodes[bIdx]
  let c = b.nodes[cIdx]

  require(approxEq(a.pos.x, 0.0), "grid fixed a pos.x mismatch")
  require(approxEq(a.pos.y, 0.0), "grid fixed a pos.y mismatch")
  require(approxEq(a.size.x, 40.0), "grid fixed a size.x mismatch")
  require(approxEq(a.size.y, 20.0), "grid fixed a size.y mismatch")

  require(approxEq(bb.pos.x, 50.0), "grid fixed b pos.x mismatch")
  require(approxEq(bb.pos.y, 0.0), "grid fixed b pos.y mismatch")
  require(approxEq(bb.size.x, 120.0), "grid fixed b size.x mismatch")
  require(approxEq(bb.size.y, 20.0), "grid fixed b size.y mismatch")

  require(approxEq(c.pos.x, 0.0), "grid fixed c pos.x mismatch")
  require(approxEq(c.pos.y, 25.0), "grid fixed c pos.y mismatch")
  require(approxEq(c.size.x, 40.0), "grid fixed c size.x mismatch")
  require(approxEq(c.size.y, 30.0), "grid fixed c size.y mismatch")

proc testGridFractionTracksAndAutoPlacement() =
  var b = newTestBuilder(320.0, 180.0)

  var firstIdx = -1
  var secondIdx = -1
  var thirdIdx = -1
  b.node:
    discard b.size(200.0, 100.0)
    discard b.gridLayout()
    discard b.gridTemplateColumns([gridFr(1.0), gridFr(2.0)])
    discard b.gridTemplateRows([gridPx(30.0), gridPx(30.0)])
    discard b.gridColumnGap(10.0)

    firstIdx = b.nodes.len
    b.node:
      discard

    secondIdx = b.nodes.len
    b.node:
      discard

    thirdIdx = b.nodes.len
    b.node:
      discard

  discard b.postProcessChildren(0)
  let first = b.nodes[firstIdx]
  let second = b.nodes[secondIdx]
  let third = b.nodes[thirdIdx]

  require(approxEq(first.pos.x, 0.0), "grid fr first pos.x mismatch")
  require(approxEq(first.pos.y, 0.0), "grid fr first pos.y mismatch")
  require(approxEq(first.size.x, 63.3333'f32, 0.01'f32), "grid fr first size.x mismatch")
  require(approxEq(first.size.y, 30.0), "grid fr first size.y mismatch")

  require(approxEq(second.pos.x, 73.3333'f32, 0.01'f32), "grid fr second pos.x mismatch")
  require(approxEq(second.pos.y, 0.0), "grid fr second pos.y mismatch")
  require(approxEq(second.size.x, 126.6667'f32, 0.01'f32), "grid fr second size.x mismatch")
  require(approxEq(second.size.y, 30.0), "grid fr second size.y mismatch")

  require(approxEq(third.pos.x, 0.0), "grid fr third pos.x mismatch")
  require(approxEq(third.pos.y, 30.0), "grid fr third pos.y mismatch")
  require(approxEq(third.size.x, 63.3333'f32, 0.01'f32), "grid fr third size.x mismatch")
  require(approxEq(third.size.y, 30.0), "grid fr third size.y mismatch")

proc testGridSelfAlignment() =
  var b = newTestBuilder(320.0, 180.0)

  var childIdx = -1
  b.node:
    discard b.size(120.0, 80.0)
    discard b.gridLayout()
    discard b.gridTemplateColumns([gridPx(40.0)])
    discard b.gridTemplateRows([gridPx(30.0)])

    childIdx = b.nodes.len
    b.node:
      discard b.size(10.0, 8.0)
      discard b.gridArea(1, 1)
      discard b.gridJustifySelf(FlexAlignCenter)
      discard b.gridAlignSelf(FlexAlignEnd)

  discard b.postProcessChildren(0)
  let child = b.nodes[childIdx]
  require(approxEq(child.pos.x, 15.0), "grid self-alignment pos.x mismatch")
  require(approxEq(child.pos.y, 22.0), "grid self-alignment pos.y mismatch")
  require(approxEq(child.size.x, 10.0), "grid self-alignment size.x mismatch")
  require(approxEq(child.size.y, 8.0), "grid self-alignment size.y mismatch")

proc testGridFillStretchesWithinCell() =
  var b = newTestBuilder(320.0, 180.0)

  var childIdx = -1
  b.node:
    discard b.size(120.0, 80.0)
    discard b.gridLayout()
    discard b.gridTemplateColumns([gridPx(70.0)])
    discard b.gridTemplateRows([gridPx(35.0)])

    childIdx = b.nodes.len
    b.node:
      discard b.size(5.0, 6.0)
      discard b.fillX().fillY()

  discard b.postProcessChildren(0)
  let child = b.nodes[childIdx]
  require(approxEq(child.pos.x, 0.0), "grid fill stretch pos.x mismatch")
  require(approxEq(child.pos.y, 0.0), "grid fill stretch pos.y mismatch")
  require(approxEq(child.size.x, 70.0), "grid fill stretch size.x mismatch")
  require(approxEq(child.size.y, 35.0), "grid fill stretch size.y mismatch")

proc testRenderTransformDoesNotAffectLayout() =
  var b = newTestBuilder(240.0, 120.0)

  let parentIdx = b.nodes.len
  b.node:
    discard b.layout(LayoutVertical)
    discard b.gap(5.0)
    discard b.size(100.0, 60.0)
    discard b.transformOffset(20.0, 10.0)
    discard b.transformRotation(0.8'f32)
    discard b.transformScale(1.5, 0.75)

    b.node:
      discard b.size(30.0, 10.0)

    b.node:
      discard b.size(30.0, 10.0)

  discard b.postProcessChildren(0)
  let parent = b.nodes[parentIdx]
  let firstChild = b.nodes[parentIdx + 1]
  let secondChild = b.nodes[parentIdx + 2]

  require(approxEq(parent.size.x, 100.0), "render transform should not change parent layout width")
  require(approxEq(parent.size.y, 60.0), "render transform should not change parent layout height")
  require(approxEq(firstChild.pos.x, 0.0), "render transform should not change child layout x")
  require(approxEq(firstChild.pos.y, 0.0), "render transform should not change first child layout y")
  require(approxEq(secondChild.pos.y, 15.0), "render transform should not change second child layout y")

proc testRenderTransformAppliesToSubtreeCommands() =
  var b = newTestBuilder(200.0, 120.0)

  var parentIdx = -1
  var childIdx = -1

  b.node:
    parentIdx = b.stack[^1]
    discard b.size(40.0, 24.0)
    discard b.padding(2.0)
    discard b.fillBackground()
    discard b.backgroundColor(rgba(0.30, 0.40, 0.50, 1.0))
    discard b.transformOffset(10.0, 5.0)

    b.node:
      childIdx = b.stack[^1]
      discard b.size(12.0, 8.0)
      discard b.fillBackground()
      discard b.backgroundColor(rgba(0.70, 0.30, 0.20, 1.0))

  b.endUiFrame()

  var parentFound = false
  var childFound = false
  for cmd in b.frameOutput.commands:
    if cmd.kind == CmdRectFill and cmd.nodeIndex == parentIdx:
      parentFound = true
      require(approxEq(cmd.pos.x, 0.0), "frame command positions should remain raw before render-time transform")
      require(approxEq(cmd.pos.y, 0.0), "frame command positions should remain raw before render-time transform")
    if cmd.kind == CmdRectFill and cmd.nodeIndex == childIdx:
      childFound = true
      require(approxEq(cmd.pos.x, 2.0), "child frame command x should stay in layout-space before render-time transform")
      require(approxEq(cmd.pos.y, 2.0), "child frame command y should stay in layout-space before render-time transform")

  require(parentFound, "expected transformed parent fill command")
  require(childFound, "expected transformed child fill command")

proc testRenderTransformIsAnimatable() =
  var b = newBuilder(fixedMeasureText)
  var nodeId = noneNodeId()

  discard b.beginUiFrame(200.0, 120.0)
  b.node("anim-transform"):
    nodeId = b.currentNode.id
    discard b.size(12.0, 10.0)
    discard b.fillBackground()
    discard b.backgroundColor(rgba(0.50, 0.40, 0.30, 1.0))
    b.animate:
      discard b.transformOffsetAnim(0.0, 0.0)
  b.endUiFrame()

  var firstOffsetX = 0.0'f32
  var firstFound = false
  for i in 0 ..< b.nodes.len:
    if b.nodes[i].id == nodeId:
      firstOffsetX = b.frame.transforms[b.nodes[i].transformIndex - 1].offset.x
      firstFound = true
      break
  require(firstFound, "expected first-frame transform state for animated node")

  discard b.beginUiFrame(200.0, 120.0)
  b.node("anim-transform"):
    discard b.size(12.0, 10.0)
    discard b.fillBackground()
    discard b.backgroundColor(rgba(0.50, 0.40, 0.30, 1.0))
    b.animate:
      discard b.transformOffsetAnim(20.0, 0.0)
  b.endUiFrame()

  var secondOffsetX = 0.0'f32
  var secondFound = false
  for i in 0 ..< b.nodes.len:
    if b.nodes[i].id == nodeId:
      secondOffsetX = b.frame.transforms[b.nodes[i].transformIndex - 1].offset.x
      secondFound = true
      break
  require(secondFound, "expected second-frame transform state for animated node")

  require(secondOffsetX > firstOffsetX, "animated transform offset should progress toward target")
  require(secondOffsetX < firstOffsetX + 20.0'f32, "animated transform offset should blend toward target")

proc testTreeTableTreeTexts() =
  # Build a 3-deep tree (levels 0..3) with 2 children per node => 15 nodes.
  let maxDepth = 3
  let branching = 2
  var b = newTestBuilder(800.0, 800.0)

  b.node:
    discard b.size(800.0, 800.0)
    var cursor = newTreeCursor(maxDepth, branching)
    # Pre-expand the whole tree by attaching an already-expanded editor storage.
    var storage = newTreeTable(cursor)
    storage.initialized = true
    expandAll(storage)
    b.nodeStorage(b.currentNode, storage)
    proc renderRow(b: var UiBuilder, cursor: TreeCursor, index: int) {.gcsafe, raises: [], nimcall.} =
      b.label(cursor.fieldName & ":"):
        discard b.fitX().fitY()
      b.node:
        b.debugName("tree-table-row-overlay")
        discard b.anchors(0.0, 0.0, 1.0, 0.0)
          .offsets(0.0, -50.0, 0.0, 50.0)
          .finishAnchors()
          .ignoreInContentExtent()

    b.treeTable(cursor, renderRow)

  # The virtual list builds its rows in a deferred pass.
  b.flushDeferredNodes()

  # Collect every tree-name label (texts ending with ':').
  var foundNames: seq[string] = @[]
  for i in 0 ..< b.frame.texts.len:
    let t = b.frame.texts[i].text.value
    if t.len > 0 and t[^1] == ':':
      foundNames.add(t[0 .. ^2])

  let expected = expectedTreeNames(maxDepth, branching)
  require(foundNames.len == expected.len, "expected " & $expected.len & " tree names, got " & $foundNames.len)
  for e in expected:
    require(e in foundNames, "missing tree name: " & e)

  # The first row is the root: verify its children are laid out as columns
  # (left-to-right, strictly increasing x) and the row height fits the columns.
  var rowNodeIdx = -1
  for i in 0 ..< b.nodes.len:
    if b.nodes[i].nodeDebugName() == "tree-table-row":
      rowNodeIdx = i
      break
  if rowNodeIdx < 0:
    for i in 0 ..< b.nodes.len:
      let textIndex = b.nodes[i].textIndex.int
      if textIndex > 0 and b.frame.texts[textIndex - 1].text.value == "root:":
        rowNodeIdx = b.nodes[i].parent.int
        break
  require(rowNodeIdx >= 0, "expected at least one tree row node")

  var colXs: seq[float32] = @[]
  var colHeights: seq[float32] = @[]
  var overlayFound = false
  for childIdx in b.children(rowNodeIdx):
    let child = b.nodes[childIdx].addr
    if AnchorX in child.flags or AnchorY in child.flags:
      overlayFound = true
      require(IgnoreInContentExtent in child.flags,
        "tree-table overlay must be excluded from row content extent")
    else:
      colXs.add(child.pos.x)
      colHeights.add(child.size.y)
  require(overlayFound, "expected an anchored direct-row overlay")
  require(colXs.len == 2, "expected 2 columns per row (symbol, name), got " & $colXs.len)
  for i in 1 ..< colXs.len:
    require(colXs[i] > colXs[i - 1] - 0.5, "columns must be laid out left-to-right")
  let rowH = b.nodes[rowNodeIdx].size.y
  require(rowH < 100.0, "anchored overlay must not affect tree-table row fit")
  for h in colHeights:
    require(rowH >= h - 0.5, "row height should encompass its columns")

  # Cross-row alignment: every row's columns must start at the same x (table style),
  # so columns line up vertically regardless of row content.
  var firstRowCols: seq[float32] = @[]
  for i in 0 ..< b.nodes.len:
    if b.nodes[i].nodeDebugName() == "property-row":
      var xs: seq[float32] = @[]
      for childIdx in b.children(i):
        xs.add(b.nodes[childIdx].pos.x)
      if firstRowCols.len == 0:
        firstRowCols = xs
      else:
        require(xs.len == firstRowCols.len, "all rows must have the same number of columns")
        for k in 0 ..< xs.len:
          require(approxEq(xs[k], firstRowCols[k], 0.5), "column " & $k & " x must align across rows")

proc testTerminalTreeTableExpandSymbols() =
  var b = newBuilder(fixedTerminalMeasureText, textHeight = 1.0'f32,
    backendType = UiBackendType.Terminal)
  discard b.beginUiFrame(80.0'f32, 24.0'f32)
  b.node:
    discard b.fill()
    let cursor = newTreeCursor(2, 2)
    proc renderRow(b: var UiBuilder, cursor: TreeCursor, index: int) {.gcsafe, raises: [], nimcall.} =
      b.label(cursor.fieldName):
        discard b.fit()
    b.treeTable(cursor, renderRow)
  b.flushDeferredNodes()

  var expandedSymbols = 0
  var collapsedSymbols = 0
  var symbolNodes = 0
  for node in b.nodes:
    let textIndex = node.textIndex.int - 1
    if textIndex >= 0 and textIndex < b.frame.texts.len and
        b.frame.texts[textIndex].text.value in ["▸", "▾"]:
      inc symbolNodes
      require(node.size == vec2(1.0'f32, 1.0'f32),
        "terminal tree table symbols should be explicitly one cell by one cell")
  require(symbolNodes >= 1, "expected a terminal tree table symbol node")
  for text in b.frame.texts:
    if text.text.value == "▾":
      inc expandedSymbols
    elif text.text.value == "▸":
      inc collapsedSymbols
  require(expandedSymbols == 1,
    "terminal tree table should render the expanded root with a down symbol")

  var hiddenRootBuilder = newBuilder(fixedTerminalMeasureText, textHeight = 1.0'f32,
    backendType = UiBackendType.Terminal)
  discard hiddenRootBuilder.beginUiFrame(80.0'f32, 24.0'f32)
  hiddenRootBuilder.node:
    discard hiddenRootBuilder.fill()
    let hiddenCursor = newTreeCursor(2, 2)
    var options = defaultTreeTableOptions()
    options.hideRoot = true
    proc renderHiddenRow(b: var UiBuilder, cursor: TreeCursor, index: int) {.gcsafe, raises: [], nimcall.} =
      b.label(cursor.fieldName):
        discard b.fit()
    hiddenRootBuilder.treeTable(hiddenCursor, options, renderHiddenRow)
  hiddenRootBuilder.flushDeferredNodes()
  for text in hiddenRootBuilder.frame.texts:
    if text.text.value == "▸":
      inc collapsedSymbols
  require(collapsedSymbols >= 1,
    "terminal tree table should render collapsed children with right symbols")

proc runTests() =
  testFlagsAndMutators()
  testPlotHoverLabels()
  testHighlightedText()
  testTextWrappingUsesNodeWidthOnlyWhenEnabled()
  testPositionAndSizeScalars()
  testBaseFontRelativePadding()
  testBaseFontRelativeSize()
  testTerminalCatalogWidgetsAreOneRowHigh()
  testVerticalLayoutTextSizing()
  testHorizontalLayoutTextSizing()
  testAlignCenterVerticalCrossAxis()
  testAlignCenterHorizontalCrossAxis()
  testAlignCenterWithoutLayout()
  testStandaloneFitOnEndNode()
  testParentFitIncludesChildren()
  testParentFitIgnoresFlaggedChildExtent()
  testParentFitIncludesChildren2()
  testHorizontalFitYWithNestedFillYPropagation()
  testImmediateFillXAndFillY()
  testImmediateFillRespectsChildPosition()
  testPostProcessFillRespectsChildPosition()
  testPostProcessFillPropagatesKnownParentAxes()
  testReverseVerticalFillXUsesContentWidth()
  testMinMaxSizeClamping()
  testPaddingOffsetsChildWithoutLayout()
  testCustomRenderCommandsInjection()
  testCustomRenderCommandsSupportsTwoFrameLifetime()
  testArenaResizeArrayView()
  testStableExplicitIdsAcrossFrames()
  testPushPopIdScopes()
  # testButtonHoverAndPressed()
  testPressAndReleaseWithinOneFrame()
  testSameFrameClickUsesCurrentPressTarget()
  testSeparateFrameMouseClickTargets()
  testSameFrameClickPreservesFinalDownState()
  testSameFrameClickOutsideUi()
  testMouseDragReleaseStillReported()
  testHitBoundsExcludeBottomEdge()
  testTerminalScrollBoxContentHasNoPadding()
  testTerminalScrollBoxUsesCellScrollbar()
  testHoveredNodeIndexAndDebugTooltip()
  # testSliderClickUpdatesValue()
  testTerminalDropdownPopupAnchorsBelowButton()
  testPreviousNodesAndIndicesDoubleBuffered()
  testDragUiCallbackAndDropState()
  testExternalDragAndDrop()
  testFileSystemCursorDragAndDrop()
  testReverseVerticalLayoutAllCombinations()
  testReverseHorizontalLayoutAllCombinations()
  testReverseVerticalParentFitRepositions()
  testReverseHorizontalParentFitRepositions()
  testAnchoredLayoutPivotPositioning()
  testAnchoredLayoutStretchUsesAnchorOffsets()
  testAnchoredLayoutTriggersParentPostProcessForFit()
  testAnchoredLayoutAxisSpecificMutators()
  testFlexHorizontalGrowDistribution()
  testFlexHorizontalShrinkDistribution()
  testFlexAlignSelfAndStretch()
  testFlexReverseHorizontalPositions()
  testFlexIgnoresAnchorLayoutOnChildren()
  # testGridFixedTracksAndPlacement()
  # testGridFractionTracksAndAutoPlacement()
  # testGridSelfAlignment()
  # testGridFillStretchesWithinCell()
  testRenderTransformDoesNotAffectLayout()
  testRenderTransformAppliesToSubtreeCommands()
  testRenderTransformIsAnimatable()
  testTreeTableTreeTexts()
  testTerminalTreeTableExpandSymbols()

proc testNamedThemeStyles() =
  var builder = newBuilder(fixedMeasureText)
  require(builder.themeStyleIndex("panel-active") == UiStyleIndexPanelActive.uint16,
    "active view surface should be registered by name")
  require(builder.themeStyleIndex("header-active") == UiStyleIndexHeaderActive.uint16,
    "active view header should be registered by name")
  for (base, active) in [(UiStyleIndexPanel, UiStyleIndexPanelActive),
      (UiStyleIndexHeader, UiStyleIndexHeaderActive)]:
    require(builder.themeStyle(base)[].paddingX == builder.themeStyle(active)[].paddingX,
      "active view styles should preserve base metrics")
    require(builder.themeStyle(base)[].fillColor != builder.themeStyle(active)[].fillColor,
      "active view styles should have distinct defaults")
  let (palette, _) = createThemeFromColor(rgba(0.2'f32, 0.4'f32, 0.6'f32, 1))
  require(palette[UiStyleIndexPanelActive.int - 1].fillColor !=
      builder.themeStyle(UiStyleIndexPanelActive)[].fillColor,
    "primary-color palette should initialize active surfaces")
  require(palette[UiStyleIndexHeaderActive.int - 1].fillColor !=
      builder.themeStyle(UiStyleIndexHeaderActive)[].fillColor,
    "primary-color palette should initialize active headers")
  require(builder.themeStyleIndex("scrollbar-handle") == UiStyleIndexScrollBarHandle.uint16,
    "built-in widget names should use kebab case with scrollbar as one word")
  require(builder.themeTextStyleIndex("default-mono") == UiStyleIndexDefaultMono.uint16,
    "built-in text names should be registered")
  for index in UiStyleIndexDefault .. UiStyleIndex.high:
    var found = false
    for name, slot in builder.themeStyleIndices.pairs:
      if slot == index.uint16:
        found = true
    require(found, "every built-in widget slot should have a name")
  for index in UiStyleIndexDefaultText .. UiTextStyleIndex.high:
    var found = false
    for name, slot in builder.themeTextStyleIndices.pairs:
      if slot == index.uint16:
        found = true
    require(found, "every built-in text slot should have a name")

  let widgetCount = builder.themeStyles.len
  let textCount = builder.themeTextStyles.len
  let tint = rgba(0.2'f32, 0.3'f32, 0.4'f32, 0.5'f32)
  discard builder.setThemeStyle("custom", UiStyle(fillColor: tint, paddingX: 7))
  discard builder.setThemeTextStyle("custom", UiNodeText(textColor: tint, fontSize: 19))
  let widgetIndex = builder.themeStyleIndex("custom")
  let textIndex = builder.themeTextStyleIndex("custom")
  require(widgetIndex.int == widgetCount + 1 and textIndex.int == textCount + 1,
    "custom widget and text names should allocate independent slots")
  discard builder.setThemeStyle("custom", UiStyle(fillColor: tint, paddingX: 9))
  discard builder.setThemeTextStyle("custom", UiNodeText(textColor: tint, fontSize: 21))
  require(builder.themeStyles.len == widgetCount + 1 and builder.themeTextStyles.len == textCount + 1,
    "updating a named style should reuse its slot")
  discard builder.setThemeStyleIndex("alias", widgetIndex)
  discard builder.setThemeTextStyleIndex("alias", textIndex)
  require(builder.themeStyle("alias")[].paddingX == 9, "widget aliases should resolve")
  require(builder.themeTextStyle("alias")[].fontSize == 21, "text aliases should resolve")
  discard builder.setThemeStyleIndex("builtin-alias", UiStyleIndexPanel)
  discard builder.setThemeTextStyleIndex("builtin-alias", UiStyleIndexDefaultText)

  for frame in 0 .. 1:
    discard builder.beginUiFrame(100.0'f32, 100.0'f32)
    builder.node:
      discard builder.fit().styleIndex("alias").textStyleIndex("alias")
      require(builder.currentNode.styleIndex == widgetIndex, "named widget setter should select slot")
      require(builder.currentNode.textIndex == textIndex, "named text setter should select slot")
      builder.setCurrentNodeStyleIndex("custom")
      builder.setCurrentNodeTextIndex("custom")
      discard builder.text("named")
      require(builder.nodeStyle(builder.currentNode)[].paddingX == 9, "named widget style should render")
      require(builder.nodeText(builder.currentNode)[].fontSize == 21, "named text style should render")
    builder.node:
      discard builder.fit().copyStyleIndex("custom").copyTextStyleIndex("custom").text("copied")
      require(builder.nodeStyle(builder.currentNode)[].paddingX == 9, "named style copy should preserve metrics")
      require(builder.nodeText(builder.currentNode)[].fontSize == 21, "named text copy should preserve metrics")
    builder.endUiFrame()
  discard builder.setThemeStyleIndex("alias", UiStyleIndexHeader)
  discard builder.setThemeTextStyleIndex("alias", UiStyleIndexHeaderText)
  require(builder.themeStyleIndex("alias") == UiStyleIndexHeader.uint16, "widget aliases may be rebound")
  require(builder.themeTextStyleIndex("alias") == UiStyleIndexHeaderText.uint16, "text aliases may be rebound")
  var separate = newBuilder(fixedMeasureText)
  require(not separate.themeStyleIndices.hasKey("custom"), "name tables should be builder-local")
  require(not separate.themeTextStyleIndices.hasKey("custom"), "text name tables should be builder-local")
  discard separate.setThemeStyle("default", UiStyle(paddingX: 13))
  discard separate.setThemeTextStyle("default-text", UiNodeText(fontSize: 27))
  require(separate.defaultStyle.paddingX == 13, "named default setter should update defaultStyle")
  require(separate.defaultText.fontSize == 27, "named default text setter should update defaultText")

when defined(nuigiProfiler):
  proc testProfiler() =
    profilerAccess:
      gprof.record = true
      gprof.frameStart = eventHistoryIndex
      let first = eventHistoryIndex
      block:
        prof("profiler-test")
        block:
          profd("dynamic-" & $first)
      require(eventHistoryIndex == first + 4, "profiler should record nested begin/end events")
      require((eventHistory[first].timestamp and TimestampEndBit) == 0, "begin timestamp must not have end bit")
      require((eventHistory[first + 3].timestamp and TimestampEndBit) != 0, "end timestamp must have end bit")
      require(eventHistory[first + 3].location.tag == "profiler-test", "scope end must retain tag")
      gprof.frameStart = eventHistoryIndex
      var frameCount = 0
      for (index, depth, frame) in profileFrames():
        require(frame.last >= frame.first, "profile duration must be nonnegative")
        inc frameCount
      require(frameCount == 2, "profiler should reconstruct nested scopes")
      gprof.record = false
      let paused = eventHistoryIndex
      block:
        prof("paused")
      require(eventHistoryIndex == paused, "paused profiler must not record")
      gprof.record = true
      gprof.frameStart = eventHistoryIndex
      profilerBeginFrame(false)
      var profilerBuilder = newTestBuilder(900, 900)
      discard profilerBuilder.beginUiFrame(900, 900)
      profilerBuilder.buildNuiProfiler()
      profilerBuilder.endUiFrame()
      require(profilerBuilder.frame.nodes.len > 1, "profiler UI must build controls and graphs")
      gprof.record = false
      echo "Profiler recording and UI tests passed"


proc testSemantics() =
  # Semantic accessibility metadata (docs/accessibility.md): setters fill the
  # per-frame side array, readers expose it, extraction carries it along.
  var b = newTestBuilder(400, 400)
  discard b.beginUiFrame(400, 400)
  discard b.semanticRole(SemanticWindow)
  discard b.semanticLabel("Root Window")
  var labelId = noneNodeId()
  var checkboxIdx = -1
  var sliderIdx = -1
  var plainIdx = -1
  b.node("semantics-label"):
    discard b.size(50, 10)
    discard b.text("Mute")
    labelId = b.currentNode.id
  b.node("semantics-checkbox"):
    discard b.size(10, 10)
    discard b.semanticRole(SemanticCheckBox)
    discard b.semanticState({SemanticChecked, SemanticDisabled})
    discard b.semanticLabelledBy(labelId)
    checkboxIdx = b.currentNodeIndex()
  b.node("semantics-slider"):
    discard b.size(100, 10)
    discard b.semanticRole(SemanticSlider)
    discard b.semanticValue(0.25'f32, 0.0'f32, 1.0'f32, 0.05'f32)
    discard b.semanticValueText("25 %")
    sliderIdx = b.currentNodeIndex()
  b.node("semantics-plain"):
    discard b.size(10, 10)
    plainIdx = b.currentNodeIndex()
  b.endUiFrame(buildRenderCommands = false)

  let rootSemantics = b.nodeSemantics(0)
  require(rootSemantics != nil, "root should carry semantics")
  require(rootSemantics.role == SemanticWindow, "root role should be Window")
  require($rootSemantics.label == "Root Window", "root label should be set")

  let checkboxSemantics = b.nodeSemantics(checkboxIdx)
  require(checkboxSemantics != nil, "checkbox should carry semantics")
  require(checkboxSemantics.role == SemanticCheckBox,
    "checkbox role should be CheckBox")
  require(SemanticChecked in checkboxSemantics.states and
    SemanticDisabled in checkboxSemantics.states,
    "checkbox states should accumulate")
  require(checkboxSemantics.labelledBy == labelId,
    "labelledBy should reference the label node")
  require(not checkboxSemantics.hasNumericValue,
    "checkbox should not report a numeric value")

  let sliderSemantics = b.nodeSemantics(sliderIdx)
  require(sliderSemantics != nil, "slider should carry semantics")
  require(sliderSemantics.hasNumericValue, "slider should have a numeric value")
  require(approxEq(sliderSemantics.numericValue, 0.25'f32) and
    approxEq(sliderSemantics.numericMin, 0.0'f32) and
    approxEq(sliderSemantics.numericMax, 1.0'f32) and
    approxEq(sliderSemantics.numericStep, 0.05'f32),
    "slider numeric value and range should be stored")
  require($sliderSemantics.valueText == "25 %",
    "slider value text should be stored")

  require(b.nodeSemantics(plainIdx) == nil,
    "unannotated node should have no semantics")
  require(b.nodeSemantics(-1) == nil and b.nodeSemantics(999999) == nil,
    "out-of-range indices should have no semantics")

  # Virtual-tree roundtrip: semantics are extracted with the subtree and the
  # node's index is rebased into the local side array.
  let extracted = extractVirtualTree(b.frame, checkboxIdx)
  require(extracted.nodes.len == 1,
    "extracted subtree should contain the checkbox node")
  require(extracted.semantics.len == 1,
    "extracted subtree should carry its semantics")
  require(extracted.nodes[0].semanticsIndex == 1,
    "extracted semantics index should be rebased")
  require(extracted.semantics[0].role == SemanticCheckBox and
    extracted.semantics[0].labelledBy == labelId,
    "extracted semantics should match the original")
  echo "Semantics metadata tests passed"


when isMainModule:
  if paramCount() > 0:
    var builder = newBuilder(fixedMeasureText)
    case paramStr(1)
    of "--unknown-style": discard builder.styleIndex("missing")
    of "--unknown-text-style": discard builder.textStyleIndex("missing")
    of "--invalid-style-slot": discard builder.setThemeStyleIndex("invalid", 0'u16)
    of "--invalid-text-slot": discard builder.setThemeTextStyleIndex("invalid", high(uint16))
    of "--empty-style-name": discard builder.setThemeStyle("", UiStyle())
    of "--empty-text-name": discard builder.setThemeTextStyle("", UiNodeText())
    else: quit "Unknown core test argument"
    quit "Expected named theme API to reject invalid input"
  testNamedThemeStyles()
  runTests()
  testSemantics()
  when defined(nuigiProfiler):
    testProfiler()

# Intentionally no endUiFrame/render calls here: tests validate flags/layout only,
# without generating render commands yet.
