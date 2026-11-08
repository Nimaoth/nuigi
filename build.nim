
import std/[parseopt, options, strutils, os, strformat, dirs, files, sequtils, unicode, osproc, times, tables, json, jsonutils, threadpool, sets, sugar, algorithm, strtabs]

let windowsMesonPath = "C:/Users/nimao/AppData/Roaming/Python/Python310/Scripts/meson.exe"
const msvcStaticRuntimeFlag =
  when defined(windows): " -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"
  else: ""

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
var nimCompilerPath = "nim"
var useNimIc = false

var wasm = false
var gEmscriptenEnv: Table[string, string] = initTable[string, string]()
var gShellEnv: Table[string, string] = initTable[string, string]()
var emsdkRoot = ""

type NimCompiler = enum
  Nim2
  Nim2Ic
  Nimony
  NimonyN
  NimonyLlvm
  Nlvm

proc nimCommand(args: string): string =
  let commandArgs =
    if useNimIc and args.startsWith("c "):
      "ic " & args[2 .. ^1]
    else:
      args
  quoteShell(nimCompilerPath) & " " & commandArgs

proc printCommandTiming(startedAt: float) =
  echo "=== command finished in ", formatFloat(epochTime() - startedAt, ffDecimal, 3), " s ==="

proc shell(command: string, workingDir: string = "") =
  echo "> ", command
  let startedAt = epochTime()
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
  printCommandTiming(startedAt)
  if res != 0:
    echo "Command failed with code ", res, ": ", command
    quit(res)

proc shellCapture(command: string, prefix: string, workingDir: string = "") =
  echo "> ", command
  let startedAt = epochTime()
  let result = execCmdEx(
    command,
    workingDir = workingDir,
    options = {poUsePath, poEvalCommand, poStdErrToStdOut}
  )
  printCommandTiming(startedAt)
  echo "=== ", prefix, " ==="
  if result.output.len > 0:
    stdout.write(result.output)
    if not result.output.endsWith('\n'):
      stdout.write('\n')
  if result.exitCode != 0:
    echo "Command failed with code ", result.exitCode, ": ", command
    quit(result.exitCode)
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

proc requireProgram(program, installHint: string) =
  if findExe(program).len == 0:
    echo "Required build program not found: ", program
    echo installHint
    quit(1)

proc copyLinuxLibrary(searchDir, libraryName: string) =
  var found = false
  createDir("build")
  createDir("bin")
  for path in walkDirRec(searchDir, yieldFilter = {pcFile, pcLinkToFile}):
    let name = extractFilename(path)
    if name == libraryName or name.startsWith(libraryName & "."):
      found = true
      copyFile(path, "build" / name)
      copyFile(path, "bin" / name)
  if not found:
    echo "Could not find ", libraryName, " under ", searchDir
    quit(1)

proc copyBuiltLibrary(searchDir, sourceName, targetName: string) =
  for path in walkDirRec(searchDir, yieldFilter = {pcFile, pcLinkToFile}):
    if extractFilename(path).toLowerAscii() == sourceName.toLowerAscii():
      createDir("build")
      copyFile(path, "build" / targetName)
      return
  echo "Could not find ", sourceName, " under ", searchDir
  quit(1)

proc buildSdl3(debug = false) =
  echo "buildSdl3"
  createDir("vendor")
  if not dirExists("vendor/SDL"):
    shell("git clone https://github.com/libsdl-org/SDL", "vendor")

  let mode = if debug: "Debug" else: "Release"
  when defined(windows):
    shell &"\"{findMsBuild()}\" VisualC/SDL/SDL.vcxproj /p:Configuration={mode} /p:Platform=x64", "vendor/SDL"
    createDir("build")
    createDir("bin")
    copyFile &"vendor/SDL/VisualC/SDL/x64/{mode}/SDL3.dll", "./bin/SDL3.dll"
    copyFile &"vendor/SDL/VisualC/SDL/x64/{mode}/SDL3.lib", "./build/SDL3.lib"
  else:
    requireProgram("cmake", "On Ubuntu: sudo apt install cmake")
    let buildDir = "build/sdl3"
    shell &"cmake -S vendor/SDL -B {buildDir} -DCMAKE_BUILD_TYPE={mode} -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF"
    shell &"cmake --build {buildDir} --config {mode} --parallel"
    copyLinuxLibrary(buildDir, "libSDL3.so")

proc buildSdl3Static() =
  echo "buildSdl3Static"
  createDir("vendor")
  if not dirExists("vendor/SDL"):
    shell("git clone https://github.com/libsdl-org/SDL", "vendor")

  requireProgram("cmake", "Install CMake to build SDL3.")
  let buildDir = "build/sdl3_static"
  shell &"cmake -S vendor/SDL -B {buildDir} -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF{msvcStaticRuntimeFlag}"
  shell &"cmake --build {buildDir} --config Release --parallel"
  when defined(windows):
    copyBuiltLibrary(buildDir, "SDL3-static.lib", "SDL3.lib")
  else:
    copyBuiltLibrary(buildDir, "libSDL3.a", "libSDL3.a")

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
    quit(1)
  # copyFile(libPath, "./build/sdl3_wasm/libSDL3.a")
  echo "wasm: SDL3 wasm static lib ready at build/sdl3_wasm/libSDL3.a"

proc installAccessKit() =
  # AccessKit ships prebuilt libraries in vendor/accesskit-c. Copy the shared
  # library next to the executables so it is found at runtime when building
  # with -d:nuiAccessKit, and the import library into build/ for linking.
  echo "installAccessKit"
  createDir("build")
  createDir("bin")
  when defined(windows):
    let src = "vendor/accesskit-c/lib/windows/x86_64/msvc/shared"
    copyFile(src & "/accesskit.dll", "bin/accesskit.dll")
    copyFile(src & "/accesskit.lib", "build/accesskit.lib")
    # Import library for gcc-based builds (nimony).
    copyFile("vendor/accesskit-c/lib/windows/x86_64/mingw/shared/libaccesskit.a",
      "build/libaccesskit.a")
  elif defined(macosx):
    let arch = if hostCPU == "arm64": "arm64" else: "x86_64"
    let src = "vendor/accesskit-c/lib/macos/" & arch & "/shared"
    copyFile(src & "/libaccesskit.dylib", "bin/libaccesskit.dylib")
    copyFile(src & "/libaccesskit.dylib", "build/libaccesskit.dylib")
  else:
    let src = "vendor/accesskit-c/lib/linux/x86_64/shared"
    copyFile(src & "/libaccesskit.so", "bin/libaccesskit.so")
    copyFile(src & "/libaccesskit.so", "build/libaccesskit.so")

proc generateAccessKitBindings() =
  # Regenerates the Nim bindings from vendor/accesskit-c/include/accesskit.h.
  # Requires Python 3 with the clang package (pip install clang) and libclang.
  echo "generateAccessKitBindings"
  requireProgram("python", "Install Python 3 and run `pip install clang`.")
  shell "python tools/generate_accesskit_bindings.py"

proc buildFreetype(debug = false) =
  echo "buildFreetype"
  createDir("vendor")
  if not dirExists("vendor/freetype"):
    shell("git clone https://gitlab.freedesktop.org/freetype/freetype.git", "vendor")
  let mode = if debug: "Debug" else: "Release"
  when defined(windows):
    shell &"\"{findMsBuild()}\" -t:Rebuild -p:Configuration={mode} -p:Platform=x64 MSBuild.sln", "vendor/freetype"
    createDir("build")
    copyFile &"vendor/freetype/objs/x64/{mode}/freetype.dll", "./bin/freetype.dll"
    copyFile &"vendor/freetype/objs/x64/{mode}/freetype.lib", "./build/freetype.lib"
  else:
    requireProgram("cmake", "On Ubuntu: sudo apt install cmake")
    let buildDir = "build/freetype"
    shell &"cmake -S vendor/freetype -B {buildDir} -DCMAKE_BUILD_TYPE={mode} -DBUILD_SHARED_LIBS=ON -DFT_DISABLE_HARFBUZZ=TRUE -DFT_DISABLE_BROTLI=TRUE -DFT_DISABLE_BZIP2=TRUE -DFT_DISABLE_PNG=TRUE -DFT_DISABLE_ZLIB=TRUE"
    shell &"cmake --build {buildDir} --config {mode} --parallel"
    copyLinuxLibrary(buildDir, "libfreetype.so")

proc buildFreetypeStatic() =
  echo "buildFreetypeStatic"
  createDir("vendor")
  if not dirExists("vendor/freetype"):
    shell("git clone https://gitlab.freedesktop.org/freetype/freetype.git", "vendor")

  requireProgram("cmake", "Install CMake to build FreeType.")
  let buildDir = "build/freetype_static"
  shell &"cmake -S vendor/freetype -B {buildDir} -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_HARFBUZZ=TRUE -DFT_DISABLE_BROTLI=TRUE -DFT_DISABLE_BZIP2=TRUE -DFT_DISABLE_PNG=TRUE -DFT_DISABLE_ZLIB=TRUE{msvcStaticRuntimeFlag}"
  shell &"cmake --build {buildDir} --config Release --parallel"
  when defined(windows):
    copyBuiltLibrary(buildDir, "freetype.lib", "freetype.lib")
  else:
    copyBuiltLibrary(buildDir, "libfreetype.a", "libfreetype.a")

proc buildFreetypeStaticNimony() =
  echo "buildFreetypeStaticNimony"
  createDir("vendor")
  if not dirExists("vendor/freetype"):
    shell("git clone https://gitlab.freedesktop.org/freetype/freetype.git", "vendor")

  requireProgram("cmake", "Install CMake to build FreeType.")
  requireProgram("ninja", "Install Ninja to build FreeType for Nimony.")
  let buildDir = "build/freetype_nimony_static"
  shell &"cmake -S vendor/freetype -B {buildDir} -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_HARFBUZZ=TRUE -DFT_DISABLE_BROTLI=TRUE -DFT_DISABLE_BZIP2=TRUE -DFT_DISABLE_PNG=TRUE -DFT_DISABLE_ZLIB=TRUE"
  shell &"cmake --build {buildDir} --config Release --parallel"

proc buildHarfbuzz() =
  echo "buildHarfbuzz"
  createDir("vendor")
  if not dirExists("vendor/harfbuzz"):
    shell("git clone https://github.com/harfbuzz/harfbuzz", "vendor")

  createDir("build")
  when defined(windows):
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
    shell &"{clangExe} -shared -std=c++17 -O3 -g -DHB_DLL_EXPORT -I./vendor/harfbuzz/src -L./build -lharfbuzz -o build/harfbuzz-subset.dll ./vendor/harfbuzz/src/harfbuzz-subset.cc -fuse-ld=lld-link -Xlinker /IMPLIB:build/harfbuzz-subset.lib"

    gShellEnv = prevEnv
    copyFile &"build/harfbuzz.dll", "./bin/harfbuzz.dll"
    copyFile &"build/harfbuzz-subset.dll", "./bin/harfbuzz-subset.dll"
  else:
    requireProgram("clang++", "On Ubuntu: sudo apt install clang")
    shell "clang++ -shared -fPIC -std=c++17 -O3 -g -DHB_DLL_EXPORT -I./vendor/harfbuzz/src -o build/libharfbuzz.so ./vendor/harfbuzz/src/harfbuzz.cc"
    shell "clang++ -shared -fPIC -std=c++17 -O3 -g -DHB_DLL_EXPORT -I./vendor/harfbuzz/src -L./build -lharfbuzz -Wl,-rpath,\\$ORIGIN -o build/libharfbuzz-subset.so ./vendor/harfbuzz/src/harfbuzz-subset.cc"
    copyFile "build/libharfbuzz.so", "bin/libharfbuzz.so"
    copyFile "build/libharfbuzz-subset.so", "bin/libharfbuzz-subset.so"

proc buildFribidi() =
  echo "buildFribidi"
  createDir("vendor")
  if not dirExists("vendor/fribidi"):
    shell("git clone https://github.com/fribidi/fribidi", "vendor")

  when defined(windows):
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
      quit(1)

    copyFile(builtDll, "./bin/fribidi.dll")
    if builtLib.len > 0:
      copyFile(builtLib, "./build/fribidi.lib")
  else:
    requireProgram("meson", "On Ubuntu: sudo apt install meson")
    let buildDir = "build/fribidi"
    let reconfigure = if dirExists(buildDir): " --reconfigure" else: ""
    shell &"meson setup {buildDir} vendor/fribidi --buildtype=release --default-library=shared -Ddocs=false -Dtests=false -Dbin=false{reconfigure}"
    shell &"meson compile -C {buildDir}"
    copyLinuxLibrary(buildDir, "libfribidi.so")

proc buildNuiDemo(compiler: NimCompiler, staticDependencies = false) =
  let passthroughArgs = passthroughArgs.join(" ")
  let useIc = compiler == Nim2Ic or (compiler == Nim2 and useNimIc)
  createDir("build")
  createDir("bin")
  let outFlag =
    if wasm: "-o:build/nuigi-demo.js"
    elif staticDependencies:
      if useNimIc: "-o:bin/demo-static-ic.exe" else: "-o:bin/demo-static.exe"
    elif useIc: "-o:bin/demo-ic.exe"
    else: "-o:bin/demo.exe"
  if wasm:
    if gEmscriptenEnv.len == 0:
      gEmscriptenEnv = emscriptenEnv()
    gShellEnv = gEmscriptenEnv
    if not fileExists("build/sdl3_wasm/libSDL3.a"):
      buildSdl3Wasm()
  else:
    gShellEnv = initTable[string, string]()
  echo "buildNuiDemo"
  let sdlLink =
    if wasm:
      "--passL:-Lbuild/sdl3_wasm --passL:-lSDL3"
    elif defined(windows):
      "--passL:-Lbuild"
    else:
      "--passL:-Lbuild --passL:'-Wl,-rpath,\\$ORIGIN'"
  let sdlSystemLink =
    when defined(windows):
      if staticDependencies or compiler == NimonyLlvm:
        "--passL:-lkernel32 --passL:-luser32 --passL:-lgdi32 --passL:-lwinmm --passL:-limm32 --passL:-lole32 --passL:-loleaut32 --passL:-lversion --passL:-luuid --passL:-ladvapi32 --passL:-lsetupapi --passL:-lshell32 --passL:-lhid --passL:-lmincore --passL:-ldinput8"
      else:
        ""
    else:
      ""
  let noHarfbuzz = if staticDependencies: "-d:nuiNoHarfbuzz" else: ""
  if "nuiAccessKit" in passthroughArgs:
    installAccessKit()
  case compiler
  of Nim2:
    shell nimCommand(&"c {outFlag} --cc:clang -d:freetypeStatic -d:sdl3 --nimcache:build/nimcache-nim {noHarfbuzz} {sdlLink} {sdlSystemLink} {passthroughArgs} examples/demo.nim")
  of Nim2Ic:
    shell nimCommand(&"ic {outFlag} --cc:clang -d:freetypeStatic -d:sdl3 --nimcache:build/nimcache-nim-ic {noHarfbuzz} {sdlLink} {sdlSystemLink} {passthroughArgs} examples/demo.nim")
  of Nimony:
    when defined(windows):
      buildFreetypeStaticNimony()
      shell &"nimony c -o:bin/demo-nimony.exe --cc:gcc -d:freetypeStatic -d:sdl3 --nimcache:build/nimcache-nimony --passL:-Lbuild/freetype_nimony_static {sdlLink} {passthroughArgs} examples/demo.nim"
    else:
      shell &"nimony c -o:bin/demo-nimony.exe --cc:gcc -d:freetypeStatic -d:sdl3 --nimcache:build/nimcache-nimony {sdlLink} {passthroughArgs} examples/demo.nim"
  of NimonyN:
    when defined(windows):
      buildFreetypeStaticNimony()
      shell &"nimony n -o:bin/demo-nimony-n.exe --cc:gcc -d:freetypeStatic -d:sdl3 --nimcache:build/nimcache-nimony-n --passL:-Lbuild/freetype_nimony_static {sdlLink} {passthroughArgs} examples/demo.nim"
    else:
      shell &"nimony n -o:bin/demo-nimony-n.exe --cc:gcc -d:freetypeStatic -d:sdl3 --nimcache:build/nimcache-nimony-n {sdlLink} {passthroughArgs} examples/demo.nim"
  of NimonyLlvm:
    shell &"nimony l -o:bin/demo-nimony-llvm.exe -d:llvm -d:freetypeStatic -d:sdl3 --nimcache:build/nimcache-nimony-llvm {sdlLink} {sdlSystemLink} {passthroughArgs} examples/demo.nim"
  of Nlvm:
    shell &"nlvm c --debuginfo:on --debugger:native {outFlag} -d:sdl3 --nimcache:build/nimcache-nlvm {sdlLink} {passthroughArgs} examples/demo.nim"

  if wasm:
    createDir("build")
    copyFile("assets/nuigi-demo.html", "build/nuigi-demo.html")

proc buildTerminalDemo(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  createDir("bin")
  echo "buildTerminalDemo"
  case compiler
  of Nim2:
    shell nimCommand(&"c -o:bin/terminal-demo.exe --cc:clang --path:src {passthroughArgs} examples/terminal_demo.nim")
  of Nim2Ic:
    shell nimCommand(&"ic -o:bin/terminal-demo.exe --cc:clang --path:src {passthroughArgs} examples/terminal_demo.nim")
  of Nimony:
    shell &"nimony c -o:bin/terminal-demo-nimony.exe --cc:gcc --path:src {passthroughArgs} examples/terminal_demo.nim"
  of NimonyN:
    shell &"nimony n -o:bin/terminal-demo-nimony-n.exe --cc:gcc --path:src {passthroughArgs} examples/terminal_demo.nim"
  of NimonyLlvm:
    shell &"nimony l -d:llvm -o:bin/terminal-demo-nimony.exe --path:src {passthroughArgs} examples/terminal_demo.nim"
  of Nlvm:
    shell &"nlvm c --debuginfo:on --debugger:native -o:bin/terminal-demo.exe --path:src {passthroughArgs} examples/terminal_demo.nim"

proc buildTerminalTest(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/terminal-unicode-test-nim.exe --cc:clang --path:src {passthroughArgs} tests/terminal_unicode_test.nim"),
      "terminal-unicode-test-nim2"
    )
    shellCapture(
      nimCommand(&"c -r -o:bin/terminal-backend-test-nim.exe --cc:clang --path:src {passthroughArgs} tests/terminal_backend_test.nim"),
      "terminal-backend-test-nim2"
    )
  of Nimony:
    shellCapture(
      &"nimony c -r -o:bin/terminal-unicode-test-nimony.exe --path:src {passthroughArgs} tests/terminal_unicode_test.nim",
      "terminal-unicode-test-nimony"
    )
    shellCapture(
      &"nimony c -r -o:bin/terminal-backend-test-nimony.exe --path:src {passthroughArgs} tests/terminal_backend_test.nim",
      "terminal-backend-test-nimony"
    )
  else:
    echo "not implemented"

proc buildCoreTest(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/ui-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/ui_basic_flags_layout_test.nim"),
      "ui-test-nim2"
    )
  of Nimony:
    shellCapture(
      &"nimony c -r -o:bin/ui-test-nimony.exe --path:src {passthroughArgs} tests/ui_basic_flags_layout_test.nim",
      "ui-test-nimony"
    )
  of NimonyN:
    shellCapture(
      &"nimony n -r -o:bin/ui-test-nimony-n.exe --path:src {passthroughArgs} tests/ui_basic_flags_layout_test.nim",
      "ui-test-nimony"
    )
  else:
    echo "not implemented"

proc buildUiTestNim2() =
  echo "buildUiTestNim2"
  let passthroughArgs = passthroughArgs.join(" ")
  createDir("build")
  shellCapture(
    nimCommand(&"c -r -o:bin/ui-mesh-style-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/ui_mesh_style_test.nim"),
    "ui-mesh-style-test-nim2"
  )
  shellCapture(
    nimCommand(&"c -r -o:bin/ui-windows-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/ui_windows_test.nim"),
    "ui-windows-test-nim2"
  )
  shellCapture(
    nimCommand(&"c -r -o:bin/ui-dynamic-virtualist-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/ui_dynamic_virtualist_test.nim"),
    "ui-dynamic-virtualist-test-nim2"
  )
  buildCoreTest(Nim2)
  shellCapture(
    nimCommand(&"c -r -o:bin/ui-tree-table-seek-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/tree_table_seek_test.nim"),
    "ui-tree-table-seek-test-nim2"
  )
  shellCapture(
    nimCommand(&"c -r -o:bin/ui-bench-nim.exe --cc:clang --d:release --path:src {passthroughArgs} tests/ui_node_creation_bench.nim"),
    "ui-bench-nim2"
  )

proc buildFontWrappingTest(compiler: NimCompiler) =
  echo "buildFontWrappingTest"
  let passthroughArgs = passthroughArgs.join(" ")
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/font-wrapping-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --d:nuiNoHarfbuzz --d:freetypeStatic --passL:-Lbuild --path:src {passthroughArgs} tests/font_wrapping_test.nim"),
      "font-wrapping-test-nim2"
    )
  of Nimony:
    let freetypeLink =
      when defined(windows):
        buildFreetypeStaticNimony()
        "--passL:-Lbuild/freetype_nimony_static --passL:-Lbuild"
      else:
        "--passL:-Lbuild"
    shellCapture(
      &"nimony c -r -o:bin/font-wrapping-test-nimony.exe --d:nuiNoHarfbuzz --d:freetypeStatic {freetypeLink} --path:src {passthroughArgs} tests/font_wrapping_test.nim",
      "font-wrapping-test-nimony"
    )
  else:
    echo "not implemented"

proc buildTextFieldTest(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/textfield-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/textfield_test.nim"),
      "textfield-test-nim2"
    )
  of Nimony:
    shellCapture(
      &"nimony c -r -o:bin/textfield-test-nimony.exe --path:src {passthroughArgs} tests/textfield_test.nim",
      "textfield-test-nimony"
    )
  else:
    echo "not implemented"

proc buildFocusTest(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/ui-focus-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/ui_focus_test.nim"),
      "ui-focus-test-nim2"
    )
  of Nimony:
    shellCapture(
      &"nimony c -r -o:bin/ui-focus-test-nimony.exe --path:src {passthroughArgs} tests/ui_focus_test.nim",
      "ui-focus-test-nimony"
    )
  else:
    echo "not implemented"

proc buildThreadQueueTest(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/thread-queue-test-nim.exe --cc:clang --threads:on --assertions:on --path:src {passthroughArgs} tests/thread_queue_test.nim"),
      "thread-queue-test-nim2"
    )
  of Nimony:
    shellCapture(
      &"nimony c -r -o:bin/thread-queue-test-nimony.exe --path:src {passthroughArgs} tests/thread_queue_test.nim",
      "thread-queue-test-nimony"
    )
  else:
    quit("thread-queue-test supports --nim2 and --nimony", 1)

proc buildSemanticActionsTest(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/semantic-actions-test-nim.exe --cc:clang --path:src {passthroughArgs} tests/semantic_actions_test.nim"),
      "semantic-actions-test-nim2")
  of Nimony:
    shellCapture(
      &"nimony c -r -o:bin/semantic-actions-test-nimony.exe --path:src {passthroughArgs} tests/semantic_actions_test.nim",
      "semantic-actions-test-nimony")
  else:
    quit("semantic-actions-test supports --nim2 and --nimony", 1)

proc buildAccessKitTreeTest(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  installAccessKit()
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/accesskit-tree-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/accesskit_tree_test.nim"),
      "accesskit-tree-test-nim2"
    )
  of Nimony:
    shellCapture(
      &"nimony c -r -o:bin/accesskit-tree-test-nimony.exe --passL:-Lbuild --path:src {passthroughArgs} tests/accesskit_tree_test.nim",
      "accesskit-tree-test-nimony"
    )
  else:
    echo "not implemented"

proc buildUiTestNimony() =
  echo "buildUiTestNimony"
  let passthroughArgs = passthroughArgs.join(" ")
  createDir("build")
  shellCapture(
    &"nimony c -r -o:bin/ui-mesh-style-test-nimony.exe --path:src {passthroughArgs} tests/ui_mesh_style_test.nim",
    "ui-mesh-style-test-nimony"
  )
  shellCapture(
    &"nimony c -r -o:bin/ui-windows-test-nimony.exe --path:src {passthroughArgs} tests/ui_windows_test.nim",
    "ui-windows-test-nimony"
  )
  shellCapture(
    &"nimony c -r -o:bin/ui-dynamic-virtualist-test-nimony.exe --path:src {passthroughArgs} tests/ui_dynamic_virtualist_test.nim",
    "ui-dynamic-virtualist-test-nimony"
  )
  buildCoreTest(Nimony)
  shellCapture(
    &"nimony c -r -o:bin/ui-tree-table-seek-test-nimony.exe --path:src {passthroughArgs} tests/tree_table_seek_test.nim",
    "ui-tree-table-seek-test-nimony"
  )
  shellCapture(
    &"nimony c -r -o:bin/ui-bench-nimony.exe --d:release --path:src {passthroughArgs} tests/ui_node_creation_bench.nim",
    "ui-bench-nimony"
  )

proc buildUiTestNimonyN() =
  echo "buildUiTestNimonyN"
  let passthroughArgs = passthroughArgs.join(" ")
  createDir("build")
  shellCapture(
    &"nimony n -r -o:bin/ui-mesh-style-test-nimony.exe --path:src {passthroughArgs} tests/ui_mesh_style_test.nim",
    "ui-mesh-style-test-nimony"
  )
  shellCapture(
    &"nimony n -r -o:bin/ui-windows-test-nimony.exe --path:src {passthroughArgs} tests/ui_windows_test.nim",
    "ui-windows-test-nimony"
  )
  shellCapture(
    &"nimony n -r -o:bin/ui-dynamic-virtualist-test-nimony.exe --path:src {passthroughArgs} tests/ui_dynamic_virtualist_test.nim",
    "ui-dynamic-virtualist-test-nimony"
  )
  buildCoreTest(Nimony)
  shellCapture(
    &"nimony n -r -o:bin/ui-tree-table-seek-test-nimony.exe --path:src {passthroughArgs} tests/tree_table_seek_test.nim",
    "ui-tree-table-seek-test-nimony"
  )
  shellCapture(
    &"nimony n -r -o:bin/ui-bench-nimony.exe --d:release --path:src {passthroughArgs} tests/ui_node_creation_bench.nim",
    "ui-bench-nimony"
  )

proc buildShader() =
  when defined(windows):
    requireProgram("dxc.exe", "Install the DirectX Shader Compiler and add it to PATH")
    shell "dxc.exe -T vs_6_0 -E VSMain ./src/nuigi/rendering/shaders/basic.hlsl -Fo ./assets/basic.vert.dxil"
    shell "dxc.exe -T ps_6_0 -E PSMain ./src/nuigi/rendering/shaders/basic.hlsl -Fo ./assets/basic.frag.dxil"
    shell "dxc.exe -T ps_6_0 -E PSMain ./src/nuigi/rendering/shaders/custom.frag.hlsl -Fo ./assets/custom.frag.dxil"
  elif defined(linux):
    requireProgram("glslc", "On Ubuntu: sudo apt install glslc")
    shell "glslc -x hlsl -fshader-stage=vert -fentry-point=VSMain ./src/nuigi/rendering/shaders/basic.hlsl -o ./assets/basic.vert.spv"
    shell "glslc -x hlsl -fshader-stage=frag -fentry-point=PSMain ./src/nuigi/rendering/shaders/basic.hlsl -o ./assets/basic.frag.spv"
    shell "glslc -x hlsl -fshader-stage=frag -fentry-point=PSMain ./src/nuigi/rendering/shaders/custom.frag.hlsl -o ./assets/custom.frag.spv"
  else:
    echo "Shader compilation is not implemented for this platform"
    quit(1)

proc buildUiTest(compiler: NimCompiler) =
  case compiler
  of Nim2:
    buildUiTestNim2()
  of Nim2Ic:
    echo "not implemented"
  of Nimony:
    buildUiTestNimony()
  of NimonyN:
    buildUiTestNimonyN()
  of NimonyLlvm:
    echo "not implemented"
  of Nlvm:
    echo "not implemented"

proc buildTreeTableRefreshTest(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/tree-table-refresh-test-nim.exe --cc:clang --stackTrace:on --lineTrace:on --d:debug --path:src {passthroughArgs} tests/tree_table_refresh_test.nim"),
      "tree-table-refresh-test-nim2"
    )
  of Nimony:
    shellCapture(
      &"nimony c -r -o:bin/tree-table-refresh-test-nimony.exe --path:src {passthroughArgs} tests/tree_table_refresh_test.nim",
      "tree-table-refresh-test-nimony"
    )
  else:
    echo "not implemented"

proc buildTreeTableRefreshBench(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/tree-table-refresh-bench-nim.exe --cc:clang -d:release --path:src {passthroughArgs} tests/tree_table_refresh_bench.nim"),
      "tree-table-refresh-bench-nim2"
    )
  of Nimony:
    shellCapture(
      &"nimony c -r -o:bin/tree-table-refresh-bench-nimony.exe -d:release --path:src {passthroughArgs} tests/tree_table_refresh_bench.nim",
      "tree-table-refresh-bench-nimony"
    )
  else:
    echo "not implemented"

proc buildFileSystemCursorBench(compiler: NimCompiler) =
  let passthroughArgs = passthroughArgs.join(" ")
  case compiler
  of Nim2:
    shellCapture(
      nimCommand(&"c -r -o:bin/file-system-cursor-bench-nim.exe --cc:clang -d:release --path:src {passthroughArgs} tests/file_system_cursor_bench.nim"),
      "file-system-cursor-bench-nim2"
    )
  of Nimony:
    shellCapture(
      &"nimony c -r -o:bin/file-system-cursor-bench-nimony.exe -d:release --path:src {passthroughArgs} tests/file_system_cursor_bench.nim",
      "file-system-cursor-bench-nimony"
    )
  else:
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
      of "nimonyn":
        compiler = NimonyN
      of "nimony-llvm":
        compiler = NimonyLlvm
      of "nlvm":
        compiler = Nlvm

      of "wasm":
        wasm = true

      of "nim-path":
        if val.len == 0:
          echo "Option --nim-path requires a compiler executable path"
          quit(1)
        nimCompilerPath = val

      of "ic":
        useNimIc = true

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

  of "sdl3-static":
    buildSdl3Static()

  of "freetype-static":
    buildFreetypeStatic()

  of "harfbuzz":
    buildHarfbuzz()

  of "fribidi":
    buildFribidi()

  of "accesskit":
    installAccessKit()

  of "accesskit-bindings":
    generateAccessKitBindings()

  of "accesskit-test":
    buildAccessKitTreeTest(compiler)

  of "thread-queue-test":
    buildThreadQueueTest(compiler)

  of "semantic-actions-test":
    buildSemanticActionsTest(compiler)

  of "clean":
    removeDir("./build", false)

  of "demo":
    when defined(linux):
      if not fileExists("assets/basic.vert.spv") or
          not fileExists("assets/basic.frag.spv") or
          not fileExists("assets/custom.frag.spv"):
        buildShader()
    buildNuiDemo(compiler)

  of "demo-static":
    buildSdl3Static()
    buildFreetypeStatic()
    buildNuiDemo(Nim2, staticDependencies = true)

  of "terminal-demo":
    buildTerminalDemo(compiler)

  of "terminal-test":
    buildTerminalTest(compiler)

  of "test":
    buildUiTest(compiler)
    buildThreadQueueTest(compiler)
    buildSemanticActionsTest(compiler)
    buildTextFieldTest(compiler)
    buildFocusTest(compiler)
    buildTerminalTest(compiler)
    buildFontWrappingTest(compiler)
    buildTreeTableRefreshTest(compiler)
    buildTreeTableRefreshBench(compiler)
    buildFileSystemCursorBench(compiler)
    when defined(windows):
      # The AccessKit integration is currently Windows only.
      buildAccessKitTreeTest(compiler)

  of "tree-table-refresh-test":
    buildTreeTableRefreshTest(compiler)

  of "font-wrapping-test":
    buildFontWrappingTest(compiler)

  of "textfield-test":
    buildTextFieldTest(compiler)

  of "focus-test":
    buildFocusTest(compiler)

  of "core-test":
    buildCoreTest(compiler)

  of "tree-table-refresh-bench":
    buildTreeTableRefreshBench(compiler)

  of "file-system-cursor-bench":
    buildFileSystemCursorBench(compiler)

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
    when defined(linux):
      if not fileExists("assets/basic.vert.spv") or
          not fileExists("assets/basic.frag.spv") or
          not fileExists("assets/custom.frag.spv"):
        buildShader()
    buildNuiDemo(compiler)

  else:
    echo "Unknown command '", cmd, "'"
    quit(1)

main()
