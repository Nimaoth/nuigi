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

when defined(wasm):
  const faqMarkdown = staticRead("../../docs/faq.md")

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

proc addParsedAnswer(question: NullableFaqPost, body: var string) =
  if question != nil:
    let answer = body.strip()
    if answer.len > 0:
      discard question.addFaqPost(
        question.key & ":answer", answer, FaqAnswer)
  body.setLen(0)

proc parseFaq(markdown: string): FaqPost =
  result = addFaqPost(nil, "faq-root", "FAQ", FaqTopic)
  var topic: NullableFaqPost = nil
  var question: NullableFaqPost = nil
  var answer = ""

  for sourceLine in markdown.splitLines():
    let line = sourceLine.strip()
    if line.startsWith("# "):
      addParsedAnswer(question, answer)
      let title = line[2 .. ^1].strip()
      topic = result.addFaqPost("topic:" & title, title, FaqTopic)
      question = nil
    elif line.startsWith("## "):
      addParsedAnswer(question, answer)
      if topic != nil:
        let title = line[3 .. ^1].strip()
        question = topic.addFaqPost(
          topic.key & ":question:" & title, title, FaqQuestion)
    elif question != nil:
      if answer.len > 0:
        answer.add('\n')
      answer.add(sourceLine)

  addParsedAnswer(question, answer)

proc createFaq(): FaqPost =
  when defined(wasm):
    result = parseFaq(faqMarkdown)
  else:
    try:
      return parseFaq(readFile("./docs/faq.md"))
    except:
      result = addFaqPost(nil, "faq-root", "FAQ", FaqTopic)
      discard result.addFaqPost(
        "faq-load-error", "Could not load docs/faq.md", FaqTopic)

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
      options.hideRoot = true
      options.highlightHoveredRow = false
      b.treeTable(faqCursor(faqRoot), options, renderFaqRow)
