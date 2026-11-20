import std/[strutils, unicode]
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
    var found = false
    for namePart in filters.nameParts:
      if process.exeName.contains(namePart):
        found = true
        break
    if not found:
      return false

  if filters.filterByCommand and
      not unicode.toLower(process.exeName).contains(
        unicode.toLower(filters.commandFilter)):
    return false
  true

func passesFilters*(process: Process; filters: Filters): bool =
  if not process.passesIdentityFilters(filters):
    return false
  if filters.filterByUser and
      cmpIgnoreCase(process.userName, filters.userName) != 0:
    return false
  if filters.filterByUserId and
      (not process.userIdValid or process.userId != filters.userId):
    return false
  true
