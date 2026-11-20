import std/[random, unittest]
import ntop/vi

suite "Vi command parsing":
  test "tokenizes empty lines, spaces, and multiple arguments":
    let empty = tokenizeCommandLine("")
    check empty.success
    check empty.name == ""
    check empty.args.len == 0

    let parsed = tokenizeCommandLine("  kill 12 34")
    check parsed.success
    check parsed.name == "kill"
    check parsed.args == @["12", "34"]

  test "quoted arguments can contain spaces":
    let parsed = tokenizeCommandLine("exec \"hello world.exe\"")
    check parsed.success
    check parsed.args == @["hello world.exe"]

  test "invalid characters, trailing junk, and unterminated quotes fail":
    check not tokenizeCommandLine("sort CPU?").success
    check not tokenizeCommandLine("sort \"CPU").success
    check not tokenizeCommandLine("sort \"CPU\"junk").success
    check not tokenizeCommandLine("bad! command").success

  test "deterministic fuzz inputs do not crash and successful tokens round-trip":
    const seeds = [
      "", "exec \"hello world.exe\"", "kill 12 34", "sort CPU%",
      "tree", "search \"\"", "bad! command"
    ]
    var rng = initRand(0x5eed)
    for iteration in 0 ..< 20_000:
      var input: string
      if iteration mod 2 == 0:
        input = newString(rand(rng, 0 .. 128))
        for character in input.mitems:
          character = char(rand(rng, 0 .. 255))
      else:
        input = seeds[rand(rng, 0 .. int(high(seeds)))]
        for _ in 0 ..< rand(rng, 0 .. 8):
          case rand(rng, 0 .. 2)
          of 0:
            if input.len < 128:
              input.add(char(rand(rng, 0 .. 255)))
          of 1:
            if input.len > 0:
              input[rand(rng, 0 .. input.high)] = char(rand(rng, 0 .. 255))
          else:
            if input.len > 0:
              input.setLen(rand(rng, 0 .. input.len))

      let parsed = tokenizeCommandLine(input)
      discard parseViCommand(input)
      if parsed.success:
        var encoded = parsed.name
        for argument in parsed.args:
          encoded.add(" \"" & argument & "\"")
        let roundTripped = tokenizeCommandLine(encoded)
        check roundTripped.success
        check roundTripped.name == parsed.name
        check roundTripped.args == parsed.args

  test "known commands and slash search alias are parsed":
    let command = parseViCommand(":sort CPU%")
    check command.success
    check command.command.kind == vcSort
    check command.command.args == @["CPU%"]

    let alias = parseViCommand("/some/path.exe")
    check alias.success
    check alias.command.kind == vcSearch
    check alias.command.args == @["some/path.exe"]

    let emptyAlias = parseViCommand("/")
    check emptyAlias.success
    check emptyAlias.command.args == @[""]

    let emptyQuotedArgument = parseViCommand(":search \"\"")
    check emptyQuotedArgument.success
    check emptyQuotedArgument.command.args == @[""]

  test "unknown commands and malformed lines report errors":
    let unknown = parseViCommand(":unknown")
    check not unknown.success
    check unknown.message.kind == vmError
    check unknown.message.text == "Not an editor command: unknown"

    let malformed = parseViCommand(":sort CPU?")
    check not malformed.success
    check malformed.message.text == "parse error"

  test "history navigation is bounded and returns to a blank line":
    var history: ViHistory
    var line = ":sort CPU%"
    history.beginInput()
    history.recordInput(line)
    line = ":tree"
    history.beginInput()
    history.recordInput(line)
    history.beginInput()
    line = ":"
    check history.previous(line)
    check line == ":tree"
    check history.previous(line)
    check line == ":sort CPU%"
    check not history.previous(line)
    check history.next(line)
    check line == ":tree"
    check history.next(line)
    check line.len == 0
    check not history.next(line)

  test "empty commands are not added to history":
    var history: ViHistory
    history.recordInput(":   ")
    var line = ":"
    check not history.previous(line)
