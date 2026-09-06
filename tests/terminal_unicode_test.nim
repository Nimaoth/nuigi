import nuigi/backend/terminal/terminal_unicode

when defined(nimony):
  import std/assertions

proc require(condition: bool, message: string) =
  when defined(nimony):
    assert condition, message
  else:
    doAssert(condition, message)

proc requireSingleGrapheme(text: string, expectedWidth: int, message: string) =
  let graphemes = text.terminalGraphemes
  require(graphemes.len == 1, message & " cluster count")
  require(graphemes[0].width == expectedWidth, message & " cell width")

proc testCombiningScripts() =
  requireSingleGrapheme("วั", 1, "Thai combining vowel")
  requireSingleGrapheme("हि", 1, "Devanagari combining vowel")
  requireSingleGrapheme("न्द", 1, "Devanagari conjunct")

proc testEmojiSequences() =
  for emoji in ["💕", "👰🏻", "👰🏻‍♂️", "👰🏻‍♀️", "😶‍🌫️", "👩🏿", "🧍‍♂️",
      "🏊🏿‍♀️", "👆🏿", "🗂️", "❌", "⭕"]:
    requireSingleGrapheme(emoji, 2, "emoji " & emoji)

proc testStressLines() =
  let thai = "Thai: สวัสดีชาวโลก จิ้งจอกสีน้ำตาลกระโดดข้ามสุนัขขี้เกียจ"
  let hindi = "Hindi: नमस्ते दुनिया। तेज भूरी लोमड़ी आलसी कुत्ते के ऊपर कूदती है।"
  let mixed = "Mixed: English 中文 日本語 한국어 العربية हिन्दी ∑ ↔"
  let emoji = "Emoji: 💕👇👍👌👆👰🏻👰🏻‍♂️👰🏻‍♀️🤬😶‍🌫️👩🏿🐅🧍‍♂️🆗😍🤣😊🐱🤣😅👀🦴👩👩🏻👩🏼👩🏽👩🏾👩🏿🏊🏿‍♀️👆🏿🤝🎈🎨🪡👑🥏🎸📁📂🗂️📝🗒️⌛📎⌛⏳🚀💦🆎❌⭕💯🆗🆒🔝🟥🟧🟨🟩"

  for line in [thai, hindi, mixed, emoji]:
    let unwrapped = terminalTextSize(line)
    let wrapped = terminalTextSize(line, 24)
    require(unwrapped.width > 0 and unwrapped.height == 1, "unwrapped stress line")
    require(wrapped.width <= 24 and wrapped.height > 1, "wrapped stress line")

proc main() =
  testCombiningScripts()
  testEmojiSequences()
  testStressLines()

main()