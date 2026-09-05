switch("mm", "arc")
switch("d", "useMalloc")
switch("nimcache", "./build/nimcache")
switch("debuginfo", "on")
switch("debugger", "native")
switch("lineDir", "off")
switch("d", "release")
switch("lineTrace", "off")
switch("stackTrace", "off")
switch("d", "nuiDebug")
switch("d", "profiler")
switch("path", "src")
switch("hints", "off")

when defined(wasm):
  echo "build wasm"
  include "wasm.config.nims"
