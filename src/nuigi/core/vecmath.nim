## Small vector and matrix math layer shared by layout and rendering.
##
## Defines generic 2D/3D/4D vectors, integer vectors, `Mat4`, component-wise
## operators, interpolation, geometry helpers, and transforms. Most operations
## are inlined; the module also re-exports `std/math` for its scalar helpers.

import std/[math, hashes]
export math

{.push inline.}
type Scalar = concept
  proc `$`(a: Self): string
  proc `-`(a: Self): Self
  proc `-`(a, b: Self): Self
  proc `+`(a, b: Self): Self
  proc `*`(a, b: Self): Self
  proc `/`(a, b: Self): Self
  proc `-=`(a: var Self, b: Self)
  proc `+=`(a: var Self, b: Self)
  proc `*=`(a: var Self, b: Self)
  proc `/=`(a: var Self, b: Self)
  proc `<=`(a, b: Self): bool
  proc `<`(a, b: Self): bool
  proc `==`(a, b: Self): bool
  proc trunc(f: Self): Self
  proc sqrt(f: Self): Self
  proc abs(f: Self): Self

type FloatLike = concept
  proc `$`(a: Self): string
  proc `-`(a: Self): Self
  proc `-`(a, b: Self): Self
  proc `+`(a, b: Self): Self
  proc `*`(a, b: Self): Self
  proc `/`(a, b: Self): Self
  proc `-=`(a: var Self, b: Self)
  proc `+=`(a: var Self, b: Self)
  proc `*=`(a: var Self, b: Self)
  proc `/=`(a: var Self, b: Self)
  proc `<=`(a, b: Self): bool
  proc `<`(a, b: Self): bool
  proc `==`(a, b: Self): bool
  proc trunc(f: Self): Self
  proc sqrt(f: Self): Self
  proc sin(f: Self): Self
  proc cos(f: Self): Self

type HasAlmostEq = concept
  proc `~=`(a, b: Self): bool

type HashableValue = concept
  proc hash(value: Self): Hash

type ModuloScalar = concept
  proc `mod`(a, b: Self): Self

type DivScalar = concept
  proc `div`(a, b: Self): Self

type ZmodScalar = concept
  proc `zmod`(a, b: Self): Self

type
  GVec2*[T] = object
    x*, y*: T
  GVec3*[T] = object
    x*, y*, z*: T
  GVec4*[T] = object
    x*, y*, z*, w*: T
  GVec34[T] = GVec3[T] | GVec4[T]
  GVec234[T] = GVec2[T] | GVec3[T] | GVec4[T]

template gvec2*[T](mx, my: T): GVec2[T] =
  GVec2[T](x: mx, y: my)

template gvec3*[T](mx, my, mz: T): GVec3[T] =
  GVec3[T](x: mx, y: my, z: mz)

template gvec4*[T](mx, my, mz, mw: T): GVec4[T] =
  GVec4[T](x: mx, y: my, z: mz, w: mw)

template `[]`*[T](a: GVec2[T], i: int): T = cast[array[2, T]](a)[i]
template `[]`*[T](a: GVec3[T], i: int): T = cast[array[3, T]](a)[i]
template `[]`*[T](a: GVec4[T], i: int): T = cast[array[4, T]](a)[i]

template `[]=`*[T](a: var GVec2[T], i: int, v: T) =
  cast[ptr T](cast[int](a.addr) + i * sizeof(T))[] = v

template `[]=`*[T](a: var GVec3[T], i: int, v: T) =
  cast[ptr T](cast[int](a.addr) + i * sizeof(T))[] = v

template `[]=`*[T](a: var GVec4[T], i: int, v: T) =
  cast[ptr T](cast[int](a.addr) + i * sizeof(T))[] = v

type
  GMat2*[T] {.bycopy.} = object
    m00*, m01*: T
    m10*, m11*: T
  GMat3*[T] {.bycopy.} = object
    m00*, m01*, m02*: T
    m10*, m11*, m12*: T
    m20*, m21*, m22*: T
  GMat4*[T] {.bycopy.} = object
    m00*, m01*, m02*, m03*: T
    m10*, m11*, m12*, m13*: T
    m20*, m21*, m22*, m23*: T
    m30*, m31*, m32*, m33*: T

func gmat2*[T](
  m00, m01,
  m10, m11: T
): GMat2[T] =
  result.m00 = m00; result.m01 = m01
  result.m10 = m10; result.m11 = m11

func gmat3*[T](
  m00, m01, m02,
  m10, m11, m12,
  m20, m21, m22: T
): GMat3[T] =
  result.m00 = m00; result.m01 = m01; result.m02 = m02
  result.m10 = m10; result.m11 = m11; result.m12 = m12
  result.m20 = m20; result.m21 = m21; result.m22 = m22

func gmat4*[T](
  m00, m01, m02, m03,
  m10, m11, m12, m13,
  m20, m21, m22, m23,
  m30, m31, m32, m33: T
): GMat4[T] =
  result.m00 = m00; result.m01 = m01; result.m02 = m02; result.m03 = m03
  result.m10 = m10; result.m11 = m11; result.m12 = m12; result.m13 = m13
  result.m20 = m20; result.m21 = m21; result.m22 = m22; result.m23 = m23
  result.m30 = m30; result.m31 = m31; result.m32 = m32; result.m33 = m33

template `[]`*[T](a: GMat2[T], i, j: int): T =
  cast[array[4, T]](a)[i * 2 + j]

template `[]`*[T](a: GMat3[T], i, j: int): T =
  cast[array[9, T]](a)[i * 3 + j]

template `[]`*[T](a: GMat4[T], i, j: int): T =
  cast[array[16, T]](a)[i * 4 + j]

template `[]=`*[T](a: var GMat2[T], i, j: int, v: T) =
  cast[ptr T](cast[int](a.addr) + (i * 2 + j) * sizeof(T))[] = v

template `[]=`*[T](a: var GMat3[T], i, j: int, v: T) =
  cast[ptr T](cast[int](a.addr) + (i * 3 + j) * sizeof(T))[] = v

template `[]=`*[T](a: var GMat4[T], i, j: int, v: T) =
  cast[ptr T](cast[int](a.addr) + (i * 4 + j) * sizeof(T))[] = v

template `[]`*[T](a: GMat2[T], i: int): GVec2[T] =
  gvec2[T](
    a[i, 0],
    a[i, 1]
  )

template `[]`*[T](a: GMat3[T], i: int): GVec3[T] =
  gvec3[T](
    a[i, 0],
    a[i, 1],
    a[i, 2]
  )

template `[]`*[T](a: GMat4[T], i: int): GVec4[T] =
  gvec4[T](
    a[i, 0],
    a[i, 1],
    a[i, 2],
    a[i, 3]
  )

type
  BVec2* = GVec2[bool]
  BVec3* = GVec3[bool]
  BVec4* = GVec4[bool]

  IVec2* = GVec2[int32]
  IVec3* = GVec3[int32]
  IVec4* = GVec4[int32]

  UVec2* = GVec2[uint32]
  UVec3* = GVec3[uint32]
  UVec4* = GVec4[uint32]

  Vec2* = GVec2[float32]
  Vec3* = GVec3[float32]
  Vec4* = GVec4[float32]

  DVec2* = GVec2[float64]
  DVec3* = GVec3[float64]
  DVec4* = GVec4[float64]

func `~=`*[T: Scalar](a, b: T): bool =
  ## Almost equal.
  const Epsilon = 0.000001
  abs(a - b) <= Epsilon.T

func between*[T: Scalar](value, min, max: T): bool =
  ## Returns true if value is between min and max or equal to them.
  (value >= min) and (value <= max)

func sign*[T: Scalar](v: T): T =
  ## Returns the sign of a number, -1 or 1.
  if v >= T(0): 1 else: -1

func quantize*[T: Scalar](v, n: T): T =
  ## Makes v be multiple of n. Rounding to integer quantize by 1.0.
  trunc(v / n) * n

func fract*[T: Scalar](v: T): T =
  ## Returns fractional part of a number.
  ## 3.14 -> 0.14
  ## -3.14 -> 0.14
  result = abs(v)
  result = result - trunc(result)

func inversesqrt*[T: Scalar](v: T): T =
  ## Returns inverse square root.
  T(1) / sqrt(v)

func mix*[T: Scalar](a, b, v: T): T =
  ## Interpolates value between a and b.
  ## * 0 -> a
  ## * 1 -> b
  ## * 0.5 -> between a and b
  v * (b - a) + a

func fixAngle*[T: Scalar](angle: T): T =
  ## Normalize the angle to be from -PI to PI radians.
  result = angle
  while result > T(PI):
    result -= T(PI) * 2.T
  while result <= -T(PI):
    result += T(PI) * 2.T

func angleBetween*[T: Scalar](a, b: T): T =
  ## Angle between angle a and angle b.
  ## All angles assume radians.
  fixAngle(b - a)

func turnAngle*[T: Scalar](a, b, speed: T): T =
  ## Move from angle a to angle b with step of v.
  ## All angles assume radians.
  var
    turn = fixAngle(b - a)
  if abs(turn) < speed:
    return b
  elif turn > speed:
    turn = speed
  elif turn < -speed:
    turn = -speed
  a + turn

func toRadians*[T: Scalar](deg: T): T =
  ## Convert degrees to radians.
  PI.T * deg / T(180.0)

func toDegrees*[T: Scalar](rad: T): T =
  ## Convert radians to degrees.
  T(180.0) * rad / PI.T

func isNan*[T: Scalar](x: T): bool =
  ## Returns true if number is a NaN.
  x != T(0.0) and (x != x or x * T(0.5) == x)

func `zmod`*(a, b: float32): float32 =
  ## Float point mod.
  return a - b * floor(a/b)

# IVec
func ivec2*(): IVec2 = gvec2[int32](int32(0), int32(0))
func ivec3*(): IVec3 = gvec3[int32](int32(0), int32(0), int32(0))
func ivec4*(): IVec4 = gvec4[int32](int32(0), int32(0), int32(0), int32(0))

func ivec2*(x, y: int32): IVec2 = gvec2[int32](x, y)
func ivec3*(x, y, z: int32): IVec3 = gvec3[int32](x, y, z)
func ivec4*(x, y, z, w: int32): IVec4 = gvec4[int32](x, y, z, w)

func ivec2*(x: int32): IVec2 = gvec2[int32](x, x)
func ivec3*(x: int32): IVec3 = gvec3[int32](x, x, x)
func ivec4*(x: int32): IVec4 = gvec4[int32](x, x, x, x)

func ivec2*[T: Scalar](x: GVec2[T]): IVec2 =
  gvec2[int32](int32(x.x), int32(x.y))
func ivec3*[T: Scalar](x: GVec3[T]): IVec3 =
  gvec3[int32](int32(x.x), int32(x.y), int32(x[2]))
func ivec4*[T: Scalar](x: GVec4[T]): IVec4 =
  gvec4[int32](int32(x.x), int32(x.y), int32(x[2]), int32(x[3]))

func ivec3*[T: Scalar](x: GVec2[T], z: T = 0): IVec3 =
  gvec3[int32](int32(x.x), int32(x.y), int32(z))
func ivec4*[T: Scalar](x: GVec3[T], w: T = 0): IVec4 =
  gvec4[int32](int32(x.x), int32(x.y), int32(x[2]), int32(w))

func ivec4*[T: Scalar](a, b: GVec2[T]): IVec4 =
  gvec4[int32](int32(a.x), int32(a.y), int32(b.x), int32(b.y))

# Vec
func vec2*(): Vec2 = gvec2[float32](float32(0), float32(0))
func vec3*(): Vec3 = gvec3[float32](float32(0), float32(0), float32(0))
func vec4*(): Vec4 = gvec4[float32](float32(0), float32(0), float32(0), float32(0))

func vec2*[T, U](x: T, y: U): Vec2 = gvec2[float32](x.float32, y.float32)
func vec3*[T, U, V](x: T, y: U, z: V): Vec3 = gvec3[float32](x.float32, y.float32, z.float32)
func vec4*[T, U, V, W](x: T, y: U, z: V, w: W): Vec4 = gvec4[float32](x.float32, y.float32, z.float32, w.float32)

func vec2*[T](x: T): Vec2 = gvec2[float32](x.float32, x.float32)
func vec3*[T](x: T): Vec3 = gvec3[float32](x.float32, x.float32, x.float32)
func vec4*[T](x: T): Vec4 = gvec4[float32](x.float32, x.float32, x.float32, x.float32)

func vec2*[T: Scalar](x: GVec2[T]): Vec2 =
  gvec2[float32](float32(x.x), float32(x.y))
func vec3*[T: Scalar](x: GVec3[T]): Vec3 =
  gvec3[float32](float32(x.x), float32(x.y), float32(x[2]))
func vec4*[T: Scalar](x: GVec4[T]): Vec4 =
  gvec4[float32](float32(x.x), float32(x.y), float32(x[2]), float32(x[3]))

func vec3*[T: Scalar](x: GVec2[T], z: T = 0): Vec3 =
  gvec3[float32](float32(x.x), float32(x.y), float32(z))
func vec4*[T: Scalar](x: GVec3[T], w: T = 0): Vec4 =
  gvec4[float32](float32(x.x), float32(x.y), float32(x[2]), float32(w))

func vec4*[T: Scalar](a, b: GVec2[T]): Vec4 =
  gvec4[float32](float32(a.x), float32(a.y), float32(b.x), float32(b.y))

func vec2*(ivec2: IVec2): Vec2 =
  vec2(ivec2.x.float32, ivec2.y.float32)

# func vec2*(uvec2: Uvec2): Vec2 =
#   vec2(uvec2.x.float32, uvec2.y.float32)

# func ivec2*(uvec2: Uvec2): IVec2 =
#   ivec2(uvec2.x.int32, uvec2.y.int32)

# func uvec2*(ivec2: IVec2): Uvec2 =
#   uvec2(ivec2.x.uint32, ivec2.y.uint32)

func vec3*(ivec3: IVec3): Vec3 =
  vec3(ivec3.x.float32, ivec3.y.float32, ivec3.z.float32)

# func vec3*(uvec3: Uvec3): Vec3 =
#   vec3(uvec3.x.float32, uvec3.y.float32, uvec3.z.float32)

# func ivec3*(uvec3: Uvec3): IVec3 =
#   ivec3(uvec3.x.int32, uvec3.y.int32, uvec3.z.int32)

# func uvec3*(ivec3: IVec3): Uvec3 =
#   uvec3(ivec3.x.uint32, ivec3.y.uint32, ivec3.z.uint32)

func vec4*(ivec4: IVec4): Vec4 =
  vec4(ivec4.x.float32, ivec4.y.float32, ivec4.z.float32, ivec4.w.float32)

# func vec4*(uvec4: Uvec4): Vec4 =
#   vec4(uvec4.x.float32, uvec4.y.float32, uvec4.z.float32, uvec4.w.float32)

# func ivec4*(uvec4: Uvec4): IVec4 =
#   ivec4(uvec4.x.int32, uvec4.y.int32, uvec4.z.int32, uvec4.w.int32)

# func uvec4*(ivec4: IVec4): Uvec4 =
#   uvec4(ivec4.x.uint32, ivec4.y.uint32, ivec4.z.uint32, ivec4.w.uint32)

# func `==`*[T: Scalar](a, b: GVec2[T]): bool =
#   a.x == b.x and a.y == b.y

# func `==`*[T: Scalar](a, b: GVec3[T]): bool =
#   a.x == b.x and a.y == b.y and a.z == b.z

# func `==`*[T: Scalar](a, b: GVec4[T]): bool =
#   a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w

# func `!=`*[T: Scalar](a, b: GVec2[T]): bool =
#   a.x != b.x or a.y != b.y

# func `!=`*[T: Scalar](a, b: GVec3[T]): bool =
#   a.x != b.x or a.y != b.y or a.z != b.z

# func `!=`*[T: Scalar](a, b: GVec4[T]): bool =
#   a.x != b.x or a.y != b.y or a.z != b.z or a.w != b.w

func `+`*[T: Scalar](a, b: GVec2[T]): GVec2[T] = gvec2[T](`+`(a.x, b.x), `+`(a.y, b.y))
func `+`*[T: Scalar](a, b: GVec3[T]): GVec3[T] = gvec3[T](`+`(a.x, b.x), `+`(a.y, b.y), `+`(a.z, b.z))
func `+`*[T: Scalar](a, b: GVec4[T]): GVec4[T] = gvec4[T](`+`(a.x, b.x), `+`(a.y, b.y), `+`(a.z, b.z), `+`(a.w, b.w))
func `+`*[T: Scalar](a: GVec2[T], b: T): GVec2[T] = gvec2[T](`+`(a.x, b), `+`(a.y, b))
func `+`*[T: Scalar](a: GVec3[T], b: T): GVec3[T] = gvec3[T](`+`(a.x, b), `+`(a.y, b), `+`(a.z, b))
func `+`*[T: Scalar](a: GVec4[T], b: T): GVec4[T] = gvec4[T](`+`(a.x, b), `+`(a.y, b), `+`(a.z, b), `+`(a.w, b))
func `+`*[T: Scalar](a: T, b: GVec2[T]): GVec2[T] = gvec2[T](`+`(a, b.x), `+`(a, b.y))
func `+`*[T: Scalar](a: T, b: GVec3[T]): GVec3[T] = gvec3[T](`+`(a, b.x), `+`(a, b.y), `+`(a, b.z))
func `+`*[T: Scalar](a: T, b: GVec4[T]): GVec4[T] = gvec4[T](`+`(a, b.x), `+`(a, b.y), `+`(a, b.z), `+`(a, b.w))

func `-`*[T: Scalar](a, b: GVec2[T]): GVec2[T] = gvec2[T](`-`(a.x, b.x), `-`(a.y, b.y))
func `-`*[T: Scalar](a, b: GVec3[T]): GVec3[T] = gvec3[T](`-`(a.x, b.x), `-`(a.y, b.y), `-`(a.z, b.z))
func `-`*[T: Scalar](a, b: GVec4[T]): GVec4[T] = gvec4[T](`-`(a.x, b.x), `-`(a.y, b.y), `-`(a.z, b.z), `-`(a.w, b.w))
func `-`*[T: Scalar](a: GVec2[T], b: T): GVec2[T] = gvec2[T](`-`(a.x, b), `-`(a.y, b))
func `-`*[T: Scalar](a: GVec3[T], b: T): GVec3[T] = gvec3[T](`-`(a.x, b), `-`(a.y, b), `-`(a.z, b))
func `-`*[T: Scalar](a: GVec4[T], b: T): GVec4[T] = gvec4[T](`-`(a.x, b), `-`(a.y, b), `-`(a.z, b), `-`(a.w, b))
func `-`*[T: Scalar](a: T, b: GVec2[T]): GVec2[T] = gvec2[T](`-`(a, b.x), `-`(a, b.y))
func `-`*[T: Scalar](a: T, b: GVec3[T]): GVec3[T] = gvec3[T](`-`(a, b.x), `-`(a, b.y), `-`(a, b.z))
func `-`*[T: Scalar](a: T, b: GVec4[T]): GVec4[T] = gvec4[T](`-`(a, b.x), `-`(a, b.y), `-`(a, b.z), `-`(a, b.w))

func `*`*[T: Scalar](a, b: GVec2[T]): GVec2[T] = gvec2[T](`*`(a.x, b.x), `*`(a.y, b.y))
func `*`*[T: Scalar](a, b: GVec3[T]): GVec3[T] = gvec3[T](`*`(a.x, b.x), `*`(a.y, b.y), `*`(a.z, b.z))
func `*`*[T: Scalar](a, b: GVec4[T]): GVec4[T] = gvec4[T](`*`(a.x, b.x), `*`(a.y, b.y), `*`(a.z, b.z), `*`(a.w, b.w))
func `*`*[T: Scalar](a: GVec2[T], b: T): GVec2[T] = gvec2[T](`*`(a.x, b), `*`(a.y, b))
func `*`*[T: Scalar](a: GVec3[T], b: T): GVec3[T] = gvec3[T](`*`(a.x, b), `*`(a.y, b), `*`(a.z, b))
func `*`*[T: Scalar](a: GVec4[T], b: T): GVec4[T] = gvec4[T](`*`(a.x, b), `*`(a.y, b), `*`(a.z, b), `*`(a.w, b))
func `*`*[T: Scalar](a: T, b: GVec2[T]): GVec2[T] = gvec2[T](`*`(a, b.x), `*`(a, b.y))
func `*`*[T: Scalar](a: T, b: GVec3[T]): GVec3[T] = gvec3[T](`*`(a, b.x), `*`(a, b.y), `*`(a, b.z))
func `*`*[T: Scalar](a: T, b: GVec4[T]): GVec4[T] = gvec4[T](`*`(a, b.x), `*`(a, b.y), `*`(a, b.z), `*`(a, b.w))

func `/`*[T: Scalar](a, b: GVec2[T]): GVec2[T] = gvec2[T](`/`(a.x, b.x), `/`(a.y, b.y))
func `/`*[T: Scalar](a, b: GVec3[T]): GVec3[T] = gvec3[T](`/`(a.x, b.x), `/`(a.y, b.y), `/`(a.z, b.z))
func `/`*[T: Scalar](a, b: GVec4[T]): GVec4[T] = gvec4[T](`/`(a.x, b.x), `/`(a.y, b.y), `/`(a.z, b.z), `/`(a.w, b.w))
func `/`*[T: Scalar](a: GVec2[T], b: T): GVec2[T] = gvec2[T](`/`(a.x, b), `/`(a.y, b))
func `/`*[T: Scalar](a: GVec3[T], b: T): GVec3[T] = gvec3[T](`/`(a.x, b), `/`(a.y, b), `/`(a.z, b))
func `/`*[T: Scalar](a: GVec4[T], b: T): GVec4[T] = gvec4[T](`/`(a.x, b), `/`(a.y, b), `/`(a.z, b), `/`(a.w, b))
func `/`*[T: Scalar](a: T, b: GVec2[T]): GVec2[T] = gvec2[T](`/`(a, b.x), `/`(a, b.y))
func `/`*[T: Scalar](a: T, b: GVec3[T]): GVec3[T] = gvec3[T](`/`(a, b.x), `/`(a, b.y), `/`(a, b.z))
func `/`*[T: Scalar](a: T, b: GVec4[T]): GVec4[T] = gvec4[T](`/`(a, b.x), `/`(a, b.y), `/`(a, b.z), `/`(a, b.w))

func `mod`*[T: ModuloScalar](a, b: GVec2[T]): GVec2[T] = gvec2[T](`mod`(a.x, b.x), `mod`(a.y, b.y))
func `mod`*[T: ModuloScalar](a, b: GVec3[T]): GVec3[T] = gvec3[T](`mod`(a.x, b.x), `mod`(a.y, b.y), `mod`(a.z, b.z))
func `mod`*[T: ModuloScalar](a, b: GVec4[T]): GVec4[T] = gvec4[T](`mod`(a.x, b.x), `mod`(a.y, b.y), `mod`(a.z, b.z), `mod`(a.w, b.w))
func `mod`*[T: ModuloScalar](a: GVec2[T], b: T): GVec2[T] = gvec2[T](`mod`(a.x, b), `mod`(a.y, b))
func `mod`*[T: ModuloScalar](a: GVec3[T], b: T): GVec3[T] = gvec3[T](`mod`(a.x, b), `mod`(a.y, b), `mod`(a.z, b))
func `mod`*[T: ModuloScalar](a: GVec4[T], b: T): GVec4[T] = gvec4[T](`mod`(a.x, b), `mod`(a.y, b), `mod`(a.z, b), `mod`(a.w, b))
func `mod`*[T: ModuloScalar](a: T, b: GVec2[T]): GVec2[T] = gvec2[T](`mod`(a, b.x), `mod`(a, b.y))
func `mod`*[T: ModuloScalar](a: T, b: GVec3[T]): GVec3[T] = gvec3[T](`mod`(a, b.x), `mod`(a, b.y), `mod`(a, b.z))
func `mod`*[T: ModuloScalar](a: T, b: GVec4[T]): GVec4[T] = gvec4[T](`mod`(a, b.x), `mod`(a, b.y), `mod`(a, b.z), `mod`(a, b.w))

func `div`*[T: DivScalar](a, b: GVec2[T]): GVec2[T] = gvec2[T](`div`(a.x, b.x), `div`(a.y, b.y))
func `div`*[T: DivScalar](a, b: GVec3[T]): GVec3[T] = gvec3[T](`div`(a.x, b.x), `div`(a.y, b.y), `div`(a.z, b.z))
func `div`*[T: DivScalar](a, b: GVec4[T]): GVec4[T] = gvec4[T](`div`(a.x, b.x), `div`(a.y, b.y), `div`(a.z, b.z), `div`(a.w, b.w))
func `div`*[T: DivScalar](a: GVec2[T], b: T): GVec2[T] = gvec2[T](`div`(a.x, b), `div`(a.y, b))
func `div`*[T: DivScalar](a: GVec3[T], b: T): GVec3[T] = gvec3[T](`div`(a.x, b), `div`(a.y, b), `div`(a.z, b))
func `div`*[T: DivScalar](a: GVec4[T], b: T): GVec4[T] = gvec4[T](`div`(a.x, b), `div`(a.y, b), `div`(a.z, b), `div`(a.w, b))
func `div`*[T: DivScalar](a: T, b: GVec2[T]): GVec2[T] = gvec2[T](`div`(a, b.x), `div`(a, b.y))
func `div`*[T: DivScalar](a: T, b: GVec3[T]): GVec3[T] = gvec3[T](`div`(a, b.x), `div`(a, b.y), `div`(a, b.z))
func `div`*[T: DivScalar](a: T, b: GVec4[T]): GVec4[T] = gvec4[T](`div`(a, b.x), `div`(a, b.y), `div`(a, b.z), `div`(a, b.w))

func `zmod`*[T: ZmodScalar](a, b: GVec2[T]): GVec2[T] = gvec2[T](`zmod`(a.x, b.x), `zmod`(a.y, b.y))
func `zmod`*[T: ZmodScalar](a, b: GVec3[T]): GVec3[T] = gvec3[T](`zmod`(a.x, b.x), `zmod`(a.y, b.y), `zmod`(a.z, b.z))
func `zmod`*[T: ZmodScalar](a, b: GVec4[T]): GVec4[T] = gvec4[T](`zmod`(a.x, b.x), `zmod`(a.y, b.y), `zmod`(a.z, b.z), `zmod`(a.w, b.w))
func `zmod`*[T: ZmodScalar](a: GVec2[T], b: T): GVec2[T] = gvec2[T](`zmod`(a.x, b), `zmod`(a.y, b))
func `zmod`*[T: ZmodScalar](a: GVec3[T], b: T): GVec3[T] = gvec3[T](`zmod`(a.x, b), `zmod`(a.y, b), `zmod`(a.z, b))
func `zmod`*[T: ZmodScalar](a: GVec4[T], b: T): GVec4[T] = gvec4[T](`zmod`(a.x, b), `zmod`(a.y, b), `zmod`(a.z, b), `zmod`(a.w, b))
func `zmod`*[T: ZmodScalar](a: T, b: GVec2[T]): GVec2[T] = gvec2[T](`zmod`(a, b.x), `zmod`(a, b.y))
func `zmod`*[T: ZmodScalar](a: T, b: GVec3[T]): GVec3[T] = gvec3[T](`zmod`(a, b.x), `zmod`(a, b.y), `zmod`(a, b.z))
func `zmod`*[T: ZmodScalar](a: T, b: GVec4[T]): GVec4[T] = gvec4[T](`zmod`(a, b.x), `zmod`(a, b.y), `zmod`(a, b.z), `zmod`(a, b.w))

func `+=`*[T: Scalar](a: var GVec2[T], b: GVec2[T]) =
  `+=`(a.x, b.x)
  `+=`(a.y, b.y)

func `+=`*[T: Scalar](a: var GVec3[T], b: GVec3[T]) =
  `+=`(a.x, b.x)
  `+=`(a.y, b.y)
  `+=`(a.z, b.z)

func `+=`*[T: Scalar](a: var GVec4[T], b: GVec4[T]) =
  `+=`(a.x, b.x)
  `+=`(a.y, b.y)
  `+=`(a.z, b.z)
  `+=`(a.w, b.w)

func `+=`*[T: Scalar](a: var GVec2[T], b: T) =
  `+=`(a.x, b)
  `+=`(a.y, b)

func `+=`*[T: Scalar](a: var GVec3[T], b: T) =
  `+=`(a.x, b)
  `+=`(a.y, b)
  `+=`(a.z, b)

func `+=`*[T: Scalar](a: var GVec4[T], b: T) =
  `+=`(a.x, b)
  `+=`(a.y, b)
  `+=`(a.z, b)
  `+=`(a.w, b)


func `-=`*[T: Scalar](a: var GVec2[T], b: GVec2[T]) =
  `-=`(a.x, b.x)
  `-=`(a.y, b.y)

func `-=`*[T: Scalar](a: var GVec3[T], b: GVec3[T]) =
  `-=`(a.x, b.x)
  `-=`(a.y, b.y)
  `-=`(a.z, b.z)

func `-=`*[T: Scalar](a: var GVec4[T], b: GVec4[T]) =
  `-=`(a.x, b.x)
  `-=`(a.y, b.y)
  `-=`(a.z, b.z)
  `-=`(a.w, b.w)

func `-=`*[T: Scalar](a: var GVec2[T], b: T) =
  `-=`(a.x, b)
  `-=`(a.y, b)

func `-=`*[T: Scalar](a: var GVec3[T], b: T) =
  `-=`(a.x, b)
  `-=`(a.y, b)
  `-=`(a.z, b)

func `-=`*[T: Scalar](a: var GVec4[T], b: T) =
  `-=`(a.x, b)
  `-=`(a.y, b)
  `-=`(a.z, b)
  `-=`(a.w, b)


func `*=`*[T: Scalar](a: var GVec2[T], b: GVec2[T]) =
  `*=`(a.x, b.x)
  `*=`(a.y, b.y)

func `*=`*[T: Scalar](a: var GVec3[T], b: GVec3[T]) =
  `*=`(a.x, b.x)
  `*=`(a.y, b.y)
  `*=`(a.z, b.z)

func `*=`*[T: Scalar](a: var GVec4[T], b: GVec4[T]) =
  `*=`(a.x, b.x)
  `*=`(a.y, b.y)
  `*=`(a.z, b.z)
  `*=`(a.w, b.w)

func `*=`*[T: Scalar](a: var GVec2[T], b: T) =
  `*=`(a.x, b)
  `*=`(a.y, b)

func `*=`*[T: Scalar](a: var GVec3[T], b: T) =
  `*=`(a.x, b)
  `*=`(a.y, b)
  `*=`(a.z, b)

func `*=`*[T: Scalar](a: var GVec4[T], b: T) =
  `*=`(a.x, b)
  `*=`(a.y, b)
  `*=`(a.z, b)
  `*=`(a.w, b)


func `/=`*[T: Scalar](a: var GVec2[T], b: GVec2[T]) =
  `/=`(a.x, b.x)
  `/=`(a.y, b.y)

func `/=`*[T: Scalar](a: var GVec3[T], b: GVec3[T]) =
  `/=`(a.x, b.x)
  `/=`(a.y, b.y)
  `/=`(a.z, b.z)

func `/=`*[T: Scalar](a: var GVec4[T], b: GVec4[T]) =
  `/=`(a.x, b.x)
  `/=`(a.y, b.y)
  `/=`(a.z, b.z)
  `/=`(a.w, b.w)

func `/=`*[T: Scalar](a: var GVec2[T], b: T) =
  `/=`(a.x, b)
  `/=`(a.y, b)

func `/=`*[T: Scalar](a: var GVec3[T], b: T) =
  `/=`(a.x, b)
  `/=`(a.y, b)
  `/=`(a.z, b)

func `/=`*[T: Scalar](a: var GVec4[T], b: T) =
  `/=`(a.x, b)
  `/=`(a.y, b)
  `/=`(a.z, b)
  `/=`(a.w, b)

func `-`*[T: Scalar](v: GVec2[T]): GVec2[T] = gvec2[T](`-`(v.x), `-`(v.y))
func `-`*[T: Scalar](v: GVec3[T]): GVec3[T] = gvec3[T](`-`(v.x), `-`(v.y), `-`(v.z))
func `-`*[T: Scalar](v: GVec4[T]): GVec4[T] = gvec4[T](`-`(v.x), `-`(v.y), `-`(v.z), `-`(v.w))

func `~=`*[T: HasAlmostEq](a, b: GVec2[T]): bool =
  ## Almost equal.
  a.x ~= b.x and a.y ~= b.y

func `~=`*[T: HasAlmostEq](a, b: GVec3[T]): bool =
  ## Almost equal.
  a.x ~= b.x and a.y ~= b.y and a.z ~= b.z

func `~=`*[T: HasAlmostEq](a, b: GVec4[T]): bool =
  ## Almost equal.
  a.x ~= b.x and a.y ~= b.y and a.z ~= b.z and a.w ~= b.w

func length*[T: Scalar](a: GVec2[T]): T =
  sqrt(a.x*a.x + a.y*a.y)

func length*[T: Scalar](a: GVec3[T]): T =
  sqrt(a.x*a.x + a.y*a.y + a.z*a.z)

func length*[T: Scalar](a: GVec4[T]): T =
  sqrt(a.x*a.x + a.y*a.y + a.z*a.z + a.w*a.w)

func lengthSq*[T: Scalar](a: GVec2[T]): T =
  a.x*a.x + a.y*a.y

func lengthSq*[T: Scalar](a: GVec3[T]): T =
  a.x*a.x + a.y*a.y + a.z*a.z

func lengthSq*[T: Scalar](a: GVec4[T]): T =
  a.x*a.x + a.y*a.y + a.z*a.z + a.w*a.w

func normalize*[T: Scalar](a: GVec2[T]): GVec2[T] =
  a / a.length

func normalize*[T: Scalar](a: GVec3[T]): GVec3[T] =
  a / a.length

func normalize*[T: Scalar](a: GVec4[T]): GVec4[T] =
  a / a.length

func mix*[T: Scalar](a, b: GVec2[T], v: T): GVec2[T] =
  a * (T(1.0) - v) + b * v

func mix*[T: Scalar](a, b: GVec3[T], v: T): GVec3[T] =
  a * (T(1.0) - v) + b * v

func mix*[T: Scalar](a, b: GVec4[T], v: T): GVec4[T] =
  a * (T(1.0) - v) + b * v

func dot*[T: Scalar](a, b: GVec2[T]): T =
  a.x * b.x + a.y * b.y

func dot*[T: Scalar](a, b: GVec3[T]): T =
  a.x * b.x + a.y * b.y + a.z * b.z

func dot*[T: Scalar](a, b: GVec4[T]): T =
  a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w

func mix*[T: Scalar](a, b, v: GVec2[T]): GVec2[T] =
  result.x = a.x * (T(1.0) - v.x) + b.x * v.x
  result.y = a.y * (T(1.0) - v.y) + b.y * v.y

func mix*[T: Scalar](a, b, v: GVec3[T]): GVec3[T] =
  result.x = a.x * (T(1.0) - v.x) + b.x * v.x
  result.y = a.y * (T(1.0) - v.y) + b.y * v.y
  result.z = a.z * (T(1.0) - v.z) + b.z * v.z

func mix*[T: Scalar](a, b, v: GVec4[T]): GVec4[T] =
  result.x = a.x * (T(1.0) - v.x) + b.x * v.x
  result.y = a.y * (T(1.0) - v.y) + b.y * v.y
  result.z = a.z * (T(1.0) - v.z) + b.z * v.z
  result.w = a.w * (T(1.0) - v.w) + b.w * v.w

func cross*[T: Scalar](a, b: GVec3[T]): GVec3[T] =
  gvec3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x
  )

# func dist*[T: Scalar](at, to: GVec2[T]): T =
#   (at - to).length

# func distSq*[T: Scalar](at, to: GVec2[T]): T =
#   (at - to).lengthSq

# func dir*[T: Scalar](at, to: GVec2[T]): GVec2[T] =
#   (at - to).normalize

# func dist*[T: Scalar](at, to: GVec3[T]): T =
#   (at - to).length

# func distSq*[T: Scalar](at, to: GVec3[T]): T =
#   (at - to).lengthSq

# func dir*[T: Scalar](at, to: GVec3[T]): GVec3[T] =
#   (at - to).normalize

# func dist*[T: Scalar](at, to: GVec4[T]): T =
#   (at - to).length

# func distSq*[T: Scalar](at, to: GVec4[T]): T =
#   (at - to).lengthSq

# func dir*[T: Scalar](at, to: GVec4[T]): GVec4[T] =
#   (at - to).normalize

func dir*[T: FloatLike](angle: T): GVec2[T] =
  gvec2(
    cos(angle),
    sin(angle),
  )

func min*(a, b: Vec2): Vec2 =
  vec2(min(a.x, b.x), min(a.y, b.y))

func min*(a, b: Vec3): Vec3 =
  vec3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))

func min*(a, b: Vec4): Vec4 =
  vec4(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z), min(a.w, b.w))

func min*(a: Vec2, b: float32): Vec2 =
  vec2(min(a.x, b), min(a.y, b))

func min*(a: Vec3, b: float32): Vec3 =
  vec3(min(a.x, b), min(a.y, b), min(a.z, b))

func min*(a: Vec4, b: float32): Vec4 =
  vec4(min(a.x, b), min(a.y, b), min(a.z, b), min(a.w, b))

func max*(a, b: Vec2): Vec2 =
  vec2(max(a.x, b.x), max(a.y, b.y))

func max*(a, b: Vec3): Vec3 =
  vec3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))

func max*(a, b: Vec4): Vec4 =
  vec4(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z), max(a.w, b.w))

func max*(a: Vec2, b: float32): Vec2 =
  vec2(max(a.x, b), max(a.y, b))

func max*(a: Vec3, b: float32): Vec3 =
  vec3(max(a.x, b), max(a.y, b), max(a.z, b))

func max*(a: Vec4, b: float32): Vec4 =
  vec4(max(a.x, b), max(a.y, b), max(a.z, b), max(a.w, b))

proc clamp*[T: Scalar](v, min, max: T): T =
  max(min(v, max), min)

proc clamp*(v, min, max: Vec2): Vec2 =
  vec2(clamp(v.x, min.x, max.x), clamp(v.y, min.y, max.y))

proc clamp*(v, min, max: Vec3): Vec3 =
  vec3(clamp(v.x, min.x, max.x), clamp(v.y, min.y, max.y), clamp(v.z, min.z, max.z))

proc clamp*(v, min, max: Vec4): Vec4 =
  vec4(clamp(v.x, min.x, max.x), clamp(v.y, min.y, max.y), clamp(v.z, min.z, max.z), clamp(v.w, min.w, max.w))

proc clamp*(v: Vec2, min, max: float32): Vec2 =
  vec2(clamp(v.x, min, max), clamp(v.y, min, max))

proc clamp*(v: Vec3, min, max: float32): Vec3 =
  vec3(clamp(v.x, min, max), clamp(v.y, min, max), clamp(v.z, min, max))

proc clamp*(v: Vec4, min, max: float32): Vec4 =
  vec4(clamp(v.x, min, max), clamp(v.y, min, max), clamp(v.z, min, max), clamp(v.w, min, max))

func hash*[T: HashableValue](x: GVec2[T]): Hash {.inline.} =
  result = hash(x.x) !& hash(x.y)
  result = !$result

func hash*[T: HashableValue](x: GVec3[T]): Hash {.inline.} =
  result = hash(x.x) !& hash(x.y) !& hash(x.z)
  result = !$result

func hash*[T: HashableValue](x: GVec4[T]): Hash {.inline.} =
  result = hash(x.x) !& hash(x.y) !& hash(x.z) !& hash(x.w)
  result = !$result

proc `$`*[T: Scalar](a: GVec2[T]): string = "{" & $a.x & ", " & $a.y & "}"
proc `$`*[T: Scalar](a: GVec3[T]): string = "{" & $a.x & ", " & $a.y & ", " & $a.z & "}"
proc `$`*[T: Scalar](a: GVec4[T]): string = "{" & $a.x & ", " & $a.y & ", " & $a.z & ", " & $a.w & "}"

{.pop.}
