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

## Thin Win32 console wrapper for the Nim port.
##
## This is the only module that talks to the Win32 console API. Everything above
## this layer works with UTF-8 Nim strings; conversion to UTF-16 happens at the
## `WriteConsoleW` / `SetConsoleTitleW` boundary.
##
## The wrapper owns an alternative console screen buffer when `interactive` is
## true, mirroring the C implementation. `restore` puts the original buffer
## back and is idempotent, so it is safe to call from `defer`, `addExitProc`,
## and a console control handler.

when not defined(windows):
  {.error: "NTop's console layer is Windows-only.".}

import std/unicode
import winim

const
  # Console attribute bits. Kept as WORD constants so they compose with the
  # color values parsed from ntop.conf.
  AttrForegroundBlue* = WORD(FOREGROUND_BLUE)
  AttrForegroundGreen* = WORD(FOREGROUND_GREEN)
  AttrForegroundRed* = WORD(FOREGROUND_RED)
  AttrForegroundIntensity* = WORD(FOREGROUND_INTENSITY)
  AttrForegroundWhite* = WORD(FOREGROUND_RED or FOREGROUND_GREEN or FOREGROUND_BLUE)
  AttrForegroundCyan* = WORD(FOREGROUND_INTENSITY or FOREGROUND_GREEN or FOREGROUND_BLUE)
  AttrBackgroundBlue* = WORD(BACKGROUND_BLUE)
  AttrBackgroundGreen* = WORD(BACKGROUND_GREEN)
  AttrBackgroundRed* = WORD(BACKGROUND_RED)
  AttrBackgroundIntensity* = WORD(BACKGROUND_INTENSITY)
  AttrBackgroundWhite* =
    WORD(BACKGROUND_RED or BACKGROUND_GREEN or BACKGROUND_BLUE)
  AttrBackgroundCyan* =
    WORD(BACKGROUND_INTENSITY or BACKGROUND_GREEN or BACKGROUND_BLUE)

  AttrDefault* = AttrForegroundWhite
  AttrMenu* = AttrForegroundWhite or AttrBackgroundBlue
  AttrHighlight* = AttrForegroundCyan or AttrBackgroundCyan
  AttrHeader* = AttrForegroundWhite or AttrBackgroundGreen
  AttrError* = AttrForegroundWhite or AttrBackgroundRed

  GenericReadWrite = DWORD(GENERIC_READ) or DWORD(GENERIC_WRITE)

type
  Key* = object
    ## A single key-down console event.
    vk*: int
    ch*: Rune
    ctrl*: bool

  Console* = object
    handle*: HANDLE          ## Active output handle.
    previousHandle*: HANDLE  ## Original stdout, restored on shutdown.
    inputHandle*: HANDLE
    interactive*: bool
    savedAttributes*: WORD
    width*: int              ## Visible window width.
    height*: int             ## Visible window height.
    sizeX*: int              ## Screen-buffer width.
    sizeY*: int              ## Screen-buffer height.

func makeAttr*(foreground, background: WORD): WORD {.inline.} =
  ## Combines foreground and background console attribute bits.
  (foreground and WORD(0x0F)) or (background and WORD(0xF0))

proc winCheck(ok: WINBOOL; what: string) =
  if ok == 0:
    raise newException(OSError,
      what & " failed (Win32 error " & $GetLastError() & ")")

proc isConsole*(c: Console): bool =
  ## Returns true when the active output handle is a real console.
  var mode: DWORD
  GetConsoleMode(c.handle, addr mode) != 0

proc setColor*(c: Console; attr: WORD) =
  if not c.isConsole():
    return
  discard SetConsoleTextAttribute(c.handle, attr)

proc getColor*(c: Console): WORD =
  ## Returns the current console text attributes, or the default on failure.
  if not c.isConsole():
    return AttrDefault
  var info: CONSOLE_SCREEN_BUFFER_INFO
  if GetConsoleScreenBufferInfo(c.handle, addr info) == 0:
    return AttrDefault
  info.wAttributes

proc setCursorPos*(c: Console; x, y: int) =
  if not c.isConsole():
    return
  let position = COORD(X: SHORT(x), Y: SHORT(y))
  discard SetConsoleCursorPosition(c.handle, position)

proc hideCursor*(c: Console) =
  if not c.isConsole():
    return
  var info: CONSOLE_CURSOR_INFO
  if GetConsoleCursorInfo(c.handle, addr info) != 0:
    info.bVisible = WINBOOL(0)
    discard SetConsoleCursorInfo(c.handle, addr info)

proc showCursor*(c: Console) =
  if not c.isConsole():
    return
  var info: CONSOLE_CURSOR_INFO
  if GetConsoleCursorInfo(c.handle, addr info) != 0:
    info.bVisible = WINBOOL(1)
    discard SetConsoleCursorInfo(c.handle, addr info)

proc setTitle*(c: Console; title: string) =
  if not c.isConsole():
    return
  var wide = newWideCString(title)
  discard SetConsoleTitleW(cast[LPCWSTR](addr wide[0]))

proc refreshSize*(c: var Console): bool =
  ## Refreshes the visible window/buffer dimensions.
  ##
  ## Returns true when the visible window changed because the console was
  ## resized. Interactive consoles also resize their screen buffer to match the
  ## window, as the C implementation does.
  if not c.isConsole():
    c.width = 80
    c.height = 25
    c.sizeX = 80
    c.sizeY = 25
    return false

  var info: CONSOLE_SCREEN_BUFFER_INFO
  if GetConsoleScreenBufferInfo(c.handle, addr info) == 0:
    return false

  let newWidth = int(info.srWindow.Right) - int(info.srWindow.Left) + 1
  let newHeight = int(info.srWindow.Bottom) - int(info.srWindow.Top) + 1

  c.sizeX = int(info.dwSize.X)
  c.sizeY = int(info.dwSize.Y)
  if c.savedAttributes == 0:
    c.savedAttributes = info.wAttributes

  result = newWidth != c.width or newHeight != c.height
  if result:
    c.width = newWidth
    c.height = newHeight
    if c.interactive:
      let bufferSize = COORD(X: SHORT(newWidth), Y: SHORT(newHeight))
      if SetConsoleScreenBufferSize(c.handle, bufferSize) != 0:
        # The buffer now matches the window; keep `clear` within bounds.
        c.sizeX = newWidth
        c.sizeY = newHeight
      c.hideCursor()

proc clear*(c: Console; attr: WORD = AttrDefault) =
  ## Fills the whole screen buffer with spaces and the given attributes.
  if not c.isConsole():
    return
  var info: CONSOLE_SCREEN_BUFFER_INFO
  var sizeX = c.sizeX
  var sizeY = c.sizeY
  if GetConsoleScreenBufferInfo(c.handle, addr info) != 0:
    sizeX = int(info.dwSize.X)
    sizeY = int(info.dwSize.Y)
  let cells = DWORD(max(0, sizeX) * max(0, sizeY))
  if cells == 0:
    return
  var written: DWORD
  let origin = COORD(X: 0, Y: 0)
  discard FillConsoleOutputCharacterW(c.handle, WCHAR(ord(' ')), cells,
    origin, addr written)
  discard FillConsoleOutputAttribute(c.handle, attr, cells, origin, addr written)
  c.setCursorPos(0, 0)

proc write*(c: Console; text: string) =
  ## Writes UTF-8 text without changing the current attributes.
  if text.len == 0:
    return
  if not c.isConsole():
    stdout.write(text)
    stdout.flushFile()
    return

  var wide = newWideCString(text)
  var written: DWORD
  winCheck(WriteConsoleW(c.handle, cast[pointer](addr wide[0]),
    DWORD(wide.len), addr written, nil), "WriteConsoleW")

proc writeColor*(c: Console; text: string; attr: WORD) =
  c.setColor(attr)
  c.write(text)

proc writeAt*(c: Console; x, y: int; text: string; attr: WORD) =
  ## Writes text at an absolute position with the given attributes.
  if not c.isConsole():
    c.write(text)
    return
  c.setCursorPos(x, y)
  c.writeColor(text, attr)

proc writeCentered*(c: Console; y: int; text: string; attr: WORD) =
  if not c.isConsole():
    c.write(text)
    return
  let x = max(0, (c.width - text.runeLen) div 2)
  c.writeAt(x, y, text, attr)

proc flushInput*(c: Console) =
  discard FlushConsoleInputBuffer(c.inputHandle)

proc readKey*(c: Console): Key =
  ## Blocks until the next key-down event and returns it.
  ##
  ## Console control keys (Ctrl+C, etc.) are processed by the system because
  ## the input mode keeps `ENABLE_PROCESSED_INPUT` enabled.
  if not c.isConsole():
    raise newException(IOError, "readKey requires an interactive console")

  var record: INPUT_RECORD
  var count: DWORD
  while true:
    winCheck(ReadConsoleInputW(c.inputHandle, addr record, 1, addr count),
      "ReadConsoleInputW")
    if record.EventType == WORD(KEY_EVENT) and
        record.Event.KeyEvent.bKeyDown != 0:
      let key = record.Event.KeyEvent
      result.vk = int(key.wVirtualKeyCode)
      result.ch = Rune(key.uChar.UnicodeChar)
      result.ctrl = (key.dwControlKeyState and
        DWORD(LEFT_CTRL_PRESSED or RIGHT_CTRL_PRESSED)) != 0
      return

proc initConsole*(interactive = true): Console =
  ## Creates (or adopts) the console screen buffer used by NTop.
  result.interactive = interactive
  result.inputHandle = GetStdHandle(STD_INPUT_HANDLE)
  result.previousHandle = GetStdHandle(STD_OUTPUT_HANDLE)
  result.handle = result.previousHandle

  if result.previousHandle == 0 or
      result.previousHandle == INVALID_HANDLE_VALUE:
    raise newException(OSError, "GetStdHandle(STD_OUTPUT_HANDLE) failed")

  # Remember the original console attributes so restore() can put them back.
  var previousInfo: CONSOLE_SCREEN_BUFFER_INFO
  if GetConsoleScreenBufferInfo(result.previousHandle, addr previousInfo) != 0:
    result.savedAttributes = previousInfo.wAttributes

  if interactive:
    let buffer = CreateConsoleScreenBuffer(
      GenericReadWrite,
      DWORD(FILE_SHARE_READ or FILE_SHARE_WRITE),
      nil,
      DWORD(CONSOLE_TEXTMODE_BUFFER),
      nil)
    if buffer == INVALID_HANDLE_VALUE or buffer == 0:
      raise newException(OSError,
        "CreateConsoleScreenBuffer failed (Win32 error " & $GetLastError() & ")")

    result.handle = buffer
    if SetConsoleActiveScreenBuffer(result.handle) == 0:
      raise newException(OSError,
        "SetConsoleActiveScreenBuffer failed (Win32 error " &
        $GetLastError() & ")")
    discard SetConsoleMode(result.handle,
      DWORD(ENABLE_PROCESSED_INPUT or ENABLE_WRAP_AT_EOL_OUTPUT))

  discard result.refreshSize()

proc restore*(c: var Console) =
  ## Restores the original console screen buffer. Safe to call more than once.
  if not c.interactive:
    return
  let previous = c.previousHandle
  c.previousHandle = 0
  if previous != 0 and previous != INVALID_HANDLE_VALUE:
    if c.savedAttributes != 0:
      discard SetConsoleTextAttribute(previous, c.savedAttributes)
    discard SetConsoleActiveScreenBuffer(previous)

proc `$`*(key: Key): string =
  result = "vk=" & $key.vk
  if key.ch != Rune(0):
    result.add(" ch=" & $key.ch)
