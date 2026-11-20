version       = "0.1.0"
author        = "Kuzey Bilgin"
description   = "htop-like system monitor for Windows with Vi keybindings"
license       = "GPL-3.0-only"
srcDir        = "src"
bin           = @["nimtop"]

requires "nim >= 2.2.0"
requires "winim >= 3.9.0"

task test, "Run the test suite":
  exec "nim c -r --hints:off --path:src tests/test_all.nim"

task release, "Build the release binary":
  exec "nim c -d:release --opt:speed --app:console --path:src --out:nimtop.exe src/nimtop.nim"
