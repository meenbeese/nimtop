import std/[math, strutils]
import types, util

const ProcessTableHeader* =
  "     ID       USER  PRI   CPU%          MEM  THRD       DISK         TIME  PROCESS"

func formatCpuPercent(value: float64): string =
  let number = formatFloat(value, ffDecimal, 1)
  let padding = max(0, 4 - number.len)
  repeat('0', padding) & number & "%"

func formatDiskRate(value: uint64): string =
  let megabytesPerSecond =
    ceil(float64(value) / 1_000_000.0 * 10.0) / 10.0
  " " & align(formatFloat(megabytesPerSecond, ffDecimal, 1), 3) & " MB/s"

func formatProcessRow*(process: Process; treeMode = false): string =
  let treePrefix =
    if treeMode and process.treeDepth > 0:
      repeat("|  ", process.treeDepth - 1) & "`- "
    else:
      ""
  "\n" & align($process.id, 7) & "  " &
    align(process.userName, 9) & "  " &
    align($process.basePriority, 3) & "  " &
    formatCpuPercent(process.percentProcessorTime) & "  " &
    formatMemoryString(process.usedMemory) & "  " &
    align($process.threadCount, 4) & "  " &
    formatDiskRate(process.diskUsage) & "  " &
    formatTimeString(process.upTime) & "  " &
    treePrefix & process.exeName

func formatProcessTable*(processes: openArray[Process];
                         treeMode = false): string =
  result = ProcessTableHeader
  for process in processes:
    result.add(formatProcessRow(process, treeMode))
  result.add('\n')
