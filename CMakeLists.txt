cmake_minimum_required(VERSION 2.6)
project(nimtop C)

option(ENABLE_UNICODE "Compile with Unicode support" OFF)

if(ENABLE_UNICODE)
	add_definitions(-DUNICODE -D_UNICODE)
endif()

add_executable(nimtop ntop.c util.c vi.c)
