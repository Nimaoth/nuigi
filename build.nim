
import std/[parseopt, options, strutils, os, strformat, dirs, files, sequtils, unicode, osproc, times, tables, json, jsonutils, threadpool, sets, sugar, algorithm, strtabs]

let windowsMesonPath = "meson.exe"

proc findMsBuild(): string =
  # Locate MSBuild.exe so the same build works locally and on CI (e.g. GitHub
  # windows-latest runners) where the install edition/path may differ.
  when defined(windows):
    let vswhere = "C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
    if fileExists(vswhere):
      let res = execCmdEx(
        &"\"{vswhere}\" -latest -requires Microsoft.Component.MSBuild -find \"MSBuild\\Current\\Bin\\MSBuild.exe\"",
        options = {poUsePath, poEvalCommand, poStdErrToStdOut}
      )
      if res.exitCode == 0:
        let p = res.output.strip()
        if p.len > 0 and fileExists(p):
          return p
    for cand in @[
      "C:/Program Files/Microsoft Visual Studio/2022/Community/MSBuild/Current/Bin/MSBuild.exe",
      "C:/Program Files/Microsoft Visual Studio/2022/Professional/MSBuild/Current/Bin/MSBuild.exe",
      "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/MSBuild/Current/Bin/MSBuild.exe",
      "C:/Program Files/Microsoft Visual Studio/2022/BuildTools/MSBuild/Current/Bin/MSBuild.exe",
      "C:/Program Files/Microsoft Visual Studio/2019/Community/MSBuild/Current/Bin/MSBuild.exe",
      "C:/Program Files (x86)/Microsoft Visual Studio/2019/Community/MSBuild/Current/Bin/MSBuild.exe"
    ]:
      if fileExists(cand): return cand
    return "MSBuild.exe"
  else:
    return "msbuild"

proc llvmBinDir(): string =
  # Best-effort location of the LLVM bin dir so clang++/lld-link can be found
  # both locally and on CI where LLVM may not be on PATH.
  when defined(windows):
    for cand in @["C:/Program Files/LLVM/bin", "C:/llvm/bin"]:
      if dirExists(cand): return cand
    # clang++ discoverable on PATH implies its sibling lld-link is too.
    if execCmdEx("clang++.exe --version", options = {poUsePath, poEvalCommand, poStdErrToStdOut}).exitCode == 0:
      return ""
    let w = execCmdEx("where clang++.exe", options = {poUsePath, poEvalCommand, poStdErrToStdOut})
    if w.exitCode == 0:
      for line in w.output.splitLines():
        let p = line.strip()
        if p.len > 2:
          return p[0 ..< p.rfind('\\')]
    return ""
  else:
    return ""
var passthroughArgs = newSeq[string]()

var wasm = false
var gEmscriptenEnv: Table[string, string] = initTable[string, string]()
var gShellEnv: Table[string, string] = initTable[string, string]()
var emsdkRoot = ""

type NimCompiler = enum
  Nim2
  Nim2Ic
  Nimony
  NimonyLlvm
  Nlvm

proc shell(command: string, workingDir: string = "") =
  echo "> ", command
  var p: Process
  if gShellEnv.len > 0:
    var envT: StringTableRef = newStringTable()
    # Seed with the inherited environment so required system variables
    # (e.g. SYSTEMROOT) are not dropped when we override PATH or others.
    for k, v in envPairs(): envT[k] = v
    for k, v in gShellEnv: envT[k] = v
    p = startProcess(command, options = {poParentStreams, poUsePath, poEvalCommand}, workingDir = workingDir, env = envT)
  else:
    p = startProcess(command, options = {poParentStreams, poUsePath, poEvalCommand}, workingDir = workingDir, env = nil)
  let res = p.waitForExit()
  if res != 0:
    echo "Command failed with code ", res, ": ", command
    quit(0)

proc shellCapture(command: string, prefix: string, workingDir: string = "") =
  echo "> ", command
  let result = execCmdEx(
    command,
    workingDir = workingDir,
    options = {poUsePath, poEvalCommand, poStdErrToStdOut}
  )
  echo "=== ", prefix, " ==="
  if result.output.len > 0:
    stdout.write(result.output)
    if not result.output.endsWith('\n'):
      stdout.write('\n')
  if result.exitCode != 0:
    echo "Command failed with code ", result.exitCode, ": ", command
    quit(0)
  else:
    echo "=== ", prefix, " succeeded (success, ok) ==="

proc emscriptenEnv(): Table[string, string] =
  # Activate the emscripten SDK environment so that `emcc` / `emcc.bat` (and its
  # python/node/llvm toolchain) are available. We do this by running the SDK's
  # env script and capturing the resulting environment, rather than guessing PATH.
  result = initTable[string, string]()
  when defined(windows):
    emsdkRoot = ""
    if existsEnv("EMSDK"):
      emsdkRoot = getEnv("EMSDK")
    else:
      for cand in @["./emsdk", "C:/dev/emsdk", "C:/emsdk", expandTilde("~/emsdk")]:
        if dirExists(cand):
          emsdkRoot = cand
          break
    if emsdkRoot == "":
      echo "wasm: could not locate an emsdk installation (set the EMSDK env var). Falling back to the inherited PATH for emcc."
      return
    let envBat = emsdkRoot / "emsdk_env.bat"
    if not fileExists(envBat):
      echo "wasm: ", envBat, " not found. Falling back to the inherited PATH for emcc."
      return
    echo "> activating emscripten environment from ", envBat
    let res = execCmdEx("cmd /c \"\"" & envBat & "\" >nul 2>&1 && set\"", options = {poUsePath, poEvalCommand, poStdErrToStdOut})
    if res.exitCode != 0:
      echo "wasm: failed to activate emscripten environment (exit ", res.exitCode, ")"
      return
    for line in res.output.splitLines():
      let idx = line.find('=')
      if idx > 0:
        result[line[0 ..< idx]] = line[idx + 1 .. ^1]
  else:
    # On non-Windows assume `emcc` (and its toolchain) is already on PATH / sourced.
    discard

proc mesonCommand(args: string): string =
  if fileExists(windowsMesonPath):
    return &"\"{windowsMesonPath}\" {args}"
  return &"meson {args}"

proc buildSdl3(debug = false) =
  echo "buildSdl3"
  createDir("vendor")
  if not dirExists("vendor/SDL"):
    shell("git clone https://github.com/libsdl-org/SDL", "vendor")

  let mode = if debug: "Debug" else: "Release"
  shell &"\"{findMsBuild()}\" VisualC/SDL/SDL.vcxproj /p:Configuration={mode} /p:Platform=x64", "vendor/SDL"
  createDir("build")
  createDir("bin")
  copyFile &"vendor/SDL/VisualC/SDL/x64/{mode}/SDL3.dll", "./bin/SDL3.dll"
  copyFile &"vendor/SDL/VisualC/SDL/x64/{mode}/SDL3.lib", "./build/SDL3.lib"

proc buildSdl3Wasm() =
  # Build SDL3 as a static wasm library with the Emscripten toolchain so it can
  # be linked into the wasm application, matching SDL's documented workflow:
  #   emcmake cmake ..  +  emmake make  ->  libSDL3.a
  echo "buildSdl3Wasm"
  if fileExists("build/sdl3_wasm/libSDL3.a"):
    echo "wasm: SDL3 wasm static library already built (build/sdl3_wasm/libSDL3.a)"
    return
  createDir("build/sdl3_wasm")
  if not dirExists("vendor/SDL"):
    echo "clone sdl"
    shell("git clone https://github.com/libsdl-org/SDL", "vendor")
  if gEmscriptenEnv.len == 0:
    gEmscriptenEnv = emscriptenEnv()
  gShellEnv = gEmscriptenEnv
  let generator = "-G Ninja"
  shell(&"{emsdkRoot}/upstream/emscripten/emcmake.bat cmake -S vendor/SDL -B build/sdl3_wasm {generator} -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF -DSDL_WERROR=OFF")
  shell(&"{emsdkRoot}/upstream/emscripten/emmake.bat ninja -C build/sdl3_wasm -j4")
  shell("ls build", ".")
  shell("ls build/sdl3_wasm", ".")
  var libPath = ""
  for path in walkDirRec("./build/sdl3_wasm"):
    if path.endsWith("libSDL3.a") or path.endsWith("libSDL3-static.a"):
      libPath = path
      break
  if libPath == "":
    echo "wasm: could not find built SDL3 static library under build/sdl3_wasm"
    quit(0)
  # copyFile(libPath, "./build/sdl3_wasm/libSDL3.a")
  echo "wasm: SDL3 wasm static lib ready at build/sdl3_wasm/libSDL3.a"

proc buildFreetype(debug = false) =
  echo "buildFreetype"
  createDir("vendor")
  if not dirExists("vendor/freetype"):
    shell("git clone https://gitlab.freedesktop.org/freetype/freetype.git", "vendor")
  let mode = if debug: "Debug" else: "Release"
  shell &"\"{findMsBuild()}\" -t:Rebuild -p:Configuration={mode} -p:Platform=x64 MSBuild.sln", "vendor/freetype"
  createDir("build")
  copyFile &"vendor/freetype/objs/x64/{mode}/freetype.dll", "./bin/freetype.dll"
  copyFile &"vendor/freetype/objs/x64/{mode}/freetype.lib", "./build/freetype.lib"

proc buildHarfbuzz() =
  echo "buildHarfbuzz"
  createDir("vendor")
  if not dirExists("vendor/harfbuzz"):
    shell("git clone https://github.com/harfbuzz/harfbuzz", "vendor")

  createDir("build")
  let llvmBin = llvmBinDir()
  let clangExe = if llvmBin.len > 0: "\"" & (llvmBin / "clang++.exe") & "\"" else: "clang++.exe"

  # Make sure the LLVM bin dir (containing lld-link.exe) is on PATH so that
  # -fuse-ld=lld-link resolves, both locally and on CI where LLVM may live in a
  # location that is not on PATH.
  let prevEnv = gShellEnv
  if llvmBin.len > 0:
    let basePath = if gShellEnv.hasKey("PATH"): gShellEnv["PATH"] else: getEnv("PATH")
    gShellEnv["PATH"] = llvmBin & ";" & basePath

  shell &"{clangExe} -shared -std=c++17 -O3 -g -DHB_DLL_EXPORT -I./vendor/harfbuzz/src -o build/harfbuzz.dll ./vendor/harfbuzz/src/harfbuzz.cc -fuse-ld=lld-link -Xlinker /IMPLIB:build/harfbuzz.lib"

  gShellEnv = prevEnv
  copyFile &"build/harfbuzz.dll", "./bin/harfbuzz.dll"

proc buildFribidi() =
  echo "buildFribidi"
  createDir("vendor")
  if not dirExists("vendor/fribidi"):
    shell("git clone https://github.com/fribidi/fribidi", "vendor")

  let fribidiBuildDir = "build-shared-vs"
  let fribidiSetupCmd = mesonCommand(&"setup {fribidiBuildDir} --default-library=shared -Ddocs=false -Dtests=false -Dbin=false")
  if dirExists("vendor/fribidi/" & fribidiBuildDir):
    shell(fribidiSetupCmd & " --reconfigure", "vendor/fribidi")
  else:
    shell(fribidiSetupCmd & " --backend=vs", "vendor/fribidi")

  shell &"\"{findMsBuild()}\" /m /v:minimal fribidi.sln", "vendor/fribidi/" & fribidiBuildDir

  createDir("build")
  var builtDll = ""
  var builtLib = ""
  for path in walkDirRec("vendor/fribidi/" & fribidiBuildDir):
    let lowerPath = path.toLowerAscii()
    if builtDll.len == 0 and lowerPath.endsWith(".dll") and lowerPath.contains("fribidi"):
      builtDll = path
    if builtLib.len == 0 and lowerPath.endsWith(".lib") and lowerPath.contains("fribidi"):
      builtLib = path

  if builtDll.len == 0:
    echo "Could not find built FriBidi DLL in vendor/fribidi/", fribidiBuildDir
    quit(0)

  copyFile(builtDll, "./bin/fribidi.dll")
  if builtLib.len > 0:
    copyFile(builtLib, "./build/fribidi.lib")

proc buildNuiDemo(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  createDir("build")
  let outFlag = if wasm: "-o:build/nuigi-demo.js" else: "-o:bin/demo.exe"
  if wasm:
    if gEmscriptenEnv.len == 0:
      gEmscriptenEnv = emscriptenEnv()
    gShellEnv = gEmscriptenEnv
    if not fileExists("build/sdl3_wasm/libSDL3.a"):
      buildSdl3Wasm()
  else:
    gShellEnv = initTable[string, string]()
  echo "buildNuiDemo"
  let sdlLink = if wasm: "--passL:-Lbuild/sdl3_wasm --passL:-lSDL3" else: "--passL:-Lbuild"
  case compiler
  of Nim2:
    shell &"nim c {outFlag} --cc:clang -d:freetypeStatic {sdlLink} {passthroughArgs} examples/demo.nim"
  of Nim2Ic:
    shell &"nim ic {outFlag} --cc:clang -d:freetypeStatic {sdlLink} {passthroughArgs} --nimcache:nimcacheic examples/demo.nim"
  of Nimony:
    shell &"nimony c -o:bin/demo-nimony.exe --cc:gcc -d:freetypeStatic -d:sdl3 {sdlLink} {passthroughArgs} examples/demo.nim"
  of NimonyLlvm:
    shell &"nimony l -d:llvm {outFlag} {sdlLink} {passthroughArgs} examples/demo.nim"
  of Nlvm:
    shell &"nlvm c --debuginfo:on --debugger:native {outFlag} {sdlLink} {passthroughArgs} examples/demo.nim"

  if wasm:
    createDir("build")
    copyFile("assets/nuigi-demo.html", "build/nuigi-demo.html")

proc buildUiTestNim2() =
  echo "buildUiTestNim2"
  let passthroughArgs = passthroughArgs.join(" ")
  createDir("build")
  shellCapture(
    &"nim c -r -o:bin/tests/ui-mesh-style-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/ui_mesh_style_test.nim",
    "ui-mesh-style-test-nim2"
  )
  shellCapture(
    &"nim c -r -o:bin/tests/ui-windows-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/ui_windows_test.nim",
    "ui-windows-test-nim2"
  )
  shellCapture(
    &"nim c -r -o:bin/tests/ui-dynamic-virtualist-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/ui_dynamic_virtualist_test.nim",
    "ui-dynamic-virtualist-test-nim2"
  )
  shellCapture(
    &"nim c -r -o:bin/tests/ui-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/ui_basic_flags_layout_test.nim",
    "ui-test-nim2"
  )
  shellCapture(
    &"nim c -r -o:bin/tests/ui-bench-nim.exe --cc:clang --d:release --path:src {passthroughArgs} tests/ui_node_creation_bench.nim",
    "ui-bench-nim2"
  )

proc buildUiTestNimony() =
  echo "buildUiTestNimony"
  let passthroughArgs = passthroughArgs.join(" ")
  createDir("build")
  shellCapture(
    &"nimony c -r -o:ui-mesh-style-test-nimony.exe --path:src {passthroughArgs} tests/ui_mesh_style_test.nim",
    "ui-mesh-style-test-nimony"
  )
  shellCapture(
    &"nimony c -r -o:ui-windows-test-nimony.exe --path:src {passthroughArgs} tests/ui_windows_test.nim",
    "ui-windows-test-nimony"
  )
  shellCapture(
    &"nimony c -r -o:ui-dynamic-virtualist-test-nimony.exe --path:src {passthroughArgs} tests/ui_dynamic_virtualist_test.nim",
    "ui-dynamic-virtualist-test-nimony"
  )
  shellCapture(
    &"nimony c -r -o:ui-test-nimony.exe --path:src {passthroughArgs} tests/ui_basic_flags_layout_test.nim",
    "ui-test-nimony"
  )
  shellCapture(
    &"nimony c -r -o:ui-bench-nimony.exe --d:release --path:src {passthroughArgs} tests/ui_node_creation_bench.nim",
    "ui-bench-nimony"
  )

proc buildShader() =
  shell "dxc.exe -T vs_6_0 -E VSMain ./src/basic.hlsl -Fo basic.vert.dxil"
  shell "dxc.exe -T ps_6_0 -E PSMain ./src/basic.hlsl -Fo basic.frag.dxil"
  shell "dxc.exe -T ps_6_0 -E PSMain ./src/custom.frag.hlsl -Fo custom.frag.dxil"

proc buildUiTest(compiler: NimCompiler) =
  case compiler
  of Nim2:
    buildUiTestNim2()
  of Nim2Ic:
    echo "not implemented"
  of Nimony:
    buildUiTestNimony()
  of NimonyLlvm:
    echo "not implemented"
  of Nlvm:
    echo "not implemented"

var optParser = initOptParser("")
proc main() =
  createDir("build")
  createDir("bin")

  var cmd = "all"
  var compiler = Nim2
  var debug = false

  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      cmd = key

    of cmdLongOption, cmdShortOption:
      case key
      of "nim2":
        compiler = Nim2
      of "nim2ic":
        compiler = Nim2Ic
      of "nimony":
        compiler = Nimony
      of "nimony-llvm":
        compiler = NimonyLlvm
      of "nlvm":
        compiler = Nlvm

      of "wasm":
        wasm = true

      of "debug":
        debug = true

      of "help", "h":
        # echo helpText
        quit(0)

      else:
        let prefix = if kind == cmdLongOption: "--" else: "-"
        if val != "":
          passthroughArgs.add prefix & key & ":" & val
        else:
          passthroughArgs.add prefix & key

    of cmdEnd: assert(false) # cannot happen

  if wasm:
    if not passthroughArgs.anyIt("wasm" in it):
      passthroughArgs.add("--d:wasm")
    gEmscriptenEnv = emscriptenEnv()

  case cmd
  of "sdl", "sdl3":
    buildSdl3(debug)

  of "sdl3-wasm", "sdl-wasm":
    buildSdl3Wasm()

  of "freetype":
    buildFreetype()

  of "harfbuzz":
    buildHarfbuzz()

  of "fribidi":
    buildFribidi()

  of "clean":
    removeDir("./build", false)

  of "demo":
    buildNuiDemo(compiler)

  of "test":
    buildUiTest(compiler)

  of "shader":
    buildShader()

  of "deps":
    buildSdl3()
    buildFreetype()
    buildHarfbuzz()
    buildFribidi()

  of "all":
    buildSdl3()
    buildFreetype()
    buildHarfbuzz()
    buildFribidi()
    buildUiTest(compiler)
    buildNuiDemo(compiler)

  else:
    echo "Unknown command '", cmd, "'"
    quit(1)

main()
