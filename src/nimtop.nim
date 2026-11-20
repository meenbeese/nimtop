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
## nimtop entry point and interactive application loop.

import std/[exitprocs, locks, os, strutils]
import ntop/[cli, config, console, input, platform, processformat, render,
  search, sorting, types, version, vi]

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
  stdout.write(formatProcessTable(processes, sortType == stTree))

proc killTaggedProcesses(state: var UiState) =
  var failures: seq[string]
  for pid in state.tagged:
    if not terminateProcess(pid).success:
      failures.add($pid)

  state.tagged.setLen(0)
  if failures.len > 0:
    state.message = "Could not terminate process IDs: " & failures.join(", ")
    state.messageError = true
  else:
    state.message = "Tagged processes terminated"
    state.messageError = false

proc showViMessage(state: var UiState; message: ViMessage) =
  state.message = message.text
  state.messageError = message.kind == vmError

proc executeViCommand(state: var UiState; command: ViCommand;
                      visibleCount: int): bool =
  case command.kind
  of vcExec:
    if command.args.len == 0:
      state.showViMessage(ViMessage(text: "Usage: exec COMMAND",
        kind: vmError))
      return

    let error = startCommand(command.args.join(" "), gConsole)
    if error.len > 0:
      state.showViMessage(ViMessage(text: error, kind: vmError))
      return

  of vcKill:
    if command.args.len == 0:
      state.showViMessage(ViMessage(text: "Usage: kill PID(s)",
        kind: vmError))
      return

    var failures: seq[string]
    for pidText in command.args:
      var pid: uint64
      try:
        pid = parseBiggestUInt(pidText)
      except ValueError:
        failures.add("Not a valid pid: " & pidText)
        continue
      if pid == 0 or pid > uint64(high(uint32)):
        failures.add("Not a valid pid: " & pidText)
        continue

      let termination = terminateProcess(uint32(pid))
      if not termination.opened:
        failures.add("Could not open process: " & $pid &
          " (" & termination.error & ")")
        continue
      if not termination.success:
        failures.add("Failed to kill process: " & $pid &
          " (" & termination.error & ")")

    if failures.len > 0:
      state.showViMessage(ViMessage(text: failures.join("; "), kind: vmError))

  of vcQuit:
    return true

  of vcSort:
    if command.args.len != 1:
      state.showViMessage(ViMessage(text: "Usage: sort COLUMN",
        kind: vmError))
      return
    var sortType: SortType
    if not sortTypeFromName(command.args[0], sortType):
      state.showViMessage(ViMessage(
        text: "Unknown column: " & command.args[0], kind: vmError))
      return
    state.setSort(sortType, visibleCount)

  of vcTree:
    if command.args.len != 0:
      state.showViMessage(ViMessage(text: "Error: trailing characters",
        kind: vmError))
      return
    state.setSort(stTree, visibleCount)

  of vcSearch:
    if command.args.len != 1:
      state.showViMessage(ViMessage(text: "Usage: search pattern",
        kind: vmError))
      return
    if command.args[0].len > 0:
      state.startSearch(command.args[0], visibleCount)

proc executeViInput(state: var UiState; inputLine: string;
                    visibleCount: int): bool =
  let parsed = parseViCommand(inputLine)
  if not parsed.success:
    state.showViMessage(parsed.message)
    return
  state.executeViCommand(parsed.command, visibleCount)

proc runInteractive(sortType: SortType; filters: Filters; config: Config;
                    maxIterations: uint64; maxIterationsSet: bool) =
  gConsole = initConsole(interactive = true)
  addExitProc(restoreConsole)
  registerConsoleControlHandler(restoreConsole)
  defer:
    gConsole.restore()

  discard gConsole.refreshSize()
  gConsole.setTitle("nimtop " & NTopVersion)
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
  var lastSystemPoll = monotonicTimeMs()
  var lastCaretToggle = lastSystemPoll
  var lastPollError = ""
  let systemPollInterval = max(1'u64, config.redrawInterval)
  var dirty = true
  var quitRequested = false
  var renderedUpdates = 0'u64
  gConsole.flushInput()

  while not quitRequested:
    if shutdownRequested():
      break
    if gConsole.refreshSize():
      state.ensureUiVisible(max(0, gConsole.height - 8))
      screen = initScreen(gConsole.width, gConsole.height,
        uint16(config.fgColor or config.bgColor))
      dirty = true

    var key: Key
    if gConsole.tryReadKey(key, 50):
      if key.keyDown:
        case state.handleKey(key, max(0, gConsole.height - 8),
            monotonicTimeMs())
        of iaQuit:
          quitRequested = true
        of iaKillTagged:
          state.killTaggedProcesses()
        of iaSubmitCommand, iaSubmitSearch:
          let submittedText = state.submittedText
          state.submittedText.setLen(0)
          if state.executeViInput(submittedText,
              max(0, gConsole.height - 8)):
            quitRequested = true
        of iaSearchNext:
          state.moveSearch(sdNext, max(0, gConsole.height - 8))
        of iaSearchPrevious:
          state.moveSearch(sdPrevious, max(0, gConsole.height - 8))
        of iaNone:
          discard
        dirty = true
      else:
        discard state.handleKey(key, max(0, gConsole.height - 8),
          monotonicTimeMs())

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

    let now = monotonicTimeMs()
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
      inc renderedUpdates
      if maxIterationsSet and renderedUpdates >= maxIterations:
        quitRequested = true

when isMainModule:
  var args: seq[string]
  for i in 1 .. paramCount():
    args.add(paramStr(i))
  let parsedCli = parseCli(args)

  if parsedCli.kind == ckHelp:
    if parsedCli.message.len > 0:
      stdout.write(parsedCli.message)
    else:
      printHelp()
  elif parsedCli.kind == ckVersion:
    echo versionString()
  elif parsedCli.kind == ckError:
    stderr.writeLine(parsedCli.message)
    quit(1)
  else:
    let sortType = if parsedCli.sortColumnSet: parsedCli.sortColumn else: stId
    var filters = parsedCli.filters
    when defined(windows):
      if filters.filterByUserId:
        stderr.writeLine("Filtering by numeric user ID is not supported on Windows")
        quit(1)
    if filters.filterByCurrentUser:
      filters.userName = currentUserName()
      filters.filterByCurrentUser = false
      filters.filterByUser = true
    var appConfig =
      if parsedCli.monochrome: monochromeConfig() else: defaultConfig()
    if not parsedCli.monochrome:
      readConfigFile(configPath(getAppFilename()), appConfig)
    try:
      if not parsedCli.interactive:
        runHeadless(sortType, filters)
      else:
        runInteractive(sortType, filters, appConfig, parsedCli.maxIterations,
          parsedCli.maxIterationsSet)
    except OSError as error:
      stderr.writeLine(error.msg)
      quit(1)
