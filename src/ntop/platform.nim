when defined(windows):
  import platform/windows
  export windows
else:
  {.error: "nimtop does not yet have a backend for this platform.".}
