import std/[strutils, unicode]
import types

type
  SearchDirection* = enum
    sdNext, sdPrevious

  SearchState* = object
    pattern*: string
    caseInsensitive*: bool
    active*: bool

  SearchResult* = object
    found*: bool
    index*: int
    wrapped*: bool
    message*: string
    messageError*: bool

proc startSearch*(state: var SearchState; pattern: string) =
  state.pattern = pattern
  state.active = pattern.len > 0
  state.caseInsensitive = state.active
  for character in pattern.runes:
    if character.isUpper():
      state.caseInsensitive = false
      break

func matches(state: SearchState; name: string): bool =
  if state.caseInsensitive:
    name.toLower().contains(state.pattern.toLower())
  else:
    name.contains(state.pattern)

func findSearchMatch*(state: SearchState; processes: openArray[Process];
                      selectedIndex: int;
                      direction: SearchDirection): SearchResult =
  if not state.active:
    return

  let count = processes.len
  let selected = clamp(selectedIndex, -1, count)
  var index: int

  case direction
  of sdNext:
    index = max(0, selected + 1)
    while index < count:
      if state.matches(processes[index].exeName):
        return SearchResult(found: true, index: index)
      inc index

    result.wrapped = true
    index = 0
    while index <= selected and index < count:
      if state.matches(processes[index].exeName):
        return SearchResult(found: true, index: index, wrapped: true,
          message: "search hit BOTTOM, continuing at TOP")
      inc index

  of sdPrevious:
    index = min(selected - 1, count - 1)
    while index >= 0:
      if state.matches(processes[index].exeName):
        return SearchResult(found: true, index: index)
      dec index

    result.wrapped = true
    index = count - 1
    while index >= selected and index >= 0:
      if state.matches(processes[index].exeName):
        return SearchResult(found: true, index: index, wrapped: true,
          message: "search hit TOP, continuing at BOTTOM")
      dec index

  result.message = "Pattern not found: " & state.pattern
  result.messageError = true
