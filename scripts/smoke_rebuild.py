"""Check the packaged reconstruction runtime, not the development venv."""
from pathlib import Path
import sys

sys.path.insert(0, sys.argv[1])
import engine
import trimesh

output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
sphere = trimesh.creation.icosphere(subdivisions=3)
sphere.update_faces(sphere.triangles_center[:, 2] < 0.8)
sphere.remove_unreferenced_vertices()
rebuilt = engine.rebuild_surface(sphere, depth=6)
trimesh.repair.fix_inversion(rebuilt, multibody=True)
rebuilt.export(output / "rebuilt.stl")
report, _ = engine.analyze(engine.load_stl(output / "rebuilt.stl"))
assert report["checks_passed"], report
print("Packaged surface rebuild passed")
