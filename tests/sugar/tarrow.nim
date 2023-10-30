discard """
action: "run"
targets: "c"
output: '''
@[6, 7, 8, 9, 10]
@[0, 8, 18, 30, 44]
'''
"""
import std/[sequtils, sugar]
import stackclosures

proc doMap(x: openArray[int]): seq[int] {.stackClosures.} =
  let local = x.len
  map(x, x => x + local)

proc zipMap[T,U](a, b: openArray[T], f: (T,T) -> U): seq[U] =
  for i in 0..<min(a.len, b.len):
    result.add f(a[i], b[i])

proc doMap2(x: openArray[int]): seq[int] {.stackClosures.} =
  let local = x.len
  let y = map(x, x => x + local)
  let local2 = x.len + 1
  zipMap(x, y, (x,y) => x*y - local2)


proc main() =
  echo doMap([1,2,3,4,5])
  echo doMap2([1,2,3,4,5])
main()

