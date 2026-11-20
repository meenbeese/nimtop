import std/unittest
import ntop/util

suite "formatTimeString":
  test "formats expected boundaries":
    check formatTimeString(0) == "00:00:00:00"
    check formatTimeString(999) == "00:00:00:00"
    check formatTimeString(1000) == "00:00:00:01"
    check formatTimeString(59_999) == "00:00:00:59"
    check formatTimeString(3_600_000) == "00:01:00:00"
    check formatTimeString(90_061_001) == "01:01:01:01"

suite "formatMemoryString":
  test "uses KB MB GB and TB boundaries":
    check formatMemoryString(999_999'u64) == "  1000.0 KB"
    check formatMemoryString(1_000_000'u64) == "     1.0 MB"
    check formatMemoryString(1_000_000_000'u64) == "     1.0 GB"
    check formatMemoryString(1_000_000_000_000'u64) == "     1.0 TB"

suite "FILETIME math":
  test "subtracts packed FILETIME values":
    let before = FileTime(lowDateTime: 100, highDateTime: 0)
    let after = FileTime(lowDateTime: 200, highDateTime: 0)
    check subtractTimes(after, before) == 100
    check subtractTimes(before, after) == 0
