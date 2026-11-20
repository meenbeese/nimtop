import std/[posix, strutils, unittest]
import ntop/[platform, types]

suite "Linux platform backend":
  test "resolves the current user name":
    check currentUserName().len > 0

  test "parses process names containing closing parentheses":
    let fields = [
      "R", "1", "1", "1", "0", "-1", "0", "10", "0", "2", "3",
      "4", "5", "0", "0", "20", "0", "3", "0", "900", "1234", "5"
    ]
    let parsed = parseLinuxProcessStat(
      "4242 (worker (with ) marks)) " & fields.join(" "))
    check parsed.valid
    check parsed.id == 4242
    check parsed.command == "worker (with ) marks)"
    check parsed.state == 'R'
    check parsed.parentPid == 1
    check parsed.userTicks == 4
    check parsed.systemTicks == 5
    check parsed.priority == 20
    check parsed.threadCount == 3
    check parsed.startTicks == 900

  test "rejects malformed process stat records":
    check not parseLinuxProcessStat("not a proc stat").valid
    check not parseLinuxProcessStat("42 (short) R 1 2").valid

  test "acquires the current process with filtered procfs data":
    let pid = uint32(getpid())
    var filters = Filters(filterByPid: true, pidList: @[pid])
    let snapshot = acquireProcessList(0, filters)
    check snapshot.processes.len == 1
    check snapshot.processes[0].id == pid
    check snapshot.processes[0].exeName.len > 0
    check snapshot.processes[0].usedMemory > 0
    check snapshot.processes[0].userIdValid
    check snapshot.processes[0].userId == uint32(getuid())

    let uidFilters = Filters(filterByPid: true, pidList: @[pid],
      filterByUserId: true, userId: uint32(getuid()))
    let uidSnapshot = acquireProcessList(0, uidFilters)
    check uidSnapshot.processes.len == 1
    check uidSnapshot.processes[0].id == pid

  test "reads host name, CPU count, and memory from procfs":
    let info = initSystemInfo()
    check info.computerName.len > 0
    check info.cpuCoreCount > 0
    check info.totalMemoryBytes > 0
