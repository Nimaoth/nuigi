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

proc newFileSystemCache*(): FileSystemCache =
  result = FileSystemCache()
  result.listings = initTable[string, seq[string]]()
  result.kinds = initTable[string, FileSystemEntryKind]()

# A cursor that walks a directory tree. Each node is a file or directory rooted
# at the working directory.
type
  FileSystemCursor* = ref object of TreeCursor
    rootPath*: string
    fullPath*: string
    parentPath*: string
    cache*: FileSystemCache
    kind*: FileSystemEntryKind

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
  let r = FileSystemCursor()
  r.rootPath = c.rootPath
  r.fullPath = c.fullPath
  r.parentPath = c.parentPath
  r.index = c.index
  r.fieldName = c.fieldName
  r.path = c.path
  r.cache = c.cache
  r.kind = c.kind
  return r

# Identity is the full path, so expansion state matches across frames.
method cursorKey*(c: FileSystemCursor): string =
  return c.fullPath

method childCount*(c: FileSystemCursor): int =
  return listEntries(c.cache, c.fullPath).len

method enterChild*(c: FileSystemCursor): bool =
  prof("enterChild")
  let listing {.cursor.} = listEntries(c.cache, c.fullPath)
  if listing.len == 0:
    return false
  c.parentPath = c.fullPath
  c.fullPath = c.fullPath / listing[0]
  c.kind = entryKind(c.cache, c.fullPath)
  c.index = 0
  c.fieldName = listing[0]
  c.path.add(0)
  return true

method moveNext*(c: FileSystemCursor, count: int = 1): bool =
  prof("moveNext")
  if c.fullPath == c.rootPath:
    return false
  let listing {.cursor.} = listEntries(c.cache, c.parentPath)
  if listing.len == 0:
    return false
  if c.index + count < listing.len:
    c.index += count
    let name = listing[c.index]
    c.fullPath = c.parentPath / name
    c.kind = entryKind(c.cache, c.fullPath)
    c.fieldName = name
    c.path[^1] = c.index
    return true
  return false

method movePrev*(c: FileSystemCursor, count: int = 1): bool =
  if c.fullPath == c.rootPath:
    return false
  let listing {.cursor.} = listEntries(c.cache, c.parentPath)
  if listing.len == 0:
    return false
  if c.index >= count:
    c.index -= count
    let name = listing[c.index]
    c.fullPath = c.parentPath / name
    c.kind = entryKind(c.cache, c.fullPath)
    c.fieldName = name
    c.path[^1] = c.index
    return true
  return false

method exitChild*(c: FileSystemCursor): bool =
  if c.fullPath == c.rootPath:
    return false
  let parent = parentDir(c.fullPath)
  let listing {.cursor.} = listEntries(c.cache, parent.parentDir)
  let name = extractFilename(parent)
  c.index = 0
  for i in 0 ..< listing.len:
    if listing[i] == name:
      c.index = i
      break
  c.fullPath = parent
  c.parentPath = parent.parentDir
  c.kind = entryKind(c.cache, c.fullPath)
  c.fieldName = extractFilename(parent)
  c.path.setLen(c.path.len - 1)
  return true

# Creates a cursor rooted at `root` (defaults to the current working directory).
# `cache` is shared across all clones of a tree; a new one is allocated if nil.
proc fileSystemCursor*(root: string = getCurrentDir(), cache: FileSystemCache = nil): FileSystemCursor =
  let name = extractFilename(root)
  result = FileSystemCursor()
  result.rootPath = root
  result.fullPath = root
  result.parentPath = root.parentDir
  result.cache = if cache != nil: cache else: newFileSystemCache()
  result.kind = entryKind(result.cache, root)
  result.index = 0
  result.path = @[]
  result.fieldName = if name.len > 0: name else: "."

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

  let destination = target.fullPath / extractFilename(dragged.fullPath)
  return not fileExists(destination) and not dirExists(destination)

proc moveTo*(dragged, target: FileSystemCursor): bool =
  if not dragged.canDropOn(target):
    return false

  let sourceParent = dragged.parentPath
  let destination = target.fullPath / extractFilename(dragged.fullPath)
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
