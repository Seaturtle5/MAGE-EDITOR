"""Stage the editor with a local MAGE content library, then run Godot."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, default=os.environ.get("MAGE_ENGINE"))
    parser.add_argument("--example", type=Path, help="Optional example pack to copy into the editor")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    args, forwarded = parser.parse_known_args()
    source = Path(__file__).resolve().parent
    engine = args.engine or source.parent / "01-Game Engine"
    if not (engine / "engine/content/content_db.gd").is_file():
        parser.error("Choose a MAGE checkout with --engine PATH or MAGE_ENGINE.")
    if not shutil.which(args.godot):
        parser.error("Godot is missing; set GODOT or pass --godot PATH.")
    example = args.example or engine / "packs/example-adventure"
    # Imports and generated files belong to this temporary project, never to
    # either source checkout. Copy the current library rather than forking it.
    with tempfile.TemporaryDirectory(prefix="mage-editor-") as staging:
        runtime = Path(staging)
        shutil.copy2(source / "project.godot", runtime / "project.godot")
        shutil.copytree(source / "src", runtime / "src", ignore=shutil.ignore_patterns("*.uid"))
        shutil.copytree(engine / "engine", runtime / "engine", ignore=shutil.ignore_patterns("*.uid"))
        if (engine / "ui/fonts").is_dir():
            shutil.copytree(engine / "ui/fonts", runtime / "fonts", ignore=shutil.ignore_patterns("*.import"))
        if (example / "pack.fsc").is_file():
            shutil.copytree(example, runtime / "example-pack")
        result = subprocess.run(
            [args.godot, "--headless", "--path", staging, "--editor", "--import"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        if result.returncode or "SCRIPT ERROR" in result.stdout or "Parse Error" in result.stdout:
            print(result.stdout)
            return result.returncode or 1
        return subprocess.run([args.godot, "--path", staging, *forwarded]).returncode


if __name__ == "__main__":
    raise SystemExit(main())
