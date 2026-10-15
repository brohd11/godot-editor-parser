"""Run tag discovery without the editor service, AddonLib, or GDScriptParser installed."""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[5]
    with tempfile.TemporaryDirectory(prefix="tag-parser-core-") as directory:
        project = Path(directory)
        for relative in (
            "addons/_lib/editor_parser/src/tag/scanner.gd",
            "addons/_lib/editor_parser/src/tag/options.gd",
            "addons/_lib/editor_parser/src/tag/registry.gd",
            "addons/_lib/editor_parser/src/tag/metadata.gd",
            "addons/_lib/editor_parser/_export_ignore/test/run_headless.gd",
            "addons/_lib/editor_parser/_export_ignore/test/registry_test.gd",
            "addons/_lib/editor_parser/_export_ignore/test/scanner_test.gd",
            "addons/_lib/editor_parser/_export_ignore/test/options_test.gd",
            "addons/_lib/editor_parser/_export_ignore/test/metadata_test.gd",
        ):
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / relative, target)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Tag Parser Core Test"\n')
        result = subprocess.run(
            [args.godot, "--headless", "--path", str(project), "--log-file", str(project / "run.log"),
             "--script", "res://addons/_lib/editor_parser/_export_ignore/test/run_headless.gd", "--", "--core"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=120,
        )
        print(result.stdout, end="")
        if result.returncode or "SCRIPT ERROR:" in result.stdout or "ERROR:" in result.stdout:
            raise SystemExit(1)
        print("PASS core runs without editor services or other addon libraries")


if __name__ == "__main__":
    main()
