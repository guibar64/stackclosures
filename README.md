![Github Actions](https://github.com/guibar64/stackclosures/workflows/Github%20Actions/badge.svg)

A macro (`stackClosures`) is provided to annotate a function, closures defined inside this function will be allocated on the stack.


```nim
import std/sequtils

proc doMap(a: openArray[int]): seq[int] {.stackClosures.} =
	map(a, proc(x: int): int = x + 1)
```

⚠⚠⚠ **UNSAFE** . The closures **must** not escape the function stack frame. ⚠⚠⚠

It is ABI compatible with Nim closures for ARC/ORC (which means sequtils and friends work)

It can work in a multithreading context, provided the threads exit before the owning function termination. For example, see `tests/threads/tthreading.nim`.

If one wish to use regular Nim closures, wrap the closure definition with
`nimClosure`:
```nim
import std/sequtils

proc doMap(a: openArray[int]): seq[int] {.stackClosures.} =
	map(a, nimClosure proc(x: int): int = x + 1)
```



Caveats (besides safety concerns):
- the current implementation is quite eager to transform any inner proc to a closure even non-capturing ones, use explicit annotations like `nimcall` to avoid that.
- Should not be compatible with `--mm:refc` (tests do pass but it may be an happy accident)
- capturing parameters is allowed, caution is advised. Currently, `openArray` is not supported.
- generics are not supported (the implementation use typed AST but generics are mostly untyped)
- compatibility with regular Nim closures implies allocating some space for ref-like bookkeeping, that is an overhead of `2*sizeof(int)`
	for ARC and `3*sizeof(int)` for ORC
- the current implementation use one environment per containing function, it works OK for this limited purpose but it could be improved