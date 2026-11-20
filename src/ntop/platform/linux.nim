import std/[monotimes, os, osproc, strutils, tables]
import std/posix as posix
import ntop/filters
import ntop/types as ntopTypes
import ntop/platform/posixconsole

export posixconsole

type
  LinuxProcessStat* = object
    valid*: bool
    id*: uint32
    command*: string
    state*: char
    parentPid*: uint32
    userTicks*: uint64
    systemTicks*: uint64
    priority*: int32
    threadCount*: uint32
    startTicks*: uint64

  LinuxMemoryInfo = object
    totalBytes: uint64
    availableBytes: uint64
    swapTotalBytes: uint64
    swapAvailableBytes: uint64

  SystemCpuTimes = object
    total: uint64
    idle: uint64

  ProcessSample = object
    process: ntopTypes.Process
    state: char
    userTicks: uint64
    systemTicks: uint64
    ioBytes: uint64

var
  shutdownRequestedFlag {.volatile.}: cint

proc posixError(operation: string): ref OSError =
  newException(OSError,
    operation & " failed: " & $posix.strerror(posix.errno))

proc parseLinuxProcessStat*(text: string): LinuxProcessStat =
  let openParen = text.find('(')
  let closeParen = text.rfind(')')
  if openParen <= 0 or closeParen <= openParen:
    return
  try:
    let pid = parseBiggestUInt(text[0 ..< openParen].strip())
    if pid == 0 or pid > uint64(high(uint32)):
      return
    let tail = strutils.splitWhitespace(text[closeParen + 1 .. ^1])
    if tail.len < 20 or tail[0].len != 1:
      return
    let parentPid = parseBiggestUInt(tail[1])
    let priority = parseInt(tail[15])
    let threadCount = parseBiggestUInt(tail[17])
    if parentPid > uint64(high(uint32)) or
        priority < int(low(int32)) or priority > int(high(int32)) or
        threadCount > uint64(high(uint32)):
      return
    result = LinuxProcessStat(
      valid: true,
      id: uint32(pid),
      command: text[openParen + 1 ..< closeParen],
      state: tail[0][0],
      parentPid: uint32(parentPid),
      userTicks: parseBiggestUInt(tail[11]),
      systemTicks: parseBiggestUInt(tail[12]),
      priority: int32(priority),
      threadCount: uint32(threadCount),
      startTicks: parseBiggestUInt(tail[19])
    )
  except ValueError:
    result = default(LinuxProcessStat)

proc optionalFile(path: string): string =
  try:
    readFile(path)
  except IOError:
    ""

proc readUid(statusText: string): tuple[found: bool, uid: uint32] =
  for line in statusText.splitLines():
    if line.startsWith("Uid:"):
      let parts = strutils.splitWhitespace(line)
      if parts.len >= 2:
        try:
          let uid = parseBiggestUInt(parts[1])
          if uid <= uint64(high(uint32)):
            return (true, uint32(uid))
        except ValueError:
          return

proc readUserNames(): Table[uint32, string] =
  result = initTable[uint32, string]()
  for line in optionalFile("/etc/passwd").splitLines():
    let fields = line.split(':')
    if fields.len < 3:
      continue
    try:
      let uid = parseBiggestUInt(fields[2])
      if uid <= uint64(high(uint32)):
        result[uint32(uid)] = fields[0]
    except ValueError:
      discard

proc processUserName(pid: uint32; names: Table[uint32, string]): string =
  let uid = readUid(optionalFile("/proc/" & $pid & "/status"))
  if not uid.found:
    return "?"
  names.getOrDefault(uid.uid, $uid.uid)

proc processMemoryBytes(pid: uint32; pageSize: uint64): uint64 =
  let fields = strutils.splitWhitespace(
    optionalFile("/proc/" & $pid & "/statm"))
  if fields.len < 2:
    return
  try:
    result = parseBiggestUInt(fields[1]) * pageSize
  except ValueError:
    discard

proc processIoBytes(pid: uint32): uint64 =
  var readBytes, writeBytes: uint64
  for line in optionalFile("/proc/" & $pid & "/io").splitLines():
    let fields = strutils.splitWhitespace(line)
    if fields.len < 2:
      continue
    try:
      if fields[0] == "read_bytes:":
        readBytes = parseBiggestUInt(fields[1])
      elif fields[0] == "write_bytes:":
        writeBytes = parseBiggestUInt(fields[1])
    except ValueError:
      discard
  readBytes + writeBytes

proc readProcessSample(pid: uint32; names: Table[uint32, string];
                       pageSize: uint64; sample: var ProcessSample): bool =
  let statText = optionalFile("/proc/" & $pid & "/stat")
  let stat = parseLinuxProcessStat(statText)
  if not stat.valid or stat.id != pid:
    return false
  var processName = optionalFile("/proc/" & $pid & "/comm").strip()
  if processName.len == 0:
    processName = stat.command
  let ioBytes = processIoBytes(pid)
  sample = ProcessSample(
    process: ntopTypes.Process(
      id: pid,
      userName: processUserName(pid, names),
      basePriority: stat.priority,
      usedMemory: processMemoryBytes(pid, pageSize),
      threadCount: stat.threadCount,
      exeName: processName,
      parentPid: stat.parentPid,
      diskOpsPrev: ioBytes,
      diskOps: ioBytes
    ),
    state: stat.state,
    userTicks: stat.userTicks,
    systemTicks: stat.systemTicks,
    ioBytes: ioBytes
  )
  true

proc readSystemCpuTimes(): SystemCpuTimes =
  for line in readFile("/proc/stat").splitLines():
    if not line.startsWith("cpu "):
      continue
    let fields = strutils.splitWhitespace(line)
    if fields.len < 5:
      break
    try:
      for i in 1 .. min(8, fields.high):
        result.total += parseBiggestUInt(fields[i])
      result.idle = parseBiggestUInt(fields[4])
      if fields.len > 5:
        result.idle += parseBiggestUInt(fields[5])
      return
    except ValueError:
      break
  raise newException(OSError, "Could not parse aggregate CPU counters in /proc/stat")

proc readUptimeMs(): uint64 =
  let fields = strutils.splitWhitespace(readFile("/proc/uptime"))
  if fields.len == 0:
    raise newException(OSError, "Could not parse system uptime in /proc/uptime")
  try:
    uint64(parseFloat(fields[0]) * 1000.0)
  except ValueError:
    raise newException(OSError, "Could not parse system uptime in /proc/uptime")

proc readLinuxMemoryInfo(): LinuxMemoryInfo =
  var values = initTable[string, uint64]()
  for line in readFile("/proc/meminfo").splitLines():
    let separator = line.find(':')
    if separator < 0:
      continue
    let fields = strutils.splitWhitespace(line[separator + 1 .. ^1])
    if fields.len == 0:
      continue
    try:
      values[line[0 ..< separator]] = parseBiggestUInt(fields[0]) * 1024
    except ValueError:
      discard

  if not values.hasKey("MemTotal"):
    raise newException(OSError, "Could not parse MemTotal in /proc/meminfo")
  result.totalBytes = values["MemTotal"]
  result.availableBytes = values.getOrDefault("MemAvailable")
  if result.availableBytes == 0:
    result.availableBytes = values.getOrDefault("MemFree") +
      values.getOrDefault("Buffers") + values.getOrDefault("Cached")
  result.swapTotalBytes = values.getOrDefault("SwapTotal")
  result.swapAvailableBytes = values.getOrDefault("SwapFree")

proc initSystemInfo*(): ntopTypes.HostInfo =
  let memory = readLinuxMemoryInfo()
  result.totalMemoryBytes = memory.totalBytes
  result.availableMemoryBytes = memory.availableBytes
  result.totalPageFileBytes = memory.swapTotalBytes
  result.availablePageFileBytes = memory.swapAvailableBytes
  result.upTimeMs = readUptimeMs()
  result.computerName = optionalFile("/etc/hostname").strip()
  if result.computerName.len == 0:
    result.computerName = getEnv("HOSTNAME", "localhost")

  for line in readFile("/proc/cpuinfo").splitLines():
    let separator = line.find(':')
    if separator < 0:
      continue
    let key = line[0 ..< separator].strip().toLowerAscii()
    let value = line[separator + 1 .. ^1].strip()
    case key
    of "model name", "hardware":
      if result.cpuName.len == 0:
        result.cpuName = value
    of "cpu mhz":
      if result.cpuFrequencyMHz == 0:
        try:
          result.cpuFrequencyMHz = parseFloat(value)
        except ValueError:
          discard
    of "processor":
      inc result.cpuCoreCount
    else:
      discard
  if result.cpuName.len == 0:
    result.cpuName = "Unknown CPU"
  if result.cpuCoreCount == 0:
    result.cpuCoreCount = 1

proc pollSystemInfo*(info: var ntopTypes.HostInfo) =
  let memory = readLinuxMemoryInfo()
  info.totalMemoryBytes = memory.totalBytes
  info.availableMemoryBytes = memory.availableBytes
  info.totalPageFileBytes = memory.swapTotalBytes
  info.availablePageFileBytes = memory.swapAvailableBytes
  info.upTimeMs = readUptimeMs()

proc acquireProcessList*(updateTimeMs: uint64;
                         filters: ntopTypes.Filters = ntopTypes.Filters()):
                         ntopTypes.ProcessSnapshot =
  let pageSizeValue = posix.sysconf(posix.SC_PAGESIZE)
  let clockTicksValue = posix.sysconf(posix.SC_CLK_TCK)
  if pageSizeValue <= 0 or clockTicksValue <= 0:
    raise newException(OSError, "Could not read Linux page size or clock tick rate")
  let pageSize = uint64(pageSizeValue)
  let clockTicks = uint64(clockTicksValue)
  let previousSystemCpu = readSystemCpuTimes()
  let userNames = readUserNames()

  var samples: seq[ProcessSample]
  for kind, path in walkDir("/proc"):
    if kind != pcDir:
      continue
    let processIdText = extractFilename(path)
    var parsedPid: uint64
    try:
      parsedPid = parseBiggestUInt(processIdText)
    except ValueError:
      continue
    if parsedPid == 0 or parsedPid > uint64(high(uint32)):
      continue
    var sample: ProcessSample
    if readProcessSample(uint32(parsedPid), userNames, pageSize, sample) and
        sample.process.passesFilters(filters):
      samples.add(sample)

  if updateTimeMs > 0:
    os.sleep(int(min(updateTimeMs, uint64(high(int)))))

  let currentSystemCpu = readSystemCpuTimes()
  let systemCpuDelta =
    if currentSystemCpu.total >= previousSystemCpu.total:
      currentSystemCpu.total - previousSystemCpu.total
    else:
      0'u64
  let systemIdleDelta =
    if currentSystemCpu.idle >= previousSystemCpu.idle:
      currentSystemCpu.idle - previousSystemCpu.idle
    else:
      0'u64
  if systemCpuDelta > 0:
    result.cpuUsage = float64(systemCpuDelta -
      min(systemIdleDelta, systemCpuDelta)) / float64(systemCpuDelta)

  let uptimeMs = readUptimeMs()
  result.processes = newSeqOfCap[ntopTypes.Process](samples.len)
  for sample in samples.mitems:
    var process = sample.process
    var currentStat: LinuxProcessStat
    let currentStatText = optionalFile("/proc/" & $process.id & "/stat")
    currentStat = parseLinuxProcessStat(currentStatText)
    if currentStat.valid and currentStat.id == process.id:
      let previousProcessTicks = sample.userTicks + sample.systemTicks
      let currentProcessTicks = currentStat.userTicks + currentStat.systemTicks
      if currentProcessTicks >= previousProcessTicks:
        let processDelta = currentProcessTicks - previousProcessTicks
        if systemCpuDelta > 0:
          process.percentProcessorTime =
            100.0 * float64(processDelta) / float64(systemCpuDelta)
          if process.percentProcessorTime >= 0.01:
            inc result.runningCount
      let processStartMs = currentStat.startTicks * 1000 div clockTicks
      if uptimeMs >= processStartMs:
        process.upTime = uptimeMs - processStartMs
      process.diskOps = processIoBytes(process.id)
      if updateTimeMs > 0 and process.diskOps >= sample.ioBytes:
        process.diskUsage =
          (process.diskOps - sample.ioBytes) * 1000 div updateTimeMs
    result.processes.add(process)

proc terminateProcess*(pid: uint32): tuple[success, opened: bool,
                                           error: string] =
  if posix.kill(posix.Pid(pid), 0) == -1:
    return (false, false, $posix.strerror(posix.errno))
  if posix.kill(posix.Pid(pid), posix.SIGKILL) == -1:
    return (false, true, $posix.strerror(posix.errno))
  (true, true, "")

proc startCommand*(command: string; console: var Console): string =
  console.suspendConsole()
  try:
    var child = osproc.startProcess("/bin/sh", args = ["-c", command],
      options = {poParentStreams})
    defer: osproc.close(child)
    discard osproc.waitForExit(child)
  except OSError as error:
    result = "Failed to create process (" & error.msg & ")"
  finally:
    console.resumeConsole()

proc monotonicTimeMs*(): uint64 =
  uint64(getMonoTime().ticks div 1_000_000)

proc linuxSignalHandler(signalNumber: cint) {.noconv.} =
  discard signalNumber
  shutdownRequestedFlag = 1

proc registerConsoleControlHandler*(callback: ConsoleShutdownCallback) =
  shutdownRequestedFlag = 0
  if posix.signal(posix.SIGINT, linuxSignalHandler) == posix.SIG_ERR:
    raise posixError("signal(SIGINT)")
  if posix.signal(posix.SIGTERM, linuxSignalHandler) == posix.SIG_ERR:
    raise posixError("signal(SIGTERM)")

proc shutdownRequested*(): bool =
  shutdownRequestedFlag != 0
