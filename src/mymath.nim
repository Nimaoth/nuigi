when true:
  ##[

  Your one stop shop for vector math routines for 2d and 3d graphics.

  * Pure Nim with no dependencies.
  * Very similar to GLSL Shader Language with extra stuff.
  * Extensively benchmarked.

  ====== =========== =================================================
  Type   Constructor Description
  ====== =========== =================================================
  BVec#  bvec#       vector of booleans
  IVec#  ivec#       vector of signed integers
  UVec#  uvec#       vector of unsigned integers
  Vec#   vec#        vector of single-precision floating-point numbers
  DVec#  dvec#       vector of double-precision floating-point numbers
  ====== =========== =================================================

  You can use these constructors to make them:

  ======= ====== ===== ===== ===== ===== ===== =====
  NIM     GLSL   2     3     4     9     16    4
  ======= ====== ===== ===== ===== ===== ===== =====
  bool    bool   BVec2 BVec3 BVec4
  int32   int    IVec2 IVec3 IVec4
  uint32  uint   UVec2 UVec3 UVec4
  float32 float  Vec2  Vec3  Vec4  Mat3  Mat4  Quat
  float64 double DVec2 DVec3 DVec4 DMat3 DMat4 DQuat
  ======= ====== ===== ===== ===== ===== ===== =====

  ]##

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

  # template lowerType(a: typed): string =
  #   ($type(a)).toLowerAscii()

  # template genVecConstructor*(lower, upper, typ: untyped) =
  #   ## Generate vector constructor for your own type.

  #   func `lower 2`*(): `upper 2` = gvec2[typ](typ(0), typ(0))
  #   func `lower 3`*(): `upper 3` = gvec3[typ](typ(0), typ(0), typ(0))
  #   func `lower 4`*(): `upper 4` = gvec4[typ](typ(0), typ(0), typ(0), typ(0))

  #   func `lower 2`*(x, y: typ): `upper 2` = gvec2[typ](x, y)
  #   func `lower 3`*(x, y, z: typ): `upper 3` = gvec3[typ](x, y, z)
  #   func `lower 4`*(x, y, z, w: typ): `upper 4` = gvec4[typ](x, y, z, w)

  #   func `lower 2`*(x: typ): `upper 2` = gvec2[typ](x, x)
  #   func `lower 3`*(x: typ): `upper 3` = gvec3[typ](x, x, x)
  #   func `lower 4`*(x: typ): `upper 4` = gvec4[typ](x, x, x, x)

  #   func `lower 2`*[T](x: GVec2[T]): `upper 2` =
  #     gvec2[typ](typ(x[0]), typ(x[1]))
  #   func `lower 3`*[T](x: GVec3[T]): `upper 3` =
  #     gvec3[typ](typ(x[0]), typ(x[1]), typ(x[2]))
  #   func `lower 4`*[T](x: GVec4[T]): `upper 4` =
  #     gvec4[typ](typ(x[0]), typ(x[1]), typ(x[2]), typ(x[3]))

  #   func `lower 3`*[T](x: GVec2[T], z: T = 0): `upper 3` =
  #     gvec3[typ](typ(x[0]), typ(x[1]), z)
  #   func `lower 4`*[T](x: GVec3[T], w: T = 0): `upper 4` =
  #     gvec4[typ](typ(x[0]), typ(x[1]), typ(x[2]), w)

  #   func `lower 4`*[T](a, b: GVec2[T]): `upper 4` =
  #     gvec4[typ](typ(a[0]), typ(a[1]), typ(b[0]), typ(b[1]))

  #   func `$`*(a: `upper 2`): string =
  #     lowerType(a) & "(" & $a.x & ", " & $a.y & ")"
  #   func `$`*(a: `upper 3`): string =
  #     lowerType(a) & "(" & $a.x & ", " & $a.y & ", " & $a.z & ")"
  #   func `$`*(a: `upper 4`): string =
  #     lowerType(a) & "(" & $a.x & ", " & $a.y & ", " & $a.z & ", " & $a.w & ")"

  # genVecConstructor(bvec, BVec, bool)
  # genVecConstructor(ivec, IVec, int32)
  # genVecConstructor(uvec, UVec, uint32)
  # genVecConstructor(vec, Vec, float32)
  # genVecConstructor(dvec, DVec, float64)

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

  # func fn*[T: Scalar](v: GVec2[T]): GVec2[T] = gvec2[T](fn(v.x), fn(v.y))
  # func fn*[T: Scalar](v: GVec3[T]): GVec3[T] = gvec3[T](fn(v.x), fn(v.y), fn(v.z))
  # func fn*[T: Scalar](v: GVec4[T]): GVec4[T] = gvec4[T](fn(v.x), fn(v.y), fn(v.z), fn(v.w))

  func `-`*[T: Scalar](v: GVec2[T]): GVec2[T] = gvec2[T](`-`(v.x), `-`(v.y))
  func `-`*[T: Scalar](v: GVec3[T]): GVec3[T] = gvec3[T](`-`(v.x), `-`(v.y), `-`(v.z))
  func `-`*[T: Scalar](v: GVec4[T]): GVec4[T] = gvec4[T](`-`(v.x), `-`(v.y), `-`(v.z), `-`(v.w))

  # genMathFn(`-`)
  # genMathFn(sin)
  # genMathFn(cos)
  # genMathFn(tan)
  # genMathFn(arcsin)
  # genMathFn(arccos)
  # genMathFn(arctan)
  # genMathFn(sinh)
  # genMathFn(cosh)
  # genMathFn(tanh)
  # genMathFn(exp2)
  # genMathFn(inversesqrt)
  # genMathFn(exp)
  # genMathFn(ln)
  # genMathFn(log2)
  # genMathFn(sqrt)
  # genMathFn(floor)
  # genMathFn(ceil)
  # genMathFn(abs)
  # genMathFn(trunc)
  # genMathFn(fract)
  # genMathFn(quantize)
  # genMathFn(toRadians)
  # genMathFn(toDegrees)

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

  # type
  #   Mat2* = GMat2[float32]
  #   Mat3* = GMat3[float32]
  #   Mat4* = GMat4[float32]

  #   DMat2* = GMat2[float64]
  #   DMat3* = GMat3[float64]
  #   DMat4* = GMat4[float64]

  # func matToString[T](a: T, n: int): string =
  #   result = ($type(a)).toLowerAscii()
  #   result.add "(\n"
  #   for x in 0 ..< n:
  #     result.add "  "
  #     for y in 0 ..< n:
  #       result.add $a[x, y] & ", "
  #     result.setLen(result.len - 1)
  #     result.add "\n"
  #   result.setLen(result.len - 2)
  #   result.add "\n)"

  # template genMatConstructor*(lower, upper, T: untyped) =
  #   ## Generate matrix constructor for your own type.
  #   func `lower 2`*(
  #     m00, m01,
  #     m10, m11: T
  #   ): `upper 2` =
  #     result[0, 0] = m00; result[0, 1] = m01
  #     result[1, 0] = m10; result[1, 1] = m11

  #   func `lower 3`*(
  #     m00, m01, m02,
  #     m10, m11, m12,
  #     m20, m21, m22: T
  #   ): `upper 3` =
  #     result[0, 0] = m00; result[0, 1] = m01; result[0, 2] = m02
  #     result[1, 0] = m10; result[1, 1] = m11; result[1, 2] = m12
  #     result[2, 0] = m20; result[2, 1] = m21; result[2, 2] = m22

  #   func `lower 4`*(
  #     m00, m01, m02, m03,
  #     m10, m11, m12, m13,
  #     m20, m21, m22, m23,
  #     m30, m31, m32, m33: T
  #   ): `upper 4` =
  #     result[0, 0] = m00; result[0, 1] = m01
  #     result[0, 2] = m02; result[0, 3] = m03

  #     result[1, 0] = m10; result[1, 1] = m11
  #     result[1, 2] = m12; result[1, 3] = m13

  #     result[2, 0] = m20; result[2, 1] = m21
  #     result[2, 2] = m22; result[2, 3] = m23

  #     result[3, 0] = m30; result[3, 1] = m31
  #     result[3, 2] = m32; result[3, 3] = m33

  #   func `lower 2`*(a, b: GVec2[T]): `upper 2` =
  #     gmat2[T](
  #       a.x, a.y,
  #       b.x, b.y
  #     )
  #   func `lower 3`*(a, b, c: GVec3[T]): `upper 3` =
  #     gmat3[T](
  #       a.x, a.y, a.z,
  #       b.x, b.y, b.z,
  #       c.x, c.y, c.z,
  #     )
  #   func `lower 4`*(a, b, c, d: GVec4[T]): `upper 4` =
  #     gmat4[T](
  #       a.x, a.y, a.z, a.w,
  #       b.x, b.y, b.z, b.w,
  #       c.x, c.y, c.z, c.w,
  #       d.x, d.y, d.z, d.w,
  #     )

  #   func `lower 2`*(): `upper 2` =
  #     gmat2[T](
  #       1.T, 0.T,
  #       0.T, 1.T
  #     )
  #   func `lower 3`*(): `upper 3` =
  #     gmat3[T](
  #       1.T, 0.T, 0.T,
  #       0.T, 1.T, 0.T,
  #       0.T, 0.T, 1.T
  #     )
  #   func `lower 4`*(): `upper 4` =
  #     gmat4[T](
  #       1.T, 0.T, 0.T, 0.T,
  #       0.T, 1.T, 0.T, 0.T,
  #       0.T, 0.T, 1.T, 0.T,
  #       0.T, 0.T, 0.T, 1.T
  #     )

  #   func `$`*(a: `upper 2`): string = matToString(a, 2)
  #   func `$`*(a: `upper 3`): string = matToString(a, 3)
  #   func `$`*(a: `upper 4`): string = matToString(a, 4)

  # genMatConstructor(mat, Mat, float32)
  # genMatConstructor(dmat, DMat, float64)

  # func `~=`*[T](a, b: GMat2[T]): bool =
  #   a[0] ~= b[0] and a[1] ~= b[1]

  # func `~=`*[T](a, b: GMat3[T]): bool =
  #   a[0] ~= b[0] and a[1] ~= b[1] and a[2] ~= b[2]

  # func `~=`*[T](a, b: GMat4[T]): bool =
  #   a[0] ~= b[0] and a[1] ~= b[1] and a[2] ~= b[2] and a[3] ~= b[3]

  # func pos*[T](a: GMat3[T]): GVec2[T] =
  #   gvec2[T](a[2].x, a[2].y)

  # func `pos=`*[T](a: var GMat3[T], pos: GVec2[T]) =
  #   a[2, 0] = pos.x
  #   a[2, 1] = pos.y

  # func forward*[T](a: GMat4[T]): GVec3[T] {.inline.} =
  #   ## Vector facing +Z.
  #   result.x = a[2, 0]
  #   result.y = a[2, 1]
  #   result.z = a[2, 2]

  # func back*[T](a: GMat4[T]): GVec3[T] {.inline.} =
  #   ## Vector facing -Z.
  #   -a.forward()

  # func left*[T](a: GMat4[T]): GVec3[T] {.inline.} =
  #   ## Vector facing +X.
  #   result.x = -a[0, 0]
  #   result.y = -a[0, 1]
  #   result.z = -a[0, 2]

  # func right*[T](a: GMat4[T]): GVec3[T] {.inline.} =
  #   ## Vector facing -X.
  #   -a.left()

  # func up*[T](a: GMat4[T]): GVec3[T] {.inline.} =
  #   ## Vector facing +Y.
  #   result.x = a[1, 0]
  #   result.y = a[1, 1]
  #   result.z = a[1, 2]

  # func down*[T](a: GMat4[T]): GVec3[T] {.inline.} =
  #   ## Vector facing -X.
  #   -a.up()

  # func pos*[T](a: GMat4[T]): GVec3[T] =
  #   ## Position of the matrix.
  #   gvec3[T](a[3].x, a[3].y, a[3].z)

  # func `pos=`*[T](a: var GMat4[T], pos: GVec3[T]) =
  #   ## See the position of the matrix.
  #   a[3, 0] = pos.x
  #   a[3, 1] = pos.y
  #   a[3, 2] = pos.z

  # func `*`*[T](a, b: GMat2[T]): GMat2[T] =
  #   result[0, 0] = b[0, 0] * a[0, 0] + b[0, 1] * a[1, 0]
  #   result[0, 1] = b[0, 0] * a[0, 1] + b[0, 1] * a[1, 1]

  #   result[1, 0] = b[1, 0] * a[0, 0] + b[1, 1] * a[1, 0]
  #   result[1, 1] = b[1, 0] * a[0, 1] + b[1, 1] * a[1, 1]

  # func `*`*[T](a, b: GMat3[T]): GMat3[T] =
  #   result[0, 0] = b[0, 0] * a[0, 0] + b[0, 1] * a[1, 0] + b[0, 2] * a[2, 0]
  #   result[0, 1] = b[0, 0] * a[0, 1] + b[0, 1] * a[1, 1] + b[0, 2] * a[2, 1]
  #   result[0, 2] = b[0, 0] * a[0, 2] + b[0, 1] * a[1, 2] + b[0, 2] * a[2, 2]

  #   result[1, 0] = b[1, 0] * a[0, 0] + b[1, 1] * a[1, 0] + b[1, 2] * a[2, 0]
  #   result[1, 1] = b[1, 0] * a[0, 1] + b[1, 1] * a[1, 1] + b[1, 2] * a[2, 1]
  #   result[1, 2] = b[1, 0] * a[0, 2] + b[1, 1] * a[1, 2] + b[1, 2] * a[2, 2]

  #   result[2, 0] = b[2, 0] * a[0, 0] + b[2, 1] * a[1, 0] + b[2, 2] * a[2, 0]
  #   result[2, 1] = b[2, 0] * a[0, 1] + b[2, 1] * a[1, 1] + b[2, 2] * a[2, 1]
  #   result[2, 2] = b[2, 0] * a[0, 2] + b[2, 1] * a[1, 2] + b[2, 2] * a[2, 2]

  # func `*`*[T](a: GMat2[T], b: GVec2[T]): GVec2[T] =
  #   gvec2[T](
  #     a[0, 0] * b.x + a[1, 0] * b.y,
  #     a[0, 1] * b.x + a[1, 1] * b.y
  #   )

  # func `*`*[T](a: GMat3[T], b: GVec2[T]): GVec2[T] =
  #   gvec2[T](
  #     a[0, 0] * b.x + a[1, 0] * b.y + a[2, 0],
  #     a[0, 1] * b.x + a[1, 1] * b.y + a[2, 1]
  #   )

  # func `*`*[T](a: GMat3[T], b: GVec3[T]): GVec3[T] =
  #   gvec3[T](
  #     a[0, 0] * b.x + a[1, 0] * b.y + a[2, 0] * b.z,
  #     a[0, 1] * b.x + a[1, 1] * b.y + a[2, 1] * b.z,
  #     a[0, 2] * b.x + a[1, 2] * b.y + a[2, 2] * b.z,
  #   )

  # func `*`*[T](a, b: GMat4[T]): GMat4[T] =
  #   let
  #     a00 = a[0, 0]
  #     a01 = a[0, 1]
  #     a02 = a[0, 2]
  #     a03 = a[0, 3]
  #     a10 = a[1, 0]
  #     a11 = a[1, 1]
  #     a12 = a[1, 2]
  #     a13 = a[1, 3]
  #     a20 = a[2, 0]
  #     a21 = a[2, 1]
  #     a22 = a[2, 2]
  #     a23 = a[2, 3]
  #     a30 = a[3, 0]
  #     a31 = a[3, 1]
  #     a32 = a[3, 2]
  #     a33 = a[3, 3]

  #   let
  #     b00 = b[0, 0]
  #     b01 = b[0, 1]
  #     b02 = b[0, 2]
  #     b03 = b[0, 3]
  #     b10 = b[1, 0]
  #     b11 = b[1, 1]
  #     b12 = b[1, 2]
  #     b13 = b[1, 3]
  #     b20 = b[2, 0]
  #     b21 = b[2, 1]
  #     b22 = b[2, 2]
  #     b23 = b[2, 3]
  #     b30 = b[3, 0]
  #     b31 = b[3, 1]
  #     b32 = b[3, 2]
  #     b33 = b[3, 3]

  #   result[0, 0] = b00 * a00 + b01 * a10 + b02 * a20 + b03 * a30
  #   result[0, 1] = b00 * a01 + b01 * a11 + b02 * a21 + b03 * a31
  #   result[0, 2] = b00 * a02 + b01 * a12 + b02 * a22 + b03 * a32
  #   result[0, 3] = b00 * a03 + b01 * a13 + b02 * a23 + b03 * a33

  #   result[1, 0] = b10 * a00 + b11 * a10 + b12 * a20 + b13 * a30
  #   result[1, 1] = b10 * a01 + b11 * a11 + b12 * a21 + b13 * a31
  #   result[1, 2] = b10 * a02 + b11 * a12 + b12 * a22 + b13 * a32
  #   result[1, 3] = b10 * a03 + b11 * a13 + b12 * a23 + b13 * a33

  #   result[2, 0] = b20 * a00 + b21 * a10 + b22 * a20 + b23 * a30
  #   result[2, 1] = b20 * a01 + b21 * a11 + b22 * a21 + b23 * a31
  #   result[2, 2] = b20 * a02 + b21 * a12 + b22 * a22 + b23 * a32
  #   result[2, 3] = b20 * a03 + b21 * a13 + b22 * a23 + b23 * a33

  #   result[3, 0] = b30 * a00 + b31 * a10 + b32 * a20 + b33 * a30
  #   result[3, 1] = b30 * a01 + b31 * a11 + b32 * a21 + b33 * a31
  #   result[3, 2] = b30 * a02 + b31 * a12 + b32 * a22 + b33 * a32
  #   result[3, 3] = b30 * a03 + b31 * a13 + b32 * a23 + b33 * a33

  # func `*`*[T](a: GMat4[T], b: GVec3[T]): GVec3[T] =
  #   gvec3[T](
  #     a[0, 0] * b.x + a[1, 0] * b.y + a[2, 0] * b.z + a[3, 0],
  #     a[0, 1] * b.x + a[1, 1] * b.y + a[2, 1] * b.z + a[3, 1],
  #     a[0, 2] * b.x + a[1, 2] * b.y + a[2, 2] * b.z + a[3, 2]
  #   )

  # func `*`*[T](a: GMat4[T], b: GVec4[T]): GVec4[T] =
  #   gvec4[T](
  #     a[0, 0] * b.x + a[1, 0] * b.y + a[2, 0] * b.z + a[3, 0] * b.w,
  #     a[0, 1] * b.x + a[1, 1] * b.y + a[2, 1] * b.z + a[3, 1] * b.w,
  #     a[0, 2] * b.x + a[1, 2] * b.y + a[2, 2] * b.z + a[3, 2] * b.w,
  #     a[0, 3] * b.x + a[1, 3] * b.y + a[2, 3] * b.z + a[3, 3] * b.w
  #   )

  # func transpose*[T](a: GMat2[T]): GMat2[T] =
  #   ## Return a transpose of the matrix.
  #   gmat2[T](
  #     a[0, 0], a[1, 0],
  #     a[0, 1], a[1, 1]
  #   )

  # func transpose*[T](a: GMat3[T]): GMat3[T] =
  #   ## Return a transpose of the matrix.
  #   gmat3[T](
  #     a[0, 0], a[1, 0], a[2, 0],
  #     a[0, 1], a[1, 1], a[2, 1],
  #     a[0, 2], a[1, 2], a[2, 2]
  #   )

  # func transpose*[T](a: GMat4[T]): GMat4[T] =
  #   ## Return an transpose of the matrix.
  #   gmat4[T](
  #     a[0, 0], a[1, 0], a[2, 0], a[3, 0],
  #     a[0, 1], a[1, 1], a[2, 1], a[3, 1],
  #     a[0, 2], a[1, 2], a[2, 2], a[3, 2],
  #     a[0, 3], a[1, 3], a[2, 3], a[3, 3]
  #   )

  # func determinant*[T](a: GMat2[T]): T =
  #   ## Compute a determinant of the matrix.
  #   a[0, 0] * a[1, 1] - a[1, 0] * a[0, 1]

  # func determinant*[T](a: GMat3[T]): T =
  #   ## Compute a determinant of the matrix.
  #   (
  #     a[0, 0] * (a[1, 1] * a[2, 2] - a[2, 1] * a[1, 2]) -
  #     a[0, 1] * (a[1, 0] * a[2, 2] - a[1, 2] * a[2, 0]) +
  #     a[0, 2] * (a[1, 0] * a[2, 1] - a[1, 1] * a[2, 0])
  #   )

  # func determinant*[T](a: GMat4[T]): T =
  #   ## Compute a determinant of the matrix.
  #   let
  #     a00 = a[0, 0]
  #     a01 = a[0, 1]
  #     a02 = a[0, 2]
  #     a03 = a[0, 3]
  #     a10 = a[1, 0]
  #     a11 = a[1, 1]
  #     a12 = a[1, 2]
  #     a13 = a[1, 3]
  #     a20 = a[2, 0]
  #     a21 = a[2, 1]
  #     a22 = a[2, 2]
  #     a23 = a[2, 3]
  #     a30 = a[3, 0]
  #     a31 = a[3, 1]
  #     a32 = a[3, 2]
  #     a33 = a[3, 3]
  #   (
  #     a30*a21*a12*a03 - a20*a31*a12*a03 - a30*a11*a22*a03 + a10*a31*a22*a03 +
  #     a20*a11*a32*a03 - a10*a21*a32*a03 - a30*a21*a02*a13 + a20*a31*a02*a13 +
  #     a30*a01*a22*a13 - a00*a31*a22*a13 - a20*a01*a32*a13 + a00*a21*a32*a13 +
  #     a30*a11*a02*a23 - a10*a31*a02*a23 - a30*a01*a12*a23 + a00*a31*a12*a23 +
  #     a10*a01*a32*a23 - a00*a11*a32*a23 - a20*a11*a02*a33 + a10*a21*a02*a33 +
  #     a20*a01*a12*a33 - a00*a21*a12*a33 - a10*a01*a22*a33 + a00*a11*a22*a33
  #   )

  # func inverse*[T](a: GMat2[T]): GMat2[T] =
  #   ## Return an inverse of the matrix.
  #   let invDet = 1 / a.determinant
  #   result[0, 0] = +a[1, 1] * invDet
  #   result[0, 1] = -a[0, 1] * invDet
  #   result[1, 0] = -a[1, 0] * invDet
  #   result[1, 1] = +a[0, 0] * invDet

  # func inverse*[T](a: GMat3[T]): GMat3[T] =
  #   ## Return an inverse of the matrix.
  #   let
  #     invDet = 1 / a.determinant

  #   result[0, 0] = +(a[1, 1] * a[2, 2] - a[2, 1] * a[1, 2]) * invDet
  #   result[0, 1] = -(a[0, 1] * a[2, 2] - a[0, 2] * a[2, 1]) * invDet
  #   result[0, 2] = +(a[0, 1] * a[1, 2] - a[0, 2] * a[1, 1]) * invDet

  #   result[1, 0] = -(a[1, 0] * a[2, 2] - a[1, 2] * a[2, 0]) * invDet
  #   result[1, 1] = +(a[0, 0] * a[2, 2] - a[0, 2] * a[2, 0]) * invDet
  #   result[1, 2] = -(a[0, 0] * a[1, 2] - a[1, 0] * a[0, 2]) * invDet

  #   result[2, 0] = +(a[1, 0] * a[2, 1] - a[2, 0] * a[1, 1]) * invDet
  #   result[2, 1] = -(a[0, 0] * a[2, 1] - a[2, 0] * a[0, 1]) * invDet
  #   result[2, 2] = +(a[0, 0] * a[1, 1] - a[1, 0] * a[0, 1]) * invDet

  # func inverse*[T](a: GMat4[T]): GMat4[T] =
  #   ## Return an inverse of the matrix.
  #   let
  #     a00 = a[0, 0]
  #     a01 = a[0, 1]
  #     a02 = a[0, 2]
  #     a03 = a[0, 3]
  #     a10 = a[1, 0]
  #     a11 = a[1, 1]
  #     a12 = a[1, 2]
  #     a13 = a[1, 3]
  #     a20 = a[2, 0]
  #     a21 = a[2, 1]
  #     a22 = a[2, 2]
  #     a23 = a[2, 3]
  #     a30 = a[3, 0]
  #     a31 = a[3, 1]
  #     a32 = a[3, 2]
  #     a33 = a[3, 3]

  #   let
  #     b00 = a00 * a11 - a01 * a10
  #     b01 = a00 * a12 - a02 * a10
  #     b02 = a00 * a13 - a03 * a10
  #     b03 = a01 * a12 - a02 * a11
  #     b04 = a01 * a13 - a03 * a11
  #     b05 = a02 * a13 - a03 * a12
  #     b06 = a20 * a31 - a21 * a30
  #     b07 = a20 * a32 - a22 * a30
  #     b08 = a20 * a33 - a23 * a30
  #     b09 = a21 * a32 - a22 * a31
  #     b10 = a21 * a33 - a23 * a31
  #     b11 = a22 * a33 - a23 * a32

  #   # Calculate the inverse determinant.
  #   let invDet = 1 / a.determinant

  #   result[0, 0] = (+a11 * b11 - a12 * b10 + a13 * b09) * invDet
  #   result[0, 1] = (-a01 * b11 + a02 * b10 - a03 * b09) * invDet
  #   result[0, 2] = (+a31 * b05 - a32 * b04 + a33 * b03) * invDet
  #   result[0, 3] = (-a21 * b05 + a22 * b04 - a23 * b03) * invDet

  #   result[1, 0] = (-a10 * b11 + a12 * b08 - a13 * b07) * invDet
  #   result[1, 1] = (+a00 * b11 - a02 * b08 + a03 * b07) * invDet
  #   result[1, 2] = (-a30 * b05 + a32 * b02 - a33 * b01) * invDet
  #   result[1, 3] = (+a20 * b05 - a22 * b02 + a23 * b01) * invDet

  #   result[2, 0] = (+a10 * b10 - a11 * b08 + a13 * b06) * invDet
  #   result[2, 1] = (-a00 * b10 + a01 * b08 - a03 * b06) * invDet
  #   result[2, 2] = (+a30 * b04 - a31 * b02 + a33 * b00) * invDet
  #   result[2, 3] = (-a20 * b04 + a21 * b02 - a23 * b00) * invDet

  #   result[3, 0] = (-a10 * b09 + a11 * b07 - a12 * b06) * invDet
  #   result[3, 1] = (+a00 * b09 - a01 * b07 + a02 * b06) * invDet
  #   result[3, 2] = (-a30 * b03 + a31 * b01 - a32 * b00) * invDet
  #   result[3, 3] = (+a20 * b03 - a21 * b01 + a22 * b00) * invDet

  # func scale*[T](v: GVec2[T]): GMat3[T] =
  #   ## Create scale matrix.
  #   gmat3[T](
  #     v.x, 0, 0,
  #     0, v.y, 0,
  #     0, 0, 1
  #   )

  # func scale*[T](v: GVec3[T]): GMat4[T] =
  #   ## Create scale matrix.
  #   gmat4[T](
  #     v.x, 0, 0, 0,
  #     0, v.y, 0, 0,
  #     0, 0, v.z, 0,
  #     0, 0, 0, 1
  #   )

  # func translate*[T](v: GVec2[T]): GMat3[T] =
  #   ## Create translation matrix.
  #   gmat3[T](
  #     1, 0, 0,
  #     0, 1, 0,
  #     v.x, v.y, 1
  #   )

  # func translate*[T](v: GVec3[T]): GMat4[T] =
  #   ## Create translation matrix.
  #   gmat4[T](
  #     1, 0, 0, 0,
  #     0, 1, 0, 0,
  #     0, 0, 1, 0,
  #     v.x, v.y, v.z, 1
  #   )

  # func rotate*[T](angle: T): GMat3[T] =
  #   ## Create a 2D rotation matrix by an angle.
  #   ## All angles assume radians.
  #   let
  #     sin = sin(angle)
  #     cos = cos(angle)
  #   gmat3[T](
  #     cos, sin, 0,
  #     -sin, cos, 0,
  #     0, 0, 1
  #   )

  # func rotationOnly*[T](a: GMat4[T]): GMat4[T] {.inline.} =
  #   ## Clears the positional component and returns rotation only.
  #   ## Assumes matrix has not been scaled.
  #   result = a
  #   result.pos = gvec3[T](0, 0, 0)

  # func rotateX*[T](angle: T): GMat4[T] =
  #   ## Return a rotation matrix around X with angle.
  #   ## All angles assume radians.
  #   result[0, 0] = 1
  #   result[0, 1] = 0
  #   result[0, 2] = 0
  #   result[0, 3] = 0

  #   result[1, 0] = 0
  #   result[1, 1] = cos(angle)
  #   result[1, 2] = sin(angle)
  #   result[1, 3] = 0

  #   result[2, 0] = 0
  #   result[2, 1] = -sin(angle)
  #   result[2, 2] = cos(angle)
  #   result[2, 3] = 0

  #   result[3, 0] = 0
  #   result[3, 1] = 0
  #   result[3, 2] = 0
  #   result[3, 3] = 1

  # func rotateY*[T](angle: T): GMat4[T] =
  #   ## Return a rotation matrix around Y with angle.
  #   ## All angles assume radians.
  #   result[0, 0] = cos(angle)
  #   result[0, 1] = 0
  #   result[0, 2] = -sin(angle)
  #   result[0, 3] = 0

  #   result[1, 0] = 0
  #   result[1, 1] = 1
  #   result[1, 2] = 0
  #   result[1, 3] = 0

  #   result[2, 0] = sin(angle)
  #   result[2, 1] = 0
  #   result[2, 2] = cos(angle)
  #   result[2, 3] = 0

  #   result[3, 0] = 0
  #   result[3, 1] = 0
  #   result[3, 2] = 0
  #   result[3, 3] = 1

  # func rotateZ*[T](angle: T): GMat4[T] =
  #   ## Return a rotation matrix around Z with angle.
  #   ## All angles assume radians.
  #   result[0, 0] = cos(angle)
  #   result[0, 1] = sin(angle)
  #   result[0, 2] = 0
  #   result[0, 3] = 0

  #   result[1, 0] = -sin(angle)
  #   result[1, 1] = cos(angle)
  #   result[1, 2] = 0
  #   result[1, 3] = 0

  #   result[2, 0] = 0
  #   result[2, 1] = 0
  #   result[2, 2] = 1
  #   result[2, 3] = 0

  #   result[3, 0] = 0
  #   result[3, 1] = 0
  #   result[3, 2] = 0
  #   result[3, 3] = 1

  # func toAngles*[T](a: GVec3[T]): GVec3[T] =
  #   ## Given a 3d vector, computes Euler angles: pitch and yaw
  #   ##   pitch (x rotation)
  #   ##   yaw (y rotation)
  #   ##   roll (z rotation) - always 0 in vector case
  #   ## All angles assume radians.
  #   if a == gvec3[T](T(0), T(0), T(0)):
  #     return
  #   let
  #     yaw = -arctan2(a.x, a.z)
  #     pitch = -arctan2(sqrt(a.x*a.x + a.z*a.z), a.y) + T(PI/2)
  #   result.x = pitch.fixAngle
  #   result.y = yaw.fixAngle

  # func toAngles*[T](origin, target: GVec3[T]): GVec3[T] =
  #   ## Gives Euler angles from origin to target
  #   ##   pitch (x rotation)
  #   ##   yaw (y rotation)
  #   ##   roll (z rotation) - always 0 in vector case
  #   ## All angles assume radians.
  #   toAngles(target - origin)

  # func toAngles*[T](m: GMat4[T]): GVec3[T] =
  #   ## Decomposes the matrix into Euler angles:
  #   ##   pitch (x rotation)
  #   ##   yaw (y rotation)
  #   ##   roll (z rotation)
  #   ## Assumes matrix has not been scaled.
  #   ## All angles assume radians.
  #   let sy = clamp(-m[2, 1], T(-1), T(1))
  #   result.x = arcsin(sy)
  #   if abs(sy) > T(0.9999999):
  #     # Degenerate case (gimbal lock).
  #     result.y = arctan2(-m[0, 2], m[0, 0])
  #   else:
  #     # Normal case.
  #     result.y = arctan2(m[2, 0], m[2, 2])
  #     result.z = arctan2(m[0, 1], m[1, 1])

  # func fromAngles*[T](a: GVec3[T]): GMat4[T] =
  #   ## Takes a vector containing Euler angles and returns a matrix.
  #   ## All angles assume radians.
  #   rotateY(a.y) * rotateX(a.x) * rotateZ(a.z)

  # func frustum*[T](left, right, bottom, top, near, far: T): GMat4[T] =
  #   ## Create a frustum matrix.
  #   let
  #     rl = (right - left)
  #     tb = (top - bottom)
  #     fn = (far - near)

  #   result[0, 0] = (near * 2) / rl
  #   result[0, 1] = 0
  #   result[0, 2] = 0
  #   result[0, 3] = 0

  #   result[1, 0] = 0
  #   result[1, 1] = (near * 2) / tb
  #   result[1, 2] = 0
  #   result[1, 3] = 0

  #   result[2, 0] = (right + left) / rl
  #   result[2, 1] = (top + bottom) / tb
  #   result[2, 2] = -(far + near) / fn
  #   result[2, 3] = -1

  #   result[3, 0] = 0
  #   result[3, 1] = 0
  #   result[3, 2] = -(far * near * 2) / fn
  #   result[3, 3] = 0

  # func perspective*[T](fovy, aspect, near, far: T): GMat4[T] =
  #   ## Create a perspective matrix.
  #   let
  #     top: T = near * tan(fovy * PI.float32 / 360.0)
  #     right: T = top * aspect
  #   frustum(-right, right, -top, top, near, far)

  # func ortho*[T](left, right, bottom, top, near, far: T): GMat4[T] =
  #   ## Create an orthographic matrix.
  #   let
  #     rl: T = (right - left)
  #     tb: T = (top - bottom)
  #     fn: T = (far - near)

  #   result[0, 0] = T(2 / rl)
  #   result[0, 1] = 0
  #   result[0, 2] = 0
  #   result[0, 3] = 0

  #   result[1, 0] = 0
  #   result[1, 1] = T(2 / tb)
  #   result[1, 2] = 0
  #   result[1, 3] = 0

  #   result[2, 0] = 0
  #   result[2, 1] = 0
  #   result[2, 2] = T(-2 / fn)
  #   result[2, 3] = 0

  #   result[3, 0] = T(-(left + right) / rl)
  #   result[3, 1] = T(-(top + bottom) / tb)
  #   result[3, 2] = T(-(far + near) / fn)
  #   result[3, 3] = 1

  # func lookAt*[T](eye, center, up: GVec3[T]): GMat4[T] =
  #   ## Create a matrix that would convert eye pos to looking at center.
  #   let
  #     eyex = eye[0]
  #     eyey = eye[1]
  #     eyez = eye[2]
  #     upx = up[0]
  #     upy = up[1]
  #     upz = up[2]
  #     centerx = center[0]
  #     centery = center[1]
  #     centerz = center[2]

  #   if eyex == centerx and eyey == centery and eyez == centerz:
  #     return

  #   var
  #     # vec3.direction(eye, center, z)
  #     z0 = eyex - center[0]
  #     z1 = eyey - center[1]
  #     z2 = eyez - center[2]

  #   # normalize (no check needed for 0 because of early return)
  #   var len = 1 / sqrt(z0 * z0 + z1 * z1 + z2 * z2)
  #   z0 *= len
  #   z1 *= len
  #   z2 *= len

  #   var
  #     # vec3.normalize(vec3.cross(up, z, x))
  #     x0 = upy * z2 - upz * z1
  #     x1 = upz * z0 - upx * z2
  #     x2 = upx * z1 - upy * z0
  #   len = sqrt(x0 * x0 + x1 * x1 + x2 * x2)
  #   if len == 0:
  #     x0 = 0
  #     x1 = 0
  #     x2 = 0
  #   else:
  #     len = 1 / len
  #     x0 *= len
  #     x1 *= len
  #     x2 *= len

  #   var
  #     # vec3.normalize(vec3.cross(z, x, y))
  #     y0 = z1 * x2 - z2 * x1
  #     y1 = z2 * x0 - z0 * x2
  #     y2 = z0 * x1 - z1 * x0

  #   len = sqrt(y0 * y0 + y1 * y1 + y2 * y2)
  #   if len == 0:
  #     y0 = 0
  #     y1 = 0
  #     y2 = 0
  #   else:
  #     len = 1/len
  #     y0 *= len
  #     y1 *= len
  #     y2 *= len

  #   result[0, 0] = x0
  #   result[0, 1] = y0
  #   result[0, 2] = z0
  #   result[0, 3] = 0

  #   result[1, 0] = x1
  #   result[1, 1] = y1
  #   result[1, 2] = z1
  #   result[1, 3] = 0

  #   result[2, 0] = x2
  #   result[2, 1] = y2
  #   result[2, 2] = z2
  #   result[2, 3] = 0

  #   result[3, 0] = -(x0 * eyex + x1 * eyey + x2 * eyez)
  #   result[3, 1] = -(y0 * eyex + y1 * eyey + y2 * eyez)
  #   result[3, 2] = -(z0 * eyex + z1 * eyey + z2 * eyez)
  #   result[3, 3] = 1

  # func lookAt*[T](eye, center: GVec3[T]): GMat4[T] =
  #   ## Look at center from eye with default UP vector.
  #   lookAt(eye, center, gvec3(T(0), 1, 0))

  # func angle*[T](a: GVec2[T]): T =
  #   ## Angle of a Vec2.
  #   arctan2(a.y, a.x)

  # func angle*[T; S: GVec2[T]|GVec3[T]](a, b: S): T =
  #   ## Angle between 2 Vec2 or Vec3.
  #   var dot = dot(a, b)
  #   dot = dot / (a.length * b.length)
  #   # The cases of angle((1, 1), (-1, -1)) and its 3d counterpart
  #   # angle((1, 1, 1), (-1, -1, -1)) result in NaN due to a domain defect going
  #   # into the arcos func: abs(x) > 1.0.
  #   # Therefore, we must `clamp` here.
  #   arccos(dot.clamp(-1.0, 1.0))

  # type
  #   Quat* = GVec4[float32]
  #   DQuat* = GVec4[float64]

  # template genQuatConstructor*(lower, upper, typ: untyped) =
  #   ## Generate quaternion constructor for your own type.
  #   func `lower`*(): `upper` = gvec4[typ](0, 0, 0, 1)
  #   func `lower`*(x, y, z, w: typ): `upper` = gvec4[typ](x, y, z, w)
  #   func `lower`*(x: typ): `upper` = gvec4[typ](x, x, x, x)
  #   func `lower`*[T](x: GVec4[T]): `upper` =
  #     gvec4[typ](typ(x[0]), typ(x[1]), typ(x[2]), typ(x[3]))

  # genQuatConstructor(quat, Quat, float32)
  # genQuatConstructor(dquat, DQuat, float64)

  # func fromAxisAngle*[T](axis: GVec3[T], angle: T): GVec4[T] =
  #   ## Create a quaternion from axis and angle.
  #   let
  #     a = axis.normalize()
  #     s = sin(angle / 2)
  #   gvec4[T](
  #     a.x * s,
  #     a.y * s,
  #     a.z * s,
  #     cos(angle / 2)
  #   )

  # func toAxisAngle*[T](q: GVec4[T]): (GVec3[T], T) =
  #   ## Convert a quaternion to axis and angle.
  #   let w = clamp(q.w, T(-1), T(1))
  #   let angle = arccos(w) * 2
  #   let sinAngle = sqrt(1 - w * w)
  #   if abs(sinAngle) < T(0.0005):
  #     return (gvec3[T](1, 0, 0), angle)
  #   return (gvec3[T](q.x / sinAngle, q.y / sinAngle, q.z / sinAngle), angle)

  # func quatInverse*[T](q: GVec4[T]): GVec4[T] =
  #   ## Return the inverse of a quaternion.
  #   ## For unit quaternions this is the conjugate.
  #   let d = dot(q, q)
  #   gvec4[T](-q.x / d, -q.y / d, -q.z / d, q.w / d)

  # func orthogonal*[T](v: GVec3[T]): GVec3[T] =
  #   ## Returns orthogonal vector to given vector.
  #   let
  #     v = abs(v)
  #     other: type(v) =
  #       if v.x < v.y:
  #         if v.x < v.z:
  #           gvec3(T(1), 0, 0) # X_AXIS
  #         else:
  #           gvec3(T(0), 0, 1) # Z_AXIS
  #       elif v.y < v.z:
  #         gvec3(T(0), 1, 0)   # Y_AXIS
  #       else:
  #         gvec3(T(0), 0, 1)   # Z_AXIS
  #   return cross(v, other)

  # func fromTwoVectors*[T](a, b: GVec3[T]): GVec4[T] =
  #   ## Return a quat that would take a and rotate it into b.

  #   # It is important that the inputs are of equal length when
  #   # calculating the half-way vector.
  #   let
  #     u = b.normalize()
  #     v = a.normalize()

  #   # Unfortunately, we have to check for when u == -v, as u + v
  #   # in this case will be (0, 0, 0), which cannot be normalized.
  #   if (u == -v):
  #     # 180 degree rotation around any orthogonal vector
  #     let q = normalize(orthogonal(u))
  #     return gvec4(q.x, q.y, q.z, 0)

  #   let
  #     half = normalize(u + v)
  #     q = cross(v, half)
  #     w = dot(v, half)
  #   return gvec4(q.x, q.y, q.z, w)

  # func nlerp*(a: Quat, b: Quat, v: float32): Quat =
  #   if dot(a, b) < 0:
  #     (-a * (1.0 - v) + b * v).normalize()
  #   else:
  #     (a * (1.0 - v) + b * v).normalize()

  # func slerp*[T](a, b: GVec4[T], t: T): GVec4[T] =
  #   ## Spherical linear interpolation between two quaternions.
  #   var z = b
  #   var cosTheta = dot(a, b)

  #   # Take short path.
  #   if cosTheta < 0:
  #     z = -b
  #     cosTheta = -cosTheta

  #   # Linear interpolation when nearly parallel to avoid division by zero.
  #   if cosTheta > 1 - T(1e-6):
  #     return gvec4(
  #       a.x + (z.x - a.x) * t,
  #       a.y + (z.y - a.y) * t,
  #       a.z + (z.z - a.z) * t,
  #       a.w + (z.w - a.w) * t,
  #     )
  #   else:
  #     let angle = arccos(cosTheta)
  #     return (sin((1 - t) * angle) * a + sin(t * angle) * z) / sin(angle)

  # func quat*[T](m: GMat4[T]): GVec4[T] =
  #   ## Create a quaternion from matrix.
  #   let
  #     m00 = m[0, 0]
  #     m01 = m[0, 1]
  #     m02 = m[0, 2]

  #     m10 = m[1, 0]
  #     m11 = m[1, 1]
  #     m12 = m[1, 2]

  #     m20 = m[2, 0]
  #     m21 = m[2, 1]
  #     m22 = m[2, 2]

  #     fourXSquaredMinus1 = m00 - m11 - m22
  #     fourYSquaredMinus1 = m11 - m00 - m22
  #     fourZSquaredMinus1 = m22 - m00 - m11
  #     fourWSquaredMinus1 = m00 + m11 + m22

  #   var
  #     q: GVec4[T]
  #     biggestIndex = 0
  #     fourBiggestSquaredMinus1 = fourWSquaredMinus1
  #   if fourXSquaredMinus1 > fourBiggestSquaredMinus1:
  #     fourBiggestSquaredMinus1 = fourXSquaredMinus1
  #     biggestIndex = 1
  #   if fourYSquaredMinus1 > fourBiggestSquaredMinus1:
  #     fourBiggestSquaredMinus1 = fourYSquaredMinus1
  #     biggestIndex = 2
  #   if fourZSquaredMinus1 > fourBiggestSquaredMinus1:
  #     fourBiggestSquaredMinus1 = fourZSquaredMinus1
  #     biggestIndex = 3

  #   let biggestVal = sqrt(fourBiggestSquaredMinus1 + T(1)) * T(0.5)
  #   let mult = T(0.25) / biggestVal

  #   case biggestIndex
  #   of 0:
  #     q.w = biggestVal
  #     q.x = (m12 - m21) * mult
  #     q.y = (m20 - m02) * mult
  #     q.z = (m01 - m10) * mult
  #   of 1:
  #     q.w = (m12 - m21) * mult
  #     q.x = biggestVal
  #     q.y = (m01 + m10) * mult
  #     q.z = (m20 + m02) * mult
  #   of 2:
  #     q.w = (m20 - m02) * mult
  #     q.x = (m01 + m10) * mult
  #     q.y = biggestVal
  #     q.z = (m12 + m21) * mult
  #   else:
  #     q.w = (m01 - m10) * mult
  #     q.x = (m20 + m02) * mult
  #     q.y = (m12 + m21) * mult
  #     q.z = biggestVal

  #   result = q

  # func mat4*[T](q: GVec4[T]): GMat4[T] =
  #   let
  #     xx = q.x * q.x
  #     xy = q.x * q.y
  #     xz = q.x * q.z
  #     xw = q.x * q.w

  #     yy = q.y * q.y
  #     yz = q.y * q.z
  #     yw = q.y * q.w

  #     zz = q.z * q.z
  #     zw = q.z * q.w

  #   result[0, 0] = 1 - 2 * (yy + zz)
  #   result[0, 1] = 0 + 2 * (xy + zw)
  #   result[0, 2] = 0 + 2 * (xz - yw)
  #   result[0, 3] = 0

  #   result[1, 0] = 0 + 2 * (xy - zw)
  #   result[1, 1] = 1 - 2 * (xx + zz)
  #   result[1, 2] = 0 + 2 * (yz + xw)
  #   result[1, 3] = 0

  #   result[2, 0] = 0 + 2 * (xz + yw)
  #   result[2, 1] = 0 + 2 * (yz - xw)
  #   result[2, 2] = 1 - 2 * (xx + yy)
  #   result[2, 3] = 0

  #   result[3, 0] = 0
  #   result[3, 1] = 0
  #   result[3, 2] = 0
  #   result[3, 3] = 1.0


  # func mat4*(m: DMat4): Mat4 {.inline.} =
  #   ## Convert a double precision matrix to a single precision matrix.
  #   result[0, 0] = float32(m[0, 0])
  #   result[0, 1] = float32(m[0, 1])
  #   result[0, 2] = float32(m[0, 2])
  #   result[0, 3] = float32(m[0, 3])
  #   result[1, 0] = float32(m[1, 0])
  #   result[1, 1] = float32(m[1, 1])
  #   result[1, 2] = float32(m[1, 2])
  #   result[1, 3] = float32(m[1, 3])
  #   result[2, 0] = float32(m[2, 0])
  #   result[2, 1] = float32(m[2, 1])
  #   result[2, 2] = float32(m[2, 2])
  #   result[2, 3] = float32(m[2, 3])
  #   result[3, 0] = float32(m[3, 0])
  #   result[3, 1] = float32(m[3, 1])
  #   result[3, 2] = float32(m[3, 2])
  #   result[3, 3] = float32(m[3, 3])

  # func mat4*(m: Mat4): Mat4 {.inline.} =
  #   ## Convert a double precision matrix to a single precision matrix.
  #   return m

  # func dmat4*(m: Mat4): DMat4 {.inline.} =
  #   ## Convert a single precision matrix to a double precision matrix.
  #   result[0, 0] = float64(m[0, 0])
  #   result[0, 1] = float64(m[0, 1])
  #   result[0, 2] = float64(m[0, 2])
  #   result[0, 3] = float64(m[0, 3])
  #   result[1, 0] = float64(m[1, 0])
  #   result[1, 1] = float64(m[1, 1])
  #   result[1, 2] = float64(m[1, 2])
  #   result[1, 3] = float64(m[1, 3])
  #   result[2, 0] = float64(m[2, 0])
  #   result[2, 1] = float64(m[2, 1])
  #   result[2, 2] = float64(m[2, 2])
  #   result[2, 3] = float64(m[2, 3])
  #   result[3, 0] = float64(m[3, 0])
  #   result[3, 1] = float64(m[3, 1])
  #   result[3, 2] = float64(m[3, 2])
  #   result[3, 3] = float64(m[3, 3])

  # func dmat4*(m: DMat4): DMat4 {.inline.} =
  #   ## Convert a double precision matrix to a double precision matrix.
  #   return m

  # func rotate*[T](angle: T, axis: GVec3[T]): GMat4[T] =
  #   ## Return a rotation matrix with axis and angle.
  #   fromAxisAngle(axis, angle).mat4()

  # func quatRotateX*[T](angle: T): GVec4[T] =
  #   ## Return a quaternion that would rotate around the X axis.
  #   fromAxisAngle(gvec3[T](1, 0, 0), angle)

  # func quatRotateY*[T](angle: T): GVec4[T] =
  #   ## Return a quaternion that would rotate around the Y axis.
  #   fromAxisAngle(gvec3[T](0, 1, 0), angle)

  # func quatRotateZ*[T](angle: T): GVec4[T] =
  #   ## Return a quaternion that would rotate around the Z axis.
  #   fromAxisAngle(gvec3[T](0, 0, 1), angle)

  # func quatMultiply*[T](a: GVec4[T], b: GVec4[T]): GVec4[T] =
  #   ## Return the product of two quaternions.
  #   gvec4[T](
  #     a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
  #     a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z,
  #     a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x,
  #     a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
  #   )

  # func quatRotate*[T](q: GVec4[T], v: GVec3[T]): GVec3[T] =
  #   ## Rotate a vector directly by a quaternion without building a matrix.
  #   let
  #     qv = gvec3[T](q.x, q.y, q.z)
  #     uv = cross(qv, v)
  #     uuv = cross(qv, uv)
  #   v + (uv * q.w + uuv) * 2

  # func `*`*[T](a: GVec4[T], b: GVec3[T]): GVec3[T] {.inline.} =
  #   ## Rotate a vector directly by a quaternion.
  #   quatRotate(a, b)

  # func toAngles*[T](m: GVec4[T]): GVec3[T] =
  #   ## Convert a quaternion to Euler angles.
  #   let
  #     x = m.x
  #     y = m.y
  #     z = m.z
  #     w = m.w

  #   result.x = arctan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
  #   result.y = arcsin(2 * (w * y - z * x))
  #   result.z = arctan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))

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
