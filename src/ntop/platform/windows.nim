import std/[os, unicode, widestrs]
import winim
import ntop/[filters, types]
import ntop/util as ntopUtil

const
  AttrForegroundBlue* = WORD(FOREGROUND_BLUE)
  AttrForegroundGreen* = WORD(FOREGROUND_GREEN)
  AttrForegroundRed* = WORD(FOREGROUND_RED)
  AttrForegroundIntensity* = WORD(FOREGROUND_INTENSITY)
  AttrForegroundWhite* =
    WORD(FOREGROUND_RED or FOREGROUND_GREEN or FOREGROUND_BLUE)
  AttrForegroundCyan* =
    WORD(FOREGROUND_INTENSITY or FOREGROUND_GREEN or FOREGROUND_BLUE)
  AttrBackgroundBlue* = WORD(BACKGROUND_BLUE)
  AttrBackgroundGreen* = WORD(BACKGROUND_GREEN)
  AttrBackgroundRed* = WORD(BACKGROUND_RED)
  AttrBackgroundIntensity* = WORD(BACKGROUND_INTENSITY)
  AttrBackgroundWhite* =
    WORD(BACKGROUND_RED or BACKGROUND_GREEN or BACKGROUND_BLUE)
  AttrBackgroundCyan* =
    WORD(BACKGROUND_INTENSITY or BACKGROUND_GREEN or BACKGROUND_BLUE)

  AttrDefault* = AttrForegroundWhite
  AttrMenu* = AttrForegroundWhite or AttrBackgroundBlue
  AttrHighlight* = AttrForegroundCyan or AttrBackgroundCyan
  AttrHeader* = AttrForegroundWhite or AttrBackgroundGreen
  AttrError* = AttrForegroundWhite or AttrBackgroundRed

  GenericReadWrite = DWORD(GENERIC_READ) or DWORD(GENERIC_WRITE)

type
  Console* = object
    handle*: HANDLE
    previousHandle*: HANDLE
    inputHandle*: HANDLE
    interactive*: bool
    savedAttributes*: WORD
    width*: int
    height*: int
    sizeX*: int
    sizeY*: int

  ConsoleShutdownCallback* = proc() {.noconv.}

  ProcessSample = object
    process: Process
    handle: HANDLE
    creationTime: winim.FILETIME
    kernelTime: winim.FILETIME
    userTime: winim.FILETIME
    ioOperations: uint64
    hasInitialTimes: bool

var consoleShutdownCallback: ConsoleShutdownCallback

func makeAttr*(foreground, background: WORD): WORD {.inline.} =
  (foreground and WORD(0x0F)) or (background and WORD(0xF0))

proc winCheck(ok: WINBOOL; what: string) =
  if ok == 0:
    raise newException(OSError,
      what & " failed (Win32 error " & $GetLastError() & ")")

proc isConsole*(c: Console): bool =
  var mode: DWORD
  GetConsoleMode(c.handle, addr mode) != 0

proc setColor*(c: Console; attr: WORD) =
  if c.isConsole():
    discard SetConsoleTextAttribute(c.handle, attr)

proc getColor*(c: Console): WORD =
  if not c.isConsole():
    return AttrDefault
  var info: CONSOLE_SCREEN_BUFFER_INFO
  if GetConsoleScreenBufferInfo(c.handle, addr info) == 0:
    return AttrDefault
  info.wAttributes

proc setCursorPos*(c: Console; x, y: int) =
  if c.isConsole():
    discard SetConsoleCursorPosition(c.handle,
      COORD(X: SHORT(x), Y: SHORT(y)))

proc setCursorVisible(c: Console; visible: bool) =
  if not c.isConsole():
    return
  var info: CONSOLE_CURSOR_INFO
  if GetConsoleCursorInfo(c.handle, addr info) != 0:
    info.bVisible = WINBOOL(ord(visible))
    discard SetConsoleCursorInfo(c.handle, addr info)

proc hideCursor*(c: Console) =
  c.setCursorVisible(false)

proc showCursor*(c: Console) =
  c.setCursorVisible(true)

proc setTitle*(c: Console; title: string) =
  if c.isConsole():
    var wide = newWideCString(title)
    discard SetConsoleTitleW(cast[LPCWSTR](addr wide[0]))

proc refreshSize*(c: var Console): bool =
  if not c.isConsole():
    c.width = 80
    c.height = 25
    c.sizeX = 80
    c.sizeY = 25
    return false

  var info: CONSOLE_SCREEN_BUFFER_INFO
  if GetConsoleScreenBufferInfo(c.handle, addr info) == 0:
    return false

  let newWidth = int(info.srWindow.Right) - int(info.srWindow.Left) + 1
  let newHeight = int(info.srWindow.Bottom) - int(info.srWindow.Top) + 1
  c.sizeX = int(info.dwSize.X)
  c.sizeY = int(info.dwSize.Y)
  if c.savedAttributes == 0:
    c.savedAttributes = info.wAttributes

  result = newWidth != c.width or newHeight != c.height
  if result:
    c.width = newWidth
    c.height = newHeight
    if c.interactive:
      if SetConsoleScreenBufferSize(c.handle,
          COORD(X: SHORT(newWidth), Y: SHORT(newHeight))) != 0:
        c.sizeX = newWidth
        c.sizeY = newHeight
      c.hideCursor()

proc clear*(c: Console; attr: WORD = AttrDefault) =
  if not c.isConsole():
    return
  var info: CONSOLE_SCREEN_BUFFER_INFO
  var sizeX = c.sizeX
  var sizeY = c.sizeY
  if GetConsoleScreenBufferInfo(c.handle, addr info) != 0:
    sizeX = int(info.dwSize.X)
    sizeY = int(info.dwSize.Y)
  let cells = DWORD(max(0, sizeX) * max(0, sizeY))
  if cells == 0:
    return
  var written: DWORD
  let origin = COORD(X: 0, Y: 0)
  discard FillConsoleOutputCharacterW(c.handle, WCHAR(ord(' ')), cells,
    origin, addr written)
  discard FillConsoleOutputAttribute(c.handle, attr, cells, origin, addr written)
  c.setCursorPos(0, 0)

proc clearRow*(c: Console; y: int; attr: WORD = AttrDefault) =
  if not c.isConsole() or y < 0 or y >= c.height or c.width <= 0:
    return
  var written: DWORD
  let origin = COORD(X: 0, Y: SHORT(y))
  discard FillConsoleOutputCharacterW(c.handle, WCHAR(ord(' ')),
    DWORD(c.width), origin, addr written)
  discard FillConsoleOutputAttribute(c.handle, attr, DWORD(c.width), origin,
    addr written)

proc write*(c: Console; text: string) =
  if text.len == 0:
    return
  if not c.isConsole():
    stdout.write(text)
    stdout.flushFile()
    return

  var wide = newWideCString(text)
  var written: DWORD
  winCheck(WriteConsoleW(c.handle, cast[pointer](addr wide[0]),
    DWORD(wide.len), addr written, nil), "WriteConsoleW")

proc writeColor*(c: Console; text: string; attr: WORD) =
  c.setColor(attr)
  c.write(text)

proc writeAt*(c: Console; x, y: int; text: string; attr: WORD) =
  if not c.isConsole():
    c.write(text)
    return
  c.setCursorPos(x, y)
  c.writeColor(text, attr)

proc writeCentered*(c: Console; y: int; text: string; attr: WORD) =
  if not c.isConsole():
    c.write(text)
    return
  let x = max(0, (c.width - text.runeLen) div 2)
  c.writeAt(x, y, text, attr)

proc flushInput*(c: Console) =
  discard FlushConsoleInputBuffer(c.inputHandle)

proc tryReadKey*(c: Console; key: var Key; timeoutMs: DWORD): bool =
  if not c.isConsole():
    raise newException(IOError, "tryReadKey requires an interactive console")

  let waitResult = WaitForSingleObject(c.inputHandle, timeoutMs)
  if waitResult == WAIT_TIMEOUT:
    return false
  if waitResult == WAIT_FAILED:
    raise newException(OSError,
      "WaitForSingleObject(console input) failed (Win32 error " &
      $GetLastError() & ")")

  while true:
    var record: INPUT_RECORD
    var count: DWORD
    winCheck(ReadConsoleInputW(c.inputHandle, addr record, 1, addr count),
      "ReadConsoleInputW")
    if record.EventType == WORD(KEY_EVENT):
      let keyEvent = record.Event.KeyEvent
      key.vk = int(keyEvent.wVirtualKeyCode)
      key.ch = Rune(keyEvent.uChar.UnicodeChar)
      key.ctrl = (keyEvent.dwControlKeyState and
        DWORD(LEFT_CTRL_PRESSED or RIGHT_CTRL_PRESSED)) != 0
      key.keyDown = keyEvent.bKeyDown != 0
      key.repeatCount = max(1, int(keyEvent.wRepeatCount))
      return true

    if WaitForSingleObject(c.inputHandle, DWORD(0)) == WAIT_TIMEOUT:
      return false

proc readKey*(c: Console): Key =
  if not c.isConsole():
    raise newException(IOError, "readKey requires an interactive console")
  while true:
    if c.tryReadKey(result, DWORD(INFINITE)) and result.keyDown:
      return

proc initConsole*(interactive = true): Console =
  result.interactive = interactive
  result.inputHandle = GetStdHandle(STD_INPUT_HANDLE)
  result.previousHandle = GetStdHandle(STD_OUTPUT_HANDLE)
  result.handle = result.previousHandle
  if result.previousHandle == 0 or
      result.previousHandle == INVALID_HANDLE_VALUE:
    raise newException(OSError, "GetStdHandle(STD_OUTPUT_HANDLE) failed")

  var previousInfo: CONSOLE_SCREEN_BUFFER_INFO
  if GetConsoleScreenBufferInfo(result.previousHandle, addr previousInfo) != 0:
    result.savedAttributes = previousInfo.wAttributes

  if interactive:
    let buffer = CreateConsoleScreenBuffer(
      GenericReadWrite,
      DWORD(FILE_SHARE_READ or FILE_SHARE_WRITE),
      nil,
      DWORD(CONSOLE_TEXTMODE_BUFFER),
      nil)
    if buffer == INVALID_HANDLE_VALUE or buffer == 0:
      raise newException(OSError,
        "CreateConsoleScreenBuffer failed (Win32 error " & $GetLastError() & ")")

    result.handle = buffer
    if SetConsoleActiveScreenBuffer(result.handle) == 0:
      raise newException(OSError,
        "SetConsoleActiveScreenBuffer failed (Win32 error " &
        $GetLastError() & ")")
    discard SetConsoleMode(result.handle,
      DWORD(ENABLE_PROCESSED_INPUT or ENABLE_WRAP_AT_EOL_OUTPUT))

  discard result.refreshSize()

proc restore*(c: var Console) =
  if not c.interactive:
    return
  let previous = c.previousHandle
  c.previousHandle = 0
  if previous != 0 and previous != INVALID_HANDLE_VALUE:
    if c.savedAttributes != 0:
      discard SetConsoleTextAttribute(previous, c.savedAttributes)
    discard SetConsoleActiveScreenBuffer(previous)

proc `$`*(key: Key): string =
  result = "vk=" & $key.vk
  if key.ch != Rune(0):
    result.add(" ch=" & $key.ch)

func packedTime(value: winim.FILETIME): uint64 =
  ntopUtil.fileTimeToUInt64(ntopUtil.FileTime(
    lowDateTime: uint32(value.dwLowDateTime),
    highDateTime: uint32(value.dwHighDateTime)
  ))

func timeDifference(current, previous: winim.FILETIME): uint64 =
  let nowValue = packedTime(current)
  let previousValue = packedTime(previous)
  if nowValue >= previousValue: nowValue - previousValue else: 0'u64

proc processUserName(processHandle: HANDLE): string =
  result = "SYSTEM"
  var token: HANDLE
  if OpenProcessToken(processHandle, DWORD(TOKEN_READ), addr token) == 0:
    return
  defer: discard CloseHandle(token)

  var tokenBuffer: array[512, uint64]
  var returnedLength: DWORD
  if GetTokenInformation(token, TOKEN_INFORMATION_CLASS(1),
      addr tokenBuffer[0], DWORD(sizeof(tokenBuffer)), addr returnedLength) == 0:
    return

  let tokenUser = cast[PTOKEN_USER](addr tokenBuffer[0])
  var userName: array[256, WCHAR]
  var domainName: array[256, WCHAR]
  var userNameLength = DWORD(userName.len)
  var domainNameLength = DWORD(domainName.len)
  var nameUse: SID_NAME_USE
  if LookupAccountSidW(nil, tokenUser.User.Sid, addr userName[0],
      addr userNameLength, addr domainName[0], addr domainNameLength,
      addr nameUse) != 0:
    result = $cast[LPWSTR](addr userName[0])

proc readIoOperations(processHandle: HANDLE): uint64 =
  var counters: IO_COUNTERS
  if GetProcessIoCounters(processHandle, addr counters) != 0:
    result = uint64(counters.ReadTransferCount) +
      uint64(counters.WriteTransferCount)

proc acquireProcessList*(updateTimeMs: uint64;
                         filters: Filters = Filters()): ProcessSnapshot =
  var snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0)
  if snapshot == 0 or snapshot == INVALID_HANDLE_VALUE:
    raise newException(OSError,
      "CreateToolhelp32Snapshot failed (Win32 error " & $GetLastError() & ")")
  defer: discard CloseHandle(snapshot)

  var entry: PROCESSENTRY32W
  entry.dwSize = DWORD(sizeof(entry))
  if Process32FirstW(snapshot, addr entry) == 0:
    raise newException(OSError,
      "Process32FirstW failed (Win32 error " & $GetLastError() & ")")

  var samples: seq[ProcessSample]
  defer:
    for sample in samples:
      if sample.handle != 0 and sample.handle != INVALID_HANDLE_VALUE:
        discard CloseHandle(sample.handle)

  var status = WINBOOL(1)
  while status != 0:
    if entry.th32ProcessID != 0:
      var process = Process(
        id: uint32(entry.th32ProcessID),
        userName: "SYSTEM",
        basePriority: int32(entry.pcPriClassBase),
        threadCount: uint32(entry.cntThreads),
        exeName: $cast[LPWSTR](addr entry.szExeFile[0]),
        parentPid: uint32(entry.th32ParentProcessID)
      )

      if process.passesIdentityFilters(filters):
        let processHandle = OpenProcess(
          DWORD(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ),
          WINBOOL(0), entry.th32ProcessID)
        if processHandle != 0 and processHandle != INVALID_HANDLE_VALUE:
          process.userName = processUserName(processHandle)
          var memory: PROCESS_MEMORY_COUNTERS
          memory.cb = DWORD(sizeof(memory))
          if GetProcessMemoryInfo(processHandle, addr memory,
              DWORD(sizeof(memory))) != 0:
            process.usedMemory = uint64(memory.WorkingSetSize)

        if process.passesFilters(filters):
          var sample = ProcessSample(process: process, handle: processHandle)
          if processHandle != 0 and processHandle != INVALID_HANDLE_VALUE:
            sample.ioOperations = readIoOperations(processHandle)
            sample.process.diskOpsPrev = sample.ioOperations
            var exitTime: winim.FILETIME
            sample.hasInitialTimes = GetProcessTimes(processHandle,
              addr sample.creationTime, addr exitTime, addr sample.kernelTime,
              addr sample.userTime) != 0
          samples.add(sample)
        elif processHandle != 0 and processHandle != INVALID_HANDLE_VALUE:
          discard CloseHandle(processHandle)

    status = Process32NextW(snapshot, addr entry)

  var previousIdle, previousKernel, previousUser: winim.FILETIME
  if GetSystemTimes(addr previousIdle, addr previousKernel, addr previousUser) == 0:
    raise newException(OSError,
      "GetSystemTimes failed (Win32 error " & $GetLastError() & ")")

  if updateTimeMs > 0:
    sleep(int(min(updateTimeMs, uint64(high(int)))))

  var currentIdle, currentKernel, currentUser: winim.FILETIME
  if GetSystemTimes(addr currentIdle, addr currentKernel, addr currentUser) == 0:
    raise newException(OSError,
      "GetSystemTimes failed (Win32 error " & $GetLastError() & ")")

  let systemKernelDelta = timeDifference(currentKernel, previousKernel)
  let systemUserDelta = timeDifference(currentUser, previousUser)
  let systemIdleDelta = timeDifference(currentIdle, previousIdle)
  let totalSystemDelta = systemKernelDelta + systemUserDelta
  if totalSystemDelta > 0:
    result.cpuUsage = min(
      float64(totalSystemDelta - min(systemIdleDelta, totalSystemDelta)) /
        float64(totalSystemDelta),
      1.0)

  result.processes = newSeqOfCap[Process](samples.len)
  for sample in samples.mitems:
    var process = sample.process
    if sample.handle != 0 and sample.handle != INVALID_HANDLE_VALUE:
      var creationTime, kernelTime, userTime: winim.FILETIME
      var exitTime: winim.FILETIME
      if GetProcessTimes(sample.handle, addr creationTime, addr exitTime,
          addr kernelTime, addr userTime) != 0:
        if sample.hasInitialTimes:
          let processDelta =
            timeDifference(kernelTime, sample.kernelTime) +
            timeDifference(userTime, sample.userTime)
          if totalSystemDelta > 0:
            process.percentProcessorTime =
              100.0 * float64(processDelta) / float64(totalSystemDelta)
            if process.percentProcessorTime >= 0.01:
              inc result.runningCount

        var systemTime: winim.FILETIME
        GetSystemTimeAsFileTime(addr systemTime)
        process.upTime = timeDifference(systemTime, creationTime) div 10_000

      process.diskOps = readIoOperations(sample.handle)
      if updateTimeMs > 0 and process.diskOps >= sample.ioOperations:
        process.diskUsage =
          (process.diskOps - sample.ioOperations) * 1000 div updateTimeMs
    result.processes.add(process)

proc readCpuName(): string =
  var key: HKEY
  let path = newWideCString(
    "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0")
  let status = RegOpenKeyExW(HKEY_LOCAL_MACHINE, cast[LPCWSTR](addr path[0]),
    0, REGSAM(KEY_READ), addr key)
  if status != 0:
    return ""
  defer: discard RegCloseKey(key)

  var value: array[256, WCHAR]
  var valueSize = DWORD(sizeof(value))
  var valueType: DWORD
  let valueName = newWideCString("ProcessorNameString")
  if RegQueryValueExW(key, cast[LPCWSTR](addr valueName[0]), nil,
      addr valueType, cast[LPBYTE](addr value[0]), addr valueSize) != 0:
    return ""
  $cast[LPWSTR](addr value[0])

proc pollSystemInfo*(info: var HostInfo) =
  var memory: MEMORYSTATUSEX
  memory.dwLength = DWORD(sizeof(memory))
  if GlobalMemoryStatusEx(addr memory) == 0:
    raise newException(OSError,
      "GlobalMemoryStatusEx failed (Win32 error " & $GetLastError() & ")")
  info.totalMemoryBytes = uint64(memory.ullTotalPhys)
  info.availableMemoryBytes = uint64(memory.ullAvailPhys)
  info.totalPageFileBytes = uint64(memory.ullTotalPageFile)
  info.availablePageFileBytes = uint64(memory.ullAvailPageFile)
  info.upTimeMs = uint64(GetTickCount64())

proc initSystemInfo*(): HostInfo =
  var frequency: LARGE_INTEGER
  if QueryPerformanceFrequency(addr frequency) == 0:
    raise newException(OSError,
      "QueryPerformanceFrequency failed (Win32 error " & $GetLastError() & ")")
  result.cpuFrequencyMHz = float64(frequency.QuadPart) / 1_000_000.0

  var nativeInfo: winim.SYSTEM_INFO
  GetNativeSystemInfo(addr nativeInfo)
  result.cpuCoreCount = uint32(nativeInfo.dwNumberOfProcessors)
  result.cpuName = readCpuName()
  result.computerName = "localhost"
  var computerName: array[256, WCHAR]
  var computerNameSize = DWORD(computerName.len)
  if GetComputerNameW(addr computerName[0], addr computerNameSize) != 0:
    result.computerName = $cast[LPWSTR](addr computerName[0])
  result.pollSystemInfo()

proc terminateProcess*(pid: uint32): tuple[success, opened: bool,
                                           errorCode: uint32] =
  let processHandle = OpenProcess(DWORD(PROCESS_TERMINATE), WINBOOL(0),
    DWORD(pid))
  if processHandle == 0 or processHandle == INVALID_HANDLE_VALUE:
    return (false, false, uint32(GetLastError()))
  defer: discard CloseHandle(processHandle)
  if TerminateProcess(processHandle, DWORD(9)) == 0:
    return (false, true, uint32(GetLastError()))
  (true, true, 0'u32)

proc startCommand*(command: string): string =
  var commandLine = newWideCString(command)
  var startupInfo: STARTUPINFOW
  startupInfo.cb = DWORD(sizeof(startupInfo))
  var processInfo: PROCESS_INFORMATION
  if CreateProcessW(nil, cast[LPWSTR](addr commandLine[0]), nil, nil,
      WINBOOL(0), DWORD(0), nil, nil, addr startupInfo, addr processInfo) == 0:
    return "Failed to create process (Win32 error " & $GetLastError() & ")"
  discard CloseHandle(processInfo.hThread)
  discard CloseHandle(processInfo.hProcess)

proc monotonicTimeMs*(): uint64 =
  uint64(GetTickCount64())

proc winConsoleCtrlHandler(ctrlType: DWORD): WINBOOL {.stdcall.} =
  if not consoleShutdownCallback.isNil:
    consoleShutdownCallback()
  ExitProcess(0)
  TRUE

proc registerConsoleControlHandler*(callback: ConsoleShutdownCallback) =
  consoleShutdownCallback = callback
  if SetConsoleCtrlHandler(winConsoleCtrlHandler, WINBOOL(1)) == 0:
    raise newException(OSError,
      "SetConsoleCtrlHandler failed (Win32 error " & $GetLastError() & ")")
