import std/[tables, hashes, macros]

proc  rawProcEnvToProc*(rawProc, rawEnv: pointer, T: typedesc[proc]): T  {.noInit, inline.} =
  ## Not meant to be used directly
  # cast does not work here so let's emit C
  # this proc use NRVO
  {.emit: """
  `result`->ClP_0 = `rawProc`; `result`->ClE_0 = `rawEnv`;
  """.}

type
  FakeNimTypeV2 = object
    destructor: pointer
    size: int
    align: int16
    depth: int16
    display: ptr uint32
    traceImpl: pointer
    typeInfoV1: pointer
    flags: int

## Not meant to be used directly
let fakeNimType* = FakeNimTypeV2(
  flags: 1 # Acyclic
)
## Not meant to be used directly
type
  FakeRefCell* = object
    rc: int = high(int)
    when defined(gcOrc):
      rootIdx: int = 0

proc nimClosure*(lambda: proc): auto = lambda
  ## Mark a closure definition as a regular Nim closure

proc hash(n: NimNode): Hash =
  result = !$ hash(n.signatureHash)

proc findLocals(n: NimNode, root: NimNode, locals: var Table[NimNode, seq[int]], nenvs: var int, currentEnv = -1, inLambda = false) =
  if inLambda and n.kind == nnkSym and n.symKind notin {nskConst, nskResult, nskParam} and n.owner == root:
    #TODO maybe include not tyVar nskParam
    
    if n notin locals:
      locals[n] = @[currentEnv]
    else:
      locals[n].add currentEnv
  else:
    if n.kind in {nnkCall, nnkCommand} and n[0].eqIdent("nimClosure") and n.len > 1 and n[1].kind == nnkLambda:
      discard
    elif n.kind == nnkLambda:
      inc nenvs
      for c in n.body:
        findLocals(c, root, locals, nenvs, currentEnv = currentEnv + 1, inLambda = true)
    else:
      for c in n:
        findLocals(c, root, locals, nenvs, currentEnv, inLambda)

proc desym(n: NimNode): NimNode =
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

proc constructEnvs(locals: Table[NimNode, seq[int]], env: NimNode, envType: NimNode, nenvs: int): NimNode =
  if nenvs <= 0: return newEmptyNode()
  let typeSec = nnkTypeSection.newTree()
  typeSec.add nnkTypeDef.newTree(envType, 
    newEmptyNode(), nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), nnkRecList.newTree()))
  var rec = typeSec[^1][^1][^1]    
  let fakeMtype = ident"fakeMType"
  rec.add nnkIdentDefs.newTree(fakeMtype, ident"pointer", newEmptyNode())
  for loc, us in locals.pairs:
    rec.add nnkIdentDefs.newTree(loc, getType(loc), newEmptyNode())

  let wrapperType = ident(envType.strVal & ":wrapper")
  typeSec.add nnkTypeDef.newTree(wrapperType, newEmptyNode(), nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), nnkRecList.newTree()))
  rec = typeSec[^1][^1][^1]
  rec.add nnkIdentDefs.newTree(ident"head", ident"FakeRefCell", newEmptyNode())
  rec.add nnkIdentDefs.newTree(ident"env", envType, newEmptyNode())

  result = newStmtList()
  result.add typeSec
  let envWrapper = ident(env.strVal & ":wrapper")
  result.add nnkVarSection.newTree(
    newIdentDefs(envWrapper, wrapperType, nnkObjConstr.newtree(wrapperType, nnkExprColonExpr.newTree(ident"head", newCall(ident"default", ident"FakeRefCell")))),
    newIdentDefs(env, nnkPtrTy.newTree(envType), newCall(ident"addr", nnkDotExpr.newTree(envWrapper, ident"env")))
  )
  # decRef & co will be called on the false closure
  result.add newAssignment(nnkDotExpr.newTree(env, fakeMtype), newCall(ident"addr", ident"fakeNimType"))

proc transfBody(n: NimNode, locals: Table[NimNode, seq[int]], env: NimNode, currentEnv: var int): NimNode =
  case n.kind
  of nnkSym:
    if n in locals:
      result = nnkDotExpr.newTree(env, ident(n.strVal))
    else:
      result = n
      
    when false:
      if currentEnv >= 0 and n.kind == nnkSym and n.symKind notin {nskConst, nskResult, nskParam} and n.owner == root:        
        if n notin locals:
          locals[n] = @[currentEnv]
        elif currentEnv notin locals[n]:
          locals[n].add currentEnv
  of nnkLetSection, nnkVarSection:
    result = newStmtList()
    let newSec = copyNimNode(n)
    for c in n:
      if c.kind == nnkIdentDefs:
        let newDef = copyNimNode(c)
        for i in 0..<c.len-2:
          let d = c[i]
          if d.kind == nnkSym and d in locals:
            if c[^1].kind != nnkEmpty:
              result.add newAssignment(nnkDotExpr.newTree(env, ident(d.strVal)), transfBody(c[^1],locals,env,currentEnv))
          else:
            newDef.add d
        if newDef.len > 0:
          newDef.add transfBody(c[^2], locals, env, currentEnv)
          newDef.add transfBody(c[^1], locals, env, currentEnv)
          newSec.add newDef
    if newSec.len > 0: result.add newSec

  else:
    if n.kind in {nnkCall, nnkCommand} and n[0].eqIdent("nimClosure") and n.len > 1 and n[1].kind == nnkLambda:
      result = copyNimTree(n[1])
      result.body = transfBody(n[1].body, locals, env, currentEnv)
    elif n.kind == nnkLambda:
      result = newStmtList()
      inc currentEnv
      let pid = ident(n[0].strVal & $(currentEnv))
      let nParams = copyNimTree(n.params)
      nParams.add newIdentDefs(env, nnkPtrTy.newTree(ident(":StackEnv")))
      result.add nnkProcDef.newTree(
        pid,
        newEmptyNode(),
        newEmptyNode(),
        nParams,
        n.pragma,
        newEmptyNode(),
        transfBody(n.body, locals, env, currentEnv),
      )
      result[^1].addPragma(ident"nimcall")
      template toClos(closType, pid, env: untyped): untyped =
        rawProcEnvToProc(cast[pointer](pid), env, closType)
      
      let closType = nnkProcTy.newTree(n.params, newEmptyNode())
      result.add getAst toClos(closType, pid, env)
    else:
      result = copyNimNode(n)
      for c in n:
        result.add transfBody(c, locals, env, currentEnv)


proc stackClosureImpl(pn: NimNode): NimNode =
  var locals: Table[NimNode, seq[int]]
  var nenvs: int
  findLocals(pn.body, pn[0], locals, nenvs)
  let envType = ident(":StackEnv")
  let env = ident(":theStackEnv")
  var cenv = -1
  result = pn.kind.newTree(
    pn.name, 
    pn[1],
    pn[2],
    pn[3],
    pn.pragma,
    pn[4],
    newStmtList(
      constructEnvs(locals, env, envType, nenvs),
      transfBody(pn.body, locals, env, cenv),
    )
  )
  result = desym(result)

macro stackClosures*(pn: typed) =
  expectKind pn, {nnkProcDef, nnkFuncDef}
  when defined(js):
    result = pn
  else:
    result =  stackCLosureImpl(pn)
