import std/[algorithm, strutils, tables]
import types

func compareBySortType(a, b: Process; sortType: SortType): int =
  case sortType
  of stId:
    cmp(a.id, b.id)
  of stUserName:
    cmpIgnoreCase(a.userName, b.userName)
  of stPriority:
    cmp(a.basePriority, b.basePriority)
  of stProcessorTime:
    cmp(a.percentProcessorTime, b.percentProcessorTime)
  of stUsedMemory:
    cmp(a.usedMemory, b.usedMemory)
  of stThreadCount:
    cmp(a.threadCount, b.threadCount)
  of stDiskUsage:
    cmp(a.diskUsage, b.diskUsage)
  of stUpTime:
    cmp(a.upTime, b.upTime)
  of stProcess:
    cmpIgnoreCase(a.exeName, b.exeName)
  of stTree:
    cmp(a.id, b.id)

func ordered(value: int; sortOrder: types.SortOrder): int {.inline.} =
  if sortOrder == soDescending: -value else: value

proc flattenTree(root: int; processes: seq[Process];
                 children: seq[seq[int]]; visited: var seq[bool];
                 output: var seq[Process]) =
  var stack = @[(root, 0)]
  while stack.len > 0:
    let (index, depth) = stack.pop()
    if visited[index]:
      continue
    visited[index] = true
    var process = processes[index]
    process.treeDepth = depth
    output.add(process)
    for childIndex in countdown(children[index].high, 0):
      stack.add((children[index][childIndex], depth + 1))

proc sortProcesses*(processes: var seq[Process]; sortType: SortType;
                    sortOrder = soDescending) =
  if sortType == stTree:
    var indexByPid = initTable[uint32, int](processes.len)
    for i, process in processes:
      if not indexByPid.hasKey(process.id):
        indexByPid[process.id] = i

    var children = newSeq[seq[int]](processes.len)
    var roots: seq[int]
    for i, process in processes:
      if process.parentPid != process.id and indexByPid.hasKey(process.parentPid):
        children[indexByPid[process.parentPid]].add(i)
      else:
        roots.add(i)

    var orderedProcesses = newSeqOfCap[Process](processes.len)
    var visited = newSeq[bool](processes.len)

    for root in roots:
      flattenTree(root, processes, children, visited, orderedProcesses)

    # A parent cycle has no natural root; emit any remaining processes once.
    for i in 0 ..< processes.len:
      if not visited[i]:
        flattenTree(i, processes, children, visited, orderedProcesses)
    processes = move(orderedProcesses)
    return

  processes.sort(proc(a, b: Process): int =
    let comparison = compareBySortType(a, b, sortType)
    if comparison == 0:
      ordered(cmp(a.id, b.id), sortOrder)
    else:
      ordered(comparison, sortOrder)
  )
