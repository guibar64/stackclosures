import std/[tables, hashes, macros]

import stackclosures/private/desym

proc rawProcEnvToProc*(rawProc, rawEnv: pointer, T: typedesc[proc]): T {.noInit, inline.} =
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

type
  LocalData = object
    number: int
    envs: seq[int]

const closureKinds = {nnkLambda, nnkProcDef, nnkFuncDef}

proc hasNonClosureConv(n: NimNode): bool =
  expectKind n, closureKinds
  for pragma in n.pragma:
    if pragma.kind in {nnkIdent,nnkSym} and (pragma.eqIdent("nimcall") or pragma.eqIdent("cdecl") or pragma.eqIdent("stdcall")):
      return false
  return true

proc findLocals(n: NimNode, root: NimNode, locals: var Table[NimNode, LocalData],
    names: var CountTable[string], nenvs: var int, currentEnv = -1, inLambda = false) =
  if inLambda and n.kind == nnkSym and n.symKind notin {nskConst, nskResult, nskParam} and
      n.owner == root:
    #TODO maybe include not tyVar nskParam

    if n notin locals:
      names.inc(n.strVal)
      locals[n] = LocalData(number: names[n.strVal]-1, envs: @[currentEnv])
    else:
      locals[n].envs.add currentEnv
  else:
    if n.kind in {nnkCall, nnkCommand} and n[0].eqIdent("nimClosure") and n.len > 1 and n[1].kind == nnkLambda:
      discard
    elif n.kind in closureKinds and n.hasNonClosureConv:
      inc nenvs
      for c in n.body:
        findLocals(c, root, locals, names, nenvs, currentEnv = currentEnv + 1, inLambda = true)
    else:
      for c in n:
        findLocals(c, root, locals, names, nenvs, currentEnv, inLambda)

proc field(n: NimNode, d: LocalData): NimNode =
  ident(n.strVal & (if d.number > 0: $d.number else: ""))

proc constructEnvs(locals: Table[NimNode, LocalData], env: NimNode, envType: NimNode,
    nenvs: int): NimNode =
  if nenvs <= 0: return newEmptyNode()
  let typeSec = nnkTypeSection.newTree()
  typeSec.add nnkTypeDef.newTree(envType,
    newEmptyNode(), nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), nnkRecList.newTree()))
  var rec = typeSec[^1][^1][^1]
  let fakeMtype = ident"fakeMType"
  rec.add nnkIdentDefs.newTree(fakeMtype, ident"pointer", newEmptyNode())
  for loc, us in locals.pairs:
    rec.add nnkIdentDefs.newTree(loc.field(us), getType(loc), newEmptyNode())

  let wrapperType = ident(envType.strVal & ":wrapper")
  typeSec.add nnkTypeDef.newTree(wrapperType, newEmptyNode(), nnkObjectTy.newTree(newEmptyNode(),
      newEmptyNode(), nnkRecList.newTree()))
  rec = typeSec[^1][^1][^1]
  rec.add nnkIdentDefs.newTree(ident"head", ident"FakeRefCell", newEmptyNode())
  rec.add nnkIdentDefs.newTree(ident"env", envType, newEmptyNode())

  result = newStmtList()
  result.add typeSec
  let envWrapper = ident(env.strVal & ":wrapper")
  result.add nnkVarSection.newTree(
    newIdentDefs(envWrapper, wrapperType, nnkObjConstr.newtree(wrapperType,
        nnkExprColonExpr.newTree(ident"head", newCall(ident"default", ident"FakeRefCell")))),
    newIdentDefs(env, nnkPtrTy.newTree(envType), newCall(ident"addr", nnkDotExpr.newTree(envWrapper, ident"env")))
  )
  # decRef & co will be called on the false closure
  result.add newAssignment(nnkDotExpr.newTree(env, fakeMtype), newCall(ident"addr",
      ident"fakeNimType"))


proc transfBody(n: NimNode, locals: Table[NimNode, LocalData], env: NimNode,
    currentEnv: var int): NimNode =
  case n.kind
  of nnkSym:
    if n in locals:
      result = nnkDotExpr.newTree(env, n.field(locals[n]))
    else:
      result = n
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
              result.add newAssignment(nnkDotExpr.newTree(env, d.field(locals[d])), transfBody(c[
                  ^1], locals, env, currentEnv))
          else:
            newDef.add d
        if newDef.len > 0:
          newDef.add transfBody(c[^2], locals, env, currentEnv)
          newDef.add transfBody(c[^1], locals, env, currentEnv)
          newSec.add newDef
    if newSec.len > 0: result.add newSec
  of nnkForStmt:
    result = copyNimNode(n)
    # the forvar should not be touched here
    for i in 0..<(n.len-2):
      result.add n[i]
    result.add transfBody(n[^2], locals, env, currentEnv)
    result.add newStmtList()
    for i in 0..<(n.len-2):
      if n[i].kind == nnkSym and n[i] in locals:
        result[^1].add newAssignment(nnkDotExpr.newTree(env, n[i].field(locals[n[i]])), n[i])
      if n[i].kind == nnkVarTuple:
        for v in n[i]:
          if v.kind == nnkSym and v in locals:
            result[^1].add newAssignment(nnkDotExpr.newTree(env, v.field(locals[v])), v)
    result[^1].add transfBody(n[^1], locals, env, currentEnv)

  else:
    if n.kind in {nnkCall, nnkCommand} and n[0].eqIdent("nimClosure") and n.len > 1 and n[1].kind == nnkLambda:
      result = copyNimTree(n[1])
      result.body = transfBody(n[1].body, locals, env, currentEnv)
    elif n.kind in closureKinds and n.hasNonClosureConv:
      let closureDef = newStmtList()
      inc currentEnv
      let pid = ident(n[0].strVal & $(currentEnv))
      let nParams = copyNimTree(n.params)
      nParams.add newIdentDefs(env, nnkPtrTy.newTree(ident(":StackEnv")))
      closureDef.add nnkProcDef.newTree(
        pid,
        newEmptyNode(),
        newEmptyNode(),
        nParams,
        n.pragma,
        newEmptyNode(),
        transfBody(n.body, locals, env, currentEnv),
      )
      closureDef[^1].addPragma(ident"nimcall")
      template toClos(closType, pid, env: untyped): untyped =
        rawProcEnvToProc(cast[pointer](pid), env, closType)

      let closType = nnkProcTy.newTree(n.params, newEmptyNode())
      closureDef.add getAst toClos(closType, pid, env)
      if n.kind == nnkLambda:
        result = closureDef
      else:
        result = nnkLetSection.newTree(newIdentDefs(ident(n[0].strVal), closType, closureDef))
    else:
      result = copyNimNode(n)
      for c in n:
        result.add transfBody(c, locals, env, currentEnv)


proc stackClosureImpl(pn: NimNode): NimNode =
  var locals: Table[NimNode, LocalData]
  var names = initCountTable[string]()
  var nenvs: int
  findLocals(pn.body, pn[0], locals, names, nenvs)
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

macro stackClosures*(pn: typed): untyped =
  ## Allocates closures of `pn` on the stack.
  expectKind pn, {nnkProcDef, nnkFuncDef}
  when defined(js):
    result = pn
  else:
    result = stackClosureImpl(pn)