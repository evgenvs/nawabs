#
#
#    Nawabs -- The Anti package manager for Nim
#        (c) Copyright 2016 Andreas Rumpf
#
#    See the file "license.txt", included in this
#    distribution, for details about the copyright.


## Recipe handling. A 'recipe' is a NimScript that produces the same build.

import os, osproc, strutils
import osutils, packages

proc projToKey(name: string): string =
  result = newStringOfCap(name.len)
  var pendingDash = false
  for c in name:
    if c in {'A'..'Z', 'a'..'z', '0'..'9'}:
      if pendingDash:
        if result.len > 0: result.add '_'
        pendingDash = false
      result.add toLowerAscii(c)
    else:
      pendingDash = true
  result.add ".nims"

proc projToKey(proj: Project): string = projToKey(proj.name)

const
  recipesDirName* = "recipes_"
  utils = "recipe_utils"
  envDirName = "env"

template recipesDir(workspace): untyped = workspace / recipesDirName

proc toRecipe*(workspace: string, proj: Project): string =
  recipesDir(workspace) / proj.projToKey

proc gitExec(dir, cmd: string): bool {.discardable.} =
  withDir dir:
    let (outp, exitCode) = execCmdEx("git " & cmd)
    result = "nothing added to commit" in outp or exitCode == 0

proc writeHelper() =
  writeFile(utils & ".nim", """
# Generated by Nawabs.

import ospaths

template withDir*(dir, body) =
  let oldDir = getCurrentDir()
  try:
    setCurrentDir(dir)
    body
  finally:
    setCurrentDir(oldDir)

template gitDep*(name, url, commit) =
  if not dirExists(name / ".git"): exec "git clone " & url
  withDir "$1":
    exec "git checkout " & commit

template hgDep*(name, url, commit) =
  if not dirExists("$1/.hg"): exec "hg clone $2"
  withDir "$1":
    exec "hg update -c $3"
""")

proc nailDeps(proj: Project, val: string; deps: seq[string]): string =
  result = """
# Generated by Nawabs.

import $1

""" % utils
  for d in deps:
    if dirExists(d / ".git"):
      withDir d:
        let url = execProcess("git remote get-url origin").strip()
        let commit = execProcess("git log -1 --pretty=format:%H").strip()
        result.addf("""gitDep("$1", "$2", "$3")""", d, url, commit)
    elif dirExists(d / ".hg"):
      withDir d:
        let url = execProcess("hg paths " & d).strip()
        let commit = execProcess("hg id -i").strip()
        result.addf("""hgDep("$1", "$2", "$3")""", d, url, commit)
  result.add "\n\nwithDir \"" & proj.toPath & "\":\n"
  result.add "  exec \"\"\"" & val & "\"\"\"\n"

proc init*(workspace: string) =
  let dir = recipesDir(workspace)
  if not dirExists(dir):
    createDir dir
    withDir dir:
      exec "git init"
      writeHelper()
      exec "git add " & utils & ".nim"
      exec "git commit -am \"nawabs: first commit\""

proc writeRecipe*(workspace: string, proj: Project, val: string; deps: seq[string]) =
  try:
    let dir = recipesDir(workspace)
    let dest = dir / proj.projToKey
    writeFile dest, nailDeps(proj, val, deps)
    gitExec dir, "add " & dest
    gitExec dir, "commit -am \"nawabs: automatic commit (store recipe)\""
  except IOError:
    discard "failure to write a recipe does no harm"

proc writeKeyValPair*(workspace: string, key, val: string) =
  let dir = recipesDir(workspace)
  let envdir = dir / envDirName
  createDir envdir
  let k = envdir / projToKey(key) & ".key"
  # if the file already exists, store the old version in git:
  if fileExists(k):
    gitExec dir, "git add " & k
    gitExec dir, "commit -am \"nawabs: automatic commit (store key/value pair)\""
  writeFile(k, val)

proc getValue*(workspace: string, key: string): string =
  let k = recipesDir(workspace) / envDirName / projToKey(key) & ".key"
  result = readFile(k)
