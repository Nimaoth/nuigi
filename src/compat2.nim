#       Nif library
# (c) Copyright 2026 Andreas Rumpf
#
# See the file "license.txt", included in this
# distribution, for details about the copyright.

## Compat shims that let a module compile under both Nim and Nimony.
## Must be `include`d, not `import`ed, because Nim does not export
## custom pragmas across module boundaries.

{.push hint[DuplicateModuleImport]: off.}
{.push warning[UnusedImport]: off.}
import std/[strutils, syncio]
{.pop.}
{.pop.}

when defined(nimony):
  {.pragma: canRaise, raises.}
else:
  {.pragma: canRaise.}

when defined(nimony):
  template onRaiseQuit(call: untyped): untyped =
    ## Calls a `{.raises.}` proc from a non-raising context: wraps in
    ## try/except and aborts with a useful diagnostic on failure. Lets us
    ## keep `raises` from spreading virally through every layer in `sem.nim`
    ## et al. without silently swallowing the raise.
    ## Unexported on purpose — `compat2.nim` is `include`d, not `import`ed,
    ## so each user file gets its own private copy and there is no
    ## cross-module ambiguity.
    try:
      call
    except:
      quit "FAILURE: " & astToStr(call)
else:
  template onRaiseQuit(call: untyped): untyped {.used.} = call

when defined(nimony):
  template debugLog*(line: string): untyped =
    echo line
else:
  template debugLog*(line: string): untyped =
    echo line

when not defined(nimony):
  from std/paths import Path

  proc path*(s: string): Path {.inline.} =
    ## Compat shim: Nimony exposes `path(string) -> Path` (its dirs/paths API
    ## takes a `Path`-typed wrapper); on host Nim the equivalent is `Path(s)`.
    ## Having both spellings lets call sites write `createDir(path(s))`
    ## unconditionally, dropping the `when defined(nimony)`/`else` ladder.
    ## `from … import` keeps `paths.getCurrentDir` etc. out of scope so it
    ## doesn't collide with `os.getCurrentDir` in modules that include this.
    Path(s)

when not defined(nimony):
  {.push hint[DuplicateModuleImport]: off.}
  import std/tables
  {.pop.}

  type HasDefault* = concept
    proc default(_: typedesc[Self]): Self

  proc getOrQuit*[A, B](t: var Table[A, B]; k: A): var B {.raises: [].} =
    ## Host-Nim shim for the Nimony `tables.getOrQuit` that returns `var B`
    ## and aborts if the key is absent. Callers guard with `hasKey` before
    ## this call, so the missing-key branch is unreachable in practice.
    if not t.hasKey(k): quit "getOrQuit: missing key"
    try:
      result = t[k]
    except:
      result = t.mgetOrPut(k, B.default)

  proc getOrQuit*[A, B](t: var OrderedTable[A, B]; k: A): var B {.raises: [].} =
    if not t.hasKey(k): quit "getOrQuit: missing key"
    try:
      result = t[k]
    except:
      result = t.mgetOrPut(k, B.default)

  proc getOrQuit*[A, B](t: Table[A, B]; k: A): B {.raises: [].} =
    ## Read-only variant for `let`-bound tables: nimony's `getOrQuit` takes
    ## the table by value and returns `var B`, but host Nim distinguishes
    ## mutable from immutable receivers.
    if not t.hasKey(k): quit "getOrQuit: missing key"
    try:
      result = t[k]
    except:
      result = B.default

  proc getOrQuit*[A, B](t: OrderedTable[A, B]; k: A): B {.raises: [].} =
    if not t.hasKey(k): quit "getOrQuit: missing key"
    try:
      result = t[k]
    except:
      result = B.default

  proc toCString(str: string): cstring {.used.} = str.cstring

  func beginStore*(s: var string; newLen: int; start = 0): ptr UncheckedArray[char] {.noSideEffect, raises: [], tags: [].} =
    s.setLen(newLen)
    return cast[ptr UncheckedArray[char]](s[start].addr)

  func endStore*(s: var string) {.inline, noSideEffect, raises: [], tags: [].} =
    discard

  func readRawData*(s {.byref.}: string; start = 0): ptr UncheckedArray[char] {.inline, noSideEffect, raises: [], tags: [].} =
    return cast[ptr UncheckedArray[char]](s[start].addr)

# func ord*[T: enum](v: set[T]): uint32 =
#   result = 0
#   for x in T.low..T.high:
#     if x in v:
#       result = result or (1'u32 shl x.uint32)

func setFromInt*[T](v: var T, ord: uint32) =
  var pv = cast[ptr uint32](v.addr)
  pv[] = ord

func `%%`*(formatstr: string; a: openArray[string]): string =
  try:
    formatstr % a
  except:
    {.cast(noSideEffect).}:
      when not defined(nimony):
        writeStackTrace()
      echo("Invalid format str '" & formatstr & "'")
      quit(1)
    formatstr

when defined(nimony):
  func `==`*(a: string, b: cstring): bool =
    if a.len != b.len:
      return false
    for i in 0..a.high:
      if a[i] != b[i]:
        return false
    return true

  func `==`*(a: cstring, b: string): bool = b == a

  template alignof[T](_: typedesc[T]): int64 = sizeof(T)

  func toUnix*(a: int64): int64 {.inline.} = a

  proc add*[T](dest: var seq[T]; src: seq[T]) {.inline.} =
    ## Nimony shim: std seqs are missing the `add(seq)` overload that
    ## host Nim provides, so append element-wise instead.
    for item in src:
      dest.add(item)

  proc add*[T](dest: var seq[T]; src: openArray[T]) {.inline.} =
    ## Nimony shim: std seqs are missing the `add(seq)` overload that
    ## host Nim provides, so append element-wise instead.
    for item in src:
      dest.add(item)

  proc insert*[T: HasDefault](dest: var seq[T]; item: T; index: int) =
    ## Nimony shim for host Nim's sequence insertion operation.
    if index < 0 or index > dest.len:
      quit "insert: index out of bounds"
    let oldLen = dest.len
    dest.setLen(oldLen + 1)
    var position = oldLen
    while position > index:
      dest[position] = dest[position - 1]
      dec position
    dest[index] = item

  template gcsafeb*(body: untyped): untyped =
    body

else:
  template gcsafeb*(body: untyped): untyped =
    {.gcsafe.}:
      body
