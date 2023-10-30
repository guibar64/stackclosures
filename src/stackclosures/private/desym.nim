import std/macros

proc lightCopyNode(n: NimNode): NimNode =
  result = n.kind.newNimNode()
  copyLineInfo(result, n)

proc desym*(n: NimNode): NimNode =
  # Transform a typed AST to an untyped one
  case n.kind
  of nnkSym:
    result = ident(n.strVal)
    copyLineInfo(result, n)
  of RoutineNodes:
    result = lightCopyNode(n)
    for i in 0..<min(7, n.len):
      if i == 0 and n.kind == nnkLambda:
        result.add newEmptyNode()
      else:
        result.add desym(n[i])
  of nnkHiddenStdConv:
    result = desym(n[1])
  of nnkHiddenCallConv, nnkHiddenSubConv:
    result = desym(n[1])
  of nnkHiddenDeref, nnkHiddenAddr:
    result = desym(n[0])
  of nnkConv:
    result = newCall(desym n[0], desym n[1])
    copyLineInfo(result, n)
  of nnkBracketExpr:
    result = lightCopyNode(n)
    if n[0].eqIdent("range"):
      result.add desym(n[0])
      result.add nnkInfix.newTree(ident"..")
      for i in 1..<n.len:
        result[^1].add desym(n[i])
    else:
      for c in n:
        result.add desym(c)
  of nnkCall, nnkCommand:
    result = lightCopyNode(n)
    for c in n:
      if c.kind == nnkHiddenStdConv and c[0].kind == nnkEmpty and c[1].kind == nnkBracket:
        # Attempt to reverse expansion of echo & co:
        for d in c[1]:
          result.add desym(d)
      else:
        result.add desym(c)
  of nnkOpenSymChoice, nnkClosedSymChoice:
    # ⚠ the syms may have different names.
    result = ident(n[0].strVal)
    copyLineInfo(result, n)
  of nnkGenericParams:
    result = lightCopyNode(n)
    for c in n:
      if c.kind == nnkSym:
        result.add newIdentDefs(ident(c.strVal), newEmptyNode(), newEmptyNode())
      else:
        result.add desym(c)
  of nnkFormalParams:
    result = lightCopyNode(n)
    if n[0].kind == nnkArgList:
      # Produced by sugar.=>
      result.add ident("auto")
    else:
      result.add desym(n[0])
    for i in 1..<n.len:
      let c = n[i]
      if c.kind == nnkSym and c.symKind() != nskType:
        result.add newIdentDefs(desym(c), desym(c.getType()))
      else:
        result.add desym(c)
  else:
    if n.len == 0:
      result = copyNimNode(n)
    else:
      result = lightCopyNode(n)
      for c in n:
        result.add desym(c)
