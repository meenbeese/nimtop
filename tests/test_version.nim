import std/[strutils, unittest]
import ntop/version

suite "version":
  test "version banner identifies nimtop and Nim":
    let banner = versionString()
    check banner.startsWith("nimtop ")
    check banner.contains("Nim ")
    check banner.len > len("nimtop ")
