when not defined(windows):
  {.error: "nimtop system information is Windows-only.".}

import std/widestrs
import winim
import types

proc checkWin32(ok: WINBOOL; operation: string) =
  if ok == 0:
    raise newException(OSError,
      operation & " failed (Win32 error " & $GetLastError() & ")")

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

proc pollSystemInfo*(info: var HostInfo)

proc initSystemInfo*(): HostInfo =
  var frequency: LARGE_INTEGER
  checkWin32(QueryPerformanceFrequency(addr frequency),
    "QueryPerformanceFrequency")
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

proc pollSystemInfo*(info: var HostInfo) =
  var memory: MEMORYSTATUSEX
  memory.dwLength = DWORD(sizeof(memory))
  checkWin32(GlobalMemoryStatusEx(addr memory), "GlobalMemoryStatusEx")
  info.totalMemoryBytes = uint64(memory.ullTotalPhys)
  info.availableMemoryBytes = uint64(memory.ullAvailPhys)
  info.totalPageFileBytes = uint64(memory.ullTotalPageFile)
  info.availablePageFileBytes = uint64(memory.ullAvailPageFile)
  info.upTimeMs = uint64(GetTickCount64())
