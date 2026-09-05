# nuigi - immediate mode UI library in Nim

Documentation for agents lives in [docs/README.md](docs/README.md) (build, architecture, compilers, config, tests, dependencies, debugging).
Read relevant parts before implementing a feature, and update relevant parts after implementing or changing a feature.

## Build system

Custom build script compiled to `./build.exe`. **Do not use `nim c` directly**; always use `./build.exe`.

| Command | What it does |
|---|---|
| `./build.exe demo` | Build examples/demo.nim (Nim2) |
| `./build.exe test` | Build and run tests |
| `./build.exe all` | dependencies + demo |
| `./build.exe clean` | Remove `build/` |

Compiler flags: `--nim2`, `--nim2ic`, `--nimony`, `--nimony-llvm`, `--nlvm`.

All extra flags are passed through to the Nim compiler automatically.

# Nim vs nimony

`nimony` is the new Nim compiler.

- You can find the nim standard library in `C:/dev/Nim/lib/` and the nimony standard library in `C:/dev/nimony/lib/`
- see `src/nuigi/util/compat2.nim` for nim2 and nimony compatibility
- make sure everything compiles with nimony as well. avoid nim2 only features like macros/option/etc.

## Important notes for creating UIs
- nodes done't have a default sizing policy. use one of (some can be different in x/y axis):
  - width()/height()/size()
  - fitX/fitY/fit
  - fillX/fillY/fill
  - anchors/offsets/pivot/finishAnchors
  - table/flex/grid layout
- for nodes with text set the text after any text related properties like font size or font
- don't pass string literals to node templates, use debugName() instead
- don't hard code colors or paddings, use theme styles (see UiStyleIndex and UiTextStyleIndex). avoid copyStyleIndex and copyTextStyleIndex unless you need to modify a property for that specific node. use `proc styleIndex*(b: var UiBuilder, value: uint16)` and `proc textStyleIndex*(b: var UiBuilder, value: int)` by default.

## Tests

Tests and benchmarks are separate programs under `tests/`. Run the complete suite for one compiler with `./build.exe test` (Nim 2 by default), `./build.exe test --nim2`, or `./build.exe test --nimony`. The Nimony suite omits `font_wrapping_test.nim`; focused test and benchmark commands are documented in [docs/testing.md](docs/testing.md).

## Key config files

- `config.nims` – injected into every Nim build. Sets ARC memory mgmt, debug info, native debugger, `nuiDebug` define.
- `nim.cfg` – dependency search paths.

## Compiler quirks

- Nimony compatibility issues tracked in `nimony_compat.md` (strformat, nil checks, template bugs).
- Open Nimony compiler bugs in `nimony_compiler_bugs.md` (2 known).
- Add workarounds to `src/nuigi/util/compat2.nim` (included, not imported).
- use proper nil types (`nil ptr`, `nil ref`) when nil is possilble. when you have a nillable global, when using it copy it into a local first, nil check type narrowing doesn't work for nillable gobals.

when working with strings, don't take address of string content, use these apis:
```nim
func beginStore*(s: var string; newLen: int; start = 0): ptr UncheckedArray[char] {.noSideEffect, raises: [], tags: [].} =
  s.setLen(newLen)
  return cast[ptr UncheckedArray[char]](s[start].addr)

func endStore*(s: var string) {.inline, noSideEffect, raises: [], tags: [].} =
  discard

func readRawData*(s {.byref.}: string; start = 0): ptr UncheckedArray[char] {.inline, noSideEffect, raises: [], tags: [].} =
  # instead of str[start].addr
  return cast[ptr UncheckedArray[char]](s[start].addr)
```

## Dependencies

C/C++ dependencies built from source:
- SDL3 (`vendor/SDL/`) – built via MSBuild, outputs `SDL3.dll` + `SDL3.lib`.

All dlls live at repo root.

## Continuous integration and tooling

`.github/workflows/build-nui-demo-wasm.yml` runs on pushes to `main` and by manual dispatch on Windows. It builds dependencies, runs the test suite separately with Nim 2 and Nimony, builds both native demos, smoke-tests the Nim 2 demo, uploads the native binaries, and builds and deploys the WASM demo to GitHub Pages.

No linters or formatters are configured.
