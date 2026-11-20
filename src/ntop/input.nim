import std/[strutils, unicode]
import search, sorting, types, vi

const
  VkBack = 0x08
  VkReturn = 0x0D
  VkEscape = 0x1B
  VkSpace = 0x20
  VkPrior = 0x21
  VkNext = 0x22
  VkLeft = 0x25
  VkUp = 0x26
  VkRight = 0x27
  VkDown = 0x28
  VkF4 = 0x73
  VkF10 = 0x79

type
  InputMode* = enum
    imNormal, imCommand, imSearch, imFilter

  InputAction* = enum
    iaNone, iaQuit, iaKillTagged, iaSubmitCommand, iaSubmitSearch,
    iaSearchNext, iaSearchPrevious

  UiState* = object
    allProcesses*: seq[Process]
    processes*: seq[Process]
    tagged*: seq[uint32]
    selectedIndex*: int
    firstVisible*: int
    sortType*: SortType
    sortOrder*: SortOrder
    followProcess*: bool
    followPid*: uint32
    runningCount*: uint32
    cpuUsage*: float64
    inputMode*: InputMode
    inputText*: string
    filterText*: string
    submittedText*: string
    history*: ViHistory
    search*: SearchState
    message*: string
    messageError*: bool
    caretVisible*: bool
    scrollKey: int
    scrollStartedAt: uint64
    lastScrollAt: uint64
    allRunningCount: uint32

func initUiState*(sortType = stId; sortOrder = soDescending): UiState =
  UiState(sortType: sortType, sortOrder: sortOrder, caretVisible: true)

proc currentProcessId(state: UiState): uint32 =
  if state.processes.len > 0 and
      state.selectedIndex >= 0 and state.selectedIndex < state.processes.len:
    state.processes[state.selectedIndex].id
  else:
    0

proc ensureVisible(state: var UiState; visibleCount: int) =
  if state.processes.len == 0:
    state.selectedIndex = 0
    state.firstVisible = 0
    return

  let visible = max(1, visibleCount)
  state.selectedIndex = clamp(state.selectedIndex, 0, state.processes.high)
  state.firstVisible = clamp(state.firstVisible, 0,
    max(0, state.processes.len - visible))
  if state.selectedIndex < state.firstVisible:
    state.firstVisible = state.selectedIndex
  elif state.selectedIndex >= state.firstVisible + visible:
    state.firstVisible = state.selectedIndex - visible + 1

proc ensureUiVisible*(state: var UiState; visibleCount: int) =
  state.ensureVisible(visibleCount)

proc setSort*(state: var UiState; sortType: SortType; visibleCount: int) =
  let selectedPid = state.currentProcessId()
  state.sortType = sortType
  sortProcesses(state.processes, state.sortType, state.sortOrder)
  if selectedPid != 0:
    for i, process in state.processes:
      if process.id == selectedPid:
        state.selectedIndex = i
        break
  state.ensureVisible(visibleCount)

proc applyFilter(state: var UiState; pattern: string; visibleCount: int) =
  let selectedPid = if state.followProcess: state.followPid
                    else: state.currentProcessId()
  let lowerPattern = unicode.toLower(pattern)
  state.processes.setLen(0)
  for process in state.allProcesses:
    if lowerPattern.len == 0 or
        unicode.toLower(process.exeName).contains(lowerPattern):
      state.processes.add(process)

  sortProcesses(state.processes, state.sortType, state.sortOrder)
  state.runningCount = state.allRunningCount
  if lowerPattern.len > 0:
    state.runningCount = 0
    for process in state.processes:
      if process.percentProcessorTime >= 0.01:
        inc state.runningCount

  var foundSelected = selectedPid == 0
  if selectedPid != 0:
    for i, process in state.processes:
      if process.id == selectedPid:
        state.selectedIndex = i
        foundSelected = true
        break
  if state.followProcess and not foundSelected and
      state.inputMode != imFilter:
    state.followProcess = false
  state.ensureVisible(visibleCount)

proc setProcesses*(state: var UiState; snapshot: ProcessSnapshot;
                   visibleCount: int) =
  state.allProcesses = snapshot.processes
  state.allRunningCount = snapshot.runningCount
  state.cpuUsage = snapshot.cpuUsage
  let pattern = if state.inputMode == imFilter: state.inputText
                else: state.filterText
  state.applyFilter(pattern, visibleCount)

proc toggleTag(state: var UiState; pid: uint32) =
  for i, taggedPid in state.tagged:
    if taggedPid == pid:
      state.tagged.delete(i)
      return
  state.tagged.add(pid)

proc scroll(state: var UiState; direction: int; nowMs: uint64;
            visibleCount: int) =
  state.followProcess = false
  if state.processes.len == 0:
    return

  if state.scrollKey != direction:
    state.scrollKey = direction
    state.scrollStartedAt = nowMs
    state.lastScrollAt = nowMs
  elif nowMs - state.scrollStartedAt < 500 or
      nowMs - state.lastScrollAt < 20:
    return
  else:
    state.lastScrollAt = nowMs

  let visible = max(1, visibleCount)
  case direction
  of VkUp:
    dec state.selectedIndex
  of VkDown:
    inc state.selectedIndex
  of VkPrior:
    state.selectedIndex -= visible
  of VkNext:
    state.selectedIndex += visible
  else:
    return
  state.ensureVisible(visible)

proc endInput(state: var UiState) =
  state.inputMode = imNormal
  state.inputText.setLen(0)
  state.message.setLen(0)
  state.messageError = false

proc removeLastRune(text: var string) =
  if text.len == 0:
    return
  var index = text.high
  while index > 0 and (ord(text[index]) and 0xC0) == 0x80:
    dec index
  text.setLen(index)

proc handleFilterLine(state: var UiState; key: Key;
                      visibleCount: int): InputAction =
  case key.vk
  of VkEscape:
    let pattern = state.filterText
    state.endInput()
    state.applyFilter(pattern, visibleCount)
  of VkReturn, VkF4:
    let pattern = state.inputText
    state.filterText = pattern
    state.endInput()
    state.applyFilter(pattern, visibleCount)
  of VkBack:
    state.inputText.removeLastRune()
    state.applyFilter(state.inputText, visibleCount)
  else:
    if not key.ctrl and key.ch != Rune(0) and
        state.inputText.runeLen < 1024:
      state.inputText.add($key.ch)
      state.applyFilter(state.inputText, visibleCount)

proc handleInputLine(state: var UiState; key: Key;
                     visibleCount: int): InputAction =
  if state.inputMode == imFilter:
    return state.handleFilterLine(key, visibleCount)
  if key.vk == VkEscape:
    state.endInput()
  elif key.vk == VkUp:
    discard state.history.previous(state.inputText)
  elif key.vk == VkDown:
    discard state.history.next(state.inputText)
  elif key.vk == VkReturn:
    state.submittedText = state.inputText
    state.history.recordInput(state.inputText)
    result = if state.inputMode == imSearch: iaSubmitSearch
             else: iaSubmitCommand
    state.endInput()
  elif key.vk == VkBack:
    state.inputText.removeLastRune()
    if state.inputText.len == 0:
      state.endInput()
  elif key.ch != Rune(0) and state.inputText.runeLen < 1024:
    state.inputText.add($key.ch)

proc applySearchResult(state: var UiState; searchResult: SearchResult;
                       visibleCount: int) =
  if searchResult.found:
    state.followProcess = false
    state.selectedIndex = searchResult.index
    state.ensureVisible(visibleCount)
  if searchResult.message.len > 0:
    state.message = searchResult.message
    state.messageError = searchResult.messageError
  elif searchResult.found:
    state.message.setLen(0)
    state.messageError = false

proc startSearch*(state: var UiState; pattern: string; visibleCount: int) =
  state.search.startSearch(pattern)
  if state.search.active:
    state.applySearchResult(findSearchMatch(state.search, state.processes,
      state.selectedIndex, sdNext), visibleCount)
  else:
    state.message.setLen(0)
    state.messageError = false

proc moveSearch*(state: var UiState; direction: SearchDirection;
                 visibleCount: int) =
  state.applySearchResult(findSearchMatch(state.search, state.processes,
    state.selectedIndex, direction), visibleCount)

proc handleKey*(state: var UiState; key: Key; visibleCount: int;
                nowMs: uint64): InputAction =
  if not key.keyDown:
    if key.vk == state.scrollKey:
      state.scrollKey = 0
    return iaNone

  if state.inputMode != imNormal:
    return state.handleInputLine(key, visibleCount)

  if key.vk == VkF4:
    state.inputMode = imFilter
    state.inputText = state.filterText
    state.message.setLen(0)
    state.messageError = false
    return iaNone

  if key.vk in [VkUp, VkDown, VkPrior, VkNext]:
    state.scroll(key.vk, nowMs, visibleCount)
    return iaNone

  if key.vk == VkSpace:
    let pid = state.currentProcessId()
    if pid != 0:
      state.toggleTag(pid)
      state.scroll(VkDown, nowMs, visibleCount)
    return iaNone

  if key.ctrl and key.vk in [VkLeft, VkRight]:
    let sortCount = ord(stProcess) + 1
    let current = ord(state.sortType)
    let next =
      if state.sortType == stTree:
        if key.vk == VkLeft: sortCount - 1 else: 0
      elif key.vk == VkLeft:
        (current + sortCount - 1) mod sortCount
      else:
        (current + 1) mod sortCount
    state.setSort(SortType(next), visibleCount)
    return iaNone

  case ord(key.ch):
  of ord('q'):
    return iaQuit
  of ord('n'):
    return iaSearchNext
  of ord('N'):
    return iaSearchPrevious
  of ord('g'):
    state.followProcess = false
    state.selectedIndex = 0
    state.firstVisible = 0
  of ord('G'):
    state.followProcess = false
    if state.processes.len > 0:
      state.selectedIndex = state.processes.high
    state.ensureVisible(visibleCount)
  of ord('I'):
    state.sortOrder =
      if state.sortOrder == soAscending: soDescending else: soAscending
    state.setSort(state.sortType, visibleCount)
  of ord('F'):
    let pid = state.currentProcessId()
    if pid != 0:
      state.followProcess = true
      state.followPid = pid
  of ord('U'):
    state.tagged.setLen(0)
  of ord('K'):
    if state.tagged.len > 0:
      return iaKillTagged
  of ord('M'):
    state.setSort(stUsedMemory, visibleCount)
  of ord('P'):
    state.setSort(stProcessorTime, visibleCount)
  of ord(':'):
    state.inputMode = imCommand
    state.inputText = ":"
    state.message.setLen(0)
    state.history.beginInput()
  of ord('/'):
    state.inputMode = imSearch
    state.inputText = "/"
    state.message.setLen(0)
    state.history.beginInput()
  else:
    discard

  if key.vk == VkF10:
    return iaQuit
  iaNone
