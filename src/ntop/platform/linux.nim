import std/[monotimes, os, osproc, strutils, tables, unicode]
import std/posix as posix
import posix/termios as posixTermios
import ntop/filters
import ntop/types as ntopTypes

const
  AttrForegroundBlue* = 0x0001'u16
  AttrForegroundGreen* = 0x0002'u16
  AttrForegroundRed* = 0x0004'u16
  AttrForegroundIntensity* = 0x0008'u16
  AttrForegroundWhite* =
    AttrForegroundRed or AttrForegroundGreen or AttrForegroundBlue
  AttrForegroundCyan* =
    AttrForegroundIntensity or AttrForegroundGreen or AttrForegroundBlue
  AttrBackgroundBlue* = 0x0010'u16
  AttrBackgroundGreen* = 0x0020'u16
  AttrBackgroundRed* = 0x0040'u16
  AttrBackgroundIntensity* = 0x0080'u16
  AttrBackgroundWhite* =
    AttrBackgroundRed or AttrBackgroundGreen or AttrBackgroundBlue
  AttrBackgroundCyan* =
    AttrBackgroundIntensity or AttrBackgroundGreen or AttrBackgroundBlue

  AttrDefault* = AttrForegroundWhite
  AttrMenu* = AttrForegroundWhite or AttrBackgroundBlue
  AttrHighlight* = AttrForegroundCyan or AttrBackgroundCyan
  AttrHeader* = AttrForegroundWhite or AttrBackgroundGreen
  AttrError* = AttrForegroundWhite or AttrBackgroundRed

  VkBack = 0x08
  VkReturn = 0x0D
  VkEscape = 0x1B
  VkPrior = 0x21
  VkNext = 0x22
  VkLeft = 0x25
  VkUp = 0x26
  VkRight = 0x27
  VkDown = 0x28
  VkF10 = 0x79

type
  Console* = object
    interactive*: bool
    width*: int
    height*: int
    sizeX*: int
    sizeY*: int
    savedAttributes*: uint16
    isTerminal: bool
    hasSavedTermios: bool
    suspended: bool
    restored: bool
    originalTermios: posixTermios.Termios

  ConsoleShutdownCallback* = proc() {.noconv.}

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
  currentAttributes = AttrDefault

func makeAttr*(foreground, background: uint16): uint16 {.inline.} =
  (foreground and 0x000F'u16) or (background and 0x00F0'u16)

proc posixError(operation: string): ref OSError =
  newException(OSError,
    operation & " failed: " & $posix.strerror(posix.errno))

func linuxColorIndex(mask: uint16): int =
  (if (mask and 0x0004'u16) != 0: 1 else: 0) +
  (if (mask and 0x0002'u16) != 0: 2 else: 0) +
  (if (mask and 0x0001'u16) != 0: 4 else: 0)

proc ansiColor(attribute: uint16): string =
  let foregroundMask = attribute and 0x0007'u16
  let backgroundMask = (attribute shr 4) and 0x0007'u16
  let foregroundCode =
    (if (attribute and AttrForegroundIntensity) != 0: 90 else: 30) +
    linuxColorIndex(foregroundMask)
  let backgroundCode =
    (if (attribute and AttrBackgroundIntensity) != 0: 100 else: 40) +
    linuxColorIndex(backgroundMask)
  "\x1b[" & $foregroundCode & ";" & $backgroundCode & "m"

proc isConsole*(c: Console): bool =
  c.isTerminal

proc setColor*(c: Console; attribute: uint16) =
  currentAttributes = attribute
  if c.isConsole():
    stdout.write(ansiColor(attribute))
    stdout.flushFile()

proc getColor*(c: Console): uint16 =
  currentAttributes

proc setCursorPos*(c: Console; x, y: int) =
  if c.isConsole():
    stdout.write("\x1b[" & $(max(0, y) + 1) & ";" &
      $(max(0, x) + 1) & "H")
    stdout.flushFile()

proc setCursorVisible(c: Console; visible: bool) =
  if c.isConsole():
    stdout.write(if visible: "\x1b[?25h" else: "\x1b[?25l")
    stdout.flushFile()

proc hideCursor*(c: Console) =
  c.setCursorVisible(false)

proc showCursor*(c: Console) =
  c.setCursorVisible(true)

proc setTitle*(c: Console; title: string) =
  if c.isConsole():
    stdout.write("\x1b]0;" & title & "\x07")
    stdout.flushFile()

proc refreshSize*(c: var Console): bool =
  if not c.isConsole():
    c.width = 80
    c.height = 25
    c.sizeX = c.width
    c.sizeY = c.height
    return false

  var windowSize: posixTermios.IOctl_WinSize
  if posixTermios.ioctl(posix.STDOUT_FILENO,
      posixTermios.TIOCGWINSZ, addr windowSize) == -1:
    return false

  let newWidth = max(1, int(windowSize.ws_col))
  let newHeight = max(1, int(windowSize.ws_row))
  result = newWidth != c.width or newHeight != c.height
  c.width = newWidth
  c.height = newHeight
  c.sizeX = newWidth
  c.sizeY = newHeight

proc clear*(c: Console; attribute: uint16 = AttrDefault) =
  if not c.isConsole():
    return
  c.setColor(attribute)
  stdout.write("\x1b[2J\x1b[H")
  stdout.flushFile()

proc clearRow*(c: Console; y: int; attribute: uint16 = AttrDefault) =
  if not c.isConsole() or y < 0 or y >= c.height:
    return
  c.setColor(attribute)
  c.setCursorPos(0, y)
  stdout.write("\x1b[2K")
  stdout.flushFile()

proc write*(c: Console; text: string) =
  if text.len == 0:
    return
  stdout.write(text)
  stdout.flushFile()

proc writeColor*(c: Console; text: string; attribute: uint16) =
  c.setColor(attribute)
  c.write(text)

proc writeAt*(c: Console; x, y: int; text: string; attribute: uint16) =
  if not c.isConsole():
    c.write(text)
    return
  c.setCursorPos(x, y)
  c.writeColor(text, attribute)

proc writeCentered*(c: Console; y: int; text: string; attribute: uint16) =
  if not c.isConsole():
    c.write(text)
    return
  c.writeAt(max(0, (c.width - text.runeLen) div 2), y, text, attribute)

proc flushInput*(c: Console) =
  if c.isConsole():
    discard posixTermios.tcFlush(posix.STDIN_FILENO, posixTermios.TCIFLUSH)

proc waitForInput(timeoutMs: int): bool =
  var descriptor = posix.TPollfd(
    fd: posix.STDIN_FILENO,
    events: posix.POLLIN,
    revents: 0
  )
  let timeout =
    if timeoutMs < 0: -1
    else: min(timeoutMs, int(high(cint)))
  let status = posix.poll(addr descriptor, posix.Tnfds(1), cint(timeout))
  if status < 0:
    if posix.errno == posix.EINTR:
      return false
    raise posixError("poll")
  status > 0 and (descriptor.revents and posix.POLLIN) != 0

proc readByte(value: var char): bool =
  let count = posix.read(posix.STDIN_FILENO, addr value, 1)
  if count == 1:
    return true
  if count < 0 and posix.errno != posix.EINTR:
    raise posixError("read")

proc readEscapeSequence(): string =
  while result.len < 12 and waitForInput(30):
    var value: char
    if not readByte(value):
      break
    result.add(value)

proc setKey(key: var ntopTypes.Key; value: int; control = false) =
  key.vk = value
  key.ctrl = control
  key.keyDown = true
  key.repeatCount = 1

proc readCharacter(key: var ntopTypes.Key; first: char) =
  let leading = ord(first) and 0xFF
  let expectedLength =
    if leading < 0x80: 1
    elif (leading and 0xE0) == 0xC0: 2
    elif (leading and 0xF0) == 0xE0: 3
    elif (leading and 0xF8) == 0xF0: 4
    else: 1
  var text = $first
  for _ in 1 ..< expectedLength:
    if not waitForInput(30):
      break
    var next: char
    if not readByte(next):
      break
    text.add(next)
  for rune in text.runes:
    key.ch = rune
    key.vk = int(rune)
    break
  key.keyDown = true
  key.repeatCount = 1

proc tryReadKey*(c: Console; key: var ntopTypes.Key; timeoutMs: int): bool =
  if not c.isConsole():
    raise newException(IOError, "tryReadKey requires an interactive terminal")
  if not waitForInput(timeoutMs):
    return false

  var value: char
  if not readByte(value):
    return false
  if value == '\x1b':
    let sequence = readEscapeSequence()
    case sequence
    of "[A": key.setKey(VkUp)
    of "[B": key.setKey(VkDown)
    of "[C": key.setKey(VkRight)
    of "[D": key.setKey(VkLeft)
    of "[1;5C": key.setKey(VkRight, true)
    of "[1;5D": key.setKey(VkLeft, true)
    of "[5~": key.setKey(VkPrior)
    of "[6~": key.setKey(VkNext)
    of "[21~": key.setKey(VkF10)
    else: key.setKey(VkEscape)
    return true

  case value
  of '\r', '\n':
    key.setKey(VkReturn)
  of '\x08', '\x7f':
    key.setKey(VkBack)
  else:
    key.readCharacter(value)
    if ord(value) in 1 .. 26:
      key.ctrl = true
      key.ch = Rune(ord('a') + ord(value) - 1)
      key.vk = int(key.ch)
  true

proc readKey*(c: Console): ntopTypes.Key =
  if not c.isConsole():
    raise newException(IOError, "readKey requires an interactive terminal")
  while not c.tryReadKey(result, -1):
    discard

proc setRawMode(c: var Console; enabled: bool) =
  if not c.hasSavedTermios:
    return
  if enabled:
    var raw = c.originalTermios
    raw.c_lflag = raw.c_lflag and
      not (posixTermios.ICANON or posixTermios.ECHO)
    raw.c_iflag = raw.c_iflag and not
      (posixTermios.IXON or posixTermios.ICRNL)
    raw.c_cc[int(posixTermios.VMIN)] = char(0)
    raw.c_cc[int(posixTermios.VTIME)] = char(0)
    if posixTermios.tcSetAttr(posix.STDIN_FILENO,
        posixTermios.TCSANOW, addr raw) == -1:
      raise posixError("tcsetattr")
  elif posixTermios.tcSetAttr(posix.STDIN_FILENO,
      posixTermios.TCSANOW, addr c.originalTermios) == -1:
    raise posixError("tcsetattr")

proc initConsole*(interactive = true): Console =
  result.interactive = interactive
  currentAttributes = AttrDefault
  result.isTerminal =
    posix.isatty(posix.STDIN_FILENO) != 0 and
    posix.isatty(posix.STDOUT_FILENO) != 0
  result.width = 80
  result.height = 25
  result.sizeX = result.width
  result.sizeY = result.height
  if interactive and not result.isTerminal:
    raise newException(IOError, "interactive mode requires a terminal")

  if interactive:
    if posixTermios.tcGetAttr(posix.STDIN_FILENO,
        addr result.originalTermios) == -1:
      raise posixError("tcgetattr")
    result.hasSavedTermios = true
    result.setRawMode(true)
    stdout.write("\x1b[?1049h")
    stdout.flushFile()
    discard result.refreshSize()
    result.hideCursor()

proc restore*(c: var Console) =
  if not c.interactive or c.restored:
    return
  c.restored = true
  if c.suspended:
    c.setRawMode(false)
  else:
    stdout.write("\x1b[0m\x1b[?25h\x1b[?1049l")
    stdout.flushFile()
    if c.hasSavedTermios:
      discard posixTermios.tcSetAttr(posix.STDIN_FILENO,
        posixTermios.TCSANOW, addr c.originalTermios)

proc suspendConsole(c: var Console) =
  if not c.interactive or c.suspended:
    return
  stdout.write("\x1b[0m\x1b[?25h\x1b[?1049l")
  stdout.flushFile()
  c.setRawMode(false)
  c.suspended = true

proc resumeConsole(c: var Console) =
  if not c.interactive or not c.suspended:
    return
  c.setRawMode(true)
  stdout.write("\x1b[?1049h")
  stdout.flushFile()
  c.suspended = false
  discard c.refreshSize()
  c.hideCursor()

proc `$`*(key: ntopTypes.Key): string =
  result = "vk=" & $key.vk
  if key.ch != Rune(0):
    result.add(" ch=" & $key.ch)

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
