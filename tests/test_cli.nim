import std/[strutils, unittest]
import ntop/cli

suite "cli":
  test "help and version exit successfully":
    check parseCli(["-h"]).kind == ckHelp
    check parseCli(["-v"]).kind == ckVersion
    check parseCli(["-V"]).kind == ckVersion
    let sortHelp = parseCli(["-s", "help"])
    check sortHelp.kind == ckHelp
    check sortHelp.message.contains("CPU%")

  test "unknown and missing options report errors":
    check parseCli(["-z"]).kind == ckError
    check parseCli(["--pid=42"]).kind == ckError
    check parseCli(["-s"]).message == "Option '-s' requires a value"
    check parseCli(["-s", "NOPE"]).kind == ckError
    check parseCli(["-n"]).kind == ckError
    check parseCli(["-n", "0"]).kind == ckError
    check parseCli(["-n", "many"]).kind == ckError

  test "filters and sort values parse":
    let result = parseCli(["-C", "-d", "-p", "12,345", "-N", "explorer,chrome",
      "-u", "KUZ", "-s", "CPU%"])
    check result.monochrome
    check not result.interactive
    check result.filters.pidList == @[12'u32, 345'u32]
    check result.filters.nameParts == @["explorer", "chrome"]
    check result.filters.userName == "KUZ"
    check result.sortColumnSet

  test "max iterations parses a positive count":
    let result = parseCli(["-n", "4"])
    check result.maxIterationsSet
    check result.maxIterations == 4

  test "htop process options support filtering, sorting, and tree mode":
    let result = parseCli(["-p", "12,345", "-F", "worker", "-s", "MEM"])
    check result.filters.pidList == @[12'u32, 345'u32]
    check result.filters.filterByCommand
    check result.filters.commandFilter == "worker"
    check result.sortColumn == stUsedMemory

    let tree = parseCli(["-t"])
    check tree.sortColumnSet
    check tree.sortColumn == stTree

  test "user option accepts current user, names, and numeric IDs":
    let currentUser = parseCli(["-u"])
    check currentUser.filters.filterByCurrentUser

    let namedUser = parseCli(["-u", "alice"])
    check namedUser.filters.filterByUser
    check namedUser.filters.userName == "alice"

    let numericUser = parseCli(["-u", "1001"])
    check numericUser.filters.filterByUserId
    check numericUser.filters.userId == 1001
