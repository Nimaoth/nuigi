import std/[monotimes, os, strformat, tables, times]

import widgets/file_system_cursor

proc buildDeepCursor(root: string, depth: int): FileSystemCursor =
  var path = root
  for level in 0 ..< depth:
    path = path / ("d" & $level)
    createDir(path)

  result = fileSystemCursor(root)
  for level in 0 ..< depth:
    doAssert result.enterChild()

proc benchmarkExitChild(depth, iterations: int) =
  let root = getTempDir() / "nuigi-fs-cursor-bench"
  if dirExists(root):
    removeDir(root)
  createDir(root)
  try:
    let deepCursor = buildDeepCursor(root, depth)
    var rebasedPath: seq[int]
    for index in deepCursor.path:
      rebasedPath.add(index)
    rebasedPath[0] = 7
    var rebasedCursor = FileSystemCursor(deepCursor.clone())
    rebasedCursor.updatePath(rebasedPath)
    doAssert rebasedCursor.exitChild()
    doAssert rebasedCursor.path == rebasedPath[0 ..< rebasedPath.len - 1]
    doAssert deepCursor.path[0] == 0

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
    echo &"exitChild: {elapsed / iterations.float64:.3f} ms/chain, {elapsed * 1_000.0 / exits.float64:.3f} us/level ({depth} levels)"
  finally:
    if dirExists(root):
      removeDir(root)

proc benchmarkResolveChild(childCount, iterations: int) =
  let root = getTempDir() / "nuigi-fs-resolve-bench"
  if dirExists(root):
    removeDir(root)
  createDir(root)
  try:
    for index in 0 ..< childCount:
      createDir(root / &"item-{index:05}")
    let parent = fileSystemCursor(root)
    var child = FileSystemCursor(parent.clone())
    doAssert child.enterChild()
    doAssert child.moveNext(childCount - 1)

    discard parent.childCount()
    for warmup in 0 ..< 100:
      doAssert parent.resolveChild(child) != nil
    var started = getMonoTime()
    for iteration in 0 ..< iterations:
      doAssert parent.resolveChild(child) != nil
    var elapsed = (getMonoTime() - started).inNanoseconds.float64 / 1_000_000.0
    echo &"resolveChild hint: {elapsed * 1_000.0 / iterations.float64:.3f} us/call ({childCount} children)"

    createDir(root / "item-00998a")
    parent.cache.listings.del(parent.fullPath)
    let freshParent = FileSystemCursor(parent.clone())
    for warmup in 0 ..< 100:
      doAssert freshParent.resolveChild(child) != nil
    started = getMonoTime()
    for iteration in 0 ..< iterations:
      doAssert freshParent.resolveChild(child) != nil
    elapsed = (getMonoTime() - started).inNanoseconds.float64 / 1_000_000.0
    echo &"resolveChild fallback: {elapsed * 1_000.0 / iterations.float64:.3f} us/call ({childCount + 1} children)"
  finally:
    if dirExists(root):
      removeDir(root)

when isMainModule:
  echo "file system cursor benchmark"
  benchmarkExitChild(32, 2_000)
  benchmarkResolveChild(1_000, 20_000)