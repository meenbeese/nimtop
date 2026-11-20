import std/unittest
import ntop/[config, input, render, types]

suite "screen rendering":
  test "renders narrow, standard, and wide terminal dimensions":
    var state = initUiState()
    state.setProcesses(ProcessSnapshot(processes: @[
      Process(id: 1, userName: "test", exeName: "process.exe")
    ]), 32)
    let host = HostInfo(computerName: "test-host")
    let config = defaultConfig()

    for (width, height) in [(1, 1), (40, 10), (240, 40)]:
      var screen = initScreen(width, height, 0)
      screen.render(state, host, config)
      check screen.width == width
      check screen.height == height
