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

  test "user filters ignore case":
    check passesFilters(process, Filters(
      filterByUser: true, userName: "exampleuser"))
    check not passesFilters(process, Filters(
      filterByUser: true, userName: "someone-else"))

  test "active filters are combined":
    check not passesFilters(process, Filters(
      filterByPid: true, pidList: @[42'u32],
      filterByUser: true, userName: "other"))
