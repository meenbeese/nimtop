import std/strutils
import types

func passesIdentityFilters*(process: Process; filters: Filters): bool =
  if filters.filterByPid:
    var found = false
    for pid in filters.pidList:
      if pid == process.id:
        found = true
        break
    if not found:
      return false

  if filters.filterByName:
    for namePart in filters.nameParts:
      if process.exeName.contains(namePart):
        return true
    return false
  true

func passesFilters*(process: Process; filters: Filters): bool =
  if not process.passesIdentityFilters(filters):
    return false
  not filters.filterByUser or
    cmpIgnoreCase(process.userName, filters.userName) == 0
