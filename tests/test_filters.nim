import std/unittest
import ntop/[filters, types]

suite "process filters":
  let process = Process(id: 42, userName: "ExampleUser",
    exeName: "ExampleApp.exe")

  test "PID filters match exact IDs":
    check passesFilters(process, Filters(
      filterByPid: true, pidList: @[42'u32]))
    check not passesFilters(process, Filters(
      filterByPid: true, pidList: @[24'u32]))

  test "name filters are case-sensitive and use any matching part":
    check passesFilters(process, Filters(
      filterByName: true, nameParts: @["Other", "App"]))
    check not passesFilters(process, Filters(
      filterByName: true, nameParts: @["app"]))

  test "command filter matches case-insensitive substrings":
    check passesFilters(process, Filters(
      filterByCommand: true, commandFilter: "exampleapp"))
    check not passesFilters(process, Filters(
      filterByCommand: true, commandFilter: "other"))

  test "user filters ignore case":
    check passesFilters(process, Filters(
      filterByUser: true, userName: "exampleuser"))
    check not passesFilters(process, Filters(
      filterByUser: true, userName: "someone-else"))

  test "user ID filters require a valid process user ID":
    let root = Process(id: 1, userId: 0, userIdValid: true)
    check passesFilters(root, Filters(filterByUserId: true, userId: 0))
    check not passesFilters(Process(id: 1),
      Filters(filterByUserId: true, userId: 0))

  test "active filters are combined":
    check not passesFilters(process, Filters(
      filterByPid: true, pidList: @[42'u32],
      filterByUser: true, userName: "other"))
