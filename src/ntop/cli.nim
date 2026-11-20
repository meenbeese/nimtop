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
    filters*: Filters

proc helpText*(argv0 = "NTop.exe"): string =
  result = versionString() & "\n\n"
  result.add("USAGE\n")
  result.add("  " & argv0 & " [OPTIONS]\n\n")
  result.add("OPTIONS\n")
  result.add("  -C                     Use a monochrome color scheme.\n")
  result.add("  -h                     Display this help info.\n")
  result.add("  -p PID,PID...          Show only the given PIDs.\n")
  result.add("  -n NamePart,NamePart... Show only processes containing at least one name part.\n")
  result.add("  -s COLUMN              Sort by this column.\n")
  result.add("  -u USERNAME            Display only processes of this user.\n")
  result.add("  -d                     Do not run in interactive mode.\n")
  result.add("  -v                     Print version.\n")

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

proc parseCli*(args: openArray[string]; argv0 = "NTop.exe"): CliResult =
  result.kind = ckRun
  result.interactive = true
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg != "-C" and arg != "-h" and arg != "-d" and arg != "-v" and
        arg != "--help" and arg != "--version" and arg.startsWith("-"):
      if arg.len != 2:
        if arg.startsWith("-"):
          return errorResult("Unknown option: '" & arg[1 .. ^1] & "'")
      else:
        let option = arg[1]
        case option
        of 'C':
          result.monochrome = true
        of 'h':
          return CliResult(kind: ckHelp)
        of 'd':
          result.interactive = false
        of 'v':
          return CliResult(kind: ckVersion)
        of 'p', 'n', 'u', 's':
          inc i
          if i >= args.len:
            return errorResult("Option '-" & $option & "' requires a value")
          let value = args[i]
          case option
          of 'p':
            for pidText in value.split(','):
              let pidText = pidText.strip()
              if pidText.len == 0:
                return errorResult("Invalid PID list")
              try:
                let pid = parseBiggestUInt(pidText)
                if pid == 0 or pid > uint64(high(uint32)):
                  return errorResult("Invalid PID: '" & pidText & "'")
                result.filters.pidList.add(uint32(pid))
              except ValueError:
                return errorResult("Invalid PID: '" & pidText & "'")
            result.filters.filterByPid = result.filters.pidList.len > 0
          of 'n':
            for namePart in value.split(','):
              let namePart = namePart.strip()
              if namePart.len == 0:
                return errorResult("Invalid name filter")
              result.filters.nameParts.add(namePart)
            result.filters.filterByName = result.filters.nameParts.len > 0
          of 'u':
            if value.strip().len == 0:
              return errorResult("Option '-u' requires a value")
            result.filters.userName = value
            result.filters.filterByUser = true
          of 's':
            if not sortTypeFromName(value, result.sortColumn):
              return errorResult("Unknown column: '" & value & "'")
            result.sortColumnSet = true
          else:
            discard
        else:
          return errorResult("Unknown option: '" & $option & "'")
    elif arg == "--help":
      return CliResult(kind: ckHelp)
    elif arg == "--version":
      return CliResult(kind: ckVersion)
    elif arg == "-C":
      result.monochrome = true
    elif arg == "-h":
      return CliResult(kind: ckHelp)
    elif arg == "-d":
      result.interactive = false
    elif arg == "-v":
      return CliResult(kind: ckVersion)
    else:
      return errorResult("Unexpected argument: '" & arg & "'")
    inc i
