# NTop — an htop-like system monitor for Windows.
# Copyright (c) 2019 Gian Sass
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

## NTop version information shared by the help text, `-v`, and the UI.

const
  NTopVersion* {.strdefine.} = "dev"
    ## Set at build time with `-d:NTopVersion=0.4.0`.

func versionString*(): string =
  ## Returns the one-line version banner used by `-v` and `--help`.
  "NTop " & NTopVersion & " (Nim " & NimVersion & ")"
