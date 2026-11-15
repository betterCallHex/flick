#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys

HOMEBREW = ("/opt/homebrew/", "/usr/local/")


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def linked(binary):
    return [line.strip().split(" (")[0] for line in run("otool", "-L", binary).splitlines()[1:]]


def rpaths(binary):
    lines = [line.split() for line in run("otool", "-l", binary).splitlines()]
    return [lines[index + 2][1] for index, line in enumerate(lines) if line == ["cmd", "LC_RPATH"]]


def homebrew_dependencies(binary):
    for name in linked(binary):
        if name.startswith(HOMEBREW):
            yield name, os.path.realpath(name)
        elif name.startswith("@rpath/") and binary.startswith(HOMEBREW):
            yield name, os.path.realpath(os.path.join(os.path.dirname(binary), name.removeprefix("@rpath/")))


def collect(executable):
    found = {}
    pending = [executable]
    while pending:
        binary = pending.pop()
        for name, source in homebrew_dependencies(binary):
            if os.path.basename(name) not in found:
                found[os.path.basename(name)] = source
                pending.append(source)
    return found


def relink(binary, libraries, keep_rpaths=False):
    changes = []
    for name in linked(binary):
        if os.path.basename(name) in libraries and not name.startswith("@rpath/"):
            changes += ["-change", name, f"@rpath/{os.path.basename(name)}"]
    for path in [] if keep_rpaths else rpaths(binary):
        changes += ["-delete_rpath", path]
    if changes:
        run("install_name_tool", *changes, binary)


def main(app):
    executable = os.path.join(app, "Contents/MacOS/Flick")
    frameworks = os.path.join(app, "Contents/Frameworks")
    libraries = collect(executable)
    for name, source in libraries.items():
        target = os.path.join(frameworks, name)
        shutil.copyfile(source, target)
        os.chmod(target, 0o755)
        run("install_name_tool", "-id", f"@rpath/{name}", target)
        relink(target, libraries)
        run("codesign", "--force", "--sign", "-", target)
    relink(executable, libraries, keep_rpaths=True)

    leftovers = [
        f"{os.path.basename(binary)} -> {name}"
        for binary in [executable] + [os.path.join(frameworks, name) for name in libraries]
        for name in linked(binary)
        if name.startswith(HOMEBREW) or (name.startswith("@rpath/") and name.removeprefix("@rpath/").split("/")[0] not in libraries.keys() | {"Sparkle.framework"})
    ]
    if leftovers:
        sys.exit("Still linked outside the app:\n" + "\n".join(leftovers))
    print(f"Bundled {len(libraries)} libraries into {frameworks}")


main(sys.argv[1])
