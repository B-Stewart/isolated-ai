#!/usr/bin/env bash
set -euo pipefail

scratch="$(mktemp -d "${TMPDIR:-/tmp}/gamedev-smoke.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

echo "[1/3] Checking Godot .NET editor"
godot_version="$(godot --headless --version)"
case "$godot_version" in
    *4.7.2*mono*) ;;
    *) echo "ERROR: expected Godot 4.7.2 .NET/mono editor, got: $godot_version" >&2; exit 1 ;;
esac
printf 'Godot OK: %s\n' "$godot_version"

echo "[2/3] Building and running disposable Godot C# .NET 8 project"
project="$scratch/godot-csharp"
mkdir -p "$project"
cat > "$project/Smoke.csproj" <<'EOF'
<Project Sdk="Godot.NET.Sdk/4.7.2">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <EnableDynamicLoading>true</EnableDynamicLoading>
  </PropertyGroup>
</Project>
EOF
cat > "$project/project.godot" <<'EOF'
config_version=5

[application]
config/name="Gamedev smoke test"
run/main_scene="res://Main.tscn"

[dotnet]
project/assembly_name="Smoke"
EOF
cat > "$project/Main.tscn" <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Smoke.cs" id="1"]

[node name="Main" type="Node"]
script = ExtResource("1")
EOF
cat > "$project/Smoke.cs" <<'EOF'
using Godot;

public partial class Smoke : Node
{
    public override void _Ready()
    {
        GD.Print("GAMEDEV_CSHARP_SMOKE_OK");
        GetTree().Quit();
    }
}
EOF
(cd "$project" && dotnet build Smoke.csproj)
godot --headless --editor --path "$project" --import
run_log="$scratch/godot-run.log"
godot --headless --path "$project" --quit-after 10 >"$run_log" 2>&1
if ! grep -q 'GAMEDEV_CSHARP_SMOKE_OK' "$run_log"; then
    cat "$run_log" >&2
    echo "ERROR: Godot did not execute the C# smoke script" >&2
    exit 1
fi
echo "Godot C# execution OK"

echo "[3/3] Rendering a disposable Blender Cycles asset"
render="$scratch/blender-smoke.png"
blender_script="$scratch/blender-smoke.py"
cat > "$blender_script" <<'PY'
import os
import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add()
cube = bpy.context.object
cube.name = "SmokeCube"
bpy.ops.object.camera_add(location=(4, -4, 3))
camera = bpy.context.object
camera.rotation_euler = (cube.location - camera.location).to_track_quat("-Z", "Y").to_euler()
scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 4
scene.render.resolution_x = 64
scene.render.resolution_y = 64
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = bpy.path.abspath(os.environ["BLENDER_SMOKE_RENDER"])
bpy.ops.render.render(write_still=True)
PY
BLENDER_SMOKE_RENDER="$render" blender --background --factory-startup --python-exit-code 1 --python "$blender_script"
python3 - "$render" <<'PY'
from pathlib import Path
import sys

render = Path(sys.argv[1])
if not render.is_file() or render.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit("ERROR: Blender did not produce a valid PNG render")
PY
echo "Blender Cycles render OK: $render"

echo "Gamedev image smoke test passed."
