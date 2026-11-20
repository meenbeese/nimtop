const
  ForegroundBlue* = 0x0001'u16
  ForegroundGreen* = 0x0002'u16
  ForegroundRed* = 0x0004'u16
  ForegroundIntensity* = 0x0008'u16
  ForegroundWhite* =
    ForegroundRed or ForegroundGreen or ForegroundBlue
  ForegroundCyan* =
    ForegroundIntensity or ForegroundGreen or ForegroundBlue

  BackgroundBlue* = 0x0010'u16
  BackgroundGreen* = 0x0020'u16
  BackgroundRed* = 0x0040'u16
  BackgroundIntensity* = 0x0080'u16
  BackgroundWhite* =
    BackgroundRed or BackgroundGreen or BackgroundBlue
  BackgroundCyan* =
    BackgroundIntensity or BackgroundGreen or BackgroundBlue
