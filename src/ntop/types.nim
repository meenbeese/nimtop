type
  SortType* = enum
    stId, stUserName, stPriority, stProcessorTime, stUsedMemory,
    stThreadCount, stDiskUsage, stUpTime, stProcess, stTree

  SortOrder* = enum
    soAscending, soDescending

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
    filterByPid*: bool
    filterByName*: bool
    filterByUser*: bool
