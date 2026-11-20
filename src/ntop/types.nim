import std/unicode

type
  Key* = object
    vk*: int
    ch*: Rune
    ctrl*: bool
    keyDown*: bool
    repeatCount*: int

  SortType* = enum
    stId, stUserName, stPriority, stProcessorTime, stUsedMemory,
    stThreadCount, stDiskUsage, stUpTime, stProcess, stTree

  SortOrder* = enum
    soAscending, soDescending

  Process* = object
    id*: uint32
    userName*: string
    userId*: uint32
    userIdValid*: bool
    basePriority*: int32
    percentProcessorTime*: float64
    usedMemory*: uint64
    threadCount*: uint32
    upTime*: uint64
    exeName*: string
    parentPid*: uint32
    diskOpsPrev*: uint64
    diskOps*: uint64
    diskUsage*: uint64
    treeDepth*: int

  HostInfo* = object
    cpuName*: string
    cpuFrequencyMHz*: float64
    cpuCoreCount*: uint32
    computerName*: string
    totalMemoryBytes*: uint64
    availableMemoryBytes*: uint64
    totalPageFileBytes*: uint64
    availablePageFileBytes*: uint64
    upTimeMs*: uint64

  ProcessSnapshot* = object
    processes*: seq[Process]
    runningCount*: uint32
    cpuUsage*: float64

  Config* = object
    fgColor*: uint16
    bgColor*: uint16
    fgHighlightColor*: uint16
    bgHighlightColor*: uint16
    menuBarColor*: uint16
    processListHeaderColor*: uint16
    errorColor*: uint16
    cpuBarColor*: uint16
    memoryBarColor*: uint16
    pageMemoryBarColor*: uint16
    redrawInterval*: uint64

  Filters* = object
    pidList*: seq[uint32]
    nameParts*: seq[string]
    userName*: string
    userId*: uint32
    commandFilter*: string
    filterByPid*: bool
    filterByName*: bool
    filterByUser*: bool
    filterByUserId*: bool
    filterByCurrentUser*: bool
    filterByCommand*: bool
