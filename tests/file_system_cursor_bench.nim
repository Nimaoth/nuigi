import std/[monotimes, os, tables, times]
when defined(nimony):
  import std/[assertions, dirs]

import nuigi/widgets/file_system_cursor

include nuigi/util/compat2

template benchAssert(condition: bool) =
  when defined(nimony):
    assert condition
  else:
    doAssert condition

proc createBenchDir(directory: string) =
  when defined(nimony):
    onRaiseQuit(createDir(path(directory)))
  else:
    createDir(directory)

proc removeBenchDir(directory: string) =
  when defined(nimony):
    try:
      for kind, entryPath in walkDir(path(directory)):
        if kind == pcDir or kind == pcLinkToDir:
          removeBenchDir($entryPath)
        else:
          removeFile(entryPath)
      removeDir(path(directory))
    except:
      quit "FAILURE: removeBenchDir(" & directory & ")"
  else:
    removeDir(directory)

proc paddedIndex(index: int): string =
  result = $index
  while result.len < 5:
    result = "0" & result

proc buildDeepCursor(root: string, depth: int): FileSystemCursor =
  var path = root
  for level in 0 ..< depth:
    path = path / ("d" & $level)
    createBenchDir(path)

  result = fileSystemCursor(root)
  for level in 0 ..< depth:
    benchAssert result.enterChild()

proc benchmarkExitChild(depth, iterations: int) =
  let root = getTempDir() / "nuigi-fs-cursor-bench"
  if dirExists(root):
    removeBenchDir(root)
  createBenchDir(root)
  try:
    let deepCursor = buildDeepCursor(root, depth)
    var rebasedPath: seq[int] = @[]
    for index in deepCursor.path:
      rebasedPath.add(index)
    rebasedPath[0] = 7
    var rebasedCursor = FileSystemCursor(deepCursor.clone())
    rebasedCursor.updatePath(rebasedPath)
    benchAssert rebasedCursor.exitChild()
    benchAssert rebasedCursor.path == rebasedPath[0 ..< rebasedPath.len - 1]
    benchAssert deepCursor.path[0] == 0

    for warmup in 0 ..< 10:
      var cursor = FileSystemCursor(deepCursor.clone())
      while cursor.exitChild():
        discard

    let started = getMonoTime()
    var exits = 0
    for iteration in 0 ..< iterations:
      var cursor = FileSystemCursor(deepCursor.clone())
      while cursor.exitChild():
        inc exits
    let elapsed = (getMonoTime() - started).inNanoseconds.float64 / 1_000_000.0
    debugLog("exitChild: " & $(elapsed / iterations.float64) & " ms/chain, " &
      $(elapsed * 1_000.0 / exits.float64) & " us/level (" & $depth & " levels)")
  finally:
    if dirExists(root):
      removeBenchDir(root)

proc benchmarkResolveChild(childCount, iterations: int) =
  let root = getTempDir() / "nuigi-fs-resolve-bench"
  if dirExists(root):
    removeBenchDir(root)
  createBenchDir(root)
  try:
    for index in 0 ..< childCount:
      createBenchDir(root / ("item-" & paddedIndex(index)))
    let parent = fileSystemCursor(root)
    var child = FileSystemCursor(parent.clone())
    benchAssert child.enterChild()
    benchAssert child.moveNext(childCount - 1)

    discard parent.childCount()
    for warmup in 0 ..< 100:
      benchAssert parent.resolveChild(child) != nil
    var started = getMonoTime()
    for iteration in 0 ..< iterations:
      benchAssert parent.resolveChild(child) != nil
    var elapsed = (getMonoTime() - started).inNanoseconds.float64 / 1_000_000.0
    debugLog("resolveChild hint: " & $(elapsed * 1_000.0 / iterations.float64) &
      " us/call (" & $childCount & " children)")

    createBenchDir(root / "item-00998a")
    parent.cache.listings.del(parent.fullPath)
    let freshParent = FileSystemCursor(parent.clone())
    for warmup in 0 ..< 100:
      benchAssert freshParent.resolveChild(child) != nil
    started = getMonoTime()
    for iteration in 0 ..< iterations:
      benchAssert freshParent.resolveChild(child) != nil
    elapsed = (getMonoTime() - started).inNanoseconds.float64 / 1_000_000.0
    debugLog("resolveChild fallback: " & $(elapsed * 1_000.0 / iterations.float64) &
      " us/call (" & $(childCount + 1) & " children)")
  finally:
    if dirExists(root):
      removeBenchDir(root)

when isMainModule:
  debugLog("file system cursor benchmark")
  benchmarkExitChild(32, 2_000)
  benchmarkResolveChild(1_000, 20_000)