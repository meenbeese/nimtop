import std/[sequtils, unittest]
import ntop/[sorting, types]

func process(id, parentPid: uint32; name: string; memory: uint64): Process =
  Process(id: id, parentPid: parentPid, exeName: name, usedMemory: memory)

suite "process sorting":
  test "sorts numeric and case-insensitive columns in either direction":
    var processes = @[
      process(3, 0, "zeta.exe", 300),
      process(1, 0, "Alpha.exe", 100),
      process(2, 0, "beta.exe", 200)
    ]
    sortProcesses(processes, stUsedMemory, soAscending)
    check processes.mapIt(it.id) == @[1'u32, 2'u32, 3'u32]
    sortProcesses(processes, stProcess, soDescending)
    check processes.mapIt(it.exeName) == @["zeta.exe", "beta.exe", "Alpha.exe"]

  test "sorts every process column":
    let columns = [
      stId, stUserName, stPriority, stProcessorTime, stUsedMemory,
      stThreadCount, stDiskUsage, stUpTime, stProcess
    ]
    for column in columns:
      var processes = @[
        Process(id: 3, userName: "z", basePriority: 1,
          percentProcessorTime: 0.3, usedMemory: 300, threadCount: 3,
          diskUsage: 30, upTime: 300, exeName: "z.exe"),
        Process(id: 1, userName: "a", basePriority: 3,
          percentProcessorTime: 0.1, usedMemory: 100, threadCount: 1,
          diskUsage: 10, upTime: 100, exeName: "a.exe"),
        Process(id: 2, userName: "m", basePriority: 2,
          percentProcessorTime: 0.2, usedMemory: 200, threadCount: 2,
          diskUsage: 20, upTime: 200, exeName: "m.exe")
      ]
      sortProcesses(processes, column, soAscending)
      let expectedIds =
        if column == stPriority: @[3'u32, 2'u32, 1'u32]
        else: @[1'u32, 2'u32, 3'u32]
      check processes.mapIt(it.id) == expectedIds

  test "flattens parent child trees and promotes missing parents":
    var processes = @[
      process(10, 0, "root.exe", 0),
      process(11, 10, "child.exe", 0),
      process(12, 11, "grandchild.exe", 0),
      process(20, 999, "orphan.exe", 0)
    ]
    sortProcesses(processes, stTree)
    check processes.mapIt(it.id) == @[10'u32, 11'u32, 12'u32, 20'u32]
    check processes.mapIt(it.treeDepth) == @[0, 1, 2, 0]

  test "emits a cyclic parent group once":
    var processes = @[
      process(1, 2, "one.exe", 0),
      process(2, 1, "two.exe", 0)
    ]
    sortProcesses(processes, stTree)
    check processes.len == 2
    check processes.mapIt(it.id) == @[1'u32, 2'u32]
