import std/[posix, unittest]
import ntop/[platform, types]

suite "macOS platform backend":
  test "acquires the current process with filtered process data":
    let pid = uint32(getpid())
    let filters = Filters(filterByPid: true, pidList: @[pid])
    let snapshot = acquireProcessList(0, filters)
    check snapshot.processes.len == 1
    check snapshot.processes[0].id == pid
    check snapshot.processes[0].exeName.len > 0
    check snapshot.processes[0].usedMemory > 0
    check snapshot.processes[0].threadCount > 0

  test "reads host name, CPU count, and memory":
    let info = initSystemInfo()
    check info.computerName.len > 0
    check info.cpuCoreCount > 0
    check info.totalMemoryBytes > 0
    check info.availableMemoryBytes <= info.totalMemoryBytes
