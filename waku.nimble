mode = ScriptMode.Verbose

### Package
version       = "0.1.0"
author        = "Status Research & Development GmbH"
description   = "Waku, Private P2P Messaging for Resource-Restricted Devices"
license       = "MIT or Apache License 2.0"
#bin           = @["build/waku"]

### Dependencies
requires "nim >= 1.6.0",
  "chronicles",
  "confutils",
  "chronos",
  "eth",
  "json_rpc",
  "libbacktrace",
  "nimcrypto",
  "stew",
  "stint",
  "metrics",
  "libp2p", # Only for Waku v2
  "web3",
  "presto",
  "regex"

### Helper functions
proc buildBinary(name: string, srcDir = "./", params = "", lang = "c") =
  if not dirExists "build":
    mkDir "build"
  # allow something like "nim nimbus --verbosity:0 --hints:off nimbus.nims"
  var extra_params = params
  for i in 2..<paramCount():
    extra_params &= " " & paramStr(i)
  exec "nim " & lang & " --out:build/" & name & " " & extra_params & " " & srcDir & name & ".nim"

proc buildLibrary(name: string, srcDir = "./", params = "", `type` = "static") =
  if not dirExists "build":
    mkDir "build"
  # allow something like "nim nimbus --verbosity:0 --hints:off nimbus.nims"
  var extra_params = params
  for i in 2..<paramCount():
    extra_params &= " " & paramStr(i)
  if `type` == "static":
    exec "nim c" & " --out:build/" & name & ".a --threads:on --app:staticlib --opt:size --noMain --header " & extra_params & " " & srcDir & name & ".nim"
  else:
    exec "nim c" & " --out:build/" & name & ".so --threads:on --app:lib --opt:size --noMain --header " & extra_params & " " & srcDir & name & ".nim"

proc test(name: string, params = "-d:chronicles_log_level=DEBUG", lang = "c") =
  # XXX: When running `> NIM_PARAMS="-d:chronicles_log_level=INFO" make test2`
  # I expect compiler flag to be overridden, however it stays with whatever is
  # specified here.
  buildBinary name, "tests/", params
  exec "build/" & name

### Waku common tasks
task testcommon, "Build & run common tests":
  test "all_tests_common", "-d:chronicles_log_level=WARN -d:chronosStrictException"

### Waku v2 tasks
task wakunode2, "Build Waku v2 cli node":
  let name = "wakunode2"
  buildBinary name, "apps/wakunode2/"

task wakucanary, "Build waku-canary tool":
  let name = "wakucanary"
  buildBinary name, "apps/wakucanary/"

task networkmonitor, "Build network monitor tool":
  let name = "networkmonitor"
  buildBinary name, "apps/networkmonitor/"

task test2, "Build & run Waku v2 tests":
  test "all_tests_v2"

task testwakunode2, "Build & run wakunode2 app tests":
  test "all_tests_wakunode2"

task example2, "Build Waku v2 example":
  buildBinary "publisher", "examples/v2/"
  buildBinary "subscriber", "examples/v2/"
  buildBinary "filter_subscriber", "examples/v2/"
  buildBinary "lightpush_publisher", "examples/v2/"

task chat2, "Build example Waku v2 chat usage":
  # NOTE For debugging, set debug level. For chat usage we want minimal log
  # output to STDOUT. Can be fixed by redirecting logs to file (e.g.)
  #buildBinary name, "examples/v2/", "-d:chronicles_log_level=WARN"

  let name = "chat2"
  buildBinary name, "apps/chat2/", "-d:chronicles_sinks=textlines[file] -d:ssl"

task chat2bridge, "Build chat2bridge":
  let name = "chat2bridge"
  buildBinary name, "apps/chat2bridge/"

### C Bindings
task libwakuStatic, "Build the cbindings waku node library":
  let name = "libwaku"
  buildLibrary name, "library/", "-d:chronicles_log_level=ERROR", "static"

task libwakuDynamic, "Build the cbindings waku node library":
  let name = "libwaku"
  buildLibrary name, "library/", "-d:chronicles_log_level=ERROR", "dynamic"
