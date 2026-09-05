## Non-owning, mutable views over contiguous memory.
##
## `ArrayView` carries a pointer, logical length, and capacity so arena-backed
## arrays and C-compatible buffers can use open-array-like indexing and
## iteration without allocating. The caller must keep the underlying storage
## alive and must not grow a view beyond its capacity.

import std/assertions

include nuigi/util/compat2

proc data*[T](a: openArray[T]): ptr UncheckedArray[T] =
  if a.len > 0:
    cast[ptr UncheckedArray[T]](a[0].addr)
  else:
    cast[ptr UncheckedArray[T]](0)

when defined(nimony):
  type BackwardsIndex = distinct int

else:
  import std/[options]
  import std/macros

type
  ArrayView*[T] = object
    data: ptr UncheckedArray[T]
    capacity: int
    len: int

proc initArrayView*[T](elems: ptr UncheckedArray[T], len: int): ArrayView[T] =
  return ArrayView[T](data: elems, len: len, capacity: len)

proc initArrayView*[T](elems: ptr UncheckedArray[T], len: int, capacity: int): ArrayView[T] =
  assert len <= capacity
  return ArrayView[T](data: elems, len: len, capacity: capacity)

proc initArrayView*[T](elems: openArray[T]): ArrayView[T] =
  return ArrayView[T](data: elems.data, len: elems.len, capacity: elems.len)

proc initArrayView*[T](elems: openArray[T], len: int): ArrayView[T] =
  assert len <= elems.len
  return ArrayView[T](data: elems.data, len: len, capacity: elems.len)

proc low*[T](arr: ArrayView[T]): int =
  0

proc high*[T](arr: ArrayView[T]): int =
  int(arr.len.int - 1)

proc `[]`*[T](arr: var ArrayView[T], index: int): var T =
  assert index >= 0
  assert index < arr.len
  return arr.data[index]

when not defined(nimony): # todo: overloading based on var not supported in nimony?
  proc `[]`*[T](arr: ArrayView[T], index: int): lent T =
    assert index >= 0
    assert index < arr.len
    return arr.data[index]

proc `[]`*[T](arr: var ArrayView[T], index: BackwardsIndex): var T =
  assert index.int >= 1
  assert index.int <= arr.len
  return arr.data[arr.len - index.int]

proc `[]`*[T](arr {.byref.}: ArrayView[T], index: BackwardsIndex): lent T =
  assert index.int >= 1
  assert index.int <= arr.len
  return arr.data[arr.len - index.int]

proc `[]=`*[T](arr: var ArrayView[T], index: int, value: T) =
  assert index >= 0
  assert index < arr.len
  arr.data[index] = value

proc first*[T](arr {.byref.}: ArrayView[T]): nil ptr T =
  if arr.len > 0:
    return arr.data[0].addr
  return nil

proc last*[T](arr {.byref.}: ArrayView[T]): nil ptr T =
  if arr.len > 0:
    return arr.data[arr.high].addr
  return nil

proc add*[T](arr: var ArrayView[T], val: T) {.nodestroy.} =
  assert arr.len < arr.capacity
  arr.data[arr.len.int] = val
  inc arr.len

proc add*[T](arr: var ArrayView[T], vals: ArrayView[T]) {.nodestroy.} =
  assert arr.len + vals.len <= arr.capacity
  for i in 0..vals.high:
    arr.data[arr.len.int + i] = vals.data[i]
  arr.len += vals.len

proc add*[T](arr: var ArrayView[T], vals: openArray[T]) {.nodestroy.} =
  assert arr.len.int + vals.len <= arr.capacity
  for i in 0..vals.high:
    arr.data[arr.len.int + i] = vals[i]
  arr.len += typeof(arr.len)(vals.len)

proc shift*[T](arr: var ArrayView[T], start: int, offset: int) {.nodestroy.} =
  if offset > 0:
    arr.len = arr.len.int + offset
    for i in countdown(arr.high, start):
      arr.data[i + offset] = arr.data[i]
  elif offset < 0:
    for i in start..arr.high:
      arr.data[i + offset] = arr.data[i]
    arr.len = arr.len.int + offset

type
  Stringable = concept
    proc `$`(x: Self): string

proc `$`*[T: Stringable](arr: ArrayView[T]): string =
  result = "("
  for i in 0..<arr.len.int:
    if i > 0:
      result.add ", "
    result.add $arr[i]
  result.add ")"

template toOpenArray*[T](arr: ArrayView[T]): openArray[T] =
  arr.data.toOpenArray(0, arr.high)

template toOpenArray*[T](arr: ArrayView[T], first, last: int): openArray[T] =
  arr.data.toOpenArray(first, last)

proc len*[T](arr: ArrayView[T]): int =
  arr.len.int

proc cap*[T](arr: ArrayView[T]): int =
  arr.capacity.int

proc hasRoom*[T](arr: ArrayView[T]): bool =
  return arr.len.int < arr.capacity.int

proc setLen*[T](arr: var ArrayView[T], newLen: int) =
  assert newLen >= 0
  assert newLen <= arr.capacity
  arr.len = newLen

proc `len=`*[T](arr: var ArrayView[T], newLen: int) =
  assert newLen >= 0
  assert newLen <= arr.capacity
  arr.len = newLen

iterator items*[T](arr: ArrayView[T]): T =
  for i in 0..<arr.len:
    yield arr.data[i]

iterator mitems*[T](arr: var ArrayView[T]): var T =
  for i in 0..<arr.len:
    yield arr.data[i]

iterator pairs*[T](arr: ArrayView[T]): (int, T) =
  for i in 0..<arr.len:
    yield (i, arr.data[i])

iterator pairs*[T](arr: var ArrayView[T]): (int, var T) =
  for i in 0..<arr.len:
    yield (i, arr.data[i])

proc data*[T](arr: var ArrayView[T]): ptr UncheckedArray[T] =
  return arr.data

when isMainModule:
  import std/syncio
  var a = [1, 2, 3, 4, 5]
  var av = initArrayView(a)
  echo av.len
  for i in 0..av.high:
    echo av[i]
