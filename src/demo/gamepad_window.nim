import sdl3
import mymath
import arena, array_view, mesh, nuigi, widgets, windows

const
  GamepadAxisCount = int(GAMEPAD_AXIS_COUNT)
  GamepadButtonCount = int(GAMEPAD_BUTTON_COUNT)
  GamepadStickNavigationThreshold = 16_000'i16
  ControllerWidth = 520.0'f32
  ControllerHeight = 286.0'f32
  CircleSegments = 20

type
  DemoGamepad = object
    handle: Gamepad
    instanceId: JoystickID
    name: string
    axes: array[GamepadAxisCount, int16]
    visualAxes: array[GamepadAxisCount, float32]
    buttons: array[GamepadButtonCount, bool]
    visualButtons: array[GamepadButtonCount, float32]

  DemoGamepadInput* = object
    gamepads: seq[DemoGamepad]
    keysDown: UiKeys
    keysPressed: UiKeys
    keysReleased: UiKeys
    navigationPressed: UiNavigationDirections

  MeshWriter = object
    vertices: nil ptr UncheckedArray[UiVertex]
    count: int
    capacity: int

func mixColor(a, b: UiColor, amount: float32): UiColor =
  let t = clamp(amount, 0.0'f32, 1.0'f32)
  rgba(
    a.r + (b.r - a.r) * t,
    a.g + (b.g - a.g) * t,
    a.b + (b.b - a.b) * t,
    a.a + (b.a - a.a) * t,
  )

proc addTriangle(writer: var MeshWriter, a, b, c: Vec2, color: UiColor) =
  if writer.count + 3 > writer.capacity:
    return
  writer.vertices[writer.count] = UiVertex(pos: a, color: color); inc writer.count
  writer.vertices[writer.count] = UiVertex(pos: b, color: color); inc writer.count
  writer.vertices[writer.count] = UiVertex(pos: c, color: color); inc writer.count

proc addQuad(writer: var MeshWriter, a, b, c, d: Vec2, color: UiColor) =
  writer.addTriangle(a, b, c, color)
  writer.addTriangle(a, c, d, color)

proc addCircle(writer: var MeshWriter, center: Vec2, radius: float32, color: UiColor,
    scale = vec2(1.0'f32), offset = vec2(0.0'f32), rotation = 0.0'f32) =
  let cosine = cos(rotation.float64).float32
  let sine = sin(rotation.float64).float32
  proc transform(point: Vec2): Vec2 =
    let local = (point - center) * scale
    center + offset + vec2(
      local.x * cosine - local.y * sine,
      local.x * sine + local.y * cosine,
    )
  let transformedCenter = transform(center)
  for segment in 0 ..< CircleSegments:
    let angle0 = segment.float32 / CircleSegments.float32 * PI.float32 * 2.0'f32
    let angle1 = (segment + 1).float32 / CircleSegments.float32 * PI.float32 * 2.0'f32
    let point0 = transform(center + vec2(cos(angle0.float64).float32, sin(angle0.float64).float32) * radius)
    let point1 = transform(center + vec2(cos(angle1.float64).float32, sin(angle1.float64).float32) * radius)
    writer.addTriangle(transformedCenter, point0, point1, color)

proc addPolygon(writer: var MeshWriter, points: openArray[Vec2], color: UiColor) =
  if points.len < 3:
    return
  var center = vec2(0.0'f32)
  for point in points:
    center += point
  center = center / points.len.float32
  for index in 0 ..< points.len:
    writer.addTriangle(center, points[index], points[(index + 1) mod points.len], color)

func transformPoint(point, pivot, offset, scale: Vec2, rotation: float32): Vec2 =
  let local = (point - pivot) * scale
  let cosine = cos(rotation.float64).float32
  let sine = sin(rotation.float64).float32
  pivot + offset + vec2(
    local.x * cosine - local.y * sine,
    local.x * sine + local.y * cosine,
  )

proc findGamepad(input: DemoGamepadInput, instanceId: JoystickID): int =
  for index in 0 ..< input.gamepads.len:
    if input.gamepads[index].instanceId == instanceId:
      return index
  return -1

proc anyButtonDown(input: DemoGamepadInput, button: GamepadButton): bool =
  let buttonIndex = ord(button)
  for gamepad in input.gamepads:
    if gamepad.buttons[buttonIndex]:
      return true
  return false

proc addGamepad(input: var DemoGamepadInput, instanceId: JoystickID) =
  if input.findGamepad(instanceId) >= 0:
    return
  let handle = openGamepad(instanceId)
  if handle == nil:
    echo "Could not open gamepad ", instanceId, ": ", $getError()
    return
  let namePtr = getGamepadName(handle)
  let name = if namePtr == nil: "Unknown gamepad" else: $namePtr
  input.gamepads.add DemoGamepad(handle: handle, instanceId: instanceId, name: name)
  echo "Gamepad added: ", name, " (", instanceId, ")"

proc removeGamepad(input: var DemoGamepadInput, instanceId: JoystickID) =
  let index = input.findGamepad(instanceId)
  if index < 0:
    return
  let releasedSouth = input.gamepads[index].buttons[ord(GAMEPAD_BUTTON_SOUTH)]
  let releasedEast = input.gamepads[index].buttons[ord(GAMEPAD_BUTTON_EAST)]
  echo "Gamepad removed: ", input.gamepads[index].name, " (", instanceId, ")"
  closeGamepad(input.gamepads[index].handle)
  input.gamepads.delete(index)
  if releasedSouth and not input.anyButtonDown(GAMEPAD_BUTTON_SOUTH):
    input.keysDown.excl KeyEnter
    input.keysReleased.incl KeyEnter
  if releasedEast and not input.anyButtonDown(GAMEPAD_BUTTON_EAST):
    input.keysDown.excl KeyEscape
    input.keysReleased.incl KeyEscape

proc updateButton(input: var DemoGamepadInput, instanceId: JoystickID,
    buttonIndex: int, down: bool) =
  let index = input.findGamepad(instanceId)
  if index < 0 or buttonIndex < 0 or buttonIndex >= GamepadButtonCount:
    return
  let wasDown = input.gamepads[index].buttons[buttonIndex]
  input.gamepads[index].buttons[buttonIndex] = down
  if down and not wasDown:
    case GamepadButton(buttonIndex)
    of GAMEPAD_BUTTON_DPAD_LEFT: input.navigationPressed.incl NavLeft
    of GAMEPAD_BUTTON_DPAD_RIGHT: input.navigationPressed.incl NavRight
    of GAMEPAD_BUTTON_DPAD_UP: input.navigationPressed.incl NavUp
    of GAMEPAD_BUTTON_DPAD_DOWN: input.navigationPressed.incl NavDown
    of GAMEPAD_BUTTON_SOUTH:
      input.keysDown.incl KeyEnter
      input.keysPressed.incl KeyEnter
    of GAMEPAD_BUTTON_EAST:
      input.keysDown.incl KeyEscape
      input.keysPressed.incl KeyEscape
    else: discard
  elif not down and wasDown:
    case GamepadButton(buttonIndex)
    of GAMEPAD_BUTTON_SOUTH:
      if not input.anyButtonDown(GAMEPAD_BUTTON_SOUTH):
        input.keysDown.excl KeyEnter
        input.keysReleased.incl KeyEnter
    of GAMEPAD_BUTTON_EAST:
      if not input.anyButtonDown(GAMEPAD_BUTTON_EAST):
        input.keysDown.excl KeyEscape
        input.keysReleased.incl KeyEscape
    else: discard

proc updateAxis(input: var DemoGamepadInput, instanceId: JoystickID,
    axisIndex: int, value: int16) =
  let index = input.findGamepad(instanceId)
  if index < 0 or axisIndex < 0 or axisIndex >= GamepadAxisCount:
    return
  let previous = input.gamepads[index].axes[axisIndex]
  input.gamepads[index].axes[axisIndex] = value
  case GamepadAxis(axisIndex)
  of GAMEPAD_AXIS_LEFTX:
    if value <= -GamepadStickNavigationThreshold and previous > -GamepadStickNavigationThreshold:
      input.navigationPressed.incl NavLeft
    elif value >= GamepadStickNavigationThreshold and previous < GamepadStickNavigationThreshold:
      input.navigationPressed.incl NavRight
  of GAMEPAD_AXIS_LEFTY:
    if value <= -GamepadStickNavigationThreshold and previous > -GamepadStickNavigationThreshold:
      input.navigationPressed.incl NavUp
    elif value >= GamepadStickNavigationThreshold and previous < GamepadStickNavigationThreshold:
      input.navigationPressed.incl NavDown
  else: discard

proc beginFrame*(input: var DemoGamepadInput) =
  input.keysPressed = {}
  input.keysReleased = {}
  input.navigationPressed = {}

proc handleEvent*(input: var DemoGamepadInput, event: var Event): bool =
  case event.`type`
  of EVENT_GAMEPAD_ADDED:
    input.addGamepad(event.gdevice.which)
  of EVENT_GAMEPAD_REMOVED:
    input.removeGamepad(event.gdevice.which)
  of EVENT_GAMEPAD_REMAPPED:
    let index = input.findGamepad(event.gdevice.which)
    if index >= 0:
      let namePtr = getGamepadName(input.gamepads[index].handle)
      input.gamepads[index].name = if namePtr == nil: "Unknown gamepad" else: $namePtr
  of EVENT_GAMEPAD_BUTTON_DOWN, EVENT_GAMEPAD_BUTTON_UP:
    input.updateButton(event.gbutton.which, event.gbutton.button.int, event.gbutton.down)
  of EVENT_GAMEPAD_AXIS_MOTION:
    input.updateAxis(event.gaxis.which, event.gaxis.axis.int, event.gaxis.value)
  else:
    return false
  return true

proc applyToSnapshot*(input: DemoGamepadInput, snapshot: var UiInputSnapshot) =
  snapshot.keysDown = snapshot.keysDown + input.keysDown
  snapshot.keysPressed = snapshot.keysPressed + input.keysPressed
  snapshot.keysReleased = snapshot.keysReleased + input.keysReleased
  snapshot.navigationPressed = snapshot.navigationPressed + input.navigationPressed

proc updateVisualState(gamepad: var DemoGamepad, b: var UiBuilder) =
  let blend = clamp(b.frameCtx.animationTick * 16.0'f32, 0.0'f32, 1.0'f32)
  var animating = false
  for axisIndex in 0 ..< GamepadAxisCount:
    let target = clamp(gamepad.axes[axisIndex].float32 / 32767.0'f32, -1.0'f32, 1.0'f32)
    gamepad.visualAxes[axisIndex] += (target - gamepad.visualAxes[axisIndex]) * blend
    animating = animating or abs(target - gamepad.visualAxes[axisIndex]) > 0.002'f32
  for buttonIndex in 0 ..< GamepadButtonCount:
    let target = if gamepad.buttons[buttonIndex]: 1.0'f32 else: 0.0'f32
    gamepad.visualButtons[buttonIndex] += (target - gamepad.visualButtons[buttonIndex]) * blend
    animating = animating or abs(target - gamepad.visualButtons[buttonIndex]) > 0.002'f32
  if animating:
    b.anythingAnimating = true

proc buttonAmount(gamepad: DemoGamepad, button: GamepadButton): float32 =
  gamepad.visualButtons[ord(button)]

proc addAnimatedButton(writer: var MeshWriter, center: Vec2, radius: float32,
    amount: float32, idleColor, activeColor: UiColor, bodyPivot: Vec2,
    bodyRotation: float32, bodyOffset: Vec2) =
  let scale = 1.0'f32 - amount * 0.12'f32
  let localCenter = center + vec2(0.0'f32, amount * 3.0'f32)
  let transformedCenter = transformPoint(localCenter, bodyPivot, bodyOffset, vec2(1.0'f32), bodyRotation)
  writer.addCircle(
    transformedCenter,
    radius,
    mixColor(idleColor, activeColor, amount),
    scale = vec2(scale),
    rotation = bodyRotation,
  )

proc buildControllerMesh(b: var UiBuilder, gamepad: var DemoGamepad,
    origin: Vec2): ArrayView[UiRenderCommand] =
  const MaxVertices = 4096
  let vertexData = cast[nil ptr UncheckedArray[UiVertex]](
    b.frame.arena[].alloc(MaxVertices * sizeof(UiVertex)))
  if vertexData == nil:
    return default(ArrayView[UiRenderCommand])
  var writer = MeshWriter(vertices: vertexData, capacity: MaxVertices)

  gamepad.updateVisualState(b)
  let controlColor = b.themeStyle(UiStyleIndexPanel)[].borderColor
  let accentColor = b.themeStyle(UiStyleIndexAccent)[].fillColor
  let bodyColor = rgba(0.055'f32, 0.06'f32, 0.065'f32, 1.0'f32)
  let stickWellColor = rgba(0.075'f32, 0.08'f32, 0.085'f32, 1.0'f32)
  let controlIdleColor = rgba(0.76'f32, 0.77'f32, 0.79'f32, 1.0'f32)
  let bodyPivot = origin + vec2(ControllerWidth * 0.5'f32, ControllerHeight * 0.48'f32)
  let bodyRotation = gamepad.visualAxes[ord(GAMEPAD_AXIS_RIGHTX)] * 0.018'f32
  let triggerLean = gamepad.visualAxes[ord(GAMEPAD_AXIS_RIGHT_TRIGGER)] -
    gamepad.visualAxes[ord(GAMEPAD_AXIS_LEFT_TRIGGER)]
  let bodyOffset = vec2(triggerLean * 2.0'f32, abs(triggerLean) * 1.5'f32)

  proc bodyPoint(x, y: float32): Vec2 =
    transformPoint(origin + vec2(x, y), bodyPivot, bodyOffset, vec2(1.0'f32), bodyRotation)

  let shellControlPoints = [
    bodyPoint(72, 58), bodyPoint(150, 32), bodyPoint(208, 45), bodyPoint(260, 38),
    bodyPoint(312, 45), bodyPoint(370, 32), bodyPoint(448, 58), bodyPoint(474, 112),
    bodyPoint(454, 220), bodyPoint(420, 274), bodyPoint(377, 264), bodyPoint(344, 190),
    bodyPoint(176, 190), bodyPoint(143, 264), bodyPoint(100, 274), bodyPoint(66, 220),
    bodyPoint(46, 112),
  ]
  var shell: array[shellControlPoints.len * 2, Vec2]
  for pointIndex in 0 ..< shellControlPoints.len:
    let current = shellControlPoints[pointIndex]
    let next = shellControlPoints[(pointIndex + 1) mod shellControlPoints.len]
    shell[pointIndex * 2] = current * 0.75'f32 + next * 0.25'f32
    shell[pointIndex * 2 + 1] = current * 0.25'f32 + next * 0.75'f32
  writer.addPolygon(shell, controlColor)
  var innerShell: array[shell.len, Vec2]
  for pointIndex in 0 ..< shell.len:
    innerShell[pointIndex] = bodyPivot + (shell[pointIndex] - bodyPivot) * 0.975'f32
  writer.addPolygon(innerShell, bodyColor)

  let centerPanel = [
    bodyPoint(151, 56), bodyPoint(205, 52), bodyPoint(224, 72), bodyPoint(296, 72),
    bodyPoint(315, 52), bodyPoint(369, 56), bodyPoint(348, 191), bodyPoint(300, 222),
    bodyPoint(220, 222), bodyPoint(172, 191),
  ]
  writer.addPolygon(centerPanel, stickWellColor)
  let touchpadAmount = gamepad.buttonAmount(GAMEPAD_BUTTON_TOUCHPAD)
  writer.addQuad(bodyPoint(211, 66 + touchpadAmount * 2), bodyPoint(309, 66 + touchpadAmount * 2),
    bodyPoint(296, 124 + touchpadAmount * 2), bodyPoint(224, 124 + touchpadAmount * 2),
    mixColor(controlIdleColor, accentColor, touchpadAmount))

  let leftTrigger = max(0.0'f32, gamepad.visualAxes[ord(GAMEPAD_AXIS_LEFT_TRIGGER)])
  let rightTrigger = max(0.0'f32, gamepad.visualAxes[ord(GAMEPAD_AXIS_RIGHT_TRIGGER)])
  let leftShoulder = gamepad.buttonAmount(GAMEPAD_BUTTON_LEFT_SHOULDER)
  let rightShoulder = gamepad.buttonAmount(GAMEPAD_BUTTON_RIGHT_SHOULDER)
  writer.addQuad(
    bodyPoint(108, 34 + leftTrigger * 5), bodyPoint(158, 23 + leftTrigger * 5),
    bodyPoint(164, 37 + leftTrigger * 5), bodyPoint(113, 48 + leftTrigger * 5),
    mixColor(controlIdleColor, accentColor, leftTrigger))
  writer.addQuad(
    bodyPoint(362, 23 + rightTrigger * 5), bodyPoint(412, 34 + rightTrigger * 5),
    bodyPoint(407, 48 + rightTrigger * 5), bodyPoint(356, 37 + rightTrigger * 5),
    mixColor(controlIdleColor, accentColor, rightTrigger))
  writer.addQuad(
    bodyPoint(94, 51 + leftShoulder * 2), bodyPoint(166, 38 + leftShoulder * 2),
    bodyPoint(171, 52 + leftShoulder * 2), bodyPoint(102, 65 + leftShoulder * 2),
    mixColor(controlIdleColor, accentColor, leftShoulder))
  writer.addQuad(
    bodyPoint(354, 38 + rightShoulder * 2), bodyPoint(426, 51 + rightShoulder * 2),
    bodyPoint(418, 65 + rightShoulder * 2), bodyPoint(349, 52 + rightShoulder * 2),
    mixColor(controlIdleColor, accentColor, rightShoulder))

  let dpadCenter = origin + vec2(145.0'f32, 119.0'f32)
  let dpadButtons = [
    (GAMEPAD_BUTTON_DPAD_UP, [
      vec2(-10.0'f32, -34.0'f32), vec2(10.0'f32, -34.0'f32),
      vec2(10.0'f32, -18.0'f32), vec2(0.0'f32, -8.0'f32),
      vec2(-10.0'f32, -18.0'f32),
    ]),
    (GAMEPAD_BUTTON_DPAD_DOWN, [
      vec2(-10.0'f32, 18.0'f32), vec2(0.0'f32, 8.0'f32),
      vec2(10.0'f32, 18.0'f32), vec2(10.0'f32, 34.0'f32),
      vec2(-10.0'f32, 34.0'f32),
    ]),
    (GAMEPAD_BUTTON_DPAD_LEFT, [
      vec2(-34.0'f32, -10.0'f32), vec2(-18.0'f32, -10.0'f32),
      vec2(-8.0'f32, 0.0'f32), vec2(-18.0'f32, 10.0'f32),
      vec2(-34.0'f32, 10.0'f32),
    ]),
    (GAMEPAD_BUTTON_DPAD_RIGHT, [
      vec2(18.0'f32, -10.0'f32), vec2(34.0'f32, -10.0'f32),
      vec2(34.0'f32, 10.0'f32), vec2(18.0'f32, 10.0'f32),
      vec2(8.0'f32, 0.0'f32),
    ]),
  ]
  for (button, localPoints) in dpadButtons:
    let amount = gamepad.buttonAmount(button)
    let move = vec2(0.0'f32, amount * 2.0'f32)
    var points: array[5, Vec2]
    for pointIndex in 0 ..< localPoints.len:
      points[pointIndex] = transformPoint(
        dpadCenter + localPoints[pointIndex] + move,
        bodyPivot, bodyOffset, vec2(1.0'f32), bodyRotation)
    writer.addPolygon(points, mixColor(controlIdleColor, accentColor, amount))

  let faceButtons = [
    (GAMEPAD_BUTTON_NORTH, vec2(392.0'f32, 88.0'f32)),
    (GAMEPAD_BUTTON_EAST, vec2(423.0'f32, 119.0'f32)),
    (GAMEPAD_BUTTON_SOUTH, vec2(392.0'f32, 150.0'f32)),
    (GAMEPAD_BUTTON_WEST, vec2(361.0'f32, 119.0'f32)),
  ]
  for (button, center) in faceButtons:
    writer.addAnimatedButton(origin + center, 14.0'f32, gamepad.buttonAmount(button),
      controlIdleColor, accentColor, bodyPivot, bodyRotation, bodyOffset)

  let leftAxis = vec2(
    gamepad.visualAxes[ord(GAMEPAD_AXIS_LEFTX)],
    gamepad.visualAxes[ord(GAMEPAD_AXIS_LEFTY)],
  )
  let rightAxis = vec2(
    gamepad.visualAxes[ord(GAMEPAD_AXIS_RIGHTX)],
    gamepad.visualAxes[ord(GAMEPAD_AXIS_RIGHTY)],
  )
  let stickData = [
    (origin + vec2(207.0'f32, 181.0'f32), leftAxis, GAMEPAD_BUTTON_LEFT_STICK),
    (origin + vec2(313.0'f32, 181.0'f32), rightAxis, GAMEPAD_BUTTON_RIGHT_STICK),
  ]
  for (center, axis, button) in stickData:
    let transformedBase = transformPoint(center, bodyPivot, bodyOffset, vec2(1.0'f32), bodyRotation)
    writer.addCircle(transformedBase, 25.0'f32, stickWellColor, rotation = bodyRotation)
    let pressAmount = gamepad.buttonAmount(button)
    let stickOffset = axis * 11.0'f32 + vec2(0.0'f32, pressAmount * 2.0'f32)
    let transformedStick = transformPoint(center + stickOffset, bodyPivot, bodyOffset, vec2(1.0'f32), bodyRotation)
    writer.addCircle(transformedStick, 17.0'f32,
      mixColor(controlIdleColor, accentColor, max(pressAmount, axis.length)),
      scale = vec2(1.0'f32 - pressAmount * 0.1'f32), rotation = bodyRotation)

  let smallButtons = [
    (GAMEPAD_BUTTON_BACK, origin + vec2(190.0'f32, 137.0'f32)),
    (GAMEPAD_BUTTON_START, origin + vec2(330.0'f32, 137.0'f32)),
    (GAMEPAD_BUTTON_GUIDE, origin + vec2(260.0'f32, 163.0'f32)),
  ]
  for (button, center) in smallButtons:
    writer.addAnimatedButton(center, 8.0'f32, gamepad.buttonAmount(button),
      controlIdleColor, accentColor, bodyPivot, bodyRotation, bodyOffset)

  var commands = b.frame.arena[].allocEmptyArray(1, UiRenderCommand)
  commands.add UiRenderCommand(
    kind: CmdRawVertices,
    vertexData: vertexData,
    vertexCount: writer.count.int32,
  )
  return commands

proc buildGamepadWindow*(input: var DemoGamepadInput, b: var UiBuilder) =
  b.window("Gamepad Input", 1180, 520, 590, 500):
    b.scrollBox():
      discard b.sizeToParentX().fitY()
      b.layoutVertical:
        discard b.fillX().fitY().padding(10).gap(12)
        b.node():
          discard b.fit().text("D-pad/left stick: navigate | South: activate | East: cancel")
        if input.gamepads.len == 0:
          b.node():
            discard b.fit().text("No gamepad connected")
        for gamepadIndex in 0 ..< input.gamepads.len:
          let gamepad = input.gamepads[gamepadIndex].addr
          b.pushId(gamepad.instanceId.uint64)
          b.layoutVertical:
            discard b.fillX().fitY().gap(4)
            b.node():
              discard b.fillX().fitY().styleIndex(UiStyleIndexHeader)
              discard b.text(gamepad.name & " (ID " & $gamepad.instanceId & ")")
            b.node("controller-mesh"):
              discard b.size(ControllerWidth, ControllerHeight)
              let origin = b.absoluteNodePos(b.currentNodeIndex())
              discard b.customRenderCommands(buildControllerMesh(b, gamepad[], origin))
          discard b.popId()

proc shutdown*(input: var DemoGamepadInput) =
  for gamepad in input.gamepads:
    closeGamepad(gamepad.handle)
  input.gamepads.setLen(0)