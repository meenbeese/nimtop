when not defined(windows):
  {.error: "nimtop's interactive renderer is Windows-only.".}

import std/[strutils, unicode]
import winim
import console, input, processformat, types, util

type
  Cell = object
    character: Rune
    attribute: WORD

  Screen* = object
    width*: int
    height*: int
    cells: seq[Cell]

func combined(foreground, background: uint16): WORD {.inline.} =
  WORD(foreground or background)

func index(screen: Screen; x, y: int): int {.inline.} =
  y * screen.width + x

proc fill*(screen: var Screen; x, y, width: int; attribute: WORD;
           character = Rune(ord(' '))) =
  if y < 0 or y >= screen.height or width <= 0:
    return
  let first = max(0, x)
  let last = min(screen.width, x + width)
  if first >= last:
    return
  for column in first ..< last:
    screen.cells[screen.index(column, y)] =
      Cell(character: character, attribute: attribute)

proc fillRect*(screen: var Screen; x, y, width, height: int;
               attribute: WORD; character = Rune(ord(' '))) =
  if height <= 0:
    return
  for row in max(0, y) ..< min(screen.height, y + height):
    screen.fill(x, row, width, attribute, character)

proc initScreen*(width, height: int; attribute: WORD): Screen =
  result.width = max(width, 1)
  result.height = max(height, 1)
  result.cells = newSeq[Cell](result.width * result.height)
  result.fillRect(0, 0, result.width, result.height, attribute)

proc put*(screen: var Screen; x, y: int; text: string; attribute: WORD) =
  if y < 0 or y >= screen.height:
    return
  var column = x
  for character in text.runes:
    if column >= screen.width:
      break
    if column >= 0:
      screen.cells[screen.index(column, y)] =
        Cell(character: character, attribute: attribute)
    inc column

proc flush*(screen: Screen; con: Console) =
  # Writing the bottom-right cell can scroll; clear the last row via Win32 instead.
  for y in 0 ..< max(0, screen.height - 1):
    var x = 0
    while x < screen.width:
      let attribute = screen.cells[screen.index(x, y)].attribute
      let start = x
      var text = ""
      while x < screen.width and
          screen.cells[screen.index(x, y)].attribute == attribute:
        text.add($screen.cells[screen.index(x, y)].character)
        inc x
      con.writeAt(start, y, text, attribute)
  if screen.height > 0:
    con.clearRow(screen.height - 1,
      screen.cells[screen.index(0, screen.height - 1)].attribute)

func barValue(value: float64): string =
  let number = formatFloat(value * 100.0, ffDecimal, 1)
  repeat('0', max(0, 4 - number.len)) & number & "%"

proc drawPercentageBar(screen: var Screen; y: int; name: string;
                       percentage: float64; barColor: uint16;
                       config: Config): int =
  let normal = combined(config.fgColor, config.bgColor)
  let accent = WORD(config.fgHighlightColor)
  screen.put(0, y, "  " & name, accent)
  result = 2 + name.len
  screen.put(result, y, "[", normal)
  inc result
  let bars = int(float64(25) * max(0.0, min(percentage, 1.0)))
  screen.fill(result, y, bars, WORD(barColor), Rune(ord('|')))
  screen.fill(result + bars, y, 25 - bars, normal)
  result += 25
  screen.put(result, y, barValue(percentage), WORD(config.bgColor))
  result += 5
  screen.put(result, y, "]", normal)
  result += 1

proc drawHeader(screen: var Screen; state: UiState; config: Config) =
  const columns = [
    ("ID", 7, stId),
    ("USER", 9, stUserName),
    ("PRI", 3, stPriority),
    ("CPU%", 5, stProcessorTime),
    ("MEM", 11, stUsedMemory),
    ("THRD", 4, stThreadCount),
    ("DISK", 9, stDiskUsage),
    ("TIME", 11, stUpTime),
    ("PROCESS", 0, stProcess)
  ]
  let normal = combined(config.fgColor, config.processListHeaderColor)
  var x = 0
  for (name, columnWidth, sortType) in columns:
    let width =
      if columnWidth == 0: max(0, screen.width - x)
      else: columnWidth
    let attribute =
      if state.sortType == sortType: WORD(config.bgHighlightColor)
      else: normal
    screen.put(x, 5, align(name, width), attribute)
    x += width + 2
    if x >= screen.width:
      break

proc isTagged(state: UiState; pid: uint32): bool =
  for taggedPid in state.tagged:
    if taggedPid == pid:
      return true

proc processAttribute(state: UiState; processIndex: int;
                      config: Config): WORD =
  let tagged = state.isTagged(state.processes[processIndex].id)
  if processIndex == state.selectedIndex:
    if tagged:
      WORD(config.bgColor or config.bgHighlightColor)
    else:
      WORD(config.bgHighlightColor)
  elif tagged:
    WORD(config.bgColor)
  else:
    combined(config.fgColor, config.bgColor)

proc render*(screen: var Screen; state: UiState; host: HostInfo;
             config: Config) =
  let normal = combined(config.fgColor, config.bgColor)
  let accent = WORD(config.fgHighlightColor)
  screen.fillRect(0, 0, screen.width, screen.height, normal)

  let menu = "nimtop on " & host.computerName
  screen.fill(0, 0, screen.width,
    combined(config.fgColor, config.menuBarColor))
  screen.put(max(0, (screen.width - menu.runeLen) div 2), 0, menu,
    combined(config.fgColor, config.menuBarColor))

  var x = screen.drawPercentageBar(2, "CPU", state.cpuUsage,
    config.cpuBarColor, config)
  let cpuLabel = "  Name: "
  let cpuDetails = host.cpuName & " (" & $host.cpuCoreCount & " Cores)"
  let taskDetails = "  Tasks: " & $state.processes.len & " total, " &
    $state.runningCount & " running"
  if x + cpuLabel.len + cpuDetails.len + taskDetails.len < screen.width:
    screen.put(x, 2, cpuLabel, accent)
    x += cpuLabel.len
    screen.put(x, 2, cpuDetails, normal)
    x += cpuDetails.len
  screen.put(x, 2, taskDetails, accent)

  let totalMemory = host.totalMemoryBytes
  let memoryUsage =
    if totalMemory > 0:
      float64(totalMemory - min(totalMemory, host.availableMemoryBytes)) /
        float64(totalMemory)
    else:
      0.0
  x = screen.drawPercentageBar(3, "Mem", memoryUsage,
    config.memoryBarColor, config)
  screen.put(x, 3, "  Size: ", accent)
  screen.put(x + 8, 3,
    $ (host.totalMemoryBytes div 1_000_000_000) & " GB", normal)

  let totalPageFile = host.totalPageFileBytes
  let pageUsage =
    if totalPageFile > 0:
      float64(totalPageFile -
        min(totalPageFile, host.availablePageFileBytes)) /
          float64(totalPageFile)
    else:
      0.0
  x = screen.drawPercentageBar(4, "Pge", pageUsage,
    config.pageMemoryBarColor, config)
  screen.put(x, 4, "  Uptime: ", accent)
  screen.put(x + 10, 4, formatTimeString(host.upTimeMs), normal)

  screen.drawHeader(state, config)
  let visibleCount = max(0, screen.height - 8)
  for row in 0 ..< visibleCount:
    let processIndex = state.firstVisible + row
    let y = 6 + row
    if processIndex < state.processes.len:
      let formatted = formatProcessRow(state.processes[processIndex],
        state.sortType == stTree)
      screen.put(0, y, formatted[1 .. ^1],
        state.processAttribute(processIndex, config))

  let statusY = screen.height - 2
  screen.fill(0, statusY, screen.width, normal)
  if state.inputMode != imNormal:
    let caret = if state.caretVisible: "_" else: " "
    screen.put(0, statusY, state.inputText & caret, AttrForegroundWhite)
  elif state.message.len > 0:
    let attribute =
      if state.messageError: WORD(config.errorColor)
      else: AttrForegroundWhite
    screen.put(0, statusY, state.message, attribute)
  else:
    screen.put(0, statusY,
      "Up/Down:Move  Space:Tag  K:Kill tagged  I:Invert sort  q:Quit",
      AttrForegroundWhite)
