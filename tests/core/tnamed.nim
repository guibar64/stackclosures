discard """
action: "run"
targets: "c"
output: '''
6
1
4
'''
"""
import stackclosures
proc doNamed() {.stackClosures.} =
  let x = 3
  let y = 2
  proc named(a: int): int =
    a*y
  proc named2(a: int): int =
    a-y
  echo named(x)
  echo named2(x)

doNamed()

proc doNotDoNamed() {.stackClosures.} =
  proc named(a: int): int {.nimcall.} =
    a+1
  echo named(3)
doNotDoNamed()