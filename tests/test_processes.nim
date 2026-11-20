when defined(windows):
  import std/unittest
  import winim
  import ntop/[platform, types]

  suite "live Windows process acquisition":
    test "snapshot includes the current process with enriched data":
      let snapshot = acquireProcessList(0)
      let currentPid = uint32(GetCurrentProcessId())
      var foundCurrentProcess = false
      for process in snapshot.processes:
        check process.id != 0
        if process.id == currentPid:
          foundCurrentProcess = true
          check process.exeName.len > 0
          check process.userName.len > 0
          check process.usedMemory > 0
          check process.upTime > 0
      check foundCurrentProcess

    test "system process remains visible when details are restricted":
      let snapshot = acquireProcessList(0,
        Filters(filterByPid: true, pidList: @[4'u32]))
      check snapshot.processes.len == 1
      check snapshot.processes[0].id == 4
      check snapshot.processes[0].exeName.len > 0

    test "system information contains host and memory values":
      let info = initSystemInfo()
      check info.cpuCoreCount > 0
      check info.computerName.len > 0
      check info.totalMemoryBytes > 0
