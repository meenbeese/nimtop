import std/unicode
import std/posix as posix
import posix/termios as posixTermios
import ntop/types as ntopTypes

const
  AttrForegroundBlue* = 0x0001'u16
  AttrForegroundGreen* = 0x0002'u16
  AttrForegroundRed* = 0x0004'u16
  AttrForegroundIntensity* = 0x0008'u16
  AttrForegroundWhite* =
    AttrForegroundRed or AttrForegroundGreen or AttrForegroundBlue
  AttrForegroundCyan* =
    AttrForegroundIntensity or AttrForegroundGreen or AttrForegroundBlue
  AttrBackgroundBlue* = 0x0010'u16
  AttrBackgroundGreen* = 0x0020'u16
  AttrBackgroundRed* = 0x0040'u16
  AttrBackgroundIntensity* = 0x0080'u16
  AttrBackgroundWhite* =
    AttrBackgroundRed or AttrBackgroundGreen or AttrBackgroundBlue
  AttrBackgroundCyan* =
    AttrBackgroundIntensity or AttrBackgroundGreen or AttrBackgroundBlue

  AttrDefault* = AttrForegroundWhite
  AttrMenu* = AttrForegroundWhite or AttrBackgroundBlue
  AttrHighlight* = AttrForegroundCyan or AttrBackgroundCyan
  AttrHeader* = AttrForegroundWhite or AttrBackgroundGreen
  AttrError* = AttrForegroundWhite or AttrBackgroundRed

  VkBack = 0x08
  VkReturn = 0x0D
  VkEscape = 0x1B
  VkPrior = 0x21
  VkNext = 0x22
  VkLeft = 0x25
  VkUp = 0x26
  VkRight = 0x27
  VkDown = 0x28
  VkF10 = 0x79

type
  Console* = object
    interactive*: bool
    width*: int
    height*: int
    sizeX*: int
    sizeY*: int
    savedAttributes*: uint16
    isTerminal: bool
    hasSavedTermios: bool
    suspended: bool
    restored: bool
    originalTermios: posixTermios.Termios

  ConsoleShutdownCallback* = proc() {.noconv.}

var currentAttributes = AttrDefault

func makeAttr*(foreground, background: uint16): uint16 {.inline.} =
  (foreground and 0x000F'u16) or (background and 0x00F0'u16)

proc posixError(operation: string): ref OSError =
  newException(OSError,
    operation & " failed: " & $posix.strerror(posix.errno))

func ansiColorIndex(mask: uint16): int =
  (if (mask and 0x0004'u16) != 0: 1 else: 0) +
  (if (mask and 0x0002'u16) != 0: 2 else: 0) +
  (if (mask and 0x0001'u16) != 0: 4 else: 0)

proc ansiColor(attribute: uint16): string =
  let foregroundMask = attribute and 0x0007'u16
  let backgroundMask = (attribute shr 4) and 0x0007'u16
  let foregroundCode =
    (if (attribute and AttrForegroundIntensity) != 0: 90 else: 30) +
    ansiColorIndex(foregroundMask)
  let backgroundCode =
    (if (attribute and AttrBackgroundIntensity) != 0: 100 else: 40) +
    ansiColorIndex(backgroundMask)
  "\x1b[" & $foregroundCode & ";" & $backgroundCode & "m"

proc isConsole*(c: Console): bool =
  c.isTerminal

proc setColor*(c: Console; attribute: uint16) =
  currentAttributes = attribute
  if c.isConsole():
    stdout.write(ansiColor(attribute))
    stdout.flushFile()

proc getColor*(c: Console): uint16 =
  currentAttributes

proc setCursorPos*(c: Console; x, y: int) =
  if c.isConsole():
    stdout.write("\x1b[" & $(max(0, y) + 1) & ";" &
      $(max(0, x) + 1) & "H")
    stdout.flushFile()

proc setCursorVisible(c: Console; visible: bool) =
  if c.isConsole():
    stdout.write(if visible: "\x1b[?25h" else: "\x1b[?25l")
    stdout.flushFile()

proc hideCursor*(c: Console) =
  c.setCursorVisible(false)

proc showCursor*(c: Console) =
  c.setCursorVisible(true)

proc setTitle*(c: Console; title: string) =
  if c.isConsole():
    stdout.write("\x1b]0;" & title & "\x07")
    stdout.flushFile()

proc refreshSize*(c: var Console): bool =
  if not c.isConsole():
    c.width = 80
    c.height = 25
    c.sizeX = c.width
    c.sizeY = c.height
    return false

  var windowSize: posixTermios.IOctl_WinSize
  if posixTermios.ioctl(posix.STDOUT_FILENO,
      posixTermios.TIOCGWINSZ, addr windowSize) == -1:
    return false

  let newWidth = max(1, int(windowSize.ws_col))
  let newHeight = max(1, int(windowSize.ws_row))
  result = newWidth != c.width or newHeight != c.height
  c.width = newWidth
  c.height = newHeight
  c.sizeX = newWidth
  c.sizeY = newHeight

proc clear*(c: Console; attribute: uint16 = AttrDefault) =
  if not c.isConsole():
    return
  c.setColor(attribute)
  stdout.write("\x1b[2J\x1b[H")
  stdout.flushFile()

proc clearRow*(c: Console; y: int; attribute: uint16 = AttrDefault) =
  if not c.isConsole() or y < 0 or y >= c.height:
    return
  c.setColor(attribute)
  c.setCursorPos(0, y)
  stdout.write("\x1b[2K")
  stdout.flushFile()

proc write*(c: Console; text: string) =
  if text.len == 0:
    return
  stdout.write(text)
  stdout.flushFile()

proc writeColor*(c: Console; text: string; attribute: uint16) =
  c.setColor(attribute)
  c.write(text)

proc writeAt*(c: Console; x, y: int; text: string; attribute: uint16) =
  if not c.isConsole():
    c.write(text)
    return
  c.setCursorPos(x, y)
  c.writeColor(text, attribute)

proc writeCentered*(c: Console; y: int; text: string; attribute: uint16) =
  if not c.isConsole():
    c.write(text)
    return
  c.writeAt(max(0, (c.width - text.runeLen) div 2), y, text, attribute)

proc flushInput*(c: Console) =
  if c.isConsole():
    discard posixTermios.tcFlush(posix.STDIN_FILENO, posixTermios.TCIFLUSH)

proc waitForInput(timeoutMs: int): bool =
  var descriptor = posix.TPollfd(
    fd: posix.STDIN_FILENO,
    events: posix.POLLIN,
    revents: 0
  )
  let timeout =
    if timeoutMs < 0: -1
    else: min(timeoutMs, int(high(cint)))
  let status = posix.poll(addr descriptor, posix.Tnfds(1), cint(timeout))
  if status < 0:
    if posix.errno == posix.EINTR:
      return false
    raise posixError("poll")
  status > 0 and (descriptor.revents and posix.POLLIN) != 0

proc readByte(value: var char): bool =
  let count = posix.read(posix.STDIN_FILENO, addr value, 1)
  if count == 1:
    return true
  if count < 0 and posix.errno != posix.EINTR:
    raise posixError("read")

proc readEscapeSequence(): string =
  while result.len < 12 and waitForInput(30):
    var value: char
    if not readByte(value):
      break
    result.add(value)

proc setKey(key: var ntopTypes.Key; value: int; control = false) =
  key.vk = value
  key.ctrl = control
  key.keyDown = true
  key.repeatCount = 1

proc readCharacter(key: var ntopTypes.Key; first: char) =
  let leading = ord(first) and 0xFF
  let expectedLength =
    if leading < 0x80: 1
    elif (leading and 0xE0) == 0xC0: 2
    elif (leading and 0xF0) == 0xE0: 3
    elif (leading and 0xF8) == 0xF0: 4
    else: 1
  var text = $first
  for _ in 1 ..< expectedLength:
    if not waitForInput(30):
      break
    var next: char
    if not readByte(next):
      break
    text.add(next)
  for rune in text.runes:
    key.ch = rune
    key.vk = int(rune)
    break
  key.keyDown = true
  key.repeatCount = 1

proc tryReadKey*(c: Console; key: var ntopTypes.Key; timeoutMs: int): bool =
  if not c.isConsole():
    raise newException(IOError, "tryReadKey requires an interactive terminal")
  if not waitForInput(timeoutMs):
    return false

  var value: char
  if not readByte(value):
    return false
  if value == '\x1b':
    let sequence = readEscapeSequence()
    case sequence
    of "[A": key.setKey(VkUp)
    of "[B": key.setKey(VkDown)
    of "[C": key.setKey(VkRight)
    of "[D": key.setKey(VkLeft)
    of "[1;5C": key.setKey(VkRight, true)
    of "[1;5D": key.setKey(VkLeft, true)
    of "[5~": key.setKey(VkPrior)
    of "[6~": key.setKey(VkNext)
    of "[21~": key.setKey(VkF10)
    else: key.setKey(VkEscape)
    return true

  case value
  of '\r', '\n':
    key.setKey(VkReturn)
  of '\x08', '\x7f':
    key.setKey(VkBack)
  else:
    key.readCharacter(value)
    if ord(value) in 1 .. 26:
      key.ctrl = true
      key.ch = Rune(ord('a') + ord(value) - 1)
      key.vk = int(key.ch)
  true

proc readKey*(c: Console): ntopTypes.Key =
  if not c.isConsole():
    raise newException(IOError, "readKey requires an interactive terminal")
  while not c.tryReadKey(result, -1):
    discard

proc setRawMode(c: var Console; enabled: bool) =
  if not c.hasSavedTermios:
    return
  if enabled:
    var raw = c.originalTermios
    raw.c_lflag = raw.c_lflag and
      not (posixTermios.ICANON or posixTermios.ECHO)
    raw.c_iflag = raw.c_iflag and not
      (posixTermios.IXON or posixTermios.ICRNL)
    raw.c_cc[int(posixTermios.VMIN)] = char(0)
    raw.c_cc[int(posixTermios.VTIME)] = char(0)
    if posixTermios.tcSetAttr(posix.STDIN_FILENO,
        posixTermios.TCSANOW, addr raw) == -1:
      raise posixError("tcsetattr")
  elif posixTermios.tcSetAttr(posix.STDIN_FILENO,
      posixTermios.TCSANOW, addr c.originalTermios) == -1:
    raise posixError("tcsetattr")

proc initConsole*(interactive = true): Console =
  result.interactive = interactive
  currentAttributes = AttrDefault
  result.isTerminal =
    posix.isatty(posix.STDIN_FILENO) != 0 and
    posix.isatty(posix.STDOUT_FILENO) != 0
  result.width = 80
  result.height = 25
  result.sizeX = result.width
  result.sizeY = result.height
  if interactive and not result.isTerminal:
    raise newException(IOError, "interactive mode requires a terminal")

  if interactive:
    if posixTermios.tcGetAttr(posix.STDIN_FILENO,
        addr result.originalTermios) == -1:
      raise posixError("tcgetattr")
    result.hasSavedTermios = true
    result.setRawMode(true)
    stdout.write("\x1b[?1049h")
    stdout.flushFile()
    discard result.refreshSize()
    result.hideCursor()

proc restore*(c: var Console) =
  if not c.interactive or c.restored:
    return
  c.restored = true
  if c.suspended:
    c.setRawMode(false)
  else:
    stdout.write("\x1b[0m\x1b[?25h\x1b[?1049l")
    stdout.flushFile()
    if c.hasSavedTermios:
      discard posixTermios.tcSetAttr(posix.STDIN_FILENO,
        posixTermios.TCSANOW, addr c.originalTermios)

proc suspendConsole*(c: var Console) =
  if not c.interactive or c.suspended:
    return
  stdout.write("\x1b[0m\x1b[?25h\x1b[?1049l")
  stdout.flushFile()
  c.setRawMode(false)
  c.suspended = true

proc resumeConsole*(c: var Console) =
  if not c.interactive or not c.suspended:
    return
  c.setRawMode(true)
  stdout.write("\x1b[?1049h")
  stdout.flushFile()
  c.suspended = false
  discard c.refreshSize()
  c.hideCursor()

proc `$`*(key: ntopTypes.Key): string =
  result = "vk=" & $key.vk
  if key.ch != Rune(0):
    result.add(" ch=" & $key.ch)
