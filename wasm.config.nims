# This file is for compiling nim plugins to wasm.

--os:linux # Emscripten pretends to be linux.
--cpu:wasm32 # Emscripten is 32bits.
--cc:clang # Emscripten is very close to clang, so we ill replace it.
when defined(windows):
  --clang.exe:emcc.bat  # Replace C
  --clang.linkerexe:emcc.bat # Replace C linker
  --clang.cpp.exe:emcc.bat # Replace C++
  --clang.cpp.linkerexe:emcc.bat # Replace C++ linker.
else:
  --clang.exe:emcc  # Replace C
  --clang.linkerexe:emcc # Replace C linker
  --clang.cpp.exe:emcc # Replace C++
  --clang.cpp.linkerexe:emcc # Replace C++ linker.
# --listCmd # List what commands we are running so that we can debug them.

--gc:arc # GC:arc is friendlier with crazy platforms.
--exceptions:goto # Goto exceptions are friendlier with crazy platforms.
--define:noSignalHandler # Emscripten doesn't support signal handlers.
# --noMain:on
# We want emscripten to emit and run a `main` entry so the generated
# HTML/JS glue actually starts the program, so Nim must produce `main`.
--threads:off # 1.7.1 defaults this on

switch("d", "wasm")
switch("d", "emscripten")
switch("nimcache", "build/nimcache_wasm")

# switch("stackTrace", "on")
# switch("lineTrace", "on")

# Pass this to Emscripten linker to generate an HTML/JS wrapper.
# Output extension `.html` makes emscripten emit `build/nui-demo.html`,
# `build/nui-demo.js` (the JS glue) and `build/nui-demo.wasm`. STANDALONE_WASM=0
# keeps the full runtime glue, and we no longer pass `--no-entry` so emscripten
# calls `main` (provided by Nim now that --noMain is off).
switch("passL", "-sSTANDALONE_WASM=0 -sERROR_ON_UNDEFINED_SYMBOLS=0 -g -gsource-map -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=134217728 -sMAXIMUM_MEMORY=4294967296 -obuild/nui-demo.html")
