import std/[strutils]
import ntop/[types, version]

type
  CliResultKind* = enum
    ckRun, ckHelp, ckVersion, ckError

  CliResult* = object
    kind*: CliResultKind
    message*: string
    monochrome*: bool
    interactive*: bool
    sortColumn*: SortType
    sortColumnSet*: bool
    maxIterations*: uint64
    maxIterationsSet*: bool
    filters*: Filters

proc helpText*(argv0 = "nimtop.exe"): string =
  result = versionString() & "\n\n"
  result.add("USAGE\n")
  result.add("  " & argv0 & " [OPTIONS]\n\n")
  result.add("OPTIONS\n")
  result.add("  -C                     Use a monochrome color scheme.\n")
  result.add("  -h                     Display this help info.\n")
  result.add("  -p PID[,PID...]        Show only the given PIDs.\n")
  result.add("  -n NUMBER              Exit after this many screen updates.\n")
  result.add("  -N NamePart[,NamePart...] Show names containing any supplied part.\n")
  result.add("  -F FILTER              Show commands matching this text filter.\n")
  result.add("  -s COLUMN              Sort by this column; use 'help' for valid names.\n")
  result.add("  -t                     Start in process tree view.\n")
  result.add("  -u [USER|UID]          Filter by user; defaults to the current user.\n")
  result.add("  -d                     Do not run in interactive mode.\n")
  result.add("  -v                     Print version.\n")

proc sortKeyHelpText*(): string =
  "Valid sort keys: ID, USER, PRI, CPU%, MEM, THRD, DISK, TIME, PROCESS\n"

proc sortTypeFromName*(name: string; sortType: var SortType): bool =
  case name.toUpperAscii():
  of "ID": sortType = stId
  of "USER": sortType = stUserName
  of "PRI": sortType = stPriority
  of "CPU%": sortType = stProcessorTime
  of "MEM": sortType = stUsedMemory
  of "THRD": sortType = stThreadCount
  of "DISK": sortType = stDiskUsage
  of "TIME": sortType = stUpTime
  of "PROCESS": sortType = stProcess
  else:
    return false
  return true

proc errorResult(message: string): CliResult =
  CliResult(kind: ckError, message: message)

proc readOptionValue(args: openArray[string]; index: var int;
                     optional = false):
                     tuple[ok: bool, value: string] =
  if index + 1 < args.len and not args[index + 1].startsWith("-"):
    inc index
    return (true, args[index])
  if optional:
    return (true, "")
  (false, "")

proc addPidFilter(value: string; filters: var Filters): string =
  for pidText in value.split(','):
    let text = pidText.strip()
    if text.len == 0:
      return "Invalid PID list"
    try:
      let pid = parseBiggestUInt(text)
      if pid == 0 or pid > uint64(high(uint32)):
        return "Invalid PID: '" & text & "'"
      filters.pidList.add(uint32(pid))
    except ValueError:
      return "Invalid PID: '" & text & "'"
  filters.filterByPid = filters.pidList.len > 0

proc setUserFilter(value: string; filters: var Filters): string =
  let user = value.strip()
  filters.filterByUser = false
  filters.filterByUserId = false
  filters.filterByCurrentUser = false
  if user.len == 0:
    filters.filterByCurrentUser = true
    return
  try:
    let userId = parseBiggestUInt(user)
    if userId > uint64(high(uint32)):
      return "Invalid user ID: '" & user & "'"
    filters.userId = uint32(userId)
    filters.filterByUserId = true
  except ValueError:
    filters.userName = user
    filters.filterByUser = true

proc parseCli*(args: openArray[string]; argv0 = "nimtop.exe"): CliResult =
  result.kind = ckRun
  result.interactive = true
  var i = 0
  while i < args.len:
    let arg = args[i]
    case arg
    of "-C":
      result.monochrome = true
    of "-h":
      return CliResult(kind: ckHelp)
    of "-v", "-V":
      return CliResult(kind: ckVersion)
    of "-d":
      result.interactive = false
    of "-t":
      result.sortColumn = stTree
      result.sortColumnSet = true
    of "-p", "-N", "-s", "-F":
      let valueResult = readOptionValue(args, i)
      if not valueResult.ok:
        return errorResult("Option '" & arg & "' requires a value")
      let value = valueResult.value
      case arg
      of "-p":
        let error = addPidFilter(value, result.filters)
        if error.len > 0:
          return errorResult(error)
      of "-N":
        for namePart in value.split(','):
          let part = namePart.strip()
          if part.len == 0:
            return errorResult("Invalid name filter")
          result.filters.nameParts.add(part)
        result.filters.filterByName = result.filters.nameParts.len > 0
      of "-s":
        if value.toLowerAscii() == "help":
          return CliResult(kind: ckHelp, message: sortKeyHelpText())
        if not sortTypeFromName(value, result.sortColumn):
          return errorResult("Unknown column: '" & value & "'")
        result.sortColumnSet = true
      of "-F":
        if value.len == 0:
          return errorResult("Invalid command filter")
        result.filters.commandFilter = value
        result.filters.filterByCommand = true
      else:
        discard
    of "-n":
      let valueResult = readOptionValue(args, i)
      if not valueResult.ok:
        return errorResult("Option '-n' requires a value")
      try:
        let iterations = parseBiggestUInt(valueResult.value)
        if iterations == 0:
          return errorResult("Option '-n' must be greater than zero")
        result.maxIterations = iterations
        result.maxIterationsSet = true
      except ValueError:
        return errorResult("Invalid iteration count: '" &
          valueResult.value & "'")
    of "-u":
      let valueResult = readOptionValue(args, i, optional = true)
      if not valueResult.ok:
        return errorResult("Option '" & arg & "' requires a value")
      let error = setUserFilter(valueResult.value, result.filters)
      if error.len > 0:
        return errorResult(error)
    else:
      if arg.startsWith("-"):
        return errorResult("Unknown option: '" & arg & "'")
      return errorResult("Unexpected argument: '" & arg & "'")
    inc i
