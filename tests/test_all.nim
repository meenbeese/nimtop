include test_version
include test_types
include test_util
include test_config
include test_cli
include test_sorting
include test_filters
include test_processformat
include test_input
include test_search
include test_vi

when defined(windows):
  include test_console
  include test_processes

when defined(linux):
  include test_linux
