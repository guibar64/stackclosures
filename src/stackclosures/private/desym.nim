import std/macros

proc desym*(n: NimNode): NimNode =
  # Transform a typed AST to an untyped one
  case n.kind
  of nnkSym:
    result = ident(n.strVal)
    copyLineInfo(result, n)
  of RoutineNodes:
    result = n.kind.newNimNode()
    copyLineInfo(result, n)
    for i in 0..<min(7, n.len):
      if i == 0 and n.kind == nnkLambda:
        result.add newEmptyNode()
      else:
        result.add desym(n[i])
  of nnkHiddenStdConv:
    # Attempt to reverse expansion of echo & co
    if n[0].kind == nnkEmpty and n[1].kind == nnkBracket:
      result = desym(n[1][0])
    else:
      result = desym(n[1])
  of nnkHiddenCallConv:
    result = desym(n[1])
  of nnkHiddenDeref, nnkHiddenAddr:
    result = desym(n[0])
  of nnkConv:
    result = newCall(desym n[0], desym n[1])
    copyLineInfo(result, n)

  else:
    if n.len == 0:
      result = copyNimNode(n)
    else:
      result = n.kind.newNimNode()
      copyLineInfo(result, n)
      for c in n:
        result.add desym(c)
