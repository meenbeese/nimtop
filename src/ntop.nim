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
## NTop entry point and interactive application loop.

import std/[exitprocs, locks, os, strutils]
import winim
import ntop/[cli, config, console, input, processes, processformat, render,
  sorting, sysinfo, types, version]

var gConsole: Console

type
  PollerContext = object
    lock: Lock
    stopped: bool
    generation: uint64
    snapshot: ProcessSnapshot
    error: string
    filters: Filters

proc restoreConsole() {.noconv.} =
  gConsole.restore()

proc consoleCtrlHandler(ctrlType: DWORD): WINBOOL {.stdcall.} =
  ## Restore the original buffer before the process goes away.
  gConsole.restore()
  ExitProcess(0)
  return TRUE

proc printHelp() =
  echo helpText()

proc pollerMain(context: ptr PollerContext) {.thread.} =
  while true:
    var stopped: bool
    withLock context.lock:
      stopped = context.stopped
    if stopped:
      break

    try:
      let snapshot = acquireProcessList(1000, context.filters)
      withLock context.lock:
        context.snapshot = snapshot
        context.error.setLen(0)
        inc context.generation
    except OSError as error:
      withLock context.lock:
        context.error = error.msg
        inc context.generation
      sleep(1000)

proc runHeadless(sortType: SortType; filters: Filters) =
  discard initSystemInfo()
  let snapshot = acquireProcessList(1000, filters)
  var processes = snapshot.processes
  sortProcesses(processes, sortType)
  stdout.write(ProcessTableHeader)
  for process in processes:
    stdout.write(formatProcessRow(process, sortType == stTree))
  stdout.write("\n")

proc killTaggedProcesses(state: var UiState) =
  var failures: seq[string]
  for pid in state.tagged:
    let processHandle = OpenProcess(DWORD(PROCESS_TERMINATE), WINBOOL(0),
      DWORD(pid))
    if processHandle == 0 or processHandle == INVALID_HANDLE_VALUE:
      failures.add($pid)
      continue
    if TerminateProcess(processHandle, DWORD(9)) == 0:
      failures.add($pid)
    discard CloseHandle(processHandle)

  state.tagged.setLen(0)
  if failures.len > 0:
    state.message = "Could not terminate process IDs: " & failures.join(", ")
    state.messageError = true
  else:
    state.message = "Tagged processes terminated"
    state.messageError = false

proc runInteractive(sortType: SortType; filters: Filters; config: Config) =
  gConsole = initConsole(interactive = true)
  addExitProc(restoreConsole)
  discard SetConsoleCtrlHandler(consoleCtrlHandler, WINBOOL(1))
  defer:
    gConsole.restore()

  discard gConsole.refreshSize()
  gConsole.setTitle("NTop " & NTopVersion)
  gConsole.hideCursor()
  let visibleCount = max(0, gConsole.height - 8)

  var host = initSystemInfo()
  var state = initUiState(sortType, soDescending)
  state.setProcesses(acquireProcessList(50, filters), visibleCount)

  var poller = PollerContext(filters: filters)
  initLock(poller.lock)
  var worker: Thread[ptr PollerContext]
  createThread(worker, pollerMain, addr poller)
  defer:
    withLock poller.lock:
      poller.stopped = true
    joinThread(worker)
    deinitLock(poller.lock)

  var screen = initScreen(gConsole.width, gConsole.height, AttrDefault)
  var generation = 0'u64
  var lastSystemPoll = uint64(GetTickCount64())
  var lastCaretToggle = lastSystemPoll
  var lastPollError = ""
  let systemPollInterval = max(1'u64, config.redrawInterval)
  var dirty = true
  var quitRequested = false
  gConsole.flushInput()

  while not quitRequested:
    if gConsole.refreshSize():
      state.ensureUiVisible(max(0, gConsole.height - 8))
      screen = initScreen(gConsole.width, gConsole.height,
        WORD(config.fgColor or config.bgColor))
      dirty = true

    var key: Key
    if gConsole.tryReadKey(key, DWORD(50)):
      if key.keyDown:
        case state.handleKey(key, max(0, gConsole.height - 8),
            uint64(GetTickCount64()))
        of iaQuit:
          quitRequested = true
        of iaKillTagged:
          state.killTaggedProcesses()
        of iaNone:
          discard
        dirty = true
      else:
        discard state.handleKey(key, max(0, gConsole.height - 8),
          uint64(GetTickCount64()))

    var updatedSnapshot: ProcessSnapshot
    var pollError: string
    var hasUpdate = false
    withLock poller.lock:
      if poller.generation != generation:
        generation = poller.generation
        updatedSnapshot = poller.snapshot
        pollError = poller.error
        hasUpdate = true
    if hasUpdate:
      if pollError.len > 0:
        state.message = pollError
        state.messageError = true
        lastPollError = pollError
      else:
        state.setProcesses(updatedSnapshot,
          max(0, gConsole.height - 8))
        if lastPollError.len > 0 and state.message == lastPollError:
          state.message.setLen(0)
          state.messageError = false
        lastPollError.setLen(0)
      dirty = true

    let now = uint64(GetTickCount64())
    if now - lastSystemPoll >= systemPollInterval:
      host.pollSystemInfo()
      lastSystemPoll = now
      dirty = true
    if state.inputMode != imNormal and now - lastCaretToggle >= 500:
      state.caretVisible = not state.caretVisible
      lastCaretToggle = now
      dirty = true

    if dirty:
      screen.render(state, host, config)
      screen.flush(gConsole)
      dirty = false

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
  else:
    let sortType = if parsedCli.sortColumnSet: parsedCli.sortColumn else: stId
    var appConfig =
      if parsedCli.monochrome: monochromeConfig() else: defaultConfig()
    if not parsedCli.monochrome:
      readConfigFile(configPath(getAppFilename()), appConfig)
    try:
      if not parsedCli.interactive:
        runHeadless(sortType, parsedCli.filters)
      else:
        runInteractive(sortType, parsedCli.filters, appConfig)
    except OSError as error:
      stderr.writeLine(error.msg)
      quit(1)
