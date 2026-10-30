"""Offline STL diagnostics and repair. Each request runs in an isolated process.

CLI: engine.py analyze|repair|demo --input FILE --output DIRECTORY [options]
Results go to result.json, never stdout (MeshFix writes native diagnostics there).
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import sys
import traceback

sys.dont_write_bytecode = True

import numpy as np
import trimesh
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import breadth_first_order, connected_components


MAX_FACES = 6_000_000
MAX_INPUT_BYTES = 512_000_000
PREVIEW_FACE_LIMIT = 300_000


class ProgressReporter:
    """Atomically publish real stage transitions for the native app to poll.

    The final stage belongs to the app's 3D viewer. Stages measure completed
    work, not estimated wall-clock time inside opaque native geometry calls.
    """
    def __init__(self, output, repairing):
        self.output = Path(output)
        self.total = 6 if repairing else 4
        self.steps = ({"load": 1, "inspect": 2, "repair": 3, "validate": 4, "preview": 5}
                      if repairing else {"load": 1, "inspect": 2, "preview": 3})
        self.state = None

    def start(self, phase, title, message):
        self.state = {"step": self.steps[phase], "total": self.total,
                      "title": title, "message": message}
        self._write()

    def detail(self, message):
        if self.state is not None:
            self.state["message"] = message
            self._write()

    def _write(self):
        temporary = self.output / "progress.json.tmp"
        temporary.write_text(json.dumps(self.state))
        os.replace(temporary, self.output / "progress.json")


def notify(progress, message):
    if progress is not None:
        progress(message)


def mesh_of(vertices, faces):
    return trimesh.Trimesh(vertices=vertices, faces=faces, process=False)


def load_stl(path):
    path = Path(path)
    if path.suffix.lower() != ".stl":
        raise ValueError("Choose a binary or ASCII STL file.")
    size = path.stat().st_size
    if size > MAX_INPUT_BYTES:
        raise ValueError("This version supports STL files up to 512 MB.")
    # Reject oversized binary tables before allocating the triangle soup.
    with path.open("rb") as source:
        header = source.read(84)
    if len(header) == 84:
        declared = struct.unpack_from("<I", header, 80)[0]
        if size == 84 + declared * 50 and declared > MAX_FACES:
            raise ValueError(f"This version supports up to {MAX_FACES:,} triangles.")
    mesh = trimesh.load_mesh(path, file_type="stl", process=False)
    if not isinstance(mesh, trimesh.Trimesh) or not len(mesh.faces):
        raise ValueError("The STL contains no triangles.")
    if len(mesh.faces) > MAX_FACES:
        raise ValueError(f"This version supports up to {MAX_FACES:,} triangles.")
    if not np.isfinite(mesh.vertices).all():
        raise ValueError("The STL contains non-finite coordinates. Re-export it from its source.")
    # STL is triangle soup. Exact welding is required for meaningful topology;
    # do not use Trimesh.process(), which would silently hide input defects.
    vertices, inverse = np.unique(mesh.vertices, axis=0, return_inverse=True)
    return mesh_of(vertices, inverse[mesh.faces])


def topology(mesh):
    f = np.asarray(mesh.faces)
    directed = f[:, [[0, 1], [1, 2], [2, 0]]].reshape(-1, 2)
    edges, inv, counts = np.unique(np.sort(directed, axis=1), axis=0,
                                   return_inverse=True, return_counts=True)
    order = np.argsort(inv, kind="stable")
    starts = np.r_[0, np.cumsum(counts)[:-1]]
    pair = starts[counts == 2]
    a, b = order[pair], order[pair + 1]
    # A vertex is manifold only when all its incident face corners form one fan.
    # Linking corners across paired edges detects bow-tie vertices even if every
    # edge has at most two incident faces.
    a0, a1 = a, (a // 3) * 3 + (a % 3 + 1) % 3
    b0, b1 = b, (b // 3) * 3 + (b % 3 + 1) % 3
    same = directed[a, 0] == directed[b, 0]
    row = np.r_[a0, a1]
    col = np.r_[np.where(same, b0, b1), np.where(same, b1, b0)]
    graph = coo_matrix((np.ones(len(row), dtype=np.uint8), (row, col)),
                       shape=(f.size, f.size)).tocsr()
    _, labels = connected_components(graph, directed=False)
    fans = np.unique(np.column_stack((f.ravel(), labels)), axis=0)
    fan_count = np.bincount(fans[:, 0], minlength=len(mesh.vertices))
    bad_vertices = set(np.flatnonzero(fan_count > 1).tolist())
    bad_vertices.update(edges[counts > 2].ravel().tolist())
    boundary = edges[counts == 1]
    boundary_groups = 0
    if len(boundary):
        _, bi = np.unique(boundary, return_inverse=True)
        bg = bi.reshape(-1, 2)
        boundary_groups = int(connected_components(coo_matrix(
            (np.ones(len(bg)), (bg[:, 0], bg[:, 1])),
            shape=(int(bi.max()) + 1,) * 2), directed=False, return_labels=False))
    face_graph = coo_matrix((np.ones(len(a)), (a // 3, b // 3)),
                            shape=(len(f), len(f))).tocsr()
    components, component_labels = connected_components(face_graph, directed=False)
    return {
        "boundary_edges": int(np.sum(counts == 1)),
        "non_manifold_edges": int(np.sum(counts > 2)),
        "non_manifold_vertices": len(bad_vertices),
        "boundary_groups": boundary_groups,
        "inconsistent_edges": int(same.sum()),
        "shells": int(components),
        "isolated_vertices": int(np.sum(np.bincount(f.ravel(), minlength=len(mesh.vertices)) == 0)),
    }, component_labels, edges[counts != 2]


def intersection_count(mesh, report):
    # MeshFix normalizes invalid connectivity while loading. Never present its
    # check of a modified surface as a check of the original invalid mesh.
    if any(report[k] for k in ("non_manifold_edges", "non_manifold_vertices",
                               "degenerate_triangles", "duplicate_triangles")):
        return None
    import pymeshfix
    check = pymeshfix.PyTMesh()
    check.set_quiet(True)
    check.load_array(np.asarray(mesh.vertices, dtype=np.float64),
                     np.asarray(mesh.faces, dtype=np.int32))
    if check.n_faces != len(mesh.faces) or check.n_points != len(mesh.vertices):
        return None
    return int(len(check.select_intersecting_triangles()))


def analyze(mesh, progress=None):
    notify(progress, "Checking edges, vertices and connected shells…")
    report, labels, bad_edges = topology(mesh)
    notify(progress, "Checking triangles, winding and volume…")
    report["vertices"] = len(mesh.vertices)
    report["triangles"] = len(mesh.faces)
    report["degenerate_triangles"] = int((~mesh.nondegenerate_faces(height=1e-10)).sum())
    report["duplicate_triangles"] = int(len(mesh.faces) - len(np.unique(
        np.sort(mesh.faces, axis=1), axis=0)))
    report["dimensions"] = mesh.extents.tolist()
    report["watertight"] = bool(mesh.is_watertight)
    report["winding_consistent"] = bool(mesh.is_winding_consistent)
    triangles = mesh.triangles
    signed = np.einsum("ij,ij->i", triangles[:, 0],
                       np.cross(triangles[:, 1], triangles[:, 2])) / 6
    volumes = np.bincount(labels, weights=signed)
    report["inverted_shells"] = int(np.sum(volumes < -1e-10))
    report["volume"] = float(signed.sum()) if mesh.is_watertight else None
    notify(progress, "Checking surface self-intersections…")
    report["intersecting_triangles"] = intersection_count(mesh, report)
    defects = ["boundary_edges", "non_manifold_edges", "non_manifold_vertices",
               "isolated_vertices", "degenerate_triangles", "duplicate_triangles",
               "inconsistent_edges", "inverted_shells"]
    report["checks_passed"] = bool(report["watertight"] and
        not any(report[k] for k in defects) and report["intersecting_triangles"] == 0
        and report["volume"] is not None and report["volume"] > 1e-10)
    return report, bad_edges


def fix_winding(mesh):
    """Orient face fans with a sparse spanning forest instead of Python graphs.

    A shared edge requires either equal or opposite flip parity on its faces.
    C-backed BFS chooses a tree; vectorized ancestor doubling propagates its
    parity. Non-orientable conflicts remain visible to the final validator.
    """
    if mesh.is_winding_consistent:
        return
    adjacency = mesh.face_adjacency
    if not len(adjacency):
        return
    shared = mesh.face_adjacency_edges

    def direction(indices):
        faces = np.asarray(mesh.faces)[indices]
        return np.any((faces == shared[:, 0, None]) &
                      (np.roll(faces, -1, axis=1) == shared[:, 1, None]), axis=1)

    weight = (direction(adjacency[:, 0]) == direction(adjacency[:, 1])).astype(np.uint8) + 1
    graph = coo_matrix((weight, (adjacency[:, 0], adjacency[:, 1])),
                       shape=(len(mesh.faces),) * 2).tocsr()
    graph = graph + graph.T
    _, labels = connected_components(graph, directed=False)
    order = np.argsort(labels, kind="stable")
    groups = np.split(order, np.flatnonzero(np.diff(labels[order])) + 1)
    flip = np.zeros(len(mesh.faces), dtype=bool)
    for group in groups:
        if len(group) < 2:
            continue
        local = graph[group][:, group]
        _, parent = breadth_first_order(local, 0, directed=False)
        nodes = np.arange(len(group))
        has_parent = parent >= 0
        parity = np.zeros(len(group), dtype=bool)
        parity[has_parent] = np.asarray(local[nodes[has_parent], parent[has_parent]]).ravel() == 2
        parent = np.where(has_parent, parent, nodes)
        while np.any(parent != parent[parent]):
            parity ^= parity[parent]
            parent = parent[parent]
        flip[group] = parity
    if flip.any():
        faces = np.asarray(mesh.faces).copy()
        faces[flip] = faces[flip, ::-1]
        mesh.faces = faces


def clean(mesh, tolerance=0):
    mesh = mesh.copy()
    if tolerance > 0:
        # Cluster points by Euclidean distance; retain existing coordinates.
        from scipy.spatial import cKDTree
        tree = cKDTree(mesh.vertices)
        if tree.count_neighbors(tree, tolerance) > 20_000_000:
            raise ValueError("That weld tolerance connects too many vertices. Choose a smaller tolerance.")
        pairs = tree.query_pairs(tolerance, output_type="ndarray")
        if len(pairs):
            graph = coo_matrix((np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])),
                               shape=(len(mesh.vertices),) * 2)
            _, labels = connected_components(graph, directed=False)
            _, first, inverse = np.unique(labels, return_index=True, return_inverse=True)
            mesh = mesh_of(mesh.vertices[first], inverse[mesh.faces])
    mesh.update_faces(mesh.nondegenerate_faces(height=1e-10))
    mesh.update_faces(mesh.unique_faces())
    mesh.remove_unreferenced_vertices()
    if not len(mesh.faces):
        raise ValueError("No surface remains after removing degenerate triangles.")
    fix_winding(mesh)
    return mesh


def rebuild_surface(mesh, depth=11, progress=None):
    """Reconstruct a separate surface; this deliberately trades some detail
    for robustness and is exposed as an explicit mode, never an auto fallback.
    """
    import pymeshlab

    notify(progress, "Preparing surface normals for reconstruction…")
    mesh = mesh.copy()
    offset = np.r_[mesh.bounds.mean(axis=0)[:2], mesh.bounds[0, 2]]
    mesh.apply_translation(-offset)
    fix_winding(mesh)
    trimesh.repair.fix_inversion(mesh, multibody=True)
    normals = np.asarray(mesh.vertex_normals)
    keep = np.isfinite(normals).all(axis=1) & (np.linalg.norm(normals, axis=1) > 0.5)
    if int(keep.sum()) < 4:
        raise ValueError("Not enough surface normals to rebuild this model.")
    surfaces = pymeshlab.MeshSet()
    surfaces.add_mesh(pymeshlab.Mesh(vertex_matrix=np.asarray(mesh.vertices)[keep],
                                     v_normals_matrix=normals[keep]))
    notify(progress, "Reconstructing the surface — this stage can take several minutes…")
    surfaces.generate_surface_reconstruction_screened_poisson(
        depth=depth, fulldepth=min(5, depth), samplespernode=1.5,
        pointweight=8, iters=8, threads=4, preclean=True)
    surface = surfaces.current_mesh()
    rebuilt = mesh_of(surface.vertex_matrix(), surface.face_matrix())
    if not len(rebuilt.faces):
        raise ValueError("Surface reconstruction produced no triangles. The original is unchanged.")
    if len(rebuilt.faces) > 5_000_000:
        notify(progress, "Reducing the reconstructed triangle count…")
        rebuilt = rebuilt.simplify_quadric_decimation(face_count=4_000_000, aggression=3)
    rebuilt.apply_translation([0, 0, -float(rebuilt.bounds[0, 2])])
    # Work at the same precision as the final STL so cleanup sees collapsed
    # edges before the exported file is independently validated.
    notify(progress, "Cleaning the reconstructed surface at STL precision…")
    vertices, inverse = np.unique(np.asarray(rebuilt.vertices, dtype=np.float32).astype(np.float64),
                                  axis=0, return_inverse=True)
    rebuilt = clean(mesh_of(vertices, inverse[rebuilt.faces]))
    if not rebuilt.is_watertight:
        notify(progress, "Closing remaining reconstructed boundaries…")
        # Poisson can reach the reconstruction domain on open inputs. Close
        # those remaining boundaries on the reconstructed surface only.
        import pymeshfix
        fix = pymeshfix.MeshFix(np.asarray(rebuilt.vertices, dtype=np.float64),
                                np.asarray(rebuilt.faces, dtype=np.int32))
        fix.repair(joincomp=False, remove_smallest_components=False)
        if len(fix.faces):
            rebuilt = clean(mesh_of(fix.points, fix.faces))
    return rebuilt


def repair(mesh, *, mode="robust", tolerance=0, largest=False, union=False, progress=None):
    import pymeshfix
    notes = []
    notify(progress, "Cleaning triangles, welding vertices and correcting winding…")
    mesh = clean(mesh, tolerance)
    # Only explicit largest-shell mode may discard entire disconnected parts.
    if largest:
        notify(progress, "Finding and keeping the largest shell…")
        parts = mesh.split(only_watertight=False, repair=False)
        if len(parts):
            mesh = max(parts, key=lambda p: p.area)
            notes.append(f"Kept the largest shell by surface area; removed {len(parts) - 1} shells.")
    if mode == "robust":
        notify(progress, "Preparing mesh topology for repair…")
        before_shells = topology(mesh)[0]["shells"]
        fixed = pymeshfix.MeshFix(np.asarray(mesh.vertices, dtype=np.float64),
                                  np.asarray(mesh.faces, dtype=np.int32))
        notify(progress, "Repairing topology, closing holes and resolving intersections…")
        fixed.repair(joincomp=False, remove_smallest_components=False)
        if len(fixed.faces) == 0:
            raise ValueError("Robust repair could not recover a surface. The original is unchanged; try Cleanup only.")
        notify(progress, "Cleaning the repaired surface…")
        mesh = clean(mesh_of(fixed.points, fixed.faces))
        after_shells = topology(mesh)[0]["shells"]
        notes.append("MeshFix repaired connectivity, closed boundaries, and attempted to remove self-intersections.")
        if after_shells < before_shells:
            notes.append(f"Shell count changed from {before_shells} to {after_shells}. Inspect the result for missing or merged features.")
    elif mode == "rebuild":
        mesh = rebuild_surface(mesh, progress=progress)
        if largest:
            parts = mesh.split(only_watertight=False, repair=False)
            if len(parts):
                mesh = max(parts, key=lambda p: p.area)
        notes.append("Rebuilt a new surface using screened Poisson reconstruction (depth 11). Fine features can be smoothed and dimensions can change; compare the result before printing.")
        notes.append("Rebuilt coordinates are centered near the origin to improve STL precision. Original world position is not retained.")
    else:
        notes.append("Cleanup removed duplicate/degenerate triangles and unused vertices, and corrected winding. Open boundaries were preserved.")
    # Orient each closed connected surface outwards. Nested void shells require
    # review; STL carries no explicit solid/cavity semantics.
    notify(progress, "Correcting repaired face winding and normals…")
    fix_winding(mesh)
    trimesh.repair.fix_inversion(mesh, multibody=True)
    if union:
        notify(progress, "Combining overlapping solids…")
        parts = mesh.split(only_watertight=False, repair=False)
        if not all(p.is_volume for p in parts):
            raise ValueError("Union needs closed, consistently oriented shells. Run robust repair first.")
        mesh = trimesh.boolean.union(parts, engine="manifold")
        if mesh is None or not len(mesh.faces):
            raise ValueError("Union produced an empty surface. The original is unchanged.")
        mesh = clean(mesh)
        notes.append("Manifold union combined overlapping solids. Nested shells become solid; review intentional cavities.")
    return mesh, notes


def preview(mesh, path, bad_edges, face_limit=PREVIEW_FACE_LIMIT, progress=None):
    # Decimate only the disposable display copy. Diagnostics, repairs and STL
    # exports always use the complete surface. QEM avoids dropping arbitrary
    # triangles (which would introduce visible holes in the preview).
    display = mesh
    if len(mesh.faces) > face_limit:
        notify(progress, "Simplifying the display copy for a responsive 3D preview…")
        display = mesh.copy()
        display.update_faces(display.nondegenerate_faces(height=1e-10))
        display.update_faces(display.unique_faces())
        display.remove_unreferenced_vertices()
        if len(display.faces):
            display = display.simplify_quadric_decimation(face_count=face_limit, aggression=5)
        if not len(display.faces):
            display = mesh
    notify(progress, "Writing the 3D preview and problem-edge highlights…")
    display.export(path / "preview.stl", file_type="stl")
    edges = mesh.vertices[bad_edges[:20000]].astype("<f4")
    (path / "edges.bin").write_bytes(edges.tobytes())
    return len(display.faces)


def run(args):
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    progress = ProgressReporter(output, repairing=args.command == "repair")
    progress.start("load", "Load model", "Loading the full-resolution STL…")
    if args.command == "demo":
        mesh = trimesh.creation.icosphere(subdivisions=3, radius=25)
        # A sphere with a missing cap, flipped face, duplicate and collapsed face.
        mesh.update_faces(mesh.triangles_center[:, 2] < 20)
        f = np.asarray(mesh.faces).copy()
        f[0] = f[0][::-1]
        mesh = mesh_of(mesh.vertices, np.vstack([f, f[10], [0, 0, 1]]))
        mesh.export(output / "Demo - damaged sphere.stl")
        args.input = str(output / "Demo - damaged sphere.stl")
    source_input = args.input
    if args.command != "repair":
        # Repairs use a stable import even if another app edits the source file.
        shutil.copyfile(args.input, output / "source.stl")
        args.input = str(output / "source.stl")
    mesh = load_stl(args.input)
    progress.start("inspect", "Inspect original", "Inspecting the original surface…")
    before, original_edges = analyze(mesh, progress=progress.detail)
    notes = []
    if args.command == "repair":
        progress.start("repair", "Rebuild surface" if args.mode == "rebuild" else "Repair geometry",
                       "Preparing the repair…")
        mesh, notes = repair(mesh, mode=args.mode, tolerance=args.tolerance,
                             largest=args.largest, union=args.union, progress=progress.detail)
        # Validate the quantized float32 STL that the user will actually export.
        progress.start("validate", "Validate repaired STL", "Saving and reloading the repaired STL…")
        mesh.export(output / "repaired.stl")
        mesh = load_stl(output / "repaired.stl")
    report, edges = analyze(mesh, progress=progress.detail) if args.command == "repair" else (before, original_edges)
    progress.start("preview", "Prepare preview", "Preparing the 3D preview…")
    preview_triangles = preview(mesh, output, edges, progress=progress.detail)
    if preview_triangles < len(mesh.faces):
        notes.append(f"Display preview simplified to {preview_triangles:,} triangles. Inspection, repair and export use all {len(mesh.faces):,} triangles.")
    if report["intersecting_triangles"] is None:
        notes.append("Self-intersection check unavailable until invalid topology is cleaned. All checks have not passed.")
    if report["inverted_shells"]:
        notes.append("Negative-volume shells detected. They can be reversed normals or intentional nested cavities.")
    if args.command == "repair":
        notes.append("Review intentional openings and nested cavities: repairing boundaries and orienting shells may change them.")
    notes.append("STL has no units; dimensions are interpreted as millimetres. Inspect cavities and thin walls, then slice in Bambu Studio.")
    return {"report": report, "before": before, "notes": notes,
            "preview": str(output / "preview.stl"), "input": source_input,
            "snapshot": args.input,
            "preview_triangles": preview_triangles,
            "repaired": str(output / "repaired.stl") if args.command == "repair" else None}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["analyze", "repair", "demo"])
    parser.add_argument("--input")
    parser.add_argument("--output", required=True)
    parser.add_argument("--mode", choices=["robust", "cleanup", "rebuild"], default="robust")
    parser.add_argument("--tolerance", type=float, default=0)
    parser.add_argument("--largest", action="store_true")
    parser.add_argument("--union", action="store_true")
    args = parser.parse_args()
    try:
        if args.tolerance < 0 or not np.isfinite(args.tolerance):
            raise ValueError("Weld tolerance must be a finite nonnegative number.")
        result = run(args)
        status = 0
    except Exception as error:
        traceback.print_exc(file=sys.stderr)
        result, status = {"error": str(error)}, 1
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    temporary = out / "result.json.tmp"
    temporary.write_text(json.dumps(result, allow_nan=False, indent=2))
    os.replace(temporary, out / "result.json")
    return status


if __name__ == "__main__":
    sys.exit(main())
