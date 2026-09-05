include "../compat2"

import "../nuigi", "../widgets", "../flex", "../widgets/tree_table"

type
  FaqPostKind = enum
    FaqTopic
    FaqQuestion
    FaqAnswer

  FaqPost = ref object
    key: string
    body: string
    kind: FaqPostKind
    score: int
    when defined(nimony):
      parent: nil FaqPost
    else:
      parent: FaqPost
    children: seq[FaqPost]

  FaqCursor = ref object of TreeCursor
    post: FaqPost
    parents: seq[FaqPost]

var faqRoot: FaqPost

when defined(nimony):
  type NullableFaqPost = nil FaqPost
else:
  type NullableFaqPost = FaqPost

proc addFaqPost(
  parent: NullableFaqPost, key, body: string, kind: FaqPostKind,
    score = 1): FaqPost =
  result = FaqPost(
    key: key,
    body: body,
    kind: kind,
    score: score,
    parent: parent,
  )
  if parent != nil:
    parent.children.add(result)

proc createFaq(): FaqPost =
  result = addFaqPost(nil, "faq-root",
    "Ask and answer practical questions about nuigi, the immediate-mode UI library for Nim.",
    FaqTopic, 42)

  let fundamentals = result.addFaqPost("fundamentals",
    "Project fundamentals",
    FaqTopic, 36)
  let gettingStarted = fundamentals.addFaqPost("getting-started",
    "What is nuigi, and what kind of interface is it intended to build?",
    FaqQuestion, 28)
  discard gettingStarted.addFaqPost("getting-started-answer",
    "nuigi is an immediate-mode UI library written in Nim. You describe the interface every frame with UiBuilder calls, while the library retains the small amount of state needed for interaction, focus, animation, and virtualized widgets.",
    FaqAnswer, 51)
  let retainedQuestion = fundamentals.addFaqPost("retained-state-question",
    "If the UI is immediate mode, where should application state live?",
    FaqQuestion, 17)
  discard retainedQuestion.addFaqPost("retained-state-answer",
    "Keep application state in your own objects or module variables. Widget-owned interaction state is stored by stable node IDs, so controls can be rebuilt each frame without losing focus, scrolling, or edit state.",
    FaqAnswer, 33)

  let layoutAndText = result.addFaqPost("layout-and-text",
    "Layout and text",
    FaqTopic, 31)
  let sizing = layoutAndText.addFaqPost("sizing",
    "Why did my new node collapse to zero size?",
    FaqQuestion, 35)
  discard sizing.addFaqPost("sizing-answer",
    "Nodes do not have a default sizing policy. Choose explicit width or height, fit to content, fill available space, use anchors and offsets, or let table, flex, and grid layout determine the size.",
    FaqAnswer, 64)
  let textSizing = layoutAndText.addFaqPost("text-sizing-question",
    "Is there a special rule for wrapped text?",
    FaqQuestion, 21)
  discard textSizing.addFaqPost("text-sizing-answer",
    "Yes. Give the text node a known width, enable wrapping, and fit its height. Also set font and text properties before assigning text so measurement uses the final style.",
    FaqAnswer, 47)

  let building = result.addFaqPost("building",
    "Building and compiler support",
    FaqTopic, 25)
  let build = building.addFaqPost("build",
    "How should I build the demo and run the tests?",
    FaqQuestion, 19)
  discard build.addFaqPost("build-answer",
    "Use the repository build driver: run ./build.exe demo for the demo and ./build.exe test for the test suite. The driver selects and configures the supported compiler paths",
    FaqAnswer, 39)
  let nimony = building.addFaqPost("nimony-question",
    "Does this library work with Nimony?",
    FaqQuestion, 12)
  discard nimony.addFaqPost("nimony-answer",
    "Yes. The core library works with Nimony, but harfbuzz is not supported on the SDL3 backend yet. Emscripten is only supported with Nim 2.",
    FaqAnswer, 26)

  let widgetsAndThemes = result.addFaqPost("widgets-and-themes",
    "Widgets and theming",
    FaqTopic, 29)
  let largeData = widgetsAndThemes.addFaqPost("large-data",
    "Which widget should I use for a very large scrolling data set?",
    FaqQuestion, 24)
  discard largeData.addFaqPost("large-data-answer",
    "Use virtualList when every row has the same height. Use dynamicVirtualList when heights vary. For expandable hierarchical data, treeTable combines cursor-based traversal with variable-height virtualization.",
    FaqAnswer, 44)

  let styling = widgetsAndThemes.addFaqPost("styling",
    "How should application code choose colors, padding, and text styles?",
    FaqQuestion, 16)
  discard styling.addFaqPost("styling-answer",
    "Prefer theme style and text-style indices so the interface follows the active theme. Copy a style only when a specific node truly needs a local modification.",
    FaqAnswer, 31)

proc faqCursor(root: FaqPost): FaqCursor =
  FaqCursor(post: root, fieldName: root.body, path: @[])

method clone*(cursor: FaqCursor): TreeCursor =
  let copy = FaqCursor(
    post: cursor.post,
    fieldName: cursor.fieldName,
    index: cursor.index,
  )
  for parent in cursor.parents:
    copy.parents.add(parent)
  for pathIndex in cursor.path:
    copy.path.add(pathIndex)
  copy

method cursorKey*(cursor: FaqCursor): string =
  cursor.post.key

method childCount*(cursor: FaqCursor): int =
  cursor.post.children.len

method enterChild*(cursor: FaqCursor): bool =
  if cursor.post.children.len == 0:
    return false
  cursor.parents.add(cursor.post)
  cursor.post = cursor.post.children[0]
  cursor.path.add(0)
  cursor.index = 0
  cursor.fieldName = cursor.post.body
  true

method moveNext*(cursor: FaqCursor, count: int = 1): bool =
  if cursor.parents.len == 0 or count < 0:
    return false
  let siblings = cursor.parents[^1].children
  if cursor.index + count >= siblings.len:
    return false
  cursor.index += count
  cursor.path[cursor.path.high] = cursor.index
  cursor.post = siblings[cursor.index]
  cursor.fieldName = cursor.post.body
  true

method movePrev*(cursor: FaqCursor, count: int = 1): bool =
  if cursor.parents.len == 0 or count < 0 or cursor.index < count:
    return false
  cursor.index -= count
  cursor.path[cursor.path.high] = cursor.index
  cursor.post = cursor.parents[^1].children[cursor.index]
  cursor.fieldName = cursor.post.body
  true

method exitChild*(cursor: FaqCursor): bool =
  if cursor.parents.len == 0:
    return false
  cursor.post = cursor.parents[^1]
  cursor.parents.setLen(cursor.parents.len - 1)
  cursor.path.setLen(cursor.path.len - 1)
  cursor.index = if cursor.path.len > 0: cursor.path[^1] else: 0
  cursor.fieldName = cursor.post.body
  true

method resolveChild*(cursor: FaqCursor, child: TreeCursor): TreeCursor =
  let expected = FaqCursor(child)
  var childIndex = expected.index
  if childIndex < 0 or childIndex >= cursor.post.children.len or
      cursor.post.children[childIndex].key != expected.post.key:
    childIndex = -1
    for index, candidate in cursor.post.children:
      if candidate.key == expected.post.key:
        childIndex = index
        break
  if childIndex < 0:
    return nil
  let resolved = FaqCursor(cursor.clone())
  resolved.parents.add(cursor.post)
  resolved.post = cursor.post.children[childIndex]
  resolved.index = childIndex
  resolved.path.add(childIndex)
  resolved.fieldName = resolved.post.body
  resolved

proc faqKindLabel(kind: FaqPostKind): string =
  case kind
  of FaqTopic: "Topic"
  of FaqQuestion: "Question"
  of FaqAnswer: "Answer"

proc renderFaqRow(
    b: var UiBuilder, cursor: TreeCursor, index: int) {.canRaise, nimcall.} =
  let faq = FaqCursor(cursor)
  let post = faq.post
  b.node:
    b.debugName("faq-comment-card")
    discard b.fitY().styleIndex(UiStyleIndexCard).padding(10).gap(7)
    discard b.layout(LayoutVertical).forwardLayout()
    discard b.fillBackground().cornerRadius(6)
    discard b.borderWidth(1).borderColor(
      b.themeStyle(UiStyleIndexCard)[].borderColor)

    b.node:
      b.debugName("faq-comment-meta")
      discard b.fillX().fitY()
      discard b.flexLayout().flexDirection(FlexDirectionRow).columnGap(6)
      b.label(faqKindLabel(post.kind)):
        discard b.fitX().fitY().fontSize(12)
          .textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)
      b.node:
        b.debugName("faq-comment-meta-spacer")
        discard b.fitY().flex(1, 1)
      b.label("score " & $post.score):
        discard b.fitX().fitY().fontSize(12)
          .textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.labelWrapped(post.body):
      discard b.fillX().fitY().fontSize(14)
        .textColor(b.themeTextStyle(UiStyleIndexDefaultText)[].textColor)

    b.layoutHorizontal:
      b.debugName("faq-comment-actions")
      discard b.fillX().fitY().gap(5)
      if b.button("Upvote"):
        inc post.score
      if b.button("Downvote"):
        dec post.score

proc buildFaqTreeTableExample*(b: var UiBuilder) =
  let parent = b.currentNode
  if faqRoot == nil:
    faqRoot = createFaq()

  b.layoutVertical:
    b.debugName("faq-tree-table-demo")
    discard b.fillX().padding(8).gap(8)
    if FitY in parent.flags:
      discard b.height(600)
    else:
      discard b.fillY()
    discard b.backgroundColor(b.themeStyle(UiStyleIndexPanel)[].fillColor)

    b.label("FAQ"):
      discard b.fontSize(18)
    b.labelWrapped("This example uses the tree table component. Resize this window to see the text in the Q&A below wrap and change the height of individual rows. The upvote scores are fake."):
      discard b.fillX().fitY().fontSize(13)
        .textColor(b.themeTextStyle(UiStyleIndexMutedText)[].textColor)

    b.layoutVertical:
      b.debugName("faq-tree-table-host")
      discard b.fillX().sizeToParentY()
      var options = defaultTreeTableOptions()
      options.columns = @[tableColumnFill()]
      options.columnGap = 6.0'f32
      options.highlightHoveredRow = false
      b.treeTable(faqCursor(faqRoot), options, renderFaqRow)
