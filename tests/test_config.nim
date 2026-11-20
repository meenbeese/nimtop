import std/[os, tempfiles, unittest]
import ntop/[config, consts]

suite "config":
  test "parses comments whitespace decimal hex and unknown keys":
    var config = defaultConfig()
    parseConfigLine(config, "# comment")
    parseConfigLine(config, "  FGColor   0x47 ")
    parseConfigLine(config, "RedrawInterval 250")
    parseConfigLine(config, "UnknownKey 123")
    check config.fgColor == 0x47'u16
    check config.redrawInterval == 250

  test "BGHighlightColor is applied independently":
    var config = defaultConfig()
    parseConfigLine(config, "FGHighlightColor 0x55")
    parseConfigLine(config, "BGHighlightColor 0xB0")
    check config.fgHighlightColor == 0x55'u16
    check config.bgHighlightColor == 0xB0'u16

  test "default and monochrome configs are distinct":
    let default = defaultConfig()
    let mono = monochromeConfig()
    check default.redrawInterval == 1000
    check mono.redrawInterval == 1000
    check mono.bgHighlightColor == BackgroundWhite

  test "nimtop.conf is preferred with ntop.conf as a legacy fallback":
    let tempDir = createTempDir("nimtop-config-", "")
    defer:
      removeFile(tempDir / "nimtop.conf")
      removeFile(tempDir / "ntop.conf")
      removeDir(tempDir)

    let path = configPath(tempDir / "nimtop.exe")
    check path == tempDir / "nimtop.conf"
    writeFile(tempDir / "ntop.conf", "FGColor 0x41\n")
    var config = defaultConfig()
    readConfigFile(path, config)
    check config.fgColor == 0x41'u16

    writeFile(path, "FGColor 0x42\n")
    config = defaultConfig()
    readConfigFile(path, config)
    check config.fgColor == 0x42'u16
