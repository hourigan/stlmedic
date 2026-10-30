#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v uv >/dev/null || { echo "Install uv first: https://docs.astral.sh/uv/getting-started/installation/"; exit 1; }
uv python install 3.12.12
uv venv --python 3.12.12 --allow-existing .venv
uv pip install --python .venv/bin/python -r requirements.txt
swift build -c release
app="$(pwd)/dist/STL Medic.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Engine"
cp .build/release/STLMedic "$app/Contents/MacOS/STLMedic"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Engine/engine.py "$app/Contents/Resources/Engine/engine.py"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
# uv's standalone CPython is relocatable. Bundle a real interpreter, not a venv
# symlink that would stop working when the app moves to another Mac.
python_base="$(.venv/bin/python -c 'import sys; print(sys.base_prefix)')"
if [ ! -x "$app/Contents/Resources/Python/bin/python3" ]; then
    ditto "$python_base" "$app/Contents/Resources/Python"
fi
uv pip install --python .venv/bin/python --target "$app/Contents/Resources/Python/lib/python3.12/site-packages" -r requirements.txt
swift scripts/icon.swift "$app/Contents/Resources"
iconutil -c icns "$app/Contents/Resources/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
# Smoke-test imports using the embedded interpreter in isolated mode.
"$app/Contents/Resources/Python/bin/python3" -I -B -c 'import trimesh, pymeshfix, manifold3d, scipy, networkx, fast_simplification, pymeshlab; print("Bundled engine verified")'
mkdir -p build/package-smoke
"$app/Contents/Resources/Python/bin/python3" -I -B "$app/Contents/Resources/Engine/engine.py" demo --output "$(pwd)/build/package-smoke/input"
"$app/Contents/Resources/Python/bin/python3" -I -B "$app/Contents/Resources/Engine/engine.py" repair --input "$(pwd)/build/package-smoke/input/Demo - damaged sphere.stl" --output "$(pwd)/build/package-smoke/output"
"$app/Contents/Resources/Python/bin/python3" -I -B -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["report"]["checks_passed"], r; print("Packaged demo repair passed")' "$(pwd)/build/package-smoke/output/result.json"
"$app/Contents/Resources/Python/bin/python3" -I -B scripts/smoke_rebuild.py "$app/Contents/Resources/Engine" "$(pwd)/build/package-smoke/rebuild"
codesign --force --deep --sign - "$app"
echo "Built: $app"
