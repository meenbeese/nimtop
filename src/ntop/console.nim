import platform
import types

export platform except acquireProcessList, initSystemInfo, pollSystemInfo,
  terminateProcess, startCommand, monotonicTimeMs,
  registerConsoleControlHandler, shutdownRequested, ConsoleShutdownCallback
export types.Key
