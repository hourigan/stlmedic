import json
from pathlib import Path
import subprocess
import sys
import time

import numpy as np
import pytest
import trimesh

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Engine"))
import engine


def test_closed_cube_passes():
    report, _ = engine.analyze(trimesh.creation.box())
    assert report["checks_passed"]
    assert report["vertices"] == 8
    assert report["triangles"] == 12
    assert report["volume"] == pytest.approx(1)


@pytest.mark.parametrize("encoding", ["stl", "stl_ascii"])
def test_binary_and_ascii_roundtrip(tmp_path, encoding):
    path = tmp_path / "model with spaces.stl"
    trimesh.creation.box(extents=[12, 24, 36]).export(path, file_type=encoding)
    mesh = engine.load_stl(path)
    assert len(mesh.vertices) == 8
    assert engine.analyze(mesh)[0]["checks_passed"]
    assert mesh.extents.tolist() == [12, 24, 36]


def test_large_open_boundary_is_filled():
    sphere = trimesh.creation.icosphere(subdivisions=3, radius=25)
    sphere.update_faces(sphere.triangles_center[:, 2] < 20)
    assert engine.analyze(sphere)[0]["boundary_edges"] > 4
    fixed, _ = engine.repair(sphere)
    assert engine.analyze(fixed)[0]["checks_passed"]
    assert fixed.extents[:2] == pytest.approx(sphere.extents[:2])


def test_cleanup_preserves_opening():
    box = trimesh.creation.box()
    box.update_faces(np.arange(12) < 10)
    fixed, _ = engine.repair(box, mode="cleanup")
    assert engine.analyze(fixed)[0]["boundary_edges"] > 0
    assert not fixed.is_watertight


def test_duplicate_degenerate_and_isolated_vertices():
    box = trimesh.creation.box()
    broken = engine.mesh_of(np.vstack([box.vertices, [99, 99, 99]]),
                            np.vstack([box.faces, box.faces[0], [0, 0, 1]]))
    report, _ = engine.analyze(broken)
    assert report["duplicate_triangles"] == 1
    assert report["degenerate_triangles"] == 1
    assert report["isolated_vertices"] == 1
    fixed, _ = engine.repair(broken, mode="cleanup")
    assert engine.analyze(fixed)[0]["checks_passed"]
    assert len(fixed.faces) == 12


def test_non_manifold_edge():
    vertices = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1]]
    mesh = engine.mesh_of(vertices, [[0, 1, 2], [1, 0, 3], [0, 1, 4]])
    report, _ = engine.analyze(mesh)
    assert report["non_manifold_edges"] == 1
    assert report["non_manifold_vertices"] == 2
    assert not report["checks_passed"]


def test_bow_tie_vertex_even_without_bad_edges():
    a = trimesh.creation.box()
    b = trimesh.creation.box()
    b.apply_translation([1, 1, 1])
    mesh = trimesh.util.concatenate([a, b])
    mesh.merge_vertices()
    report, _ = engine.analyze(mesh)
    assert report["non_manifold_edges"] == 0
    assert report["non_manifold_vertices"] == 1
    assert not report["checks_passed"]


def test_flipped_face_and_inside_out_shell():
    box = trimesh.creation.box()
    box.faces[0] = box.faces[0][::-1]
    assert not engine.analyze(box)[0]["winding_consistent"]
    fixed, _ = engine.repair(box, mode="cleanup")
    assert engine.analyze(fixed)[0]["checks_passed"]
    box.invert()
    fixed, _ = engine.repair(box, mode="cleanup")
    assert fixed.volume > 0


def separated_boxes():
    a = trimesh.creation.box()
    b = trimesh.creation.box()
    b.apply_translation([4, 0, 0])
    return trimesh.util.concatenate([a, b])


def test_default_preserves_disconnected_printable_parts():
    fixed, _ = engine.repair(separated_boxes())
    report, _ = engine.analyze(fixed)
    assert report["shells"] == 2
    assert report["volume"] == pytest.approx(2)
    assert report["checks_passed"]


def test_largest_shell_is_explicit():
    fixed, notes = engine.repair(separated_boxes(), largest=True)
    assert engine.analyze(fixed)[0]["shells"] == 1
    assert fixed.volume == pytest.approx(1)
    assert any("removed 1" in n for n in notes)


def test_overlaps_detected_then_unioned():
    a = trimesh.creation.box(extents=[2, 2, 2])
    b = trimesh.creation.box(extents=[2, 2, 2])
    b.apply_translation([1.1, 0.2, 0.3])
    mesh = trimesh.util.concatenate([a, b])
    report, _ = engine.analyze(mesh)
    assert report["intersecting_triangles"] > 0
    assert not report["checks_passed"]
    fixed, _ = engine.repair(mesh, mode="cleanup", union=True)
    report, _ = engine.analyze(fixed)
    assert report["checks_passed"]
    assert report["shells"] == 1
    assert report["volume"] == pytest.approx(16 - 0.9 * 1.8 * 1.7)


def test_weld_nearby_seam():
    box = trimesh.creation.box()
    vertices = box.vertices[box.faces].reshape(-1, 3).copy()
    vertices[0] += [0.00001, 0, 0]
    mesh = engine.mesh_of(vertices, np.arange(len(vertices)).reshape(-1, 3))
    fixed, _ = engine.repair(mesh, mode="cleanup", tolerance=0.001)
    assert engine.analyze(fixed)[0]["checks_passed"]


def test_empty_and_malformed_input(tmp_path):
    path = tmp_path / "empty.stl"
    path.write_bytes(b"not an STL")
    with pytest.raises((ValueError, IndexError)):
        engine.load_stl(path)


def test_end_to_end_validates_export_without_changing_source(tmp_path):
    source = tmp_path / "original.stl"
    box = trimesh.creation.box()
    box.update_faces(np.arange(12) < 10)
    box.export(source)
    original_bytes = source.read_bytes()
    output = tmp_path / "result"
    process = subprocess.run([sys.executable, "Engine/engine.py", "repair", "--input", str(source),
                              "--output", str(output)], capture_output=True)
    assert process.returncode == 0, process.stderr.decode()
    result = json.loads((output / "result.json").read_text())
    assert result["report"]["checks_passed"]
    assert not result["before"]["watertight"]
    assert source.read_bytes() == original_bytes
    assert engine.analyze(engine.load_stl(output / "repaired.stl"))[0]["checks_passed"]


def test_cli_failure_is_structured(tmp_path):
    output = tmp_path / "failure"
    process = subprocess.run([sys.executable, "Engine/engine.py", "analyze", "--input", "/missing.stl",
                              "--output", str(output)], capture_output=True)
    assert process.returncode != 0
    assert "error" in json.loads((output / "result.json").read_text())
    progress = json.loads((output / "progress.json").read_text())
    assert progress["step"] == 1
    assert progress["total"] == 4


def test_import_snapshot_survives_source_changes(tmp_path):
    source = tmp_path / "original.stl"
    trimesh.creation.box().export(source)
    original = source.read_bytes()
    output = tmp_path / "inspection"
    process = subprocess.run([sys.executable, "Engine/engine.py", "analyze", "--input", str(source),
                              "--output", str(output)], capture_output=True)
    assert process.returncode == 0, process.stderr.decode()
    result = json.loads((output / "result.json").read_text())
    source.write_bytes(b"changed outside the app")
    assert Path(result["snapshot"]).read_bytes() == original
    assert result["input"] == str(source)
    assert engine.analyze(engine.load_stl(result["snapshot"]))[0]["checks_passed"]


def test_simplified_preview_preserves_full_resolution_mesh_and_export(tmp_path):
    mesh = trimesh.creation.icosphere(subdivisions=3)
    original_vertices = mesh.vertices.copy()
    original_faces = mesh.faces.copy()
    count = engine.preview(mesh, tmp_path, np.empty((0, 2), dtype=np.int64), face_limit=100)
    assert 0 < count <= 100
    assert len(engine.load_stl(tmp_path / "preview.stl").faces) == count
    np.testing.assert_array_equal(mesh.vertices, original_vertices)
    np.testing.assert_array_equal(mesh.faces, original_faces)
    mesh.export(tmp_path / "full.stl")
    full = engine.load_stl(tmp_path / "full.stl")
    assert len(full.faces) == 1280
    assert engine.analyze(full)[0]["checks_passed"]


def test_binary_triangle_limit_checked_before_allocating(tmp_path, monkeypatch):
    path = tmp_path / "two shells.stl"
    separated_boxes().export(path)
    monkeypatch.setattr(engine, "MAX_FACES", 12)

    def unexpected_load(*args, **kwargs):
        pytest.fail("Oversized binary input was allocated before its count was checked")

    monkeypatch.setattr(engine.trimesh, "load_mesh", unexpected_load)
    with pytest.raises(ValueError, match="up to 12 triangles"):
        engine.load_stl(path)


def test_sparse_winding_repairs_many_random_flips_on_separate_shells():
    a = trimesh.creation.icosphere(subdivisions=3)
    b = a.copy()
    b.apply_translation([5, 0, 0])
    mesh = trimesh.util.concatenate([a, b])
    faces = mesh.faces.copy()
    flip = np.random.default_rng(42).random(len(faces)) < 0.4
    faces[flip] = faces[flip, ::-1]
    mesh.faces = faces
    assert not mesh.is_winding_consistent
    fixed, _ = engine.repair(mesh, mode="cleanup")
    report, _ = engine.analyze(fixed)
    assert report["shells"] == 2
    assert report["checks_passed"]
    assert fixed.volume == pytest.approx(2 * a.volume)


def test_rebuild_recovers_closed_surface_from_damaged_sphere(tmp_path):
    sphere = trimesh.creation.icosphere(subdivisions=3)
    sphere.update_faces(sphere.triangles_center[:, 2] < 0.8)
    sphere.remove_unreferenced_vertices()
    original_vertices = sphere.vertices.copy()
    original_faces = sphere.faces.copy()
    rebuilt = engine.rebuild_surface(sphere, depth=6)
    engine.trimesh.repair.fix_inversion(rebuilt, multibody=True)
    rebuilt.export(tmp_path / "rebuilt.stl")
    report, _ = engine.analyze(engine.load_stl(tmp_path / "rebuilt.stl"))
    assert report["checks_passed"]
    assert rebuilt.extents[0] == pytest.approx(2, abs=0.08)
    np.testing.assert_array_equal(sphere.vertices, original_vertices)
    np.testing.assert_array_equal(sphere.faces, original_faces)


def test_live_cli_progress_is_atomic_monotonic_and_reserves_viewer_stage(tmp_path):
    source = tmp_path / "damaged.stl"
    mesh = trimesh.creation.icosphere(subdivisions=4)
    mesh.update_faces(mesh.triangles_center[:, 2] < 0.8)
    mesh.export(source)
    output = tmp_path / "repair"
    snapshots = []
    with (tmp_path / "engine.log").open("wb") as log:
        process = subprocess.Popen(
            [sys.executable, "Engine/engine.py", "repair", "--input", str(source),
             "--output", str(output)], stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 30
            while process.poll() is None:
                progress = output / "progress.json"
                if progress.exists():
                    # Concurrent readers must never observe half-written JSON.
                    snapshots.append(json.loads(progress.read_text()))
                if time.monotonic() > deadline:
                    pytest.fail("Geometry fixture exceeded its progress-test timeout")
                time.sleep(0.002)
            assert process.returncode == 0, (tmp_path / "engine.log").read_text()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    snapshots.append(json.loads((output / "progress.json").read_text()))
    assert len(snapshots) > 1
    assert [s["step"] for s in snapshots] == sorted(s["step"] for s in snapshots)
    assert all(s["total"] == 6 and 1 <= s["step"] <= 5 for s in snapshots)
    assert all(s["title"] and s["message"] for s in snapshots)
    assert snapshots[-1]["step"] == 5  # Stage 6 runs in the native 3D viewer.
    assert json.loads((output / "result.json").read_text())["report"]["checks_passed"]
