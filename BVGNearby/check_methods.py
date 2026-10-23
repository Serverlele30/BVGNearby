#!/usr/bin/env python3
"""Prueft, ob jede in einer .h deklarierte Methode in der passenden .m implementiert ist.
Hintergrund: Objective-C kompiliert auch dann, wenn eine Methode fehlt - die App stuerzt erst
zur Laufzeit mit "unrecognized selector" ab.

Aufruf (im Projektordner):  python3 BVGNearby/check_methods.py BVGNearby
Rueckgabe: 0 = alles da, 1 = etwas fehlt (bricht z.B. deploy.sh ab)
"""
import glob
import os
import re
import sys

folder = sys.argv[1] if len(sys.argv) > 1 else "."
missing = []

for header in sorted(glob.glob(os.path.join(folder, "*.h"))):
    impl_path = header[:-2] + ".m"
    if not os.path.exists(impl_path):
        continue
    hdr = open(header, encoding="utf-8").read()
    impl = open(impl_path, encoding="utf-8").read()
    for decl in re.findall(r"^[+-]\s*\([^)]*\)\s*[^;]+;", hdr, re.M):
        kind = decl[0]
        parts = re.findall(r"(\w+)\s*:", decl)
        if parts:
            selector = "".join(p + ":" for p in parts)
            pattern = (r"^" + re.escape(kind) + r"\s*\([^)]*\)\s*"
                       + r".*?".join(re.escape(p) + r"\s*:" for p in parts) + r"[^;{]*\{")
        else:
            selector = re.match(r"^[+-]\s*\([^)]*\)\s*(\w+)", decl).group(1)
            pattern = r"^" + re.escape(kind) + r"\s*\([^)]*\)\s*" + re.escape(selector) + r"\s*\{"
        if not re.search(pattern, impl, re.M | re.S):
            missing.append(f"{os.path.basename(impl_path)}: {kind}{selector}")

if missing:
    print("FEHLENDE METHODEN (App würde abstürzen):")
    print("\n".join("  " + m for m in missing))
    sys.exit(1)
print("Methoden-Check: alle deklarierten Methoden sind implementiert.")
