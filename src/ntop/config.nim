import std/[os, strutils]
import consts, types

func defaultConfig*(): Config =
  Config(
    fgColor: ForegroundWhite,
    bgColor: ForegroundIntensity,
    fgHighlightColor: ForegroundCyan,
    bgHighlightColor: BackgroundCyan,
    menuBarColor: BackgroundBlue,
    processListHeaderColor: BackgroundGreen,
    errorColor: BackgroundRed or ForegroundWhite,
    cpuBarColor: ForegroundRed,
    memoryBarColor: ForegroundGreen,
    pageMemoryBarColor: ForegroundGreen,
    redrawInterval: 1000
  )

func monochromeConfig*(): Config =
  Config(
    fgColor: ForegroundWhite,
    bgColor: ForegroundIntensity,
    fgHighlightColor: ForegroundIntensity or ForegroundWhite,
    bgHighlightColor: BackgroundWhite,
    menuBarColor: 0,
    processListHeaderColor: BackgroundWhite,
    errorColor: ForegroundWhite,
    cpuBarColor: ForegroundWhite,
    memoryBarColor: ForegroundWhite,
    pageMemoryBarColor: ForegroundWhite,
    redrawInterval: 1000
  )

func parseConfigNumber*(text: string; ok: var bool): uint64 =
  ok = false
  if text.len == 0:
    return 0
  try:
    if text.startsWith("0x") or text.startsWith("0X"):
      result = uint64(parseHexInt(text[2 .. ^1]))
    else:
      result = uint64(parseInt(text))
    ok = true
  except ValueError:
    discard

proc parseConfigLine*(config: var Config; line: string) =
  let stripped = line.strip()
  if stripped.len == 0 or stripped.startsWith("#"):
    return
  let parts = stripped.splitWhitespace(maxsplit = 1)
  if parts.len != 2:
    return
  var ok: bool
  let number = parseConfigNumber(parts[1], ok)
  if not ok:
    return
  let value = uint16(number and 0xffff)
  case parts[0].toLowerAscii():
  of "fgcolor":
    config.fgColor = value
  of "bgcolor":
    config.bgColor = value
  of "fghighlightcolor":
    config.fgHighlightColor = value
  of "bghighlightcolor":
    config.bgHighlightColor = value
  of "menubarcolor":
    config.menuBarColor = value
  of "processlistheadercolor":
    config.processListHeaderColor = value
  of "errorcolor":
    config.errorColor = value
  of "cpubarcolor":
    config.cpuBarColor = value
  of "memorybarcolor":
    config.memoryBarColor = value
  of "pagememorybarcolor":
    config.pageMemoryBarColor = value
  of "redrawinterval":
    config.redrawInterval = number
  else:
    discard

func configPath*(executablePath: string): string =
  executablePath.parentDir / "ntop.conf"

proc readConfigFile*(path: string; config: var Config) =
  if not fileExists(path):
    return
  for line in lines(path):
    parseConfigLine(config, line)
