discard """
action: "run"
valgrind: true
matrix: "--d:useMalloc -g;--d:useMalloc -g --gc:arc"
targets: "c"
output: '''
@[0, -2, -3, -1, 6]
'''
"""
import std/sequtils
import stackclosures

proc doMap(x: openArray[int]): seq[int] {.stackClosures.} =
  let a = x.len
  let y = map(x, proc(x: int): int = 
    x + a
  )
  let b = y[0]
  map(x, nimClosure proc(x: int): int = x - b + a)

proc main() =
  echo doMap([1, -1, -2, 0, 7])

main()