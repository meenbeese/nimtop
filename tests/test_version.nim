import std/[strutils, unittest]
import ntop/version

suite "version":
  test "version banner identifies NTop and Nim":
    let banner = versionString()
    check banner.startsWith("NTop ")
    check banner.contains("Nim ")
    check banner.len > len("NTop ")
