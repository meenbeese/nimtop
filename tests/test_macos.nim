import std/[posix, unittest]
import ntop/[platform, types]

suite "macOS platform backend":
  test "resolves the current user name":
    check currentUserName().len > 0

  test "acquires the current process with filtered process data":
    let pid = uint32(getpid())
    let filters = Filters(filterByPid: true, pidList: @[pid])
    let snapshot = acquireProcessList(0, filters)
    check snapshot.processes.len == 1
    check snapshot.processes[0].id == pid
    check snapshot.processes[0].exeName.len > 0
    check snapshot.processes[0].usedMemory > 0
    check snapshot.processes[0].threadCount > 0
    check snapshot.processes[0].userIdValid
    check snapshot.processes[0].userId == uint32(getuid())

    let uidFilters = Filters(filterByPid: true, pidList: @[pid],
      filterByUserId: true, userId: uint32(getuid()))
    let uidSnapshot = acquireProcessList(0, uidFilters)
    check uidSnapshot.processes.len == 1
    check uidSnapshot.processes[0].id == pid

  test "reads host name, CPU count, and memory":
    let info = initSystemInfo()
    check info.computerName.len > 0
    check info.cpuCoreCount > 0
    check info.totalMemoryBytes > 0
    check info.availableMemoryBytes <= info.totalMemoryBytes
