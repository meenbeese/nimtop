# Nim configuration for NTop.
#
# The package layout and dependencies live in nimtop.nimble. This file only adds
# source-path and build settings that should also apply when compiling
# directly with `nim c src/nimtop.nim`.

switch("path", "src")

# The process poller uses a background thread. Nim 2.x enables threads by
# default, but keep the switch explicit for older toolchains.
switch("threads", "on")

when defined(macosx):
  switch("passL", "-lproc")
