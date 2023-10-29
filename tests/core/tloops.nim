discard """
action: "run"
targets: "c cpp"
output: '''
1
2
3
4
13
-1-3
04
16
28
01
12
'''
"""
import std/enumerate
import stackclosures

proc tforSimple() {.stackClosures.} =
  for i in 1..4:
    (proc() = echo i)()
tforSimple()

proc tforTuple() {.stackClosures.} =
  for (i,j,k) in [(1,2,3),(-1,-2,-3)]:
    (proc() = echo i,k)()
tforTuple()

proc tforPairs() {.stackClosures.} =
  for i,j in pairs([4, 6, 8]):
    (proc() = echo i,j)()
tforPairs()

proc tEnumerate() {.stackClosures.} =
  for i, (j,k) in enumerate([(0, 1),(3,2)]):
    (proc() = echo i,k)()
tEnumerate()