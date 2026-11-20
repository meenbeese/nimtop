when not defined(windows):
  {.error: "nimtop process acquisition is Windows-only.".}

import std/os
import winim
import filters, types
import util as ntopUtil

type
  ProcessSample = object
    process: Process
    handle: HANDLE
    creationTime: winim.FILETIME
    kernelTime: winim.FILETIME
    userTime: winim.FILETIME
    ioOperations: uint64
    hasInitialTimes: bool

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
