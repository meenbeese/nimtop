import std/unittest
import ntop/cli

suite "cli":
  test "help and version exit successfully":
    check parseCli(["-h"]).kind == ckHelp
    check parseCli(["--help"]).kind == ckHelp
    check parseCli(["-v"]).kind == ckVersion
    check parseCli(["--version"]).kind == ckVersion

  test "unknown and missing options report errors":
    check parseCli(["-z"]).kind == ckError
    check parseCli(["-s"]).message == "Option '-s' requires a value"
    check parseCli(["-s", "NOPE"]).kind == ckError

  test "filters and sort values parse":
    let result = parseCli(["-C", "-d", "-p", "12,345", "-n", "explorer,chrome",
      "-u", "KUZ", "-s", "CPU%"])
    check result.monochrome
    check not result.interactive
    check result.filters.pidList == @[12'u32, 345'u32]
    check result.filters.nameParts == @["explorer", "chrome"]
    check result.filters.userName == "KUZ"
    check result.sortColumnSet
