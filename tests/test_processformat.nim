import std/[strutils, unittest]
import ntop/[processformat, types]

suite "headless process formatting":
  test "prints the process columns with C-compatible widths":
    let process = Process(
      id: 42, userName: "bob", basePriority: 8,
      percentProcessorTime: 1.2, usedMemory: 12_300_000,
      threadCount: 5, upTime: 1000, exeName: "worker.exe"
    )
    let row = formatProcessRow(process)
    check ProcessTableHeader.endsWith("PROCESS")
    check row.startsWith("\n     42  ")
    check row.contains("01.2%")
    check row.contains("12.3 MB")
    check row.endsWith("worker.exe")

  test "tree rows include depth prefixes":
    let process = Process(id: 5, treeDepth: 3, exeName: "child.exe")
    check formatProcessRow(process, treeMode = true).endsWith("|  `- child.exe")

  test "headless table output matches the C byte layout":
    let process = Process(
      id: 42, userName: "bob", basePriority: 8,
      percentProcessorTime: 1.2, usedMemory: 12_300_000,
      threadCount: 5, upTime: 1000, diskUsage: 1_234_567,
      exeName: "worker.exe"
    )
    let expected = ProcessTableHeader &
      "\n     42  " & "      bob" & "  " & "  8" & "  " & "01.2%" &
      "  " & "    12.3 MB" & "  " & "   5" & "  " &
      " 1.3 MB/s" & "  " & "00:00:00:01" & "  worker.exe\n"
    check formatProcessTable([process]) == expected
    check formatProcessTable([]) == ProcessTableHeader & "\n"
