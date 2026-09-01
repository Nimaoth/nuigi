import os
import algorithm
import strutils
import tables

import tree_table, profiler

# Shared, clone-transparent cache of directory listings and entry kinds.
type
  FileSystemEntryKind* = enum
    File, Folder

  FileSystemCache* = ref object
    listings*: Table[string, seq[string]]
    kinds*: Table[string, FileSystemEntryKind]

  FileSystemCursorLocation = ref object
    parent: FileSystemCursorLocation
    fullPath: string
    parentPath: string
    fieldName: string
    path: seq[int]
    index: int
    kind: FileSystemEntryKind

proc newFileSystemCache*(): FileSystemCache =
  result = FileSystemCache()
  result.listings = initTable[string, seq[string]]()
  result.kinds = initTable[string, FileSystemEntryKind]()

# A cursor that walks a directory tree. Each node is a file or directory rooted
# at the working directory.
type
  FileSystemCursor* = ref object of TreeCursor
    cache*: FileSystemCache
    location: FileSystemCursorLocation

func fullPath*(c: FileSystemCursor): string {.inline.} =
  c.location.fullPath

func parentPath*(c: FileSystemCursor): string {.inline.} =
  c.location.parentPath

func kind*(c: FileSystemCursor): FileSystemEntryKind {.inline.} =
  c.location.kind

func rootPath*(c: FileSystemCursor): string =
  var location = c.location
  while location.parent != nil:
    location = location.parent
  location.fullPath

proc pathWithIndex(path: seq[int], index: int): seq[int] =
  result = newSeqOfCap[int](path.len + 1)
  for value in path:
    result.add(value)
  result.add(index)

proc applyLocation(c: FileSystemCursor, location: FileSystemCursorLocation) =
  c.location = location
  c.fieldName = location.fieldName
  c.path = location.path
  c.index = location.index

proc cursorAt(c: FileSystemCursor, location: FileSystemCursorLocation): FileSystemCursor =
  result = FileSystemCursor(cache: c.cache)
  result.applyLocation(location)

proc copyPathPrefix(path: seq[int], count: int): seq[int] =
  result = newSeqOfCap[int](count)
  for index in 0 ..< count:
    result.add(path[index])

proc rebaseLocation(location: FileSystemCursorLocation, path: seq[int], depth: int): FileSystemCursorLocation =
  let parent = if location.parent == nil:
    nil
  else:
    rebaseLocation(location.parent, path, depth - 1)
  result = FileSystemCursorLocation(
    parent: parent,
    fullPath: location.fullPath,
    parentPath: location.parentPath,
    fieldName: location.fieldName,
    path: copyPathPrefix(path, depth),
    index: if depth > 0: path[depth - 1] else: 0,
    kind: location.kind)

proc entryKind(cache: FileSystemCache, path: string): FileSystemEntryKind =
  if path in cache.kinds:
    return cache.kinds[path]
  result = if dirExists(path): Folder else: File
  cache.kinds[path] = result

proc comparablePath(path: string): string =
  result = absolutePath(path)
  normalizePath(result)
  when defined(windows):
    result = result.toLowerAscii()

proc listEntries(cache: FileSystemCache, path: string): lent seq[string] =
  if path in cache.listings:
    return cache.listings[path]
  var entries: seq[string]
  if dirExists(path):
    for kind, entryPath in walkDir(path):
      entries.add(extractFilename(entryPath))
      cache.kinds[entryPath] =
        if kind == pcDir or kind == pcLinkToDir: Folder else: File
    cache.kinds[path] = Folder
    entries.sort()
  cache.listings[path] = entries
  return cache.listings[path]

method clone*(c: FileSystemCursor): TreeCursor =
  return c.cursorAt(c.location)

method updatePath*(c: FileSystemCursor, path: seq[int]) =
  c.applyLocation(c.location.rebaseLocation(path, path.len))

method replacePathPrefix*(c: FileSystemCursor, oldPrefixLen: int, newPrefix: seq[int]) =
  if oldPrefixLen != newPrefix.len:
    proc replacedPath(): seq[int] =
      let suffixLen = max(0, c.path.len - oldPrefixLen)
      result = newSeq[int](newPrefix.len + suffixLen)
      for index in 0 ..< newPrefix.len:
        result[index] = newPrefix[index]
      for index in 0 ..< suffixLen:
        result[newPrefix.len + index] = c.path[oldPrefixLen + index]
    c.updatePath(replacedPath())
    return

  var sharedDepth = 0
  while sharedDepth < newPrefix.len and c.path[sharedDepth] == newPrefix[sharedDepth]:
    inc sharedDepth
  if sharedDepth == newPrefix.len:
    return

  var oldLocations: seq[FileSystemCursorLocation]
  var sharedLocation = c.location
  while sharedLocation.path.len > sharedDepth:
    oldLocations.add(sharedLocation)
    sharedLocation = sharedLocation.parent

  var parentLocation = sharedLocation
  for locationIndex in countdown(oldLocations.high, 0):
    let oldLocation = oldLocations[locationIndex]
    var path = newSeq[int](oldLocation.path.len)
    for pathIndex in 0 ..< path.len:
      path[pathIndex] = if pathIndex < newPrefix.len:
        newPrefix[pathIndex]
      else:
        oldLocation.path[pathIndex]
    parentLocation = FileSystemCursorLocation(
      parent: parentLocation,
      fullPath: oldLocation.fullPath,
      parentPath: oldLocation.parentPath,
      fieldName: oldLocation.fieldName,
      path: path,
      index: path[^1],
      kind: oldLocation.kind)
  c.applyLocation(parentLocation)

# Identity is the full path, so expansion state matches across frames.
method cursorKey*(c: FileSystemCursor): string =
  return c.fullPath

method childCount*(c: FileSystemCursor): int =
  let listing {.cursor.} = listEntries(c.cache, c.fullPath)
  return listing.len

proc resolveListedChild(c, expected: FileSystemCursor, listing: openArray[string]): TreeCursor =
  let name = expected.fieldName
  var foundIndex = -1
  if expected.index >= 0 and expected.index < listing.len and listing[expected.index] == name:
    foundIndex = expected.index
  else:
    var low = 0
    var high = listing.len
    while low < high:
      let middle = (low + high) div 2
      if listing[middle] < name:
        low = middle + 1
      else:
        high = middle
    if low < listing.len and listing[low] == name:
      foundIndex = low
  if foundIndex < 0:
    return nil

  if foundIndex == expected.index and expected.location.parent == c.location:
    return c.cursorAt(expected.location)

  return c.cursorAt(FileSystemCursorLocation(
    parent: c.location,
    fullPath: expected.fullPath,
    parentPath: c.fullPath,
    fieldName: name,
    path: pathWithIndex(c.path, foundIndex),
    index: foundIndex,
    kind: expected.kind))

method resolveChild*(c: FileSystemCursor, child: TreeCursor): TreeCursor =
  prof("resolveChild")
  let expected = FileSystemCursor(child)
  if expected.parentPath != c.fullPath:
    return nil
  let listing {.cursor.} = listEntries(c.cache, c.fullPath)
  return resolveListedChild(c, expected, listing)

method enterChild*(c: FileSystemCursor): bool =
  prof("enterChild")
  let listing {.cursor.} = listEntries(c.cache, c.fullPath)
  if listing.len == 0:
    return false
  let name = listing[0]
  let fullPath = c.fullPath / name
  c.applyLocation(FileSystemCursorLocation(
    parent: c.location,
    fullPath: fullPath,
    parentPath: c.fullPath,
    fieldName: name,
    path: pathWithIndex(c.path, 0),
    index: 0,
    kind: entryKind(c.cache, fullPath)))
  return true

method moveNext*(c: FileSystemCursor, count: int = 1): bool =
  prof("moveNext")
  if c.location.parent == nil:
    return false
  let listing {.cursor.} = listEntries(c.cache, c.parentPath)
  if listing.len == 0:
    return false
  if c.index + count < listing.len:
    let index = c.index + count
    let name = listing[index]
    let fullPath = c.parentPath / name
    c.applyLocation(FileSystemCursorLocation(
      parent: c.location.parent,
      fullPath: fullPath,
      parentPath: c.parentPath,
      fieldName: name,
      path: pathWithIndex(c.location.parent.path, index),
      index: index,
      kind: entryKind(c.cache, fullPath)))
    return true
  return false

method movePrev*(c: FileSystemCursor, count: int = 1): bool =
  if c.location.parent == nil:
    return false
  let listing {.cursor.} = listEntries(c.cache, c.parentPath)
  if listing.len == 0:
    return false
  if c.index >= count:
    let index = c.index - count
    let name = listing[index]
    let fullPath = c.parentPath / name
    c.applyLocation(FileSystemCursorLocation(
      parent: c.location.parent,
      fullPath: fullPath,
      parentPath: c.parentPath,
      fieldName: name,
      path: pathWithIndex(c.location.parent.path, index),
      index: index,
      kind: entryKind(c.cache, fullPath)))
    return true
  return false

method exitChild*(c: FileSystemCursor): bool =
  prof("exitChild")
  if c.location.parent == nil:
    return false
  c.applyLocation(c.location.parent)
  return true

# Creates a cursor rooted at `root` (defaults to the current working directory).
# `cache` is shared across all clones of a tree; a new one is allocated if nil.
proc fileSystemCursor*(root: string = getCurrentDir(), cache: FileSystemCache = nil): FileSystemCursor =
  let name = extractFilename(root)
  let cursorCache = if cache != nil: cache else: newFileSystemCache()
  result = FileSystemCursor(cache: cursorCache)
  result.applyLocation(FileSystemCursorLocation(
    fullPath: root,
    parentPath: root.parentDir,
    fieldName: if name.len > 0: name else: ".",
    path: @[],
    index: 0,
    kind: entryKind(cursorCache, root)))

proc canDropOn*(dragged, target: FileSystemCursor): bool =
  if dragged == nil or target == nil or target.kind != Folder:
    return false

  let sourcePath = comparablePath(dragged.fullPath)
  let sourceParent = comparablePath(dragged.parentPath)
  let targetPath = comparablePath(target.fullPath)
  if targetPath == sourcePath or targetPath == sourceParent:
    return false
  if targetPath.startsWith(sourcePath & $DirSep):
    return false

  let destination = target.fullPath / dragged.fieldName
  return not fileExists(destination) and not dirExists(destination)

proc moveTo*(dragged, target: FileSystemCursor): bool =
  if not dragged.canDropOn(target):
    return false

  let sourceParent = dragged.parentPath
  let destination = target.fullPath / dragged.fieldName
  try:
    case dragged.kind
    of File:
      moveFile(dragged.fullPath, destination)
    of Folder:
      moveDir(dragged.fullPath, destination)
  except OSError:
    return false

  dragged.cache.listings.del(sourceParent)
  target.cache.listings.del(target.fullPath)
  dragged.cache.kinds.del(dragged.fullPath)
  target.cache.kinds[destination] = dragged.kind
  return true
