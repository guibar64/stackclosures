discard """
action: "run"
valgrind: true
disabled: true
matrix: "--d:useMalloc -g;"
targets: "c"
output: '''
@[6, 7, 8, 9, 10]
'''
"""
import std/[sequtils, strutils]
import stackclosures

proc doMap[T](x: openArray[T]): seq[T] {.stackClosures.} =
  let local = x.len
  map(x, proc(x: T): T = 
    x + local
  )


proc main() =
  var x = [1,2,3,4,5]
  echo doMap(x)

main()
