version       = "0.4.0"
author        = "Gian Sass"
description   = "htop-like system monitor for Windows with Vi keybindings"
license       = "GPL-3.0-only"
srcDir        = "src"
bin           = @["ntop"]

requires "nim >= 2.2.0"
requires "winim >= 3.9.0"

task test, "Run the test suite":
  exec "nim c -r --hints:off --path:src tests/test_all.nim"

task release, "Build the release binary":
  exec "nim c -d:release --opt:speed --app:console --path:src --out:NTop.exe src/ntop.nim"
