discard """
action: "run"
valgrind: true
matrix: "--d:useMalloc -g;--d:useMalloc -g --gc:arc"
targets: "c"
output: '''
@[6, 7, 8, 9, 10]
[11, 11, 11, 11, 11]
AABACADAEAFAGA
@[2, 4, 6, 8, 10]
5
'''
"""
import std/[sequtils, strutils]
import stackclosures

proc doMap(x: openArray[int]): seq[int] {.stackClosures.} =
  let local = x.len
  map(x, proc(x: int): int = 
    x + local
  )

proc doApply(x: openArray[int], y: var openArray[int]) {.stackClosures.} =
  let local = x.len
  var local2 = if x.len > 0: 0 else: x[0]
  let p = proc(x: int): int =
      let y = local - local2
      result = x + y
      inc local2
  for i in 0..<x.len: y[i] = x[i]
  apply(y, proc(x: int): int = 
    x + local
  )
  apply(y, p)

proc with_strings(s: string): string {.stackClosures.} =
  let y = toUpperAscii(s)
  var chars: seq[char]
  for c in s: chars.add(c)
  result = map(chars, proc(c: char): string = $toUpperAscii(c) & y[0] ).join("")

proc mapAndCount(x: openArray[int]): int {.stackClosures.} = 
  var n = 0
  echo map(x, proc(i: int): int = 
    inc n
    i + n
  )
  result = n

proc main() =
  var x = [1,2,3,4,5]
  echo doMap(x)
  var y: array[x.len, int]
  doApply(x, y)
  echo y
  echo with_strings("abcdefg")
  echo mapAndCount(x)

main()

