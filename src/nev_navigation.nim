import std/os

proc openInNev*(path: string, line: int = 1) =
  discard execShellCmd("nev --attach:0 --location:" & $line & ",1 " & path.quoteShell)
