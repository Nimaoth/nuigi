## Glue between Nuigi and AccessKit (https://accesskit.dev/), enabled by
## compiling with -d:nuiAccessKit. Owns the platform adapter and translates
## the current Nuigi frame into AccessKit tree updates. Hosts (such as
## sdl3_app.nim) hand the native window handle and the builder to `init`,
## call `update` once per built frame (after `endUiFrame`, so layout is
## resolved), and `deinit` on shutdown.
##
## Tree mapping (see docs/accessibility.md):
## - Only semantically meaningful nodes appear in the tree: nodes with
##   `UiSemantics`, focus items, text nodes, scrollables and the frame root.
##   Children of excluded nodes are promoted to the nearest included
##   ancestor; `semanticHidden` prunes whole subtrees.
## - Roles, states (checked/expanded/disabled/...), textual and numeric
##   values come from `UiSemantics`; unannotated focusable nodes fall back
##   to Button/TextInput based on their focus flags.
## - The accessible name follows the precedence: explicit `semanticLabel`,
##   text of the `semanticLabelledBy` node, the node's own text, the text of
##   a dedicated descendant label. Descendant labels are merged into the
##   control and removed from the tree; non-descendant `labelledBy` targets
##   stay and are linked via the AccessKit `labelled_by` relation.
## - Stable `UiNodeId`s are reused as AccessKit node ids (duplicate ids keep
##   their first occurrence, id-less nodes get a synthetic id from their
##   frame index); bounds are absolute viewport pixels; the AccessKit focus
##   follows `UiBuilder.focusedNode`.
## Actions are queued and consumed by widgets during the next actual build.

when not defined(windows):
  {.error: "-d:nuiAccessKit is currently only supported on Windows".}

when defined(nimony):
  {.feature: "lenientnils".}

import std/[tables, locks]
from std/parseutils import parseFloat
import nuigi/util/pointer_queue
import nuigi
import nuigi/core/vecmath
import nuigi/backend/accesskit/accesskit

include nuigi/util/compat2

{.push gcsafe, raises: [].}

type
  ActionContext = object
    queue: PointerQueue
    diagnosticLock: Lock
    overflow: int
    publishedVersion: uint64
  ActionEnvelope = object
    request: ptr AccessKitActionRequest
    version: uint64
  ActionRoute = object
    target: UiNodeId
    actions: UiSemanticActions
    generation: uint64
  NuigiAccessKit* = object
    error*: string
      ## Why `init` failed, if it returned false.
    builder: ptr UiBuilder
    actions: ptr ActionContext
    routes: Table[uint64, ActionRoute]
    treeId: AccessKitTreeId
    nextGeneration: uint64
    when defined(windows):
      adapter: ptr AccessKitWindowsSubclassingAdapter

  TreeBuildContext = object
    builder: ptr UiBuilder
    update: ptr AccessKitTreeUpdate
    focusFlags: Table[uint64, UiFocusFlags]
    visited: Table[uint64, bool]
    consumed: seq[bool]
      ## Per node index: the node's text was merged into a control's
      ## accessible name, so the node itself is excluded from the tree.
    nameSource: Table[int, int]
    owner: ptr NuigiAccessKit
    routes: Table[uint64, ActionRoute]
      ## Control node index -> descendant text node index used as its name.

const fallbackRootId = AccessKitNodeId(1)

proc actionCalloc(count, size: csize_t): pointer {.importc: "calloc", header: "<stdlib.h>".}
proc actionFree(data: pointer) {.importc: "free", header: "<stdlib.h>".}

proc routableActions(b: ptr UiBuilder, idx: int): UiSemanticActions =
  result = {}
  let sem = b[].nodeSemantics(idx)
  if sem != nil:
    result = sem.actions
  for item in b.frame.focusItems:
    if item.nodeIndex == idx and FocusDisabled notin item.flags:
      result.incl SemanticFocus
  for action in SemanticFocus .. SemanticSelect:
    if action in result and not b[].semanticActionAllowed(idx, action):
      result.excl action
  if b.frame.nodes[idx].id == UiNodeId(0):
    result = {}

const labelConsumingRoles = {
  SemanticButton, SemanticCheckBox, SemanticRadioButton, SemanticSwitch,
  SemanticSlider, SemanticSpinButton, SemanticProgressIndicator,
  SemanticTextInput, SemanticMultilineTextInput, SemanticComboBox,
  SemanticTab, SemanticMenuItem, SemanticTreeItem, SemanticListItem}
  ## Roles whose accessible name may be taken from a dedicated label inside
  ## the control (which is then removed from the tree).

proc accessKitNodeId(b: ptr UiBuilder, idx: int): AccessKitNodeId =
  ## AccessKit node ids reuse Nuigi's stable node ids so assistive
  ## technology keeps referring to the same node across frames. The rare
  ## id-less node gets a synthetic id derived from its frame index.
  let id = uint64(b.frame.nodes[idx].id)
  if id == 0:
    AccessKitNodeId(0x8000000000000000'u64 or uint64(idx))
  else:
    AccessKitNodeId(id)

proc nodeIndexOf(b: ptr UiBuilder, id: UiNodeId): int =
  b[].nodeIndex(id)

proc hasOwnText(b: ptr UiBuilder, idx: int): bool =
  if DrawText notin b.frame.nodes[idx].flags:
    return false
  let slot = int(b.frame.nodes[idx].textIndex)
  slot > 0 and slot <= b.frame.texts.len and
    b.frame.texts[slot - 1].text.len > 0

proc nodeTextValue(b: ptr UiBuilder, idx: int): string =
  ## Owned copy of the node's text ("" if none).
  let slot = int(b.frame.nodes[idx].textIndex)
  if slot > 0 and slot <= b.frame.texts.len:
    value(b.frame.texts[slot - 1].text)
  else:
    ""

proc isDescendantOf(b: ptr UiBuilder, idx, ancestorIdx: int): bool =
  var current = int(b.frame.nodes[idx].parent)
  while current >= 0 and current < b.frame.nodes.len:
    if current == ancestorIdx:
      return true
    current = int(b.frame.nodes[current].parent)
  false

proc isFocusable(ctx: TreeBuildContext, idx: int): bool =
  ctx.focusFlags.contains(uint64(ctx.builder.frame.nodes[idx].id))

proc isHiddenSubtree(sem: ptr UiSemantics): bool =
  sem != nil and SemanticHideSubtree in sem.states

proc findDescendantLabel(ctx: TreeBuildContext, idx: int): int =
  ## First descendant text node usable as the control's accessible name, in
  ## build order; -1 if none. Does not descend into nodes that are elements
  ## of their own (annotated or focusable) or hidden subtrees.
  let b = ctx.builder
  for childIdx in b[].children(idx):
    let sem = b[].nodeSemantics(childIdx)
    if sem != nil or ctx.isFocusable(childIdx):
      continue
    if b.hasOwnText(childIdx):
      return childIdx
    let found = ctx.findDescendantLabel(childIdx)
    if found >= 0:
      return found
  -1

proc computeNameSources(ctx: var TreeBuildContext) =
  ## Pre-pass: decide which text nodes are merged into a control's name
  ## (and therefore excluded from the tree). Runs before the main walk
  ## because labels can appear before or after their control in build order.
  let b = ctx.builder
  ctx.consumed = newSeq[bool](b.frame.nodes.len)
  for idx in 0 ..< b.frame.nodes.len:
    let sem = b[].nodeSemantics(idx)
    let focusable = ctx.isFocusable(idx)
    let consuming =
      if sem != nil:
        sem.role in labelConsumingRoles or
          (sem.role == SemanticNone and focusable)
      else:
        focusable
    if not consuming:
      continue
    if sem != nil:
      if sem.label.len > 0:
        continue
      if uint64(sem.labelledBy) != 0:
        let labelIdx = b.nodeIndexOf(sem.labelledBy)
        # Merge only dedicated, unannotated labels inside the control;
        # external or explicitly annotated labels stay in the tree.
        if labelIdx >= 0 and b[].nodeSemantics(labelIdx) == nil and
            b.isDescendantOf(labelIdx, idx):
          ctx.consumed[labelIdx] = true
        continue
    if b.hasOwnText(idx):
      continue
    let found = ctx.findDescendantLabel(idx)
    if found >= 0:
      ctx.consumed[found] = true
      ctx.nameSource[idx] = found

proc remainsInTree(ctx: TreeBuildContext, idx: int): bool =
  ## Whether the main walk will create an AccessKit node for `idx`. Used to
  ## decide if a `labelled_by` relation may safely reference it.
  let b = ctx.builder
  if idx < ctx.consumed.len and ctx.consumed[idx]:
    return false
  let sem = b[].nodeSemantics(idx)
  if sem.isHiddenSubtree:
    return false
  if idx != 0 and sem == nil and not ctx.isFocusable(idx) and
      Scrollable notin b.frame.nodes[idx].flags and not b.hasOwnText(idx):
    return false
  var current = int(b.frame.nodes[idx].parent)
  while current >= 0 and current < b.frame.nodes.len:
    if b[].nodeSemantics(current).isHiddenSubtree:
      return false
    current = int(b.frame.nodes[current].parent)
  true

proc mapRole(role: UiSemanticRole): AccessKitRole =
  case role
  of SemanticNone: ROLE_GENERIC_CONTAINER
  of SemanticGroup: ROLE_GROUP
  of SemanticWindow: ROLE_WINDOW
  of SemanticDialog: ROLE_DIALOG
  of SemanticTooltip: ROLE_TOOLTIP
  of SemanticTitleBar: ROLE_TITLE_BAR
  of SemanticLabel: ROLE_LABEL
  of SemanticButton: ROLE_BUTTON
  of SemanticCheckBox: ROLE_CHECK_BOX
  of SemanticRadioButton: ROLE_RADIO_BUTTON
  of SemanticSwitch: ROLE_SWITCH
  of SemanticSlider: ROLE_SLIDER
  of SemanticSpinButton: ROLE_SPIN_BUTTON
  of SemanticProgressIndicator: ROLE_PROGRESS_INDICATOR
  of SemanticTextInput: ROLE_TEXT_INPUT
  of SemanticMultilineTextInput: ROLE_MULTILINE_TEXT_INPUT
  of SemanticComboBox: ROLE_COMBO_BOX
  of SemanticListBox: ROLE_LIST_BOX
  of SemanticListItem: ROLE_LIST_ITEM
  of SemanticTabList: ROLE_TAB_LIST
  of SemanticTab: ROLE_TAB
  of SemanticTabPanel: ROLE_TAB_PANEL
  of SemanticTree: ROLE_TREE
  of SemanticTreeItem: ROLE_TREE_ITEM
  of SemanticTable: ROLE_TABLE
  of SemanticRow: ROLE_ROW
  of SemanticCell: ROLE_CELL
  of SemanticColumnHeader: ROLE_COLUMN_HEADER
  of SemanticMenu: ROLE_MENU
  of SemanticMenuBar: ROLE_MENU_BAR
  of SemanticMenuItem: ROLE_MENU_ITEM
  of SemanticScrollView: ROLE_SCROLL_VIEW
  of SemanticImage: ROLE_IMAGE
  of SemanticCanvas: ROLE_CANVAS

proc addSubtree(ctx: var TreeBuildContext, idx: int, origin: Vec2,
    siblings: var seq[AccessKitNodeId]) =
  let b = ctx.builder
  let sem = b[].nodeSemantics(idx)
  if sem.isHiddenSubtree:
    return

  let pos = origin + b.frame.nodes[idx].pos
  var childOrigin = pos
  if b.frame.nodes[idx].styleIndex > 0:
    let si = int(b.frame.nodes[idx].styleIndex) - 1
    if si < b.frame.styles.len:
      childOrigin = childOrigin +
        vec2(b.frame.styles[si].paddingX, b.frame.styles[si].paddingY)

  let flags = b.frame.nodes[idx].flags
  let focusable = ctx.isFocusable(idx)
  let hasText = b.hasOwnText(idx)
  let consumed = idx < ctx.consumed.len and ctx.consumed[idx]
  let included = idx == 0 or sem != nil or focusable or
    Scrollable in flags or (hasText and not consumed)

  if not included:
    # Promote children to the nearest included ancestor; geometry is
    # unaffected because bounds are absolute.
    for childIdx in b[].children(idx):
      ctx.addSubtree(childIdx, childOrigin, siblings)
    return

  let akId = accessKitNodeId(b, idx)
  if ctx.visited.contains(uint64(akId)):
    # Duplicate node id: keep the first occurrence, skip the rest.
    return
  ctx.visited[uint64(akId)] = true

  var childIds = newSeq[AccessKitNodeId]()
  for childIdx in b[].children(idx):
    ctx.addSubtree(childIdx, childOrigin, childIds)

  # Role: explicit semantics win; otherwise infer like the first iteration.
  let role =
    if sem != nil and sem.role != SemanticNone:
      mapRole(sem.role)
    elif idx == 0:
      ROLE_WINDOW
    elif focusable:
      if FocusTextInput in ctx.focusFlags.getOrDefault(
          uint64(b.frame.nodes[idx].id)): ROLE_TEXT_INPUT
      else: ROLE_BUTTON
    elif Scrollable in flags:
      ROLE_SCROLL_VIEW
    elif hasText:
      ROLE_LABEL
    else:
      ROLE_GENERIC_CONTAINER

  # Accessible name: explicit label > labelledBy text > own text >
  # consumed descendant label text.
  var name = ""
  var labelRelation = -1
  if sem != nil and sem.label.len > 0:
    name = $sem.label
  elif sem != nil and uint64(sem.labelledBy) != 0:
    let labelIdx = b.nodeIndexOf(sem.labelledBy)
    if labelIdx >= 0:
      name = b.nodeTextValue(labelIdx)
      if ctx.remainsInTree(labelIdx):
        labelRelation = labelIdx
  elif hasText:
    name = b.nodeTextValue(idx)
  elif ctx.nameSource.contains(idx):
    name = b.nodeTextValue(ctx.nameSource.getOrDefault(idx))

  let akNode = nodeNew(role)
  let size = b.frame.nodes[idx].size
  nodeSetBounds(akNode, AccessKitRect(
    x0: pos.x.float64, y0: pos.y.float64,
    x1: (pos.x + size.x).float64, y1: (pos.y + size.y).float64))
  for childId in childIds:
    nodePushChild(akNode, childId)

  if name.len > 0:
    # Plain text nodes expose their content as the value; controls use it
    # as their label.
    if role == ROLE_LABEL:
      nodeSetValueWithLength(akNode, toCString(name), csize_t(name.len))
    else:
      nodeSetLabelWithLength(akNode, toCString(name), csize_t(name.len))
  if labelRelation >= 0:
    nodePushLabelledBy(akNode, accessKitNodeId(b, labelRelation))

  if sem != nil:
    if sem.description.len > 0:
      var description = $sem.description
      nodeSetDescriptionWithLength(akNode, toCString(description),
        csize_t(description.len))
    if sem.valueText.len > 0:
      var valueText = $sem.valueText
      nodeSetValueWithLength(akNode, toCString(valueText),
        csize_t(valueText.len))
    if SemanticCheckedMixed in sem.states:
      nodeSetToggled(akNode, TOGGLED_MIXED)
    elif SemanticChecked in sem.states:
      nodeSetToggled(akNode, TOGGLED_TRUE)
    elif role == ROLE_CHECK_BOX or role == ROLE_RADIO_BUTTON or
        role == ROLE_SWITCH:
      nodeSetToggled(akNode, TOGGLED_FALSE)
    if SemanticExpanded in sem.states:
      nodeSetExpanded(akNode, true)
    elif SemanticCollapsed in sem.states:
      nodeSetExpanded(akNode, false)
    if SemanticSelected in sem.states:
      nodeSetSelected(akNode, true)
    elif SemanticSelect in sem.actions:
      nodeSetSelected(akNode, false)
    if SemanticDisabled in sem.states:
      nodeSetDisabled(akNode)
    if SemanticReadOnly in sem.states:
      nodeSetReadOnly(akNode)
    if SemanticRequired in sem.states:
      nodeSetRequired(akNode)
    if SemanticModal in sem.states:
      nodeSetModal(akNode)
    if SemanticLiveRegion in sem.states:
      nodeSetLive(akNode, LIVE_POLITE)
    if sem.hasNumericValue:
      nodeSetNumericValue(akNode, sem.numericValue.float64)
      if sem.numericMax > sem.numericMin:
        nodeSetMinNumericValue(akNode, sem.numericMin.float64)
        nodeSetMaxNumericValue(akNode, sem.numericMax.float64)
      if sem.numericStep != 0.0'f32:
        nodeSetNumericValueStep(akNode, sem.numericStep.float64)
  let actions = routableActions(b, idx)
  if SemanticFocus in actions: nodeAddAction(akNode, ACTION_FOCUS)
  if SemanticActivate in actions or SemanticSelect in actions: nodeAddAction(akNode, ACTION_CLICK)
  if SemanticExpand in actions: nodeAddAction(akNode, ACTION_EXPAND)
  if SemanticCollapse in actions: nodeAddAction(akNode, ACTION_COLLAPSE)
  if SemanticSetNumericValue in actions or SemanticSetTextValue in actions:
    nodeAddAction(akNode, ACTION_SET_VALUE)
  if ctx.owner != nil:
    var generation = ctx.owner.nextGeneration
    if ctx.owner.routes.hasKey(uint64(akId)):
      let previous = ctx.owner.routes.getOrDefault(uint64(akId))
      if previous.actions != {} and actions != {}:
        generation = previous.generation
    ctx.routes[uint64(akId)] = ActionRoute(
      target: b.frame.nodes[idx].id, actions: actions, generation: generation)
  if focusable and FocusDisabled in ctx.focusFlags.getOrDefault(uint64(b.frame.nodes[idx].id)):
    nodeSetDisabled(akNode)

  treeUpdatePushNode(ctx.update, akId, akNode)
  siblings.add akId

proc newTreeInfo(rootId: AccessKitNodeId): ptr AccessKitTreeInfo =
  result = treeInfoNew(rootId)
  treeInfoSetToolkitName(result, cstring"Nuigi")

proc buildFallbackTree(): ptr AccessKitTreeUpdate =
  # Minimal tree used until the first frame has been built.
  result = treeUpdateWithCapacityAndFocus(1, fallbackRootId)
  treeUpdateSetTreeInfo(result, newTreeInfo(fallbackRootId))
  treeUpdatePushNode(result, fallbackRootId, nodeNew(ROLE_WINDOW))

proc buildTreeSnapshot*(b: ptr UiBuilder, owner: ptr NuigiAccessKit = nil): ptr AccessKitTreeUpdate =
  ## Builds a filtered AccessKit snapshot of the most recently completed
  ## frame. The caller transfers ownership to AccessKit (or frees it with
  ## `treeUpdateFree`).
  if owner != nil:
    inc owner.nextGeneration
    owner.builder = b
  if b == nil or b.frame.nodes.len == 0:
    if owner != nil:
      owner.routes.clear()
    return buildFallbackTree()
  let rootId = accessKitNodeId(b, 0)
  var ctx = TreeBuildContext(
    builder: b,
    update: treeUpdateWithCapacityAndFocus(csize_t(b.frame.nodes.len),
      rootId),
    focusFlags: initTable[uint64, UiFocusFlags](),
    visited: initTable[uint64, bool](),
    nameSource: initTable[int, int](),
    owner: owner,
    routes: initTable[uint64, ActionRoute]())
  for item in b.frame.focusItems:
    # Focus items may use a logical id (e.g. tree-table rows); key by the id
    # of the actual node they mark as focusable.
    var key = uint64(item.nodeId)
    if item.nodeIndex >= 0 and item.nodeIndex < b.frame.nodes.len:
      key = uint64(b.frame.nodes[item.nodeIndex].id)
    ctx.focusFlags[key] = item.flags
  ctx.computeNameSources()
  treeUpdateSetTreeInfo(ctx.update, newTreeInfo(rootId))
  var rootSiblings = newSeq[AccessKitNodeId]()
  ctx.addSubtree(0, vec2(0, 0), rootSiblings)
  var focusedId = uint64(b.focusedNode)
  if focusedId != 0:
    # Translate a logical focus id to the focused node's AccessKit id.
    for item in b.frame.focusItems:
      if uint64(item.nodeId) == focusedId:
        if item.nodeIndex >= 0 and item.nodeIndex < b.frame.nodes.len:
          focusedId = uint64(accessKitNodeId(b, item.nodeIndex))
        break
  if focusedId != 0 and ctx.visited.contains(focusedId):
    treeUpdateSetFocus(ctx.update, AccessKitNodeId(focusedId))
  if owner != nil:
    owner.routes = move(ctx.routes)
    owner.treeId = treeUpdateGetTreeId(ctx.update)
    if owner.actions != nil:
      withLock owner.actions.diagnosticLock:
        owner.actions.publishedVersion = owner.nextGeneration
  ctx.update

proc buildTreeUpdate(userdata: pointer): ptr AccessKitTreeUpdate {.cdecl.} =
  let owner = cast[ptr NuigiAccessKit](userdata)
  buildTreeSnapshot(owner.builder, owner)

proc handleAction(request: ptr AccessKitActionRequest,
    userdata: pointer) {.cdecl.} =
  let context = cast[ptr ActionContext](userdata)
  let envelope = cast[ptr ActionEnvelope](actionCalloc(1, csize_t(sizeof(ActionEnvelope))))
  if envelope == nil:
    actionRequestFree(request)
    withLock context.diagnosticLock:
      inc context.overflow
    return
  envelope.request = request
  withLock context.diagnosticLock:
    envelope.version = context.publishedVersion
  let status = context.queue.tryPush(envelope)
  if status != QueueAccepted:
    actionRequestFree(request)
    actionFree(envelope)
    if status == QueueFull:
      withLock context.diagnosticLock:
        inc context.overflow

proc pendingActions*(ak: var NuigiAccessKit): bool =
  if ak.actions == nil: return false
  ak.actions.queue.pending()

proc dispatchRequest*(ak: var NuigiAccessKit, request: ptr AccessKitActionRequest,
    version: uint64): bool =
  ## Decode on the UI thread. Caller retains/frees the request.
  result = false
  if request == nil:
    echo "AccessKit: rejected nil action request"
    return
  for i in 0 ..< 16:
    if request.targetTree.bytes[i] != ak.treeId.bytes[i]:
      echo "AccessKit: rejected foreign tree"
      return
  let id = uint64(request.targetNode)
  if not ak.routes.hasKey(id):
    echo "AccessKit: rejected stale target"
    return
  let route = ak.routes.getOrDefault(id)
  if version < route.generation:
    echo "AccessKit: rejected previous target incarnation"
    return
  var decoded = UiSemanticRequest(target: route.target)
  case request.action
  of ACTION_FOCUS: decoded.action = SemanticFocus
  of ACTION_CLICK:
    decoded.action = if SemanticActivate in route.actions: SemanticActivate else: SemanticSelect
  of ACTION_EXPAND: decoded.action = SemanticExpand
  of ACTION_COLLAPSE: decoded.action = SemanticCollapse
  of ACTION_SET_VALUE:
    if not request.data.hasValue:
      echo "AccessKit: SetValue requires data"
      return
    let data = request.data.value
    if data.tag == ACTION_DATA_NUMERIC_VALUE and SemanticSetNumericValue in route.actions:
      decoded.action = SemanticSetNumericValue
      decoded.numericValue = data.anon0.numericValue
    elif data.tag == ACTION_DATA_VALUE and data.anon0.value != nil:
      if SemanticSetTextValue in route.actions:
        decoded.action = SemanticSetTextValue
        decoded.textValue = $data.anon0.value
      elif SemanticSetNumericValue in route.actions:
        decoded.action = SemanticSetNumericValue
        let text = $data.anon0.value
        var number = 0.0
        let parsed = parseFloat(text, number)
        if parsed == 0 or parsed != text.len:
          echo "AccessKit: rejected malformed numeric text"
          return
        decoded.numericValue = number
      else:
        echo "AccessKit: unsupported value payload"
        return
    else:
      echo "AccessKit: rejected value payload tag"
      return
  else:
    echo "AccessKit: unsupported action"
    return
  if decoded.action notin route.actions:
    echo "AccessKit: rejected unsupported control action"
    return
  if decoded.action == SemanticSetNumericValue and
      (decoded.numericValue != decoded.numericValue or
      decoded.numericValue == Inf or decoded.numericValue == -Inf):
    echo "AccessKit: rejected non-finite numeric data"
    return
  if decoded.action != SemanticSetNumericValue and decoded.action != SemanticSetTextValue and request.data.hasValue:
    echo "AccessKit: rejected unexpected action data"
    return
  ak.builder[].enqueueSemanticRequest(decoded)
  result = true

proc prepareFrame*(ak: var NuigiAccessKit) =
  ## Call only when a UI build will occur. Arrivals during dispatch wait.
  if ak.actions == nil: return
  let batch = ak.actions.queue.drain()
  var overflow = 0
  withLock ak.actions.diagnosticLock:
    overflow = ak.actions.overflow
    ak.actions.overflow = 0
  if overflow > 0: echo "AccessKit: action queue overflow/allocation failures: ", overflow
  for i in 0 ..< batch.count:
    let envelope = cast[ptr ActionEnvelope](batch.items[i])
    discard ak.dispatchRequest(envelope.request, envelope.version)
    actionRequestFree(envelope.request)
    actionFree(envelope)

proc initialized*(ak: NuigiAccessKit): bool =
  when defined(windows):
    ak.adapter != nil
  else:
    false

proc init*(ak: var NuigiAccessKit, nativeWindow: pointer,
    builder: ptr UiBuilder): bool =
  ## Creates the platform adapter for the given native window handle (an HWND
  ## on Windows) and the builder whose frames are exposed to assistive
  ## technology. Must be called on the thread that owns the window, before
  ## the window is shown or focused for the first time. Both `ak` and the
  ## builder must remain at stable addresses until deinit. Returns false and
  ## sets `error` on failure.
  if ak.initialized:
    ak.error = "AccessKit is already initialized"
    return false
  if nativeWindow == nil:
    ak.error = "AccessKit requires a native window handle"
    return false
  if builder == nil:
    ak.error = "AccessKit requires a UI builder"
    return false
  ak.builder = builder
  ak.routes = initTable[uint64, ActionRoute]()
  ak.actions = cast[ptr ActionContext](actionCalloc(1, csize_t(sizeof(ActionContext))))
  if ak.actions == nil:
    ak.error = "Could not allocate the AccessKit action queue"
    return false
  ak.actions.queue.initPointerQueue()
  initLock(ak.actions.diagnosticLock)
  when defined(windows):
    ak.adapter = windowsSubclassingAdapterNew(nativeWindow,
      buildTreeUpdate, ak.addr, handleAction, ak.actions)
    if ak.adapter == nil:
      ak.actions.queue.close()
      ak.error = "Could not create the AccessKit Windows adapter"
      return false
    echo "AccessKit: initialized Windows subclassing adapter"
    true

proc update*(ak: var NuigiAccessKit) =
  ## Pushes the just-built frame to assistive technology. Call once per
  ## frame after `endUiFrame`; does nothing while no assistive technology
  ## is active.
  when defined(windows):
    if ak.adapter == nil:
      return
    let events = windowsSubclassingAdapterUpdateIfActive(ak.adapter,
      buildTreeUpdate, ak.addr)
    if events != nil:
      windowsQueuedEventsRaise(events)

proc deinit*(ak: var NuigiAccessKit) =
  if ak.actions != nil:
    ak.actions.queue.close()
  when defined(windows):
    if ak.adapter != nil:
      windowsSubclassingAdapterFree(ak.adapter)
      ak.adapter = nil
  if ak.actions != nil:
    let batch = ak.actions.queue.drain()
    for i in 0 ..< batch.count:
      let envelope = cast[ptr ActionEnvelope](batch.items[i])
      actionRequestFree(envelope.request)
      actionFree(envelope)
    # UIA providers may retain the Rust action handler after adapter_free.
    # Keep this closed, unmanaged context (and its locks) until process exit;
    # late callbacks cannot touch the builder or enqueue work.
    ak.actions = nil
  ak.routes.clear()
  ak.builder = nil
  ak.error = ""

{.pop.}
