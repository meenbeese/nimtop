version       = "0.1.0"
author        = "Kuzey Bilgin"
description   = "htop-like system monitor for Windows and Linux with Vi keybindings"
license       = "GPL-3.0-only"
srcDir        = "src"
bin           = @["nimtop"]

requires "nim >= 2.2.0"

when defined(windows):
  requires "winim >= 3.9.0"
  const releaseExecutable = "nimtop.exe"
else:
  const releaseExecutable = "nimtop"

task test, "Run the test suite":
  exec "nim c -r --hints:off --path:src tests/test_all.nim"

task release, "Build the release binary":
  exec "nim c -d:release -d:NTopVersion=" & version &
    " --opt:speed --app:console --path:src --out:" & releaseExecutable &
    " src/nimtop.nim"
