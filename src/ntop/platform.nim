when defined(windows):
  import platform/windows
  export windows
elif defined(linux):
  import platform/linux
  export linux
else:
  {.error: "nimtop does not yet have a backend for this platform.".}
