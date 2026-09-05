## SDL3 GPU renderer for nuigi's renderer-independent command stream.
##
## Owns pipelines, materials, samplers, textures, staging buffers, and font
## atlas uploads, then translates `UiRenderCommand`s into SDL GPU passes.
## Applications must initialize and destroy `Render2D` against the same GPU
## device and provide the platform shaders compiled into `assets/`.

import std/[os, syncio, times, tables, strutils, math]
import nuigi/backend/sdl3/sdl3
import nuigi/debug/profiler, nuigi/core/[vecmath, array_view], nuigi/text/fonts, nuigi

include nuigi/util/compat2

const
  render2DTargetFormat* = GPU_TEXTUREFORMAT_B8G8R8A8_UNORM
  basicVertDxilPath* = "./assets/basic.vert.dxil"
  basicFragDxilPath* = "./assets/basic.frag.dxil"
  basicVertSpirvPath* = "./assets/basic.vert.spv"
  basicFragSpirvPath* = "./assets/basic.frag.spv"
  propTextureCreateFormat* = "SDL.texture.create.format".cstring
  propTextureCreateAccess* = "SDL.texture.create.access".cstring
  propTextureCreateWidth* = "SDL.texture.create.width".cstring
  propTextureCreateHeight* = "SDL.texture.create.height".cstring
  propTextureCreateGpuTexture* = "SDL.texture.create.gpu.texture".cstring

when defined(linux):
  const
    render2DShaderFormat* = GPU_SHADERFORMAT_SPIRV.uint32
    basicVertShaderPath* = basicVertSpirvPath
    basicFragShaderPath* = basicFragSpirvPath
else:
  const
    render2DShaderFormat* = GPU_SHADERFORMAT_DXIL.uint32
    basicVertShaderPath* = basicVertDxilPath
    basicFragShaderPath* = basicFragDxilPath

type
  Render2DSamplerMode* {.pure.} = enum
    Linear
    Nearest

  Render2DMaterial = object
    id: MaterialId
    fragmentShader: GPUShader
    pipeline: GPUGraphicsPipeline
    hasFragmentUniform: bool

  Render2DVertex* {.packed.} = object
    x*, y*: float32
    u*, v*: float32
    r*, g*, b*, a*: float32

  Render2DVertexUniformData = object
    mvp: array[4, array[4, float32]]

  GPUState = object
    loadOp: GPULoadOp


  CommandKind = enum
    cClear
    cVertices
    cClipPush
    cClipPop

  Command = object
    kind: CommandKind
    vertexIndex: int
    vertices: int
    count: int
    texture: int
    customTexture: nil GPUTexture
    customSampler: nil GPUSampler
    scissorRect: Rect
    rawData: nil ptr Render2DVertex
    materialId: MaterialId
    materialUniform: ArrayView[uint8]

  Render2D* = object
    device*: GPUDevice
    commandBuffer*: GPUCommandBuffer
    vertexShader*: GPUShader
    fragmentShader*: GPUShader
    pipeline*: GPUGraphicsPipeline
    pipelineFormat*: GPUTextureFormat
    whiteTexture*: GPUTexture
    whiteSampler*: GPUSampler
    nearestSampler*: GPUSampler
    vertexBuffer*: GPUBuffer
    textureIndexBuffer*: GPUBuffer
    transferBuffer*: GPUTransferBuffer
    textureIndexTransferBuffer*: GPUTransferBuffer
    vertexBufferSize*: uint32
    queuedVertices*: seq[Render2DVertex]
    vertexIndex: int
    target*: GPUTexture
    targetMsaa*: GPUTexture
    previousTarget*: GPUTexture
    previousTargetReady: bool
    targetTexture*: Texture
    targetWidth*: uint32
    targetHeight*: uint32
    lastUiShaderReloadSourceMtime*: int64
    hasLastUiShaderReloadSourceMtime*: bool
    fontTexture*: GPUTexture
    fontTextureSampler*: GPUSampler
    fontAtlasTransferBuffer*: GPUTransferBuffer
    fontAtlasTransferBufferSize*: uint32

    activeTextures: array[3, GPUTextureSamplerBinding]

    renderPass: nil GPURenderPass

    commands: seq[Command]
    textureIndices: seq[(int, int)]
    clipStack: seq[Rect]

    materials: Table[MaterialId, Render2DMaterial]
    nextMaterialId: MaterialId
    lastBoundMaterial: MaterialId
    defaultMaterialId: MaterialId

    state: GPUState
    sample_count*: GPUSampleCount
    fontRender*: ptr FontRender

proc deinitRender2D*(r: var Render2D)

proc initRender2D*(r: var Render2D, fontRender: ptr FontRender, device: GPUDevice, targetFormat: GPUTextureFormat = render2DTargetFormat): bool

proc cancelRender2DCommandBuffer(r: var Render2D) =
  if r.device != nil and r.commandBuffer != nil:
    discard cancelGPUCommandBuffer(r.commandBuffer)
  r.commandBuffer = nil

proc releaseRenderTarget(r: var Render2D) =
  if r.targetTexture != nil:
    destroyTexture(r.targetTexture)
    r.targetTexture = nil

  if r.device != nil and r.target != nil:
    releaseGPUTexture(r.device, r.target)
    r.target = nil

  if r.device != nil and r.targetMsaa != nil:
    releaseGPUTexture(r.device, r.targetMsaa)
    r.targetMsaa = nil

  if r.device != nil and r.previousTarget != nil:
    releaseGPUTexture(r.device, r.previousTarget)
    r.previousTarget = nil

  r.targetWidth = 0
  r.targetHeight = 0
  r.previousTargetReady = false

proc ensureRenderTargetTexture(r: var Render2D, renderer: Renderer): nil Texture =
  if renderer == nil or r.target == nil or r.targetWidth == 0 or r.targetHeight == 0:
    return nil

  if r.targetTexture != nil:
    return r.targetTexture

  let props = createProperties()
  if props == 0:
    return nil

  discard setNumberProperty(props, propTextureCreateFormat, PIXELFORMAT_BGRA32.int64)
  discard setNumberProperty(props, propTextureCreateAccess, TEXTUREACCESS_STATIC.int64)
  discard setNumberProperty(props, propTextureCreateWidth, r.targetWidth.int64)
  discard setNumberProperty(props, propTextureCreateHeight, r.targetHeight.int64)
  discard setPointerProperty(props, propTextureCreateGpuTexture, cast[pointer](r.target))

  r.targetTexture = createTextureWithProperties(renderer, props)
  destroyProperties(props)
  if r.targetTexture != nil:
    discard r.targetTexture.setTextureScaleMode(SCALEMODE_LINEAR)
    discard r.targetTexture.setTextureBlendMode(BLENDMODE_BLEND)
  r.targetTexture

proc ensureRenderTarget(r: var Render2D, renderer: nil Renderer, width, height: uint32, targetFormat: GPUTextureFormat,
    sample_count: GPUSampleCount
  ): bool =
  if r.device == nil or width == 0 or height == 0:
    return false

  let renderer = renderer
  if r.target != nil and r.targetWidth == width and r.targetHeight == height and r.pipelineFormat == targetFormat and r.sample_count == sample_count:
    return renderer == nil or r.ensureRenderTargetTexture(renderer) != nil

  releaseRenderTarget(r)

  var createInfo = GPUTextureCreateInfo(
    `type`: GPU_TEXTURETYPE_2D,
    format: targetFormat,
    usage: (GPU_TEXTUREUSAGE_COLOR_TARGET or GPU_TEXTUREUSAGE_SAMPLER).uint32,
    width: width,
    height: height,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: GPU_SAMPLECOUNT_1,
    props: 0,
  )

  r.target = createGPUTexture(r.device, createInfo.addr)
  if r.target == nil:
    return false

  var previousTargetInfo = createInfo
  previousTargetInfo.usage = GPU_TEXTUREUSAGE_SAMPLER.uint32
  r.previousTarget = createGPUTexture(r.device, previousTargetInfo.addr)
  if r.previousTarget == nil:
    releaseRenderTarget(r)
    return false

  if sample_count != GPU_SAMPLECOUNT_1:
    var createInfoMsaa = GPUTextureCreateInfo(
      `type`: GPU_TEXTURETYPE_2D,
      format: targetFormat,
      usage: (GPU_TEXTUREUSAGE_COLOR_TARGET).uint32,
      width: width,
      height: height,
      layer_count_or_depth: 1,
      num_levels: 1,
      sample_count: sample_count,
      props: 0,
    )

    r.targetMsaa = createGPUTexture(r.device, createInfoMsaa.addr)
    if r.targetMsaa == nil:
      return false

  r.targetWidth = width
  r.targetHeight = height
  r.sample_count = sample_count
  if renderer != nil:
    return r.ensureRenderTargetTexture(renderer) != nil
  return true

proc releaseBuffers(r: var Render2D) =
  if r.vertexBuffer != nil:
    releaseGPUBuffer(r.device, r.vertexBuffer)
    r.vertexBuffer = nil
  if r.textureIndexBuffer != nil:
    releaseGPUBuffer(r.device, r.textureIndexBuffer)
    r.textureIndexBuffer = nil
  if r.transferBuffer != nil:
    releaseGPUTransferBuffer(r.device, r.transferBuffer)
    r.transferBuffer = nil
  if r.textureIndexTransferBuffer != nil:
    releaseGPUTransferBuffer(r.device, r.textureIndexTransferBuffer)
    r.textureIndexTransferBuffer = nil
  r.vertexBufferSize = 0

proc createWhiteTexture(device: GPUDevice): GPUTexture =
  var textureInfo = GPUTextureCreateInfo(
    `type`: GPU_TEXTURETYPE_2D,
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    usage: GPU_TEXTUREUSAGE_SAMPLER.uint32,
    width: 1,
    height: 1,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: GPU_SAMPLECOUNT_1,
    props: 0,
  )
  let texture = createGPUTexture(device, textureInfo.addr)
  if texture == nil:
    return nil

  var transferInfo = GPUTransferBufferCreateInfo(
    usage: GPU_TRANSFERBUFFERUSAGE_UPLOAD,
    size: 4,
    props: 0,
  )
  let transfer = createGPUTransferBuffer(device, transferInfo.addr)
  if transfer == nil:
    releaseGPUTexture(device, texture)
    return nil

  let mapped = mapGPUTransferBuffer(device, transfer, false)
  if mapped == nil:
    releaseGPUTransferBuffer(device, transfer)
    releaseGPUTexture(device, texture)
    return nil

  let pixel = cast[ptr UncheckedArray[uint8]](mapped)
  pixel[0] = 255'u8
  pixel[1] = 255'u8
  pixel[2] = 255'u8
  pixel[3] = 255'u8
  unmapGPUTransferBuffer(device, transfer)

  let cmd = acquireGPUCommandBuffer(device)
  if cmd == nil:
    releaseGPUTransferBuffer(device, transfer)
    releaseGPUTexture(device, texture)
    return nil

  let copyPass = beginGPUCopyPass(cmd)
  if copyPass == nil:
    discard cancelGPUCommandBuffer(cmd)
    releaseGPUTransferBuffer(device, transfer)
    releaseGPUTexture(device, texture)
    return nil

  var src = GPUTextureTransferInfo(
    transfer_buffer: transfer,
    offset: 0,
    pixels_per_row: 1,
    rows_per_layer: 1,
  )
  var dst = GPUTextureRegion(
    texture: texture,
    mip_level: 0,
    layer: 0,
    x: 0,
    y: 0,
    z: 0,
    w: 1,
    h: 1,
    d: 1,
  )
  uploadToGPUTexture(copyPass, src.addr, dst.addr, false)
  endGPUCopyPass(copyPass)

  if not submitGPUCommandBuffer(cmd):
    releaseGPUTransferBuffer(device, transfer)
    releaseGPUTexture(device, texture)
    return nil

  discard waitForGPUIdle(device)
  releaseGPUTransferBuffer(device, transfer)
  texture

proc createFontAtlasTexture(r: Render2D, width, height: uint32): GPUTexture =
  var fontTexInfo = GPUTextureCreateInfo(
    `type`: GPU_TEXTURETYPE_2D,
    format: GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    usage: GPU_TEXTUREUSAGE_SAMPLER.uint32,
    width: width,
    height: height,
    layer_count_or_depth: 1,
    num_levels: 1,
    sample_count: GPU_SAMPLECOUNT_1,
    props: 0,
  )
  createGPUTexture(r.device, fontTexInfo.addr)

proc loadShaderFromFile(device: GPUDevice, path: string, stage: GPUShaderStage, numSamplers, numUniformBuffers: uint32, entrypoint: cstring = "main"): GPUShader =
  prof("Render2D.loadShaderFromFile")
  if not fileExists(path):
    return nil

  var code: string
  try:
    code = readFile(path)
  except:
    return nil
  if code.len == 0:
    return nil

  let codePtr = cast[ptr UncheckedArray[uint8]](readRawData(code))

  var info = GPUShaderCreateInfo(
    code_size: code.len.csize_t,
    code: codePtr,
    entrypoint: entrypoint,
    format: render2DShaderFormat,
    stage: stage,
    num_samplers: numSamplers,
    num_storage_textures: 0'u32,
    num_storage_buffers: 0'u32,
    num_uniform_buffers: numUniformBuffers,
    props: 0,
  )
  createGPUShader(device, info.addr)

proc buildGraphicsPipeline(
  device: GPUDevice,
  vertexShader: GPUShader,
  fragmentShader: GPUShader,
  targetFormat: GPUTextureFormat,
  vbDesc: openArray[GPUVertexBufferDescription],
  attrs: ptr UncheckedArray[GPUVertexAttribute],
  numAttrs: uint32,
  sample_count: GPUSampleCount
): GPUGraphicsPipeline =
  var blend = GPUColorTargetBlendState(
    src_color_blendfactor: GPU_BLENDFACTOR_SRC_ALPHA,
    dst_color_blendfactor: GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
    color_blend_op: GPU_BLENDOP_ADD,
    src_alpha_blendfactor: GPU_BLENDFACTOR_ONE,
    dst_alpha_blendfactor: GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
    alpha_blend_op: GPU_BLENDOP_ADD,
    color_write_mask: 0xF,
    enable_blend: true,
    enable_color_write_mask: false,
  )
  var colorTarget = GPUColorTargetDescription(format: targetFormat, blend_state: blend)

  var inputState = GPUVertexInputState(
    vertex_buffer_descriptions: cast[ptr UncheckedArray[GPUVertexBufferDescription]](vbDesc[0].addr),
    num_vertex_buffers: vbDesc.len.uint32,
    vertex_attributes: attrs,
    num_vertex_attributes: numAttrs,
  )

  var pipelineInfo = GPUGraphicsPipelineCreateInfo(
    vertex_shader: vertexShader,
    fragment_shader: fragmentShader,
    vertex_input_state: inputState,
    primitive_type: GPU_PRIMITIVETYPE_TRIANGLELIST,
    rasterizer_state: GPURasterizerState(
      fill_mode: GPU_FILLMODE_FILL,
      cull_mode: GPU_CULLMODE_NONE,
      front_face: GPU_FRONTFACE_COUNTER_CLOCKWISE,
      depth_bias_constant_factor: 0,
      depth_bias_clamp: 0,
      depth_bias_slope_factor: 0,
      enable_depth_bias: false,
      enable_depth_clip: true,
    ),
    multisample_state: GPUMultisampleState(
      sample_count: sample_count,
    ),
    depth_stencil_state: GPUDepthStencilState(
      compare_op: GPU_COMPAREOP_INVALID,
      back_stencil_state: GPUStencilOpState(fail_op: GPU_STENCILOP_INVALID, pass_op: GPU_STENCILOP_INVALID, depth_fail_op: GPU_STENCILOP_INVALID, compare_op: GPU_COMPAREOP_INVALID),
      front_stencil_state: GPUStencilOpState(fail_op: GPU_STENCILOP_INVALID, pass_op: GPU_STENCILOP_INVALID, depth_fail_op: GPU_STENCILOP_INVALID, compare_op: GPU_COMPAREOP_INVALID),
      compare_mask: 0,
      write_mask: 0,
      enable_depth_test: false,
      enable_depth_write: false,
      enable_stencil_test: false,
    ),
    target_info: GPUGraphicsPipelineTargetInfo(
      color_target_descriptions: cast[ptr UncheckedArray[GPUColorTargetDescription]](colorTarget.addr),
      num_color_targets: 1,
      depth_stencil_format: GPU_TEXTUREFORMAT_INVALID,
      has_depth_stencil_target: false,
    ),
    props: 0,
  )

  createGPUGraphicsPipeline(device, pipelineInfo.addr)

proc createPipeline(r: var Render2D, targetFormat: GPUTextureFormat, sample_count: GPUSampleCount): bool =
  prof("Render2D.createPipeline")
  if r.pipeline != nil:
    releaseGPUGraphicsPipeline(r.device, r.pipeline)
    r.pipeline = nil

  if r.vertexShader == nil or r.fragmentShader == nil:
    return false

  var vbDesc = [
    GPUVertexBufferDescription(
      slot: 0,
      pitch: sizeof(Render2DVertex).uint32,
      input_rate: GPU_VERTEXINPUTRATE_VERTEX,
    ),
    GPUVertexBufferDescription(
      slot: 1,
      pitch: sizeof(uint32).uint32,
      input_rate: GPU_VERTEXINPUTRATE_VERTEX,
    ),
  ]

  var attrs = [
    GPUVertexAttribute(location: 0, buffer_slot: 0, format: GPU_VERTEXELEMENTFORMAT_FLOAT2, offset: 0),
    GPUVertexAttribute(location: 1, buffer_slot: 0, format: GPU_VERTEXELEMENTFORMAT_FLOAT2, offset: 8),
    GPUVertexAttribute(location: 2, buffer_slot: 0, format: GPU_VERTEXELEMENTFORMAT_FLOAT4, offset: 16),
    GPUVertexAttribute(location: 3, buffer_slot: 1, format: GPU_VERTEXELEMENTFORMAT_UINT, offset: 0),
  ]

  r.pipeline = buildGraphicsPipeline(
    r.device,
    r.vertexShader,
    r.fragmentShader,
    targetFormat,
    vbDesc,
    cast[ptr UncheckedArray[GPUVertexAttribute]](attrs[0].addr),
    attrs.len.uint32,
    sample_count
  )
  r.pipelineFormat = targetFormat
  r.pipeline != nil

proc buildMaterialPipeline(r: var Render2D, fragmentShader: GPUShader): GPUGraphicsPipeline =
  prof("Render2D.buildMaterialPipeline")
  if r.device == nil or r.vertexShader == nil or fragmentShader == nil:
    return nil

  var vbDesc = [
    GPUVertexBufferDescription(
      slot: 0,
      pitch: sizeof(Render2DVertex).uint32,
      input_rate: GPU_VERTEXINPUTRATE_VERTEX,
    ),
    GPUVertexBufferDescription(
      slot: 1,
      pitch: sizeof(uint32).uint32,
      input_rate: GPU_VERTEXINPUTRATE_VERTEX,
    ),
  ]

  var attrs = [
    GPUVertexAttribute(location: 0, buffer_slot: 0, format: GPU_VERTEXELEMENTFORMAT_FLOAT2, offset: 0),
    GPUVertexAttribute(location: 1, buffer_slot: 0, format: GPU_VERTEXELEMENTFORMAT_FLOAT2, offset: 8),
    GPUVertexAttribute(location: 2, buffer_slot: 0, format: GPU_VERTEXELEMENTFORMAT_FLOAT4, offset: 16),
    GPUVertexAttribute(location: 3, buffer_slot: 1, format: GPU_VERTEXELEMENTFORMAT_UINT, offset: 0),
  ]

  buildGraphicsPipeline(
    r.device,
    r.vertexShader,
    fragmentShader,
    r.pipelineFormat,
    vbDesc,
    cast[ptr UncheckedArray[GPUVertexAttribute]](attrs[0].addr),
    attrs.len.uint32,
    r.sample_count,
  )

proc registerMaterial*(r: var Render2D, fragmentShader: openArray[uint8], numUniformBuffers: uint32 = 0): MaterialId =
  prof("Render2D.registerMaterial")
  if r.device == nil or fragmentShader.len == 0:
    return 0

  let codePtr = cast[ptr UncheckedArray[uint8]](fragmentShader[0].unsafeAddr)
  var info = GPUShaderCreateInfo(
    code_size: fragmentShader.len.csize_t,
    code: codePtr,
    entrypoint: "PSMain",
    format: render2DShaderFormat,
    stage: GPU_SHADERSTAGE_FRAGMENT,
    num_samplers: 3,
    num_storage_textures: 0'u32,
    num_storage_buffers: 0'u32,
    num_uniform_buffers: numUniformBuffers,
    props: 0,
  )
  let frag = createGPUShader(r.device, info.addr)
  if frag == nil:
    return 0

  let pipeline = r.buildMaterialPipeline(frag)
  if pipeline == nil:
    releaseGPUShader(r.device, frag)
    return 0

  r.nextMaterialId += 1
  let id = r.nextMaterialId
  r.materials[id] = Render2DMaterial(
    id: id,
    fragmentShader: frag,
    pipeline: pipeline,
    hasFragmentUniform: numUniformBuffers > 0,
  )
  id

proc ensureVertexBuffers(r: var Render2D, minBytes: uint32): bool =
  if r.vertexBuffer != nil and
      r.textureIndexBuffer != nil and
      r.transferBuffer != nil and
      r.textureIndexTransferBuffer != nil and
      minBytes <= r.vertexBufferSize:
    return true

  releaseBuffers(r)

  var bci = GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_VERTEX.uint32,
    size: minBytes,
  )
  r.vertexBuffer = createGPUBuffer(r.device, bci.addr)
  if r.vertexBuffer == nil:
    return false

  var bci2 = GPUBufferCreateInfo(
    usage: GPU_BUFFERUSAGE_VERTEX.uint32,
    size: minBytes,
  )
  r.textureIndexBuffer = createGPUBuffer(r.device, bci2.addr)
  if r.textureIndexBuffer == nil:
    return false

  var tbci = GPUTransferBufferCreateInfo(
    usage: GPU_TRANSFERBUFFERUSAGE_UPLOAD,
    size: minBytes,
    props: 0,
  )
  r.transferBuffer = createGPUTransferBuffer(r.device, tbci.addr)
  if r.transferBuffer == nil:
    releaseBuffers(r)
    return false
  r.textureIndexTransferBuffer = createGPUTransferBuffer(r.device, tbci.addr)
  if r.textureIndexTransferBuffer == nil:
    releaseBuffers(r)
    return false

  r.vertexBufferSize = minBytes
  true

proc releaseShaders*(r: var Render2D) =
  if r.vertexShader != nil:
    releaseGPUShader(r.device, r.vertexShader)
    r.vertexShader = nil

  if r.fragmentShader != nil:
    releaseGPUShader(r.device, r.fragmentShader)
    r.fragmentShader = nil

proc loadBasicShaders(r: var Render2D): bool =
  prof("Render2D.loadBasicShaders")
  if r.vertexShader == nil:
    r.vertexShader = loadShaderFromFile(r.device, basicVertShaderPath, GPU_SHADERSTAGE_VERTEX, 0, 1, "VSMain")
  if r.vertexShader == nil:
    return false

  if r.fragmentShader == nil:
    r.fragmentShader = loadShaderFromFile(r.device, basicFragShaderPath, GPU_SHADERSTAGE_FRAGMENT, 3, 0, "PSMain")
  if r.fragmentShader == nil:
    return false

  return true

proc reloadShaders(r: var Render2D): bool =
  prof("Render2D.reloadShaders")
  r.releaseShaders()

  r.vertexShader = loadShaderFromFile(r.device, basicVertShaderPath, GPU_SHADERSTAGE_VERTEX, 0, 1, "VSMain")
  if r.vertexShader == nil:
    return false

  r.fragmentShader = loadShaderFromFile(r.device, basicFragShaderPath, GPU_SHADERSTAGE_FRAGMENT, 3, 0, "PSMain")
  if r.fragmentShader == nil:
    return false

  return true

proc initRender2D*(r: var Render2D, fontRender: ptr FontRender, device: GPUDevice, targetFormat: GPUTextureFormat = render2DTargetFormat): bool =
  prof("Render2D.initRender2D")
  if device == nil:
    return false

  r.device = device
  r.fontRender = fontRender
  r.state.loadOp = GPU_LOADOP_LOAD
  r.defaultMaterialId = 0
  r.lastBoundMaterial = 0
  r.sample_count = GPU_SAMPLECOUNT_8
  r.queuedVertices = newSeqOfCap[Render2DVertex](10 * 1024 * 1024)

  if not r.reloadShaders():
    deinitRender2D(r)
    return false

  var samplerInfo = GPUSamplerCreateInfo(
    min_filter: GPU_FILTER_LINEAR,
    mag_filter: GPU_FILTER_LINEAR,
    mipmap_mode: GPU_SAMPLERMIPMAPMODE_LINEAR,
    address_mode_u: GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    address_mode_v: GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    address_mode_w: GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    mip_lod_bias: 0,
    max_anisotropy: 1,
    compare_op: GPU_COMPAREOP_INVALID,
    min_lod: 0,
    max_lod: 0,
    enable_anisotropy: false,
    enable_compare: false,
    padding1: 0,
    padding2: 0,
    props: 0,
  )
  r.whiteSampler = createGPUSampler(r.device, samplerInfo.addr)
  if r.whiteSampler == nil:
    deinitRender2D(r)
    return false

  samplerInfo.min_filter = GPU_FILTER_NEAREST
  samplerInfo.mag_filter = GPU_FILTER_NEAREST
  samplerInfo.mipmap_mode = GPU_SAMPLERMIPMAPMODE_NEAREST
  r.nearestSampler = createGPUSampler(r.device, samplerInfo.addr)
  if r.nearestSampler == nil:
    deinitRender2D(r)
    return false

  r.whiteTexture = createWhiteTexture(r.device)
  if r.whiteTexture == nil:
    deinitRender2D(r)
    return false

  block loadFont:
    r.fontTexture = r.createFontAtlasTexture(
      r.fontRender[].fontAtlasWidth.uint32,
      r.fontRender[].fontAtlasHeight.uint32,
    )
    if r.fontTexture == nil:
      break loadFont

    var samplerInfo = GPUSamplerCreateInfo(
      min_filter: GPU_FILTER_LINEAR,
      mag_filter: GPU_FILTER_LINEAR,
      mipmap_mode: GPU_SAMPLERMIPMAPMODE_LINEAR,
      address_mode_u: GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
      address_mode_v: GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
      address_mode_w: GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
      mip_lod_bias: 0,
      max_anisotropy: 1,
      compare_op: GPU_COMPAREOP_INVALID,
      min_lod: 0,
      max_lod: 0,
      enable_anisotropy: false,
      enable_compare: false,
      padding1: 0,
      padding2: 0,
      props: 0,
    )
    r.fontTextureSampler = createGPUSampler(r.device, samplerInfo.addr)
    if r.fontTextureSampler == nil:
      releaseGPUTexture(r.device, r.fontTexture)
      r.fontTexture = nil
      break loadFont

    echo "Fonts loaded: ", r.fontRender[].fonts.len, " face(s)"

  if not loadBasicShaders(r):
    deinitRender2D(r)
    return false

  if not createPipeline(r, targetFormat, r.sample_count):
    deinitRender2D(r)
    return false

  true

proc uiShaderSourcesNeedReload*(r: Render2D): tuple[reload: bool, newestSourceTime: int64] =
  prof("Render2D.uiShaderSourcesNeedReload")
  # if not fileExists(uiVertSourcePath) or not fileExists(uiFragSourcePath):
  #   return (false, 0'i64)
  # if not fileExists(uiVertDxilPath) or not fileExists(uiFragDxilPath):
  #   return (false, 0'i64)

  # try:
  #   let vertSourceTime = getLastModificationTime(uiVertSourcePath).toUnix
  #   let fragSourceTime = getLastModificationTime(uiFragSourcePath).toUnix
  #   let vertDxilTime = getLastModificationTime(uiVertDxilPath).toUnix
  #   let fragDxilTime = getLastModificationTime(uiFragDxilPath).toUnix
  #   let newestSourceTime = if vertSourceTime >= fragSourceTime: vertSourceTime else: fragSourceTime

  #   if r.hasLastUiShaderReloadSourceMtime and newestSourceTime <= r.lastUiShaderReloadSourceMtime:
  #     return (false, newestSourceTime)

  #   let reload = vertSourceTime > vertDxilTime or fragSourceTime > fragDxilTime
  #   (reload, newestSourceTime)
  # except:
  #   (false, 0'i64)
  (false, 0'i64)

proc clearBatch*(r: var Render2D) =
  r.queuedVertices.setLen(0)
  r.commands.setLen(0)
  r.textureIndices.setLen(0)
  r.vertexIndex = 0

proc beginRender*(r: var Render2D, renderer: nil Renderer, targetWidth, targetHeight: uint32, targetFormat: GPUTextureFormat = render2DTargetFormat,
    sample_count: GPUSampleCount = GPU_SAMPLECOUNT_1): bool =
  prof("Render2D.beginRender")
  if r.device == nil or targetWidth == 0 or targetHeight == 0:
    return false

  r.fontRender[].beginFontRenderFrame()
  r.clearBatch()
  r.clipStack.setLen(0)
  r.cancelRender2DCommandBuffer()
  r.activeTextures[0] = GPUTextureSamplerBinding(
    texture: r.whiteTexture,
    sampler: r.whiteSampler,
  )
  r.activeTextures[1] = GPUTextureSamplerBinding(
    texture: r.fontTexture,
    sampler: r.fontTextureSampler,
  )
  r.activeTextures[2] = GPUTextureSamplerBinding(
    texture: r.whiteTexture,
    sampler: r.whiteSampler,
  )

  if r.pipeline == nil or r.whiteTexture == nil or r.whiteSampler == nil or r.nearestSampler == nil:
    return false

  if r.pipelineFormat != targetFormat or r.sample_count != sample_count:
    if not createPipeline(r, targetFormat, sample_count):
      return false
    for id, m in r.materials.mpairs:
      let newPipe = r.buildMaterialPipeline(m.fragmentShader)
      if newPipe != nil:
        if m.pipeline != nil:
          releaseGPUGraphicsPipeline(r.device, m.pipeline)
        m.pipeline = newPipe

  # try:
  #   let (reload, newestSourceTime) = uiShaderSourcesNeedReload(r)
  #   if reload:
  #     echo "Hot reloading Render2D shaders"
  #     r.lastUiShaderReloadSourceMtime = newestSourceTime
  #     r.hasLastUiShaderReloadSourceMtime = true
  #     let buildResult = execShellCmd("build.exe shader")
  #     if buildResult != 0:
  #       return false
  #     discard waitForGPUIdle(r.device)
  #     discard r.reloadShaders()
  #     if not createPipeline(r, targetFormat, r.sample_count):
  #       return false
  # except:
  #   discard

  if not r.ensureRenderTarget(renderer, targetWidth, targetHeight, targetFormat, sample_count):
    return false

  r.commandBuffer = acquireGPUCommandBuffer(r.device)
  r.commandBuffer != nil

proc deinitRender2D*(r: var Render2D) =
  prof("Render2D.deinitRender2D")
  if r.device == nil:
    return

  r.cancelRender2DCommandBuffer()
  releaseRenderTarget(r)
  releaseBuffers(r)

  for id, m in r.materials.mpairs:
    if m.pipeline != nil:
      releaseGPUGraphicsPipeline(r.device, m.pipeline)
      m.pipeline = nil
    if m.fragmentShader != nil:
      releaseGPUShader(r.device, m.fragmentShader)
      m.fragmentShader = nil
  r.materials.clear()
  r.nextMaterialId = 0
  r.lastBoundMaterial = r.defaultMaterialId

  if r.pipeline != nil:
    releaseGPUGraphicsPipeline(r.device, r.pipeline)
    r.pipeline = nil

  if r.whiteTexture != nil:
    releaseGPUTexture(r.device, r.whiteTexture)
    r.whiteTexture = nil

  if r.whiteSampler != nil:
    releaseGPUSampler(r.device, r.whiteSampler)
    r.whiteSampler = nil

  if r.nearestSampler != nil:
    releaseGPUSampler(r.device, r.nearestSampler)
    r.nearestSampler = nil

  if r.vertexShader != nil:
    releaseGPUShader(r.device, r.vertexShader)
    r.vertexShader = nil

  if r.fragmentShader != nil:
    releaseGPUShader(r.device, r.fragmentShader)
    r.fragmentShader = nil

  if r.fontTexture != nil:
    releaseGPUTexture(r.device, r.fontTexture)
    r.fontTexture = nil

  if r.fontTextureSampler != nil:
    releaseGPUSampler(r.device, r.fontTextureSampler)
    r.fontTextureSampler = nil

  if r.fontAtlasTransferBuffer != nil:
    releaseGPUTransferBuffer(r.device, r.fontAtlasTransferBuffer)
    r.fontAtlasTransferBuffer = nil
    r.fontAtlasTransferBufferSize = 0
  r.queuedVertices.setLen(0)
  r.device = nil

proc ensureFontAtlasTransferBuffer(r: var Render2D, minSize: uint32): bool =
  if r.fontAtlasTransferBuffer != nil and r.fontAtlasTransferBufferSize >= minSize:
    return true

  prof("ensureFontAtlasTransferBuffer")
  var transferInfo = GPUTransferBufferCreateInfo(
    usage: GPU_TRANSFERBUFFERUSAGE_UPLOAD,
    size: minSize,
    props: 0,
  )
  let newTransferBuffer = createGPUTransferBuffer(r.device, transferInfo.addr)
  if newTransferBuffer == nil:
    return false

  if r.fontAtlasTransferBuffer != nil:
    discard waitForGPUIdle(r.device)
    releaseGPUTransferBuffer(r.device, r.fontAtlasTransferBuffer)

  r.fontAtlasTransferBuffer = newTransferBuffer
  r.fontAtlasTransferBufferSize = minSize
  true

proc uploadFontAtlasGPU*(r: var Render2D): bool =
  prof("Render2D.uploadFontAtlasGPU")
  if not r.fontRender[].fontAtlasDirty:
    return true
  if r.device == nil or r.fontTexture == nil:
    return false
  if r.fontRender[].fontAtlasPixels.len == 0:
    return false

  let dirtyX = r.fontRender[].fontAtlasDirtyMinX
  let dirtyY = r.fontRender[].fontAtlasDirtyMinY
  let dirtyWidth = r.fontRender[].fontAtlasDirtyMaxX - dirtyX
  let dirtyHeight = r.fontRender[].fontAtlasDirtyMaxY - dirtyY
  if dirtyWidth <= 0 or dirtyHeight <= 0:
    r.fontRender[].clearFontAtlasDirty()
    return true

  let rowBytes = dirtyWidth.uint32 * 4
  let dirtyBytes = rowBytes * dirtyHeight.uint32
  if not r.ensureFontAtlasTransferBuffer(dirtyBytes):
    return false

  let mapped = mapGPUTransferBuffer(r.device, r.fontAtlasTransferBuffer, true)
  if mapped == nil:
    return false

  let dstPixels = cast[ptr UncheckedArray[uint8]](mapped)
  block:
    prof("copyPixels")
    for row in 0 ..< dirtyHeight.int:
      let srcOffset = ((dirtyY.int + row) * r.fontRender[].fontAtlasWidth.int + dirtyX.int) * 4
      let dstOffset = row * rowBytes.int
      copyMem(dstPixels[dstOffset].addr, r.fontRender[].fontAtlasPixels[srcOffset].addr, rowBytes.int)

  unmapGPUTransferBuffer(r.device, r.fontAtlasTransferBuffer)

  let cmd = acquireGPUCommandBuffer(r.device)
  if cmd == nil:
    return false

  let copyPass = beginGPUCopyPass(cmd)
  if copyPass == nil:
    discard cancelGPUCommandBuffer(cmd)
    return false

  var src = GPUTextureTransferInfo(
    transfer_buffer: r.fontAtlasTransferBuffer,
    offset: 0,
    pixels_per_row: dirtyWidth.uint32,
    rows_per_layer: dirtyHeight.uint32,
  )
  var dst = GPUTextureRegion(
    texture: r.fontTexture,
    mip_level: 0,
    layer: 0,
    x: dirtyX.uint32,
    y: dirtyY.uint32,
    z: 0,
    w: dirtyWidth.uint32,
    h: dirtyHeight.uint32,
    d: 1,
  )
  uploadToGPUTexture(copyPass, src.addr, dst.addr, false)
  endGPUCopyPass(copyPass)

  block:
    prof("submitGPUCommandBuffer")
    if not submitGPUCommandBuffer(cmd):
      return false

  r.fontRender[].clearFontAtlasDirty()
  true

proc addCommand(r: var Render2D, start, count: int, textureIndex: int, texture: nil GPUTexture = nil, sampler: nil GPUSampler = nil, rawData: nil ptr Render2DVertex = nil, materialId: MaterialId = 0, materialUniform: ArrayView[uint8] = default(ArrayView[uint8])) =
  if r.commands.len > 0:
    let last = r.commands[^1].addr
    let requireBindingChange = ((texture != nil and last.customTexture != nil and
      (texture != last.customTexture or sampler != last.customSampler)) or
      last.materialId != materialId or last.materialUniform.len > 0 or materialUniform.len > 0)
    if last.kind == cVertices and not requireBindingChange:
      last.count += count
      r.textureIndices.add (count, textureIndex)
      r.vertexIndex += count
      if texture != nil:
        last.customTexture = texture
        last.customSampler = sampler
      return

  r.commands.add Command(
    kind: cVertices,
    vertices: start,
    count: count,
    texture: textureIndex,
    vertexIndex: r.vertexIndex,
    customTexture: texture,
    customSampler: sampler,
    rawData: rawData,
    materialId: materialId,
    materialUniform: materialUniform,
  )
  r.textureIndices.add (count, textureIndex)
  r.vertexIndex += count

proc renderQuad*(
  r: var Render2D,
  x, y, w, h: float32,
  color: FColor,
  angle: float = 0,
  pivotX: float = 0.5,
  pivotY: float = 0.5,
  texture: nil GPUTexture = nil,
  samplerMode: Render2DSamplerMode = Render2DSamplerMode.Linear,
  uv0: Vec2 = Vec2(x: 0, y: 0),
  uv1: Vec2 = Vec2(x: 1, y: 1),
): bool =
  if w <= 0 or h <= 0:
    return false

  var
    textureIndex: int = 0
    texture2: nil GPUTexture = nil
  if texture == nil:
    textureIndex = 0
  elif cast[uint64](texture) == 1:
    textureIndex = 1
  elif cast[uint64](texture) == 2:
    textureIndex = 2
    texture2 = if r.previousTargetReady: r.previousTarget else: r.whiteTexture
  else:
    textureIndex = 2
    texture2 = texture

  var (rx0, ry0) = (x, y)
  var (rx1, ry1) = (x + w, y)
  var (rx2, ry2) = (x + w, y + h)
  var (rx3, ry3) = (x, y + h)

  if angle != 0:
    let pcx: float32 = x + w * pivotX.float32
    let pcy: float32 = y + h * pivotY.float32
    let rad = angle.float32 * (PI.float32 / 180'f32)
    let cosA = cos(rad).float32
    let sinA = sin(rad).float32

    template rotate(px, py: float32): (float32, float32) =
      block:
        let dx = px - pcx
        let dy = py - pcy
        (pcx + dx * cosA - dy * sinA, pcy + dx * sinA + dy * cosA)

    (rx0, ry0) = rotate(rx0, ry0)
    (rx1, ry1) = rotate(rx1, ry1)
    (rx2, ry2) = rotate(rx2, ry2)
    (rx3, ry3) = rotate(rx3, ry3)

  let oldLen = r.queuedVertices.len
  r.queuedVertices.setLen(oldLen + 6)
  r.queuedVertices[oldLen + 0] = Render2DVertex(x: rx0, y: ry0, u: uv0.x, v: uv0.y, r: color.r, g: color.g, b: color.b, a: color.a)
  r.queuedVertices[oldLen + 1] = Render2DVertex(x: rx1, y: ry1, u: uv1.x, v: uv0.y, r: color.r, g: color.g, b: color.b, a: color.a)
  r.queuedVertices[oldLen + 2] = Render2DVertex(x: rx2, y: ry2, u: uv1.x, v: uv1.y, r: color.r, g: color.g, b: color.b, a: color.a)
  r.queuedVertices[oldLen + 3] = Render2DVertex(x: rx0, y: ry0, u: uv0.x, v: uv0.y, r: color.r, g: color.g, b: color.b, a: color.a)
  r.queuedVertices[oldLen + 4] = Render2DVertex(x: rx2, y: ry2, u: uv1.x, v: uv1.y, r: color.r, g: color.g, b: color.b, a: color.a)
  r.queuedVertices[oldLen + 5] = Render2DVertex(x: rx3, y: ry3, u: uv0.x, v: uv1.y, r: color.r, g: color.g, b: color.b, a: color.a)

  var customSampler: nil GPUSampler = nil
  if texture2 != nil:
    customSampler = case samplerMode
      of Render2DSamplerMode.Linear: r.whiteSampler
      of Render2DSamplerMode.Nearest: r.nearestSampler

  r.addCommand(oldLen, 6, if texture2 != nil: 2 else: 0, texture2, customSampler)
  true

proc drawLine*(
  r: var Render2D,
  a, b: Vec2,
  thickness: float32 = 1.0,
  color1: FColor = FColor(r: 1, g: 1, b: 1, a: 1),
  color2: FColor = FColor(r: 1, g: 1, b: 1, a: 1),
): bool =
  let dx = b.x - a.x
  let dy = b.y - a.y
  let len = sqrt(dx * dx + dy * dy)
  if len < 0.0001 or thickness <= 0:
    return false

  let halfThick = thickness * 0.5
  let nx = (-dy / len) * halfThick
  let ny = (dx / len) * halfThick

  let oldLen = r.queuedVertices.len
  r.queuedVertices.setLen(oldLen + 6)
  r.queuedVertices[oldLen + 0] = Render2DVertex(x: a.x + nx, y: a.y + ny, u: 0, v: 0, r: color1.r, g: color1.g, b: color1.b, a: color1.a)
  r.queuedVertices[oldLen + 1] = Render2DVertex(x: b.x + nx, y: b.y + ny, u: 1, v: 0, r: color2.r, g: color2.g, b: color2.b, a: color2.a)
  r.queuedVertices[oldLen + 2] = Render2DVertex(x: b.x - nx, y: b.y - ny, u: 1, v: 1, r: color2.r, g: color2.g, b: color2.b, a: color2.a)
  r.queuedVertices[oldLen + 3] = Render2DVertex(x: a.x + nx, y: a.y + ny, u: 0, v: 0, r: color1.r, g: color1.g, b: color1.b, a: color1.a)
  r.queuedVertices[oldLen + 4] = Render2DVertex(x: b.x - nx, y: b.y - ny, u: 1, v: 1, r: color2.r, g: color2.g, b: color2.b, a: color2.a)
  r.queuedVertices[oldLen + 5] = Render2DVertex(x: a.x - nx, y: a.y - ny, u: 0, v: 1, r: color1.r, g: color1.g, b: color1.b, a: color1.a)

  r.addCommand(oldLen, 6, 0)
  true

proc drawLines*(
  r: var Render2D,
  points: openArray[Vec2],
  thickness1: float32 = 1.0,
  thickness2: float32 = 1.0,
  color1: FColor = FColor(r: 1, g: 1, b: 1, a: 1),
  color2: FColor = FColor(r: 1, g: 1, b: 1, a: 1),
): bool =
  if points.len < 2:
    return false

  var totalLen: float32 = 0
  for i in 0 ..< points.len - 1:
    let dx = points[i + 1].x - points[i].x
    let dy = points[i + 1].y - points[i].y
    totalLen += sqrt(dx * dx + dy * dy)

  if totalLen < 0.0001:
    return false

  let totalVerts = (points.len - 1) * 6
  let oldLen = r.queuedVertices.len
  r.queuedVertices.setLen(oldLen + totalVerts)

  var cumLen: float32 = 0
  for i in 0 ..< points.len - 1:
    let px1 = points[i].x
    let py1 = points[i].y
    let px2 = points[i + 1].x
    let py2 = points[i + 1].y
    let dx = px2 - px1
    let dy = py2 - py1
    let segLen = sqrt(dx * dx + dy * dy)

    let t0 = cumLen / totalLen
    let t1 = (cumLen + segLen) / totalLen

    let thick0 = thickness1 + (thickness2 - thickness1) * t0
    let thick1 = thickness1 + (thickness2 - thickness1) * t1

    let c0 = FColor(
      r: color1.r + (color2.r - color1.r) * t0,
      g: color1.g + (color2.g - color1.g) * t0,
      b: color1.b + (color2.b - color1.b) * t0,
      a: color1.a + (color2.a - color1.a) * t0,
    )
    let c1 = FColor(
      r: color1.r + (color2.r - color1.r) * t1,
      g: color1.g + (color2.g - color1.g) * t1,
      b: color1.b + (color2.b - color1.b) * t1,
      a: color1.a + (color2.a - color1.a) * t1,
    )

    var nx0, ny0, nx1, ny1: float32
    if segLen < 0.0001:
      nx0 = 0; ny0 = 0; nx1 = 0; ny1 = 0
    else:
      nx0 = (-dy / segLen) * thick0 * 0.5
      ny0 = (dx / segLen) * thick0 * 0.5
      nx1 = (-dy / segLen) * thick1 * 0.5
      ny1 = (dx / segLen) * thick1 * 0.5

    let base = oldLen + i * 6
    r.queuedVertices[base + 0] = Render2DVertex(x: px1 + nx0, y: py1 + ny0, u: 0, v: 0, r: c0.r, g: c0.g, b: c0.b, a: c0.a)
    r.queuedVertices[base + 1] = Render2DVertex(x: px2 + nx1, y: py2 + ny1, u: 1, v: 0, r: c1.r, g: c1.g, b: c1.b, a: c1.a)
    r.queuedVertices[base + 2] = Render2DVertex(x: px2 - nx1, y: py2 - ny1, u: 1, v: 1, r: c1.r, g: c1.g, b: c1.b, a: c1.a)
    r.queuedVertices[base + 3] = Render2DVertex(x: px1 + nx0, y: py1 + ny0, u: 0, v: 0, r: c0.r, g: c0.g, b: c0.b, a: c0.a)
    r.queuedVertices[base + 4] = Render2DVertex(x: px2 - nx1, y: py2 - ny1, u: 1, v: 1, r: c1.r, g: c1.g, b: c1.b, a: c1.a)
    r.queuedVertices[base + 5] = Render2DVertex(x: px1 - nx0, y: py1 - ny0, u: 0, v: 1, r: c0.r, g: c0.g, b: c0.b, a: c0.a)

    cumLen += segLen

  r.addCommand(oldLen, totalVerts, 0)
  true

proc drawVertices*(
  r: var Render2D,
  vertices: openArray[Render2DVertex],
  texture: nil GPUTexture = nil,
  samplerMode: Render2DSamplerMode = Render2DSamplerMode.Linear,
  materialId: MaterialId = 0,
  materialUniform: ArrayView[uint8] = default(ArrayView[uint8]),
): bool =
  if vertices.len == 0:
    return false
  if r.pipeline == nil:
    return false
  var
    textureIndex: int = 0
    texture2: nil GPUTexture = nil
  if texture == nil:
    textureIndex = 0
  elif cast[uint64](texture) == 1:
    textureIndex = 1
  elif cast[uint64](texture) == 2:
    textureIndex = 2
    texture2 = if r.previousTargetReady: r.previousTarget else: r.whiteTexture
  else:
    textureIndex = 2
    texture2 = texture
  let oldLen = r.queuedVertices.len
  r.queuedVertices.add vertices
  let customSampler = case samplerMode
    of Render2DSamplerMode.Linear: r.whiteSampler
    of Render2DSamplerMode.Nearest: r.nearestSampler
  r.addCommand(oldLen, vertices.len, textureIndex, texture2, customSampler, materialId = materialId, materialUniform = materialUniform)
  true

proc restartRenderpass*(r: var Render2D) =
  prof("Render2D.restartRenderpass")
  let oldPass = r.renderPass
  if oldPass != nil:
    endGPURenderPass(oldPass)
    r.state.loadOp = GPU_LOADOP_LOAD
    r.renderPass = nil

  var target = r.target
  var resolveTarget: nil GPUTexture = nil
  var storeOp = GPU_STOREOP_STORE
  if r.sample_count != GPU_SAMPLECOUNT_1:
    target = r.targetMsaa
    resolveTarget = r.target
    storeOp = GPU_STOREOP_RESOLVE
  var targetInfo = GPUColorTargetInfo(
    texture: target,
    mip_level: 0,
    layer_or_depth_plane: 0,
    clear_color: FColor(r: 0, g: 0, b: 0, a: 0),
    load_op: r.state.loadOp,
    store_op: storeOp,
    resolve_texture: resolveTarget,
    resolve_mip_level: 0,
    resolve_layer: 0,
    cycle: false,
    cycle_resolve_texture: false,
    padding1: 0,
    padding2: 0,
  )
  let pass = beginGPURenderPass(r.commandBuffer, targetInfo.addr, 1, nil)

  pass.bindGPUGraphicsPipeline(r.pipeline)
  r.lastBoundMaterial = r.defaultMaterialId

  var viewport = GPUViewport(
    x: 0,
    y: 0,
    w: r.targetWidth.cfloat,
    h: r.targetHeight.cfloat,
    min_depth: 0,
    max_depth: 1,
  )
  pass.setGPUViewport(viewport.addr)

  var vbBinding = [
    GPUBufferBinding(
      buffer: r.vertexBuffer,
      offset: 0,
    ),
    GPUBufferBinding(
      buffer: r.textureIndexBuffer,
      offset: 0,
    ),
  ]
  pass.bindGPUVertexBuffers(0, vbBinding[0].addr, vbBinding.len.uint32)
  pass.bindGPUFragmentSamplers(0, r.activeTextures[0].addr, r.activeTextures.len.uint32)

  r.renderPass = pass

proc clear*(r: var Render2D) =
  r.commands.add(Command(kind: cClear))

func intersectRect*(a, b: Rect): Rect =
  let x1 = max(a.x, b.x)
  let y1 = max(a.y, b.y)
  let x2 = min(a.x + a.w, b.x + b.w)
  let y2 = min(a.y + a.h, b.y + b.h)
  Rect(
    x: x1,
    y: y1,
    w: max(0, x2 - x1),
    h: max(0, y2 - y1),
  )

proc pushClipRect*(r: var Render2D, x, y, w, h: cint) =
  var clipRect = Rect(x: x, y: y, w: w, h: h)
  if r.clipStack.len > 0:
    clipRect = intersectRect(r.clipStack[^1], clipRect)
  r.clipStack.add clipRect
  r.commands.add Command(kind: cClipPush, scissorRect: clipRect)

proc popClipRect*(r: var Render2D) =
  if r.clipStack.len > 0:
    discard r.clipStack.pop()
  var restoreRect: Rect
  if r.clipStack.len > 0:
    restoreRect = r.clipStack[^1]
  else:
    restoreRect = Rect(x: 0, y: 0, w: r.targetWidth.cint, h: r.targetHeight.cint)
  r.commands.add Command(kind: cClipPop, scissorRect: restoreRect)

proc flush(r: var Render2D): bool =
  prof("Render2D.flush")
  var hasDrawWork = false
  for c in r.commands:
    if c.kind == cVertices:
      hasDrawWork = true
  if not hasDrawWork:
    return true

  if not r.uploadFontAtlasGPU():
    return false

  if r.device == nil or r.commandBuffer == nil or r.target == nil:
    return false
  if r.targetWidth == 0 or r.targetHeight == 0:
    return false
  if r.pipeline == nil:
    return false
  if r.whiteTexture == nil or r.whiteSampler == nil:
    return false

  let queuedRawBytes = uint32(sizeof(Render2DVertex) * r.queuedVertices.len)

  block:
    prof("Render2D.upload")
    var externalBytes: uint32 = 0
    for c in r.commands:
      if c.kind == cVertices and c.rawData != nil:
        externalBytes += uint32(c.count) * uint32(sizeof(Render2DVertex))
    let byteCount = queuedRawBytes + externalBytes
    if byteCount == 0:
      return true
    if not ensureVertexBuffers(r, byteCount):
      return false

    let copyPass = beginGPUCopyPass(r.commandBuffer)
    if copyPass == nil:
      return false

    block:
      let mapped = cast[ptr UncheckedArray[uint32]](mapGPUTransferBuffer(r.device, r.textureIndexTransferBuffer, true))
      if mapped == nil:
        return false

      var dstOffset: int = 0
      for (count, texture) in r.textureIndices:
        for i in 0..<count:
          mapped[dstOffset + i] = texture.uint32
        dstOffset += count

      unmapGPUTransferBuffer(r.device, r.textureIndexTransferBuffer)

      var src = GPUTransferBufferLocation(
        transfer_buffer: r.textureIndexTransferBuffer,
        offset: 0,
      )
      var dst = GPUBufferRegion(
        buffer: r.textureIndexBuffer,
        offset: 0,
        size: dstOffset.uint32 * 4,
      )
      uploadToGPUBuffer(copyPass, src.addr, dst.addr, true)

    block:
      let mapped = mapGPUTransferBuffer(r.device, r.transferBuffer, true)
      if mapped == nil:
        return false

      var dstOffset: uint = 0
      for c in r.commands:
        if c.kind == cVertices:
          let size = c.count * sizeof(Render2DVertex)
          if c.rawData != nil and c.count > 0:
            copyMem(cast[pointer](cast[uint](mapped) + dstOffset), cast[pointer](c.rawData), size)
          else:
            copyMem(cast[pointer](cast[uint](mapped) + dstOffset), r.queuedVertices[c.vertices].unsafeAddr, size)
          dstOffset += size.uint32

      unmapGPUTransferBuffer(r.device, r.transferBuffer)

      var src = GPUTransferBufferLocation(
        transfer_buffer: r.transferBuffer,
        offset: 0,
      )
      var dst = GPUBufferRegion(
        buffer: r.vertexBuffer,
        offset: 0,
        size: byteCount,
      )
      uploadToGPUBuffer(copyPass, src.addr, dst.addr, true)
    endGPUCopyPass(copyPass)

  for c in r.commands:
    case c.kind
    of cClear:
      prof("Render2D.clear")
      r.state.loadOp = GPU_LOADOP_CLEAR

    of cClipPush:
      prof("Render2D.pushClip")
      if r.renderPass == nil:
        r.restartRenderpass()
      let pass = r.renderPass
      if pass != nil:
        var scissor = c.scissorRect
        pass.setGPUScissor(scissor.addr)

    of cClipPop:
      prof("Render2D.popClip")
      if r.renderPass == nil:
        r.restartRenderpass()
      let pass = r.renderPass
      if pass != nil:
        var scissor = c.scissorRect
        pass.setGPUScissor(scissor.addr)

    of cVertices:
      prof("Render2D.flush.cVertices")
      if r.renderPass == nil:
        r.restartRenderpass()

      let pass = r.renderPass
      if pass == nil:
        continue

      if r.lastBoundMaterial != c.materialId:
        let mat = r.materials.getOrDefault(c.materialId, Render2DMaterial())
        let desiredPipeline = if c.materialId == r.defaultMaterialId:
            r.pipeline
          elif mat.pipeline != nil:
            mat.pipeline
          else:
            r.pipeline
        if desiredPipeline != nil:
          pass.bindGPUGraphicsPipeline(desiredPipeline)
        if mat.hasFragmentUniform and c.materialUniform.len > 0:
          pushGPUFragmentUniformData(r.commandBuffer, 0, c.materialUniform.toOpenArray(0, c.materialUniform.high).data, uint32(c.materialUniform.len))
        r.lastBoundMaterial = c.materialId

      r.activeTextures[2] = GPUTextureSamplerBinding(
        texture: if c.customTexture != nil: c.customTexture else: r.whiteTexture,
        sampler: if c.customTexture != nil and c.customSampler != nil: c.customSampler else: r.whiteSampler,
      )
      pass.bindGPUFragmentSamplers(0, r.activeTextures[0].addr, r.activeTextures.len.uint32)

      var uniforms = Render2DVertexUniformData()
      uniforms.mvp[0][0] = 2.0 / r.targetWidth.float32
      uniforms.mvp[1][1] = -2.0 / r.targetHeight.float32
      uniforms.mvp[2][2] = 1.0
      uniforms.mvp[3][0] = -1.0
      uniforms.mvp[3][1] = 1.0
      uniforms.mvp[3][3] = 1.0
      pushGPUVertexUniformData(r.commandBuffer, 0, uniforms.addr, uint32(sizeof(uniforms)))

      pass.drawGPUPrimitives(c.count.uint32, 1, c.vertexIndex.uint32, 0)

  r.clearBatch()

  return true

proc present*(r: var Render2D, renderer: Renderer): bool =
  prof("Render2D.present")
  let targetTexture = r.ensureRenderTargetTexture(renderer)
  if targetTexture == nil:
    return false

  var dstRect = FRect(x: 0, y: 0, w: r.targetWidth.float32, h: r.targetHeight.float32)
  return renderer.renderTexture(targetTexture, cast[ptr FRect](nil), dstRect.addr)

proc presentToSwapchain*(r: var Render2D, window: Window) =
  let commandBuffer = r.device.acquireGPUCommandBuffer()
  var swapchainTexture: nil GPUTexture = nil
  var swapchainWidth: uint32 = 0
  var swapchainHeight: uint32 = 0
  discard commandBuffer.waitAndAcquireGPUSwapchainTexture(window, swapchainTexture, swapchainWidth, swapchainHeight)
  if swapchainTexture != nil:
    let copyPass = commandBuffer.beginGPUCopyPass()
    var source = GPUTextureLocation(texture: r.target)
    var destination = GPUTextureLocation(texture: swapchainTexture)
    copyPass.copyGPUTextureToTexture(source.addr, destination.addr, r.targetWidth, r.targetHeight, 1, false)
    copyPass.endGPUCopyPass()
    discard submitGPUCommandBuffer(commandBuffer)

proc copyTargetToPreviousFrame(r: var Render2D): bool =
  if r.commandBuffer == nil or r.target == nil or r.previousTarget == nil:
    return false
  if r.targetWidth == 0 or r.targetHeight == 0:
    return false

  let copyPass = beginGPUCopyPass(r.commandBuffer)
  if copyPass == nil:
    return false

  var source = GPUTextureLocation(texture: r.target)
  var destination = GPUTextureLocation(texture: r.previousTarget)
  copyGPUTextureToTexture(copyPass, source.addr, destination.addr, r.targetWidth, r.targetHeight, 1, true)
  endGPUCopyPass(copyPass)
  true

proc resetFontAtlasAfterFrame(r: var Render2D) =
  if not r.fontRender[].fontAtlasNeedsReset or r.device == nil:
    return

  let shouldGrow = r.fontRender[].fontAtlasNeedsResize and r.fontRender[].canGrowFontAtlas()
  if not shouldGrow:
    r.fontRender[].resetFontAtlas(false)
    return

  let nextSize = r.fontRender[].nextFontAtlasSize()
  let newTexture = r.createFontAtlasTexture(nextSize.width.uint32, nextSize.height.uint32)
  if newTexture == nil:
    return

  discard waitForGPUIdle(r.device)
  let oldTexture = r.fontTexture
  r.fontRender[].resetFontAtlas(true)
  r.fontTexture = newTexture
  if oldTexture != nil:
    releaseGPUTexture(r.device, oldTexture)

proc endRender*(r: var Render2D) =
  prof("Render2D.endRender")
  discard r.flush()
  let pass = r.renderPass
  if pass != nil:
    endGPURenderPass(pass)
    r.state.loadOp = GPU_LOADOP_LOAD
  r.renderPass = nil

  let copiedPreviousFrame = r.copyTargetToPreviousFrame()

  if not submitGPUCommandBuffer(r.commandBuffer):
    r.commandBuffer = nil
    r.clearBatch()
    return

  r.commandBuffer = nil
  if copiedPreviousFrame:
    r.previousTargetReady = true

  r.clearBatch()
  r.resetFontAtlasAfterFrame()
