import std/unittest
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
