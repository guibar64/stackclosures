discard """
action: "run"
valgrind: true
matrix: "--d:useMalloc -g;--d:useMalloc -g --gc:arc"
targets: "c cpp"
output: '''
Hello!
Hello!
Hello!
Hello!
4
'''
"""
import std/[locks, deques]
import stackclosures

type Task = proc() {.closure.}

var tguard: Lock 
initLock(tguard)

var tasks {.guard: tguard.} = initDeque[Task]()

proc worker() {.thread.} =
  var task: Task
  while true:
    {.cast(gcSafe).}:
      withLock tguard:
        if tasks.len == 0: break
        task = tasks.popFirst()
      if not task.isNil:
        task()


proc main() {.stackclosures.} =
  var th1, th2: Thread[void]
  let punc = "!"
  var counter = 0
  withLock tguard:
    tasks.addLast proc() = 
      echo "Hello" & punc
      atomicInc counter, 1
    tasks.addLast proc() = 
      echo "Hello" & punc
      atomicInc counter, 1
    tasks.addLast proc() = 
      echo "Hello" & punc
      atomicInc counter, 1
    tasks.addLast proc() = 
      echo "Hello" & punc
      atomicInc counter, 1
  createThread(th1, worker)
  createThread(th2, worker)
  joinThreads(th1, th2)
  echo counter

main()