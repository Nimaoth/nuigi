## Tiny bridge from the debug UI to the external `nev` source navigator.
##
## `openInNev` launches an attached nev instance at a quoted path and 1-based
## line. The call is best-effort and deliberately ignores the process status,
## so hosts may use the debug panel without depending on nev at runtime.

import std/os

proc openInNev*(path: string, line: int = 1) =
  discard execShellCmd("nev --attach:0 --location:" & $line & ",1 " & path.quoteShell)
