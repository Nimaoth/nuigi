# This is a fork of Nim2 stdlib hash.nim, but with `int` replaced with `int64`.

include nuigi/util/compat2

type
  Hash* = uint64
    ## Integer type carrying hash values; combine with `!&` and finish with `!$`.

  Hashable* = concept ## Concept describing types that supply `hash` for tables and sets.
    func hash(a: Self): Hash

func `!&`*(h: Hash; val: uint64): Hash {.inline.} =
  ## Mixes a hash value `h` with `val` to produce a new hash value.
  result = h + val
  result = result + (result shl 10)
  result = result xor (result shr 6)

func `!$`*(h: Hash): Hash {.inline.} =
  ## Finishes the computation of the hash value.
  result = h + h shl 3
  result = result xor (result shr 11)
  result = result + result shl 15

func hash*(u: uint64): Hash {.inline.} = u
when not defined(nimony):
  func hash*(x: int): Hash {.inline.} = cast[Hash](x)

func hash*(x: int64): Hash {.inline.} = cast[Hash](x)
func hash*(x: int32): Hash {.inline.} = cast[Hash](int x)
func hash*(x: char): Hash {.inline.} = Hash(x)
func hash*(x: bool): Hash {.inline.} = Hash(x)
func hash*(x: float64): Hash {.inline.} = cast[Hash](x + 0.0) # +0.0 normalizes -0.0
func hash*(x: float32): Hash {.inline.} = hash(float64(x))
func hash*[T: enum](x: T): Hash {.inline.} = Hash(x)

func hash*[A: Hashable, B: Hashable](x: (A, B)): Hash {.inline.} =
  result = hash(x[0]) !& hash(x[1])
  result = !$result

func hash*[A: Hashable, B: Hashable, C: Hashable](x: (A, B, C)): Hash {.inline.} =
  ## Computes a hash value for `x`.
  result = hash(x[0]) !& hash(x[1]) !& hash(x[2])
  result = !$result

func hash*[T: Hashable](x: seq[T]): Hash =
  ## Computes a hash value for `x`, mixing each element's hash in order.
  result = 0'u
  for a in items(x):
    result = result !& hash(a)
  result = !$result

#[
func hash*[T: object](x: T): Hash {.inline.} =
  result = 0'u
  for y in fields(x):
    result = result !& hash(y)
  result = !$result
]#

func nextTry*(h: Hash; maxHash: int64): Hash {.inline.} =
  ## Advances a hash probe index inside `0 .. maxHash` (linear probing helper).
  result = (h + 1'u) and maxHash.uint64

func hashIgnoreStyle*(x: string): Hash =
  ## Efficient hashing of strings; style is ignored.
  ##
  ## **Note:** This uses a different hashing algorithm than `hash(string)`.
  ##
  ## **See also:**
  ## * `hashIgnoreCase <#hashIgnoreCase,string>`_
  # runnableExamples:
  #   doAssert hashIgnoreStyle("aBr_aCa_dAB_ra") == hashIgnoreStyle("abracadabra")
  #   doAssert hashIgnoreStyle("abcdefghi") != hash("abcdefghi")

  var h: Hash = 0
  var i = 0
  let xLen = x.len
  while i < xLen:
    var c = x[i]
    if c == '_':
      inc(i)
    else:
      if c in {'A'..'Z'}:
        c = chr(ord(c) + (ord('a') - ord('A'))) # toLower()
      h = h !& uint64(ord(c))
      inc(i)
  result = !$h

func hashIgnoreStyle*(sBuf: string, sPos, ePos: int64): Hash =
  ## Efficient hashing of a string buffer, from starting
  ## position `sPos` to ending position `ePos` (included); style is ignored.
  ##
  ## **Note:** This uses a different hashing algorithm than `hash(string)`.
  ##
  ## `hashIgnoreStyle(myBuf, 0, myBuf.high)` is equivalent
  ## to `hashIgnoreStyle(myBuf)`.
  # runnableExamples:
  #   var a = "ABracada_b_r_a"
  #   doAssert hashIgnoreStyle(a, 0, 3) == hashIgnoreStyle(a, 7, a.high)

  var h: Hash = 0
  var i = sPos
  while i <= ePos:
    var c = sBuf[i]
    if c == '_':
      inc(i)
    else:
      if c in {'A'..'Z'}:
        c = chr(ord(c) + (ord('a') - ord('A'))) # toLower()
      h = h !& uint64(ord(c))
      inc(i)
  result = !$h

func hashIgnoreCase*(x: string): Hash =
  ## Efficient hashing of strings; case is ignored.
  ##
  ## **Note:** This uses a different hashing algorithm than `hash(string)`.
  ##
  ## **See also:**
  ## * `hashIgnoreStyle <#hashIgnoreStyle,string>`_
  # runnableExamples:
  #   doAssert hashIgnoreCase("ABRAcaDABRA") == hashIgnoreCase("abRACAdabra")
  #   doAssert hashIgnoreCase("abcdefghi") != hash("abcdefghi")

  var h: Hash = 0
  for i in 0..x.len-1:
    var c = x[i]
    if c in {'A'..'Z'}:
      c = chr(ord(c) + (ord('a') - ord('A'))) # toLower()
    h = h !& uint64(ord(c))
  result = !$h

func hashIgnoreCase*(sBuf: string, sPos, ePos: int64): Hash =
  ## Efficient hashing of a string buffer, from starting
  ## position `sPos` to ending position `ePos` (included); case is ignored.
  ##
  ## **Note:** This uses a different hashing algorithm than `hash(string)`.
  ##
  ## `hashIgnoreCase(myBuf, 0, myBuf.high)` is equivalent
  ## to `hashIgnoreCase(myBuf)`.
  # runnableExamples:
  #   var a = "ABracadabRA"
  #   doAssert hashIgnoreCase(a, 0, 3) == hashIgnoreCase(a, 7, 10)

  var h: Hash = 0
  for i in sPos..ePos:
    var c = sBuf[i]
    if c in {'A'..'Z'}:
      c = chr(ord(c) + (ord('a') - ord('A'))) # toLower()
    h = h !& uint64(ord(c))
  result = !$h

    # discard gFontRender.addFontFace("assets/dontuse/fonts/DejaVuSansMono-Bold.ttf")

func rotl32(x: uint32, r: int64): uint32 {.inline.} =
  (x shl r) or (x shr (32 - r))

func murmurHash(x: openArray[char]): Hash =
  # https://github.com/PeterScott/murmur3/blob/master/murmur3.c
  const
    c1 = 0xcc9e2d51'u32
    c2 = 0x1b873593'u32
    n1 = 0xe6546b64'u32
    m1 = 0x85ebca6b'u32
    m2 = 0xc2b2ae35'u32
  let
    size = len(x)
    stepSize = 4 # 32-bit
    n = size div stepSize
  var
    h1: uint32 = uint32(0)
    i = 0

  # body
  while i < n * stepSize:
    var k1: uint32 = uint32(0)

    copyMem(addr k1, addr x[i], 4)
    inc i, stepSize

    k1 = k1 * c1
    k1 = rotl32(k1, 15)
    k1 = k1 * c2

    h1 = h1 xor k1
    h1 = rotl32(h1, 13)
    h1 = h1*5 + n1

  # tail
  var k1: uint32 = uint32(0)
  var rem = size mod stepSize
  while rem > 0:
    dec rem
    k1 = (k1 shl 8) or (ord(x[i+rem])).uint32
  k1 = k1 * c1
  k1 = rotl32(k1, 15)
  k1 = k1 * c2
  h1 = h1 xor k1

  # finalization
  h1 = h1 xor size.uint32
  h1 = h1 xor (h1 shr 16)
  h1 = h1 * m1
  h1 = h1 xor (h1 shr 13)
  h1 = h1 * m2
  h1 = h1 xor (h1 shr 16)
  return cast[Hash](h1)

func hash*(x: string): Hash =
  ## Efficient hashing of strings.
  ##
  ## **See also:**
  ## * `hashIgnoreStyle <#hashIgnoreStyle,string>`_
  ## * `hashIgnoreCase <#hashIgnoreCase,string>`_
  runnableExamples:
    doAssert hash("abracadabra") != hash("AbracadabrA")
  result = murmurHash(x)
