import std/strutils

type
  FileTime* = object
    lowDateTime*: uint32
    highDateTime*: uint32

func fileTimeToUInt64*(value: FileTime): uint64 =
  uint64(value.lowDateTime) or (uint64(value.highDateTime) shl 32)

func subtractTimes*(a, b: FileTime): uint64 =
  let left = fileTimeToUInt64(a)
  let right = fileTimeToUInt64(b)
  if left >= right:
    left - right
  else:
    0'u64

func formatTimeString*(milliseconds: uint64): string =
  let seconds = (milliseconds div 1000) mod 60
  let minutes = (milliseconds div 60_000) mod 60
  let hours = (milliseconds div 3_600_000) mod 24
  let days = milliseconds div 86_400_000
  let dayText = align($days, 2, '0')
  dayText & ":" & align($hours, 2, '0') & ":" &
    align($minutes, 2, '0') & ":" & align($seconds, 2, '0')

func formatMemoryString*(memoryBytes: uint64): string =
  var value: float
  var unit: string
  if memoryBytes < 1_000'u64 * 1_000'u64:
    value = float(memoryBytes) / 1000.0
    unit = "KB"
  elif memoryBytes < 1_000'u64 * 1_000'u64 * 1_000'u64:
    value = float(memoryBytes) / 1_000_000.0
    unit = "MB"
  elif memoryBytes < 1_000'u64 * 1_000'u64 * 1_000'u64 * 1_000'u64:
    value = float(memoryBytes) / 1_000_000_000.0
    unit = "GB"
  else:
    value = float(memoryBytes) / 1_000_000_000_000.0
    unit = "TB"

  let number = formatFloat(value, ffDecimal, 1)
  spaces(max(0, 8 - number.len)) & number & " " & unit
