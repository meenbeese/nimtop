import std/unittest
import ntop/types

suite "types":
  test "default filter state is inactive":
    let filters = Filters()
    check not filters.filterByPid
    check not filters.filterByName
    check not filters.filterByUser
