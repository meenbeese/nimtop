when defined(windows):
  import std/[unicode, unittest]
  import winim
  import ntop/console

  suite "console attributes":
    test "foreground and background bits pack into one WORD":
      check makeAttr(AttrForegroundRed, AttrBackgroundBlue) ==
        (AttrForegroundRed or AttrBackgroundBlue)
      check makeAttr(AttrForegroundWhite, WORD(0)) == AttrForegroundWhite

    test "default foreground is white":
      check AttrForegroundWhite ==
        (AttrForegroundRed or AttrForegroundGreen or AttrForegroundBlue)
      check AttrForegroundCyan ==
        (AttrForegroundIntensity or AttrForegroundGreen or AttrForegroundBlue)

    test "key descriptions are stable":
      check $Key(vk: 65, ch: Rune(65)) == "vk=65 ch=A"
      check $Key(vk: 13) == "vk=13"
