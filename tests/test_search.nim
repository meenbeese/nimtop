import std/unittest
import ntop/[search, types]

func searchProcesses(): seq[Process] =
  @[
    Process(id: 1, exeName: "one.exe"),
    Process(id: 2, exeName: "two.exe"),
    Process(id: 3, exeName: "TWO-copy.exe")
  ]

suite "process search":
  test "lowercase patterns match case-insensitively":
    var searchState: SearchState
    searchState.startSearch("two")
    check searchState.caseInsensitive
    let found = findSearchMatch(searchState, searchProcesses(), 0, sdNext)
    check found.found
    check found.index == 1

  test "uppercase patterns remain case-sensitive":
    var searchState: SearchState
    searchState.startSearch("TWO")
    check not searchState.caseInsensitive
    let found = findSearchMatch(searchState, searchProcesses(), 0, sdNext)
    check found.found
    check found.index == 2

  test "next and previous wrap with notices":
    var searchState: SearchState
    searchState.startSearch("two")
    let nextMatch = findSearchMatch(searchState, searchProcesses(), 2, sdNext)
    check nextMatch.found
    check nextMatch.index == 1
    check nextMatch.wrapped
    check nextMatch.message == "search hit BOTTOM, continuing at TOP"

    let previousMatch = findSearchMatch(searchState, searchProcesses(), 1,
      sdPrevious)
    check previousMatch.found
    check previousMatch.index == 2
    check previousMatch.wrapped
    check previousMatch.message == "search hit TOP, continuing at BOTTOM"

  test "empty and missing patterns do not match":
    var searchState: SearchState
    searchState.startSearch("")
    check not searchState.active
    check not findSearchMatch(searchState, searchProcesses(), 0, sdNext).found

    searchState.startSearch("absent")
    let missing = findSearchMatch(searchState, searchProcesses(), 0, sdNext)
    check not missing.found
    check missing.messageError
    check missing.message == "Pattern not found: absent"
