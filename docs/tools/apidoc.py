#!/usr/bin/env python3
"""Довідник API з fpdoc-описів (packages/*/xml/*.xml).

Пакети та їхні модулі перелічено в docs/apidoc.toml.

  apidoc.py build      генерує Markdown у docs/concurrency/api/<пакет>/ для MkDocs
  apidoc.py coverage   покриття описами; --strict повертає 1, якщо є неописані
                       або «осиротілі» елементи (опис є, а в коді елемента вже немає)
  apidoc.py skeleton P [МОДУЛЬ]
                       XML-заготовки для неописаних елементів пакета P

Потрібні makeskel і fpdoc: спершу шукаються в utils/fpdoc/bin/<ціль>/,
потім у PATH; шлях можна задати змінними MAKESKEL і FPDOC.
"""
import argparse
import fnmatch
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONF = os.path.join(ROOT, "docs", "apidoc.toml")
API_OUT = os.path.join(ROOT, "docs", "concurrency", "api")

# Вузли, які makeskel створює, але описувати їх не потрібно.
SKIP_KINDS = {"uses unit"}

# Прапорці makeskel для перевірки покриття: аргументи й результати функцій
# описуються в тексті методу, приватні й захищені члени не є публічним API.
COVERAGE_FLAGS = ["--disable-arguments", "--disable-function-results",
                  "--disable-private", "--disable-protected", "--disable-override",
                  "--disable-errors", "--disable-seealso"]

ELEMENT_RE = re.compile(r"<!--\s*(.*?)\s+Visibility:[^>]*-->\s*<element name=\"([^\"]+)\"")


def load_config():
    with open(CONF, "rb") as f:
        conf = tomllib.load(f)
    return conf["defaults"], conf["package"]


def find_tool(name):
    env = os.environ.get(name.upper())
    if env:
        return env
    for target in ("x86_64-linux", "aarch64-linux"):
        p = os.path.join(ROOT, "utils", "fpdoc", "bin", target, name)
        if os.access(p, os.X_OK):
            return p
    p = shutil.which(name)
    if not p:
        sys.exit(f"apidoc: не знайдено {name} (зберіть utils/fpdoc або задайте {name.upper()})")
    return p


def input_arg(unit, pkg, defaults):
    dirs = {os.path.dirname(u) for u in pkg["units"]} | set(pkg.get("include", []))
    inc = " ".join(f"-Fi{os.path.join(ROOT, d)}" for d in sorted(dirs))
    return f"{os.path.join(ROOT, unit)} {defaults['options']} {inc}"


def module_name(unit):
    return os.path.splitext(os.path.basename(unit))[0]


def skeleton_text(unit, pkg, defaults, flags, update_descr=None):
    """Запускає makeskel для одного модуля й повертає згенерований XML."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "skel.xml")
        cmd = [find_tool("makeskel"), f"--package={pkg['name']}",
               f"--input={input_arg(unit, pkg, defaults)}", f"--output={out}"] + flags
        if update_descr:
            cmd.append("--update")
            cmd += [f"--descr={os.path.join(ROOT, d)}" for d in update_descr]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0 or not os.path.exists(out):
            sys.exit(f"apidoc: makeskel не розібрав {unit}:\n{res.stdout}{res.stderr}")
        with open(out, encoding="latin-1") as f:
            return f.read()


def skeleton_elements(text, keep_all=False):
    """Пари (ім'я, вид) з XML makeskel; вузли uses і параметри дженериків пропускаються."""
    result = {}
    for kind, name in ELEMENT_RE.findall(text):
        if not keep_all and kind in SKIP_KINDS:
            continue
        if not keep_all and kind == "generic type" and "." in name:
            continue  # параметр типу, наприклад IFuture.T
        result.setdefault(name.lower(), (name, kind))
    return result


def described_elements(pkg):
    """{модуль: {ім'я: має_опис}} з XML-описів пакета."""
    modules = {}
    for d in pkg["descr"]:
        path = os.path.join(ROOT, d)
        if not os.path.exists(path):
            continue
        root = ET.parse(path).getroot()
        for mod in root.iter("module"):
            elems = modules.setdefault(mod.get("name").lower(), {})
            for el in mod.iter("element"):
                texts = ["".join(el.find(t).itertext()).strip()
                         for t in ("short", "descr") if el.find(t) is not None]
                elems[el.get("name").lower()] = bool(el.get("link")) or any(texts)
    return modules


def matches(name, patterns):
    """Ігнор-правила у стилі .gitignore: останній збіг перемагає, «!» повертає в область."""
    result = False
    for p in patterns:
        neg = p.startswith("!")
        if fnmatch.fnmatchcase(name.lower(), p.lstrip("!").lower()):
            result = not neg
    return result


def in_scope(name, mod, pkg):
    scope = pkg.get("scope", {}).get(mod)
    if scope and not matches(name, scope):
        return False
    return not matches(name, pkg.get("internal", []))


def coverage(args):
    defaults, packages = load_config()
    total_missing = total_orphans = 0
    print(f"{'модуль':<26}{'описано':>10}{'усього':>8}{'%':>6}")
    for pkg in packages:
        if args.package and pkg["name"] != args.package:
            continue
        described = described_elements(pkg)
        for unit in pkg["units"]:
            mod = module_name(unit)
            elems = skeleton_elements(skeleton_text(unit, pkg, defaults, COVERAGE_FLAGS))
            scoped = {k: v for k, v in elems.items() if in_scope(v[0], mod, pkg)}
            have = described.get(mod.lower(), {})
            missing = sorted(v[0] for k, v in scoped.items() if not have.get(k))
            # Повний скелет (з аргументами, приватними членами тощо) для пошуку
            # описів, яким у коді вже нічого не відповідає.
            full = skeleton_elements(skeleton_text(unit, pkg, defaults, []), keep_all=True)
            orphans = sorted(n for n in have if n not in full)
            done = len(scoped) - len(missing)
            pct = 100 * done // len(scoped) if scoped else 100
            print(f"{mod:<26}{done:>10}{len(scoped):>8}{pct:>5}%")
            if missing and (args.list or args.strict):
                for m in missing:
                    print(f"    неописано: {m}  [{scoped[m.lower()][1]}]")
            for o in orphans:
                print(f"    осиротілий опис: {o}")
            total_missing += len(missing)
            total_orphans += len(orphans)
    if args.strict and (total_missing or total_orphans):
        print(f"\napidoc: неописаних {total_missing}, осиротілих {total_orphans}", file=sys.stderr)
        return 1
    return 0


def skeleton(args):
    defaults, packages = load_config()
    pkg = next((p for p in packages if p["name"] == args.package), None)
    if not pkg:
        sys.exit(f"apidoc: пакета {args.package} немає в {CONF}")
    for unit in pkg["units"]:
        if args.module and module_name(unit).lower() != args.module.lower():
            continue
        print(skeleton_text(unit, pkg, defaults, COVERAGE_FLAGS, update_descr=pkg["descr"]))
    return 0


def build(args):
    defaults, packages = load_config()
    fpdoc = find_tool("fpdoc")
    os.makedirs(API_OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        contents = []  # файли --content попередніх пакетів для перехресних посилань
        for pkg in packages:
            out = os.path.join(tmp, pkg["name"])
            content = os.path.join(tmp, pkg["name"] + ".cnt")
            cmd = [fpdoc, "--format=md", f"--package={pkg['name']}", f"--output={out}",
                   f"--content={content}", "--use-subpagenames"]
            cmd += [f"--descr={os.path.join(ROOT, d)}" for d in pkg["descr"]
                    if os.path.exists(os.path.join(ROOT, d))]
            cmd += [f"--input={input_arg(u, pkg, defaults)}" for u in pkg["units"]]
            cmd += [f"--import={c},../../{n}/" for c, n in contents]
            res = subprocess.run(cmd, capture_output=True, text=True)
            log = res.stdout + res.stderr
            if res.returncode != 0:
                sys.exit(f"apidoc: fpdoc не зміг зібрати {pkg['name']}:\n{log}")
            unresolved = re.search(r"Unresolved links: (\d+)", log)
            n = int(unresolved.group(1)) if unresolved else 0
            print(f"{pkg['name']}: {len(os.listdir(os.path.join(out, 'docs')))} записів, "
                  f"нерозв'язаних посилань: {n}")
            if n and args.verbose:
                print(log)
            dest = os.path.join(API_OUT, pkg["name"])
            shutil.rmtree(dest, ignore_errors=True)
            shutil.copytree(os.path.join(out, "docs"), dest)
            contents.append((content, pkg["name"]))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("-v", "--verbose", action="store_true")
    c = sub.add_parser("coverage")
    c.add_argument("package", nargs="?")
    c.add_argument("--list", action="store_true", help="перелічити неописані елементи")
    c.add_argument("--strict", action="store_true")
    s = sub.add_parser("skeleton")
    s.add_argument("package")
    s.add_argument("module", nargs="?")
    args = ap.parse_args()
    return {"build": build, "coverage": coverage, "skeleton": skeleton}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
