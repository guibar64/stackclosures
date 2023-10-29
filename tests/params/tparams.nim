discard """
action: "run"
valgrind: true
targets: "c"
output: '''
BO
-1
'''
"""
import stackclosures
proc useParam(s: string, i: var int) {.stackClosures.} =
  (proc () =
    echo s
    i = -1
  )()

var i: int
useParam("BO", i)
echo i
