import std/[unicode, unittest]
import ntop/[input, search, types]

func sampleProcesses(): ProcessSnapshot =
  ProcessSnapshot(processes: @[
    Process(id: 1, exeName: "one.exe"),
    Process(id: 2, exeName: "two.exe"),
    Process(id: 3, exeName: "three.exe")
  ])

func key(vk: int; ch = Rune(0); ctrl = false; down = true): Key =
  Key(vk: vk, ch: ch, ctrl: ctrl, keyDown: down, repeatCount: 1)

suite "interactive input state":
  test "scroll, page, top and bottom keep selection visible":
    var state = initUiState(sortOrder = soAscending)
    state.setProcesses(sampleProcesses(), 2)
    discard state.handleKey(key(0x28), 2, 1000)
    check state.selectedIndex == 1
    discard state.handleKey(key(0x22), 2, 1100)
    check state.selectedIndex == 2
    discard state.handleKey(key(0x47, Rune(ord('G'))), 2, 1200)
    check state.selectedIndex == 2
    check state.firstVisible == 1
    discard state.handleKey(key(0, Rune(ord('g'))), 2, 1300)
    check state.selectedIndex == 0
    check state.firstVisible == 0

  test "scroll repeat waits before repeating":
    var state = initUiState(sortOrder = soAscending)
    state.setProcesses(sampleProcesses(), 3)
    discard state.handleKey(key(0x28), 3, 1000)
    discard state.handleKey(key(0x28), 3, 1400)
    check state.selectedIndex == 1
    discard state.handleKey(key(0x28), 3, 1500)
    check state.selectedIndex == 2

  test "tagging, sort, follow, kill request and quit":
    var state = initUiState(sortOrder = soAscending)
    state.setProcesses(sampleProcesses(), 3)
    discard state.handleKey(key(0x20), 3, 100)
    check state.tagged == @[1'u32]
    check state.selectedIndex == 1
    discard state.handleKey(key(0, Rune(ord('F'))), 3, 200)
    check state.followProcess
    check state.followPid == 2
    discard state.handleKey(key(0, Rune(ord('M'))), 3, 300)
    check state.sortType == stUsedMemory
    state.tagged = @[2'u32]
    check state.handleKey(key(0, Rune(ord('K'))), 3, 400) == iaKillTagged
    check state.handleKey(key(0, Rune(ord('q'))), 3, 500) == iaQuit

  test "command and search inputs accept UTF-8 and cancel":
    var state = initUiState()
    discard state.handleKey(key(0, Rune(ord(':'))), 3, 100)
    discard state.handleKey(key(0, Rune(0x00E9)), 3, 200)
    check state.inputText == ":é"
    discard state.handleKey(key(0x1B), 3, 300)
    check state.inputMode == imNormal
    check state.inputText.len == 0

  test "search input submits and n/N navigate matches":
    var state = initUiState(sortOrder = soAscending)
    state.setProcesses(ProcessSnapshot(processes: @[
      Process(id: 1, exeName: "one.exe"),
      Process(id: 2, exeName: "two.exe"),
      Process(id: 3, exeName: "TWO-copy.exe")
    ]), 3)
    discard state.handleKey(key(0, Rune(ord('/'))), 3, 100)
    discard state.handleKey(key(0, Rune(ord('t'))), 3, 200)
    check state.handleKey(key(0x0D), 3, 300) == iaSubmitSearch
    check state.submittedText == "/t"
    state.startSearch("t", 3)
    check state.processes[state.selectedIndex].id == 2
    check state.handleKey(key(0, Rune(ord('n'))), 3, 400) == iaSearchNext
    state.moveSearch(sdNext, 3)
    check state.processes[state.selectedIndex].id == 3
    check state.handleKey(key(0, Rune(ord('N'))), 3, 500) ==
      iaSearchPrevious
    state.moveSearch(sdPrevious, 3)
    check state.processes[state.selectedIndex].id == 2

  test "command input submits the line for Vi dispatch":
    var state = initUiState()
    discard state.handleKey(key(0, Rune(ord(':'))), 3, 100)
    discard state.handleKey(key(0, Rune(ord('q'))), 3, 200)
    check state.handleKey(key(0x0D), 3, 300) == iaSubmitCommand
    check state.submittedText == ":q"
    check state.inputMode == imNormal

  test "sort changes preserve the selected process":
    var state = initUiState(sortOrder = soAscending)
    state.setProcesses(sampleProcesses(), 3)
    discard state.handleKey(key(0x28), 3, 100)
    let selectedPid = state.processes[state.selectedIndex].id
    discard state.handleKey(key(0x27, ctrl = true), 3, 200)
    check state.processes[state.selectedIndex].id == selectedPid
