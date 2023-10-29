discard """
action: "run"
valgrind: true
matrix: "--d:useMalloc -g"
targets: "c"
output: '''
B
A
C
A
B
A
A1
A2
'''
"""
import stackClosures
proc blocks() {.stackClosures.} =
  let a = 'A'
  block:
    let a = 'B'
    (proc () = echo a)()
  (proc () = echo a)()

blocks()

proc ifs(cond: bool) {.stackClosures.} =
  let a = 'A'
  if cond:
    let a = 'C'
    (proc () = echo a)()
  else:
    let a = 'B'
    (proc () = echo a)()
  (proc () = echo a)()

ifs(true)
ifs(false)

proc escapeBlock() {.stackClosures.} =
  var p1, p2: proc() {.closure.}
  block:
    let a = "A1"
    p1 = (proc () = echo a)
  block:
    let a = "A2"
    p2 = (proc () = echo a)
  p1()
  p2()

escapeBlock()
