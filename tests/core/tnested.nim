discard """
action: "run"
valgrind: true
matrix: "--d:useMalloc -g"
targets: "c cpp"
output: '''
@[3.0, 5.0, 2.0, 2.0, 2.0, 2.0, 4.0, 3.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 3.0, 2.0, 2.0]
'''
"""
import std/[sequtils]
import stackclosures

proc foo(x: openArray[float]): seq[seq[float]] {.stackClosures.} =
  proc bar(x: seq[float]): seq[float] {.stackClosures.} =
    let l = x.len.float
    map(x, proc(x: float): float = x + l)
  let zz = count(x, 0.0).float
  let y = map(x, proc(x: float): float = x*(1+zz))
  for val in y:
    result.add bar(@[count(x, val).float, count(x, val-1).float])


proc main() =
  echo concat(foo([1.0, 2, -1, 0.0, 2.0, 3.0, 33.3, 0.0, 2.0]))

main()