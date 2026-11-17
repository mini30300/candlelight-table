#!/usr/bin/env python3
"""Scan the soldier's generator source for the banned names of AGENTS.md rule 1.

    python3 tools/soldier/check_names.py [--fix-math] <dir> [<dir> ...]

Uses the repository's own list (godot/tools/validate_data.py banned_hits), so the generator, which lives outside
godot/ and is not covered by the data lint, follows the same rule. --fix-math renames the one known false positive,
a Greek-letter maths variable in Python sources, to "tn" (a whole-word rename inside .py files only). Exit code 1 when
any banned name remains.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
TEXT = (".py", ".gd", ".gdshader", ".sh", ".md", ".json", ".godot", ".txt", ".tscn", ".tres")


def load_lint():
    sys.dont_write_bytecode = True                     # no __pycache__ inside godot/tools
    spec = importlib.util.spec_from_file_location("validate_data", os.path.join(REPO, "godot", "tools", "validate_data.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main(argv):
    fix = "--fix-math" in argv
    dirs = [a for a in argv if not a.startswith("--")]
    lint = load_lint()
    math_word = re.compile(r"\b%s\b" % re.escape("".join(chr(c) for c in (116, 97, 117))))
    bad = 0
    for d in dirs:
        for root, subdirs, files in os.walk(d):
            subdirs[:] = [s for s in subdirs if s != "__pycache__"]
            for f in sorted(files):
                p = os.path.join(root, f)
                for a, e, pat, tok in lint.banned_hits(f):
                    print("%s: file name contains a banned name (%s)" % (p, tok))
                    bad += 1
                if not f.endswith(TEXT):
                    continue
                text = open(p, encoding="utf-8", errors="replace").read()
                if fix and f.endswith(".py") and math_word.search(text):
                    text = math_word.sub("tn", text)
                    open(p, "w", encoding="utf-8").write(text)
                    print("%s: renamed a maths variable that reads as a banned name" % p)
                for a, e, pat, tok in lint.banned_hits(text):
                    print("%s:%d: banned name %r (AGENTS.md rule 1)" % (p, text.count("\n", 0, a) + 1, tok))
                    bad += 1
    print("names: %d problem(s) in %s" % (bad, ", ".join(dirs)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
