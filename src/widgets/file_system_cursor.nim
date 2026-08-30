import os
import algorithm
import tables

import tree_table, profiler

# Shared, clone-transparent cache of directory listings (path -> sorted entry names).
type
  FileSystemCache* = ref object
    listings*: Table[string, seq[string]]

proc newFileSystemCache*(): FileSystemCache =
  result = FileSystemCache()
  result.listings = initTable[string, seq[string]]()

# A cursor that walks a directory tree. Each node is a file or directory rooted
# at the working directory.
type
  FileSystemCursor* = ref object of TreeCursor
    rootPath*: string
    fullPath*: string
    parentPath*: string
    cache*: FileSystemCache

proc listEntries(cache: FileSystemCache, path: string): lent seq[string] =
  if path in cache.listings:
    return cache.listings[path]
  var entries: seq[string]
  if dirExists(path):
    for kind, entryPath in walkDir(path):
      discard kind
      entries.add(extractFilename(entryPath))
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
  result.index = 0
  result.path = @[]
  result.fieldName = if name.len > 0: name else: "."
