import std/[strutils, unicode]

type
  ViCommandKind* = enum
    vcExec, vcKill, vcQuit, vcSort, vcTree, vcSearch

  ViMessageKind* = enum
    vmNotice, vmError

  ViMessage* = object
    text*: string
    kind*: ViMessageKind

  ViCommand* = object
    kind*: ViCommandKind
    args*: seq[string]

  TokenizeResult* = object
    success*: bool
    name*: string
    args*: seq[string]

  ViParseResult* = object
    success*: bool
    command*: ViCommand
    message*: ViMessage

  ViHistory* = object
    entries: seq[string]
    index: int

const commandNames: array[7, tuple[name: string, kind: ViCommandKind]] = [
  ("exec", vcExec),
  ("kill", vcKill),
  ("q", vcQuit),
  ("quit", vcQuit),
  ("sort", vcSort),
  ("tree", vcTree),
  ("search", vcSearch)
]

func isNameCharacter(character: Rune): bool {.inline.} =
  character.isAlpha() or ord(character) in ord('0') .. ord('9')

func isArgumentCharacter(character: Rune): bool {.inline.} =
  character.isNameCharacter() or character in [Rune(ord('%')), Rune(ord('/')),
    Rune(ord('.'))]

func asString(characters: openArray[Rune]; first, pastLast: int): string =
  for i in first ..< pastLast:
    result.add($characters[i])

proc tokenizeCommandLine*(line: string): TokenizeResult =
  let characters = toRunes(line)
  var index = 0

  while index < characters.len and characters[index].isWhiteSpace():
    inc index

  let nameStart = index
  while index < characters.len and characters[index].isNameCharacter():
    inc index
  result.name = asString(characters, nameStart, index)
  if index < characters.len and not characters[index].isWhiteSpace():
    return

  while index < characters.len:
    while index < characters.len and characters[index].isWhiteSpace():
      inc index
    if index >= characters.len:
      break

    var argument = ""
    if characters[index] == Rune(ord('"')):
      inc index
      var closed = false
      while index < characters.len:
        if characters[index] == Rune(ord('"')):
          inc index
          closed = true
          break
        if not characters[index].isWhiteSpace() and
            not characters[index].isArgumentCharacter():
          return
        argument.add($characters[index])
        inc index
      if not closed:
        return
      if index < characters.len and not characters[index].isWhiteSpace():
        return
    else:
      let argumentStart = index
      while index < characters.len and
          characters[index].isArgumentCharacter():
        inc index
      if argumentStart == index:
        return
      argument = asString(characters, argumentStart, index)

    result.args.add(argument)

  result.success = true

func commandKind(name: string; kind: var ViCommandKind): bool =
  for entry in commandNames:
    if name.toLowerAscii() == entry.name:
      kind = entry.kind
      return true

proc commandBody(line: string): string =
  var index = 0
  while index < line.len and (line[index] == ':' or line[index].isSpaceAscii()):
    inc index
  if index == line.len:
    return
  line[index .. ^1]

proc parseViCommand*(line: string): ViParseResult =
  let body = commandBody(line)
  if body.startsWith("/"):
    result.success = true
    let pattern = if body.len > 1: body[1 .. ^1] else: ""
    result.command = ViCommand(kind: vcSearch, args: @[pattern])
    return

  let parsed = tokenizeCommandLine(body)
  if not parsed.success:
    result.message = ViMessage(text: "parse error", kind: vmError)
    return

  var kind: ViCommandKind
  if not commandKind(parsed.name, kind):
    result.message = ViMessage(
      text: "Not an editor command: " & parsed.name,
      kind: vmError)
    return

  result.success = true
  result.command = ViCommand(kind: kind, args: parsed.args)

proc beginInput*(history: var ViHistory) =
  history.index = history.entries.len

proc recordInput*(history: var ViHistory; line: string) =
  let body = commandBody(line)
  if body.len == 0:
    return
  history.entries.add(line)
  history.index = history.entries.len

proc previous*(history: var ViHistory; line: var string): bool =
  if history.index <= 0:
    return false
  dec history.index
  line = history.entries[history.index]
  true

proc next*(history: var ViHistory; line: var string): bool =
  if history.index >= history.entries.len:
    return false
  inc history.index
  if history.index == history.entries.len:
    line.setLen(0)
  else:
    line = history.entries[history.index]
  true
