import std/[monotimes, os, osproc, tables, times]
import std/posix as posix
import ntop/[filters, types as ntopTypes]
import ntop/platform/posixconsole

export posixconsole

const
  ProcAllPids = 1
  ProcPidBsdInfo = 3
  ProcPidTaskInfo = 4
  RusageInfoV4 = 4
  HostCpuLoadInfo = 3
  HostVmInfo64 = 4

type
  ProcBsdInfo {.importc: "struct proc_bsdinfo", header: "<sys/proc_info.h>",
                bycopy.} = object
    pbi_flags: uint32
    pbi_status: uint32
    pbi_xstatus: uint32
    pbi_pid: uint32
    pbi_ppid: uint32
    pbi_uid: uint32
    pbi_gid: uint32
    pbi_ruid: uint32
    pbi_rgid: uint32
    pbi_svuid: uint32
    pbi_svgid: uint32
    rfu_1: uint32
    pbi_comm: array[16, char]
    pbi_name: array[32, char]
    pbi_nfiles: uint32
    pbi_pgid: uint32
    pbi_pjobc: uint32
    e_tdev: uint32
    e_tpgid: uint32
    pbi_nice: int32
    pbi_start_tvsec: uint64
    pbi_start_tvusec: uint64

  ProcTaskInfo {.importc: "struct proc_taskinfo", header: "<sys/proc_info.h>",
                bycopy.} = object
    pti_virtual_size: uint64
    pti_resident_size: uint64
    pti_total_user: uint64
    pti_total_system: uint64
    pti_threads_user: uint64
    pti_threads_system: uint64
    pti_policy: int32
    pti_faults: int32
    pti_pageins: int32
    pti_cow_faults: int32
    pti_messages_sent: int32
    pti_messages_received: int32
    pti_syscalls_mach: int32
    pti_syscalls_unix: int32
    pti_csw: int32
    pti_threadnum: int32
    pti_numrunning: int32
    pti_priority: int32

  RusageInfoV4Data {.importc: "struct rusage_info_v4",
                    header: "<sys/resource.h>", bycopy.} = object
    ri_uuid: array[16, uint8]
    ri_user_time: uint64
    ri_system_time: uint64
    ri_pkg_idle_wkups: uint64
    ri_interrupt_wkups: uint64
    ri_pageins: uint64
    ri_wired_size: uint64
    ri_resident_size: uint64
    ri_phys_footprint: uint64
    ri_proc_start_abstime: uint64
    ri_proc_exit_abstime: uint64
    ri_child_user_time: uint64
    ri_child_system_time: uint64
    ri_child_pkg_idle_wkups: uint64
    ri_child_interrupt_wkups: uint64
    ri_child_pageins: uint64
    ri_child_elapsed_abstime: uint64
    ri_diskio_bytesread: uint64
    ri_diskio_byteswritten: uint64

  HostCpuLoadInfoData {.importc: "struct host_cpu_load_info",
                       header: "<mach/host_info.h>", bycopy.} = object
    cpu_ticks: array[4, uint32]

  VmStatistics64Data {.importc: "struct vm_statistics64",
                      header: "<mach/vm_statistics.h>", bycopy.} = object
    free_count: uint32
    inactive_count: uint32
    purgeable_count: uint32
    speculative_count: uint32

  XswUsageData {.importc: "struct xsw_usage", header: "<sys/sysctl.h>",
                 bycopy.} = object
    xsu_total: uint64
    xsu_avail: uint64
    xsu_used: uint64
    xsu_pagesize: uint32
    xsu_encrypted: cint

  Passwd {.importc: "struct passwd", header: "<pwd.h>", bycopy.} = object
    pw_name: cstring

  CpuTimes = object
    ticks: array[4, uint32]

  ProcessSample = object
    process: ntopTypes.Process
    cpuTimeNs: uint64
    ioBytes: uint64

var shutdownRequestedFlag {.volatile.}: cint

proc procListPids(processType, typeInfo: uint32; buffer: pointer;
                  bufferSize: cint): cint
  {.importc: "proc_listpids", cdecl, header: "<libproc.h>".}
proc procPidInfo(pid, flavor: cint; arg: uint64; buffer: pointer;
                 bufferSize: cint): cint
  {.importc: "proc_pidinfo", cdecl, header: "<libproc.h>".}
proc procPidRusage(pid, flavor: cint; buffer: ptr pointer): cint
  {.importc: "proc_pid_rusage", cdecl, header: "<libproc.h>".}
proc procPidPath(pid: cint; buffer: pointer; bufferSize: uint32): cint
  {.importc: "proc_pidpath", cdecl, header: "<libproc.h>".}
proc sysctlbyname(name: cstring; oldValue: pointer; oldLength: ptr csize_t;
                  newValue: pointer; newLength: csize_t): cint
  {.importc, cdecl, header: "<sys/sysctl.h>".}
proc machHostSelf(): cuint
  {.importc: "mach_host_self", cdecl, header: "<mach/mach_init.h>".}
proc hostStatistics(host: cuint; flavor: cint; output: ptr cint;
                    outputCount: ptr cuint): cint
  {.importc: "host_statistics", cdecl, header: "<mach/mach_host.h>".}
proc hostStatistics64(host: cuint; flavor: cint; output: ptr cint;
                      outputCount: ptr cuint): cint
  {.importc: "host_statistics64", cdecl, header: "<mach/mach_host.h>".}
proc getpwuid(uid: cuint): ptr Passwd
  {.importc, cdecl, header: "<pwd.h>".}

let hostPort = machHostSelf()

proc sysctlError(name: string): ref OSError =
  newException(OSError,
    "sysctlbyname(" & name & ") failed: " & $posix.strerror(posix.errno))

proc readSysctlValue[T](name: string; value: var T): bool =
  var length = csize_t(sizeof(value))
  sysctlbyname(name, addr value, addr length, nil, 0) == 0 and
    length <= csize_t(sizeof(value))

proc requiredSysctlValue[T](name: string; value: var T) =
  if not readSysctlValue(name, value):
    raise sysctlError(name)

proc cStringValue(buffer: openArray[char]): string =
  for character in buffer:
    if character == '\0':
      break
    result.add(character)

proc readSysctlString(name: string): string =
  var buffer: array[256, char]
  if readSysctlValue(name, buffer):
    result = cStringValue(buffer)

proc readCpuTimes(): CpuTimes =
  var values: HostCpuLoadInfoData
  var count = cuint(sizeof(values) div sizeof(cint))
  let status = hostStatistics(hostPort, HostCpuLoadInfo,
    cast[ptr cint](addr values), addr count)
  if status != 0:
    raise newException(OSError,
      "host_statistics(HOST_CPU_LOAD_INFO) failed (Mach error " &
      $status & ")")

  result.ticks = values.cpu_ticks

proc tickDelta(current, previous: uint32): uint64 =
  if current >= previous:
    uint64(current - previous)
  else:
    uint64(high(uint32) - previous) + uint64(current) + 1

proc cpuDeltas(current, previous: CpuTimes): CpuTimes =
  for index, currentTick in current.ticks:
    result.ticks[index] = uint32(tickDelta(currentTick,
      previous.ticks[index]) mod (uint64(high(uint32)) + 1))

proc cpuTotal(times: CpuTimes): uint64 =
  for tick in times.ticks:
    result += uint64(tick)

proc readMemoryInfo(): tuple[total, available, swapTotal, swapAvailable: uint64] =
  var totalMemory: uint64
  requiredSysctlValue("hw.memsize", totalMemory)
  result.total = totalMemory

  var vm: VmStatistics64Data
  var count = cuint(sizeof(vm) div sizeof(cint))
  let status = hostStatistics64(hostPort, HostVmInfo64,
    cast[ptr cint](addr vm), addr count)
  if status != 0:
    raise newException(OSError,
      "host_statistics64(HOST_VM_INFO64) failed (Mach error " &
      $status & ")")

  let pageSize = posix.sysconf(posix.SC_PAGESIZE)
  if pageSize <= 0:
    raise newException(OSError, "Could not read the macOS page size")
  result.available = (uint64(vm.free_count) + uint64(vm.inactive_count) +
    uint64(vm.purgeable_count)) * uint64(pageSize)

  var swap: XswUsageData
  if readSysctlValue("vm.swapusage", swap):
    result.swapTotal = swap.xsu_total
    result.swapAvailable = swap.xsu_avail

proc readProcessIds(): seq[cint] =
  var requiredBytes = procListPids(ProcAllPids, 0, nil, 0)
  if requiredBytes < 0:
    raise newException(OSError,
      "proc_listpids failed: " & $posix.strerror(posix.errno))

  var bufferBytes = max(int(requiredBytes) + 32 * sizeof(cint),
    64 * sizeof(cint))
  for _ in 0 .. 3:
    var pids = newSeq[cint](bufferBytes div sizeof(cint))
    let returnedBytes = procListPids(ProcAllPids, 0, addr pids[0],
      cint(bufferBytes))
    if returnedBytes < 0:
      raise newException(OSError,
        "proc_listpids failed: " & $posix.strerror(posix.errno))
    if int(returnedBytes) < bufferBytes:
      pids.setLen(int(returnedBytes) div sizeof(cint))
      return pids
    bufferBytes *= 2
  raise newException(OSError, "Process list changed too quickly to enumerate")

proc readBsdInfo(pid: cint; info: var ProcBsdInfo): bool =
  procPidInfo(pid, ProcPidBsdInfo, 0, addr info,
    cint(sizeof(ProcBsdInfo))) == cint(sizeof(ProcBsdInfo))

proc readTaskInfo(pid: cint; info: var ProcTaskInfo): bool =
  procPidInfo(pid, ProcPidTaskInfo, 0, addr info,
    cint(sizeof(ProcTaskInfo))) == cint(sizeof(ProcTaskInfo))

proc readIoBytes(pid: cint): uint64 =
  var usage: RusageInfoV4Data
  var usageBuffer: pointer = addr usage
  if procPidRusage(pid, RusageInfoV4, addr usageBuffer) == 0:
    result = usage.ri_diskio_bytesread + usage.ri_diskio_byteswritten

proc processUserName(uid: uint32; cache: var Table[uint32, string]): string =
  if cache.hasKey(uid):
    return cache[uid]
  let entry = getpwuid(cuint(uid))
  if entry != nil and entry.pw_name != nil:
    result = $entry.pw_name
  else:
    result = $uid
  cache[uid] = result

proc currentUserName*(): string =
  var users = initTable[uint32, string]()
  processUserName(uint32(posix.getuid()), users)

proc processName(pid: cint; info: ProcBsdInfo): string =
  result = cStringValue(info.pbi_name)
  if result.len == 0:
    result = cStringValue(info.pbi_comm)
  if result.len == 0:
    var path: array[1024, char]
    if procPidPath(pid, addr path[0], uint32(path.len)) > 0:
      result = extractFilename(cStringValue(path))
  if result.len == 0:
    result = $info.pbi_pid

proc readProcessSample(pid: cint; users: var Table[uint32, string];
                       sample: var ProcessSample): bool =
  var bsdInfo: ProcBsdInfo
  var taskInfo: ProcTaskInfo
  if not readBsdInfo(pid, bsdInfo) or not readTaskInfo(pid, taskInfo):
    return false
  if bsdInfo.pbi_pid == 0:
    return false

  let process = ntopTypes.Process(
    id: bsdInfo.pbi_pid,
    userName: processUserName(bsdInfo.pbi_ruid, users),
    userId: bsdInfo.pbi_ruid,
    userIdValid: true,
    basePriority: bsdInfo.pbi_nice,
    usedMemory: taskInfo.pti_resident_size,
    threadCount: uint32(max(0, taskInfo.pti_threadnum)),
    exeName: processName(pid, bsdInfo),
    parentPid: bsdInfo.pbi_ppid
  )
  let ioBytes = readIoBytes(pid)
  sample = ProcessSample(
    process: process,
    cpuTimeNs: taskInfo.pti_total_user + taskInfo.pti_total_system,
    ioBytes: ioBytes
  )
  true

proc processStartTimeMs(pid: cint): uint64 =
  var bsdInfo: ProcBsdInfo
  if readBsdInfo(pid, bsdInfo):
    result = bsdInfo.pbi_start_tvsec * 1000 +
      bsdInfo.pbi_start_tvusec div 1000

proc monotonicTimeMs*(): uint64 =
  uint64(getMonoTime().ticks div 1_000_000)

proc currentTimeMs(): uint64 =
  uint64(max(0.0, getTime().toUnixFloat() * 1000.0))

proc pollSystemInfo*(info: var ntopTypes.HostInfo)

proc initSystemInfo*(): ntopTypes.HostInfo =
  var coreCount: cint
  requiredSysctlValue("hw.logicalcpu", coreCount)
  if coreCount < 1:
    raise newException(OSError, "macOS reported no available CPU cores")
  result.cpuCoreCount = uint32(coreCount)

  var frequencyHz: uint64
  if readSysctlValue("hw.cpufrequency", frequencyHz):
    result.cpuFrequencyMHz = float64(frequencyHz) / 1_000_000.0
  result.cpuName = readSysctlString("machdep.cpu.brand_string")
  if result.cpuName.len == 0:
    result.cpuName = readSysctlString("hw.model")
  if result.cpuName.len == 0:
    result.cpuName = "Unknown CPU"
  result.computerName = readSysctlString("kern.hostname")
  if result.computerName.len == 0:
    result.computerName = "localhost"
  result.pollSystemInfo()

proc pollSystemInfo*(info: var ntopTypes.HostInfo) =
  let memory = readMemoryInfo()
  info.totalMemoryBytes = memory.total
  info.availableMemoryBytes = min(memory.available, memory.total)
  info.totalPageFileBytes = memory.swapTotal
  info.availablePageFileBytes = memory.swapAvailable
  info.upTimeMs = monotonicTimeMs()

proc acquireProcessList*(updateTimeMs: uint64;
                         filters: ntopTypes.Filters = ntopTypes.Filters()):
                         ntopTypes.ProcessSnapshot =
  let previousSystemCpu = readCpuTimes()
  let sampleStartedAt = monotonicTimeMs()
  var samples: seq[ProcessSample]
  var users = initTable[uint32, string]()
  for pid in readProcessIds():
    if pid <= 0:
      continue
    var sample: ProcessSample
    if readProcessSample(pid, users, sample) and
        sample.process.passesFilters(filters):
      samples.add(sample)

  if updateTimeMs > 0:
    os.sleep(int(min(updateTimeMs, uint64(high(int)))))

  let elapsedMs = max(1'u64, monotonicTimeMs() - sampleStartedAt)
  let currentSystemCpu = readCpuTimes()
  let systemCpuDelta = cpuDeltas(currentSystemCpu, previousSystemCpu)
  let totalDelta = cpuTotal(systemCpuDelta)
  let busyDelta = totalDelta - uint64(systemCpuDelta.ticks[2])
  if totalDelta > 0:
    result.cpuUsage = float64(min(busyDelta, totalDelta)) /
      float64(totalDelta)

  let nowMs = currentTimeMs()
  result.processes = newSeqOfCap[ntopTypes.Process](samples.len)
  for sample in samples:
    var process = sample.process
    let pid = cint(process.id)
    var taskInfo: ProcTaskInfo
    if readTaskInfo(pid, taskInfo):
      let currentCpuTime = taskInfo.pti_total_user + taskInfo.pti_total_system
      if currentCpuTime >= sample.cpuTimeNs:
        process.percentProcessorTime =
          100.0 * float64(currentCpuTime - sample.cpuTimeNs) /
            (float64(elapsedMs) * 1_000_000.0)
        if process.percentProcessorTime >= 0.01:
          inc result.runningCount
      process.usedMemory = taskInfo.pti_resident_size
      process.threadCount = uint32(max(0, taskInfo.pti_threadnum))

    let startedAtMs = processStartTimeMs(pid)
    if startedAtMs > 0 and nowMs >= startedAtMs:
      process.upTime = nowMs - startedAtMs

    let ioBytes = readIoBytes(pid)
    process.diskOpsPrev = sample.ioBytes
    process.diskOps = ioBytes
    if updateTimeMs > 0 and ioBytes >= sample.ioBytes:
      process.diskUsage = (ioBytes - sample.ioBytes) * 1000 div elapsedMs
    result.processes.add(process)

proc terminateProcess*(pid: uint32): tuple[success, opened: bool,
                                           error: string] =
  if posix.kill(posix.Pid(pid), 0) == -1:
    let error = $posix.strerror(posix.errno)
    return (posix.errno == posix.EPERM, posix.errno == posix.EPERM, error)
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

proc macSignalHandler(signalNumber: cint) {.noconv.} =
  discard signalNumber
  shutdownRequestedFlag = 1

proc registerConsoleControlHandler*(callback: ConsoleShutdownCallback) =
  shutdownRequestedFlag = 0
  if posix.signal(posix.SIGINT, macSignalHandler) == posix.SIG_ERR:
    raise newException(OSError,
      "signal(SIGINT) failed: " & $posix.strerror(posix.errno))
  if posix.signal(posix.SIGTERM, macSignalHandler) == posix.SIG_ERR:
    raise newException(OSError,
      "signal(SIGTERM) failed: " & $posix.strerror(posix.errno))

proc shutdownRequested*(): bool =
  shutdownRequestedFlag != 0
