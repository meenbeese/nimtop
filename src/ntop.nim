# NTop — an htop-like system monitor for Windows.
# Copyright (c) 2019 Gian Sass
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

## NTop — Nim port.
##
## Phase 2 entry point: non-interactive process acquisition is implemented;
## interactive mode still uses the Phase 0 console bootstrap screen.

import std/[exitprocs, os, strutils, unicode]
import winim
import ntop/[console, cli, processes, processformat, sorting, sysinfo, types,
  version]

var gConsole: Console

proc restoreConsole() {.noconv.} =
  gConsole.restore()

proc consoleCtrlHandler(ctrlType: DWORD): WINBOOL {.stdcall.} =
  ## Restore the original buffer before the process goes away.
  gConsole.restore()
  ExitProcess(0)
  return TRUE

func center(text: string; width: int): string =
  let padding = max(0, (width - text.runeLen) div 2)
  spaces(padding) & text

func truncateRunes(text: string; width: int): string =
  if width <= 0:
    return ""
  var count = 0
  for rune in text.runes:
    if count >= width:
      break
    result.add($rune)
    inc count

func fit(text: string; width: int): string =
  let length = text.runeLen
  if length >= width:
    truncateRunes(text, width)
  else:
    text & spaces(width - length)

proc drawRow(con: Console; y: int; text: string; attr: WORD) =
  if y < 0 or y >= con.height:
    return
  con.writeAt(0, y, fit(text, con.width), attr)

proc printHelp() =
  echo helpText()

proc runHeadless(sortType: SortType; filters: Filters) =
  discard initSystemInfo()
  let snapshot = acquireProcessList(1000, filters)
  var processes = snapshot.processes
  sortProcesses(processes, sortType)
  stdout.write(ProcessTableHeader)
  for process in processes:
    stdout.write(formatProcessRow(process, sortType == stTree))
  stdout.write("\n")

proc runSmoke() =
  gConsole = initConsole(interactive = true)
  addExitProc(restoreConsole)
  discard SetConsoleCtrlHandler(consoleCtrlHandler, WINBOOL(1))
  defer:
    gConsole.restore()

  discard gConsole.refreshSize()
  let width = max(gConsole.width, 1)
  let height = max(gConsole.height, 1)

  gConsole.setTitle("NTop " & NTopVersion & " — Nim bootstrap")
  gConsole.clear(AttrDefault)

  drawRow(gConsole, 0,
    center(" NTop " & versionString() & " — Phase 0 console bootstrap ", width),
    AttrMenu)
  drawRow(gConsole, 1, "", AttrDefault)

  drawRow(gConsole, 2, "  Console layer", AttrHeader)
  drawRow(gConsole, 3, "    Screen buffer : alternative buffer created and activated", AttrDefault)
  drawRow(gConsole, 4, "    Terminal size : " & $width & " x " & $height, AttrDefault)
  drawRow(gConsole, 5,
    "    Unicode       : Ünïcödé ✓ 日本語 — written via WriteConsoleW", AttrDefault)
  drawRow(gConsole, 6, "", AttrDefault)

  gConsole.writeAt(2, 7, "  Colors: ", AttrDefault)
  var x = 12
  const swatches = [
    (" NORMAL ", AttrDefault),
    (" HIGHLIGHT ", AttrHighlight),
    (" HEADER ", AttrHeader),
    (" ERROR ", AttrError),
  ]
  for (text, attr) in swatches:
    gConsole.writeAt(x, 7, text, attr)
    x += text.runeLen

  drawRow(gConsole, 9, "  Process table preview", AttrHeader)
  drawRow(gConsole, 10,
    "      ID  USER       PRI  CPU%          MEM  THRD       DISK         TIME  PROCESS",
    AttrHeader)
  drawRow(gConsole, 11,
    "    1234  kuz          8  01.2%     12.3 MB     4     0.0 MB/s  00:00:01:23  explorer.exe",
    AttrDefault)
  drawRow(gConsole, 12,
    "    1235  kuz          8  00.4%      4.1 MB     2     0.0 MB/s  00:00:00:41  `- child.exe",
    AttrDefault)

  drawRow(gConsole, height - 2, "", AttrHighlight)
  gConsole.writeCentered(height - 2,
    " Press any key to restore the original console buffer ", AttrHighlight)

  discard gConsole.readKey()

when isMainModule:
  var args: seq[string]
  for i in 1 .. paramCount():
    args.add(paramStr(i))
  let parsedCli = parseCli(args)

  if parsedCli.kind == ckHelp:
    printHelp()
  elif parsedCli.kind == ckVersion:
    echo versionString()
  elif parsedCli.kind == ckError:
    stderr.writeLine(parsedCli.message)
    quit(1)
  elif not parsedCli.interactive:
    let sortType =
      if parsedCli.sortColumnSet: parsedCli.sortColumn else: stId
    try:
      runHeadless(sortType, parsedCli.filters)
    except OSError as error:
      stderr.writeLine(error.msg)
      quit(1)
  else:
    runSmoke()
