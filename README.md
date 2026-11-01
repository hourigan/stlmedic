# STL Medic

A native macOS application for inspecting and repairing STL meshes before slicing in Bambu Studio. Built with SwiftUI, SceneKit, and an offline Python geometry engine.

The current source version is **1.0.0 (build 4)**. The production release is pending Developer ID signing and Apple notarization; no 1.0.0 download is published yet. See [the signing guide](docs/SIGNING.md) for the release steps. The published 0.2.1 download remains a development preview.

## Run

Open **`dist/STL Medic.app`**. The built app includes its own Python runtime and dependencies; Python, Homebrew, and network access are not needed to use it. This is a local, ad-hoc signed development build for the Mac architecture it was built on, not a notarized release.

1. Drop a binary or ASCII STL into the window, or choose **Open STL** (⌘O).
2. Review the mesh inspection panel and orange problem edges.
3. Choose **Robust repair** to close boundaries and repair topology, or **Cleanup only** to preserve open boundaries. **Rebuild surface** is a separate fallback for heavily damaged meshes; it can smooth details and change dimensions.
4. Select **Repair model** (⌘R), then compare **Original / Repaired**.
5. **Export STL** (⌘S) saves a separate binary STL. **Save & open in Bambu Studio** saves your STL and opens it in an installed Bambu Studio.
6. Inspect the sliced layers before printing.

While a model is processing, a progress card shows the current operation, completed stages, total elapsed time, and time spent in the current stage. The stage bar follows actual engine transitions, including export validation and loading the 3D preview. Native geometry stages can take several minutes; the timer continues updating during them. Cancel preserves the last completed result.

Open **STL Medic → About STL Medic** to see **Justin Hourigan** and the clickable [Buy Me a Coffee](https://buymeacoffee.com/justhour) link.

A damaged demo model is available on the welcome screen and in the File menu. Every repair starts from the original. Failed or cancelled operations preserve the previous completed result. Export refuses the source filename.

Imports are snapshotted locally so edits made to the source file in another application do not change the model being repaired. Reopen the STL to import external changes.

## Repairs and inspection

- Non-manifold edges (more than two incident faces).
- Non-manifold vertices, including disconnected triangle fans / bow-tie vertices.
- Isolated / unreferenced vertices in internal meshes. STL stores triangle soup and cannot encode standalone vertices.
- Degenerate and duplicate triangles, inconsistent winding, reversed shells.
- Open boundary edges and boundary groups; robust repair attempts to close holes, including large boundaries.
- Watertightness, connected shells, dimensions, signed volume, self-intersecting triangles.
- Optional Euclidean welding at 0.001, 0.01, or 0.1 mm.
- Optional removal of all but the largest shell by area.
- Optional Manifold boolean union for overlapping closed solids.
- Explicit screened Poisson surface reconstruction for difficult meshes, with a warning about softened features and changed dimensions. Rebuilt models are centered near the origin to improve STL coordinate precision.
- Exportable JSON inspection reports; validated output is read back from the actual float32 STL.

“Mesh checks passed” means the exported surface is closed, manifold, consistently oriented, nondegenerate, duplicate-free, with positive volume and no intersections found by the checker. It is not a slicing or printability guarantee. Thin walls, tiny features, support requirements, bed fit, materials, and printer settings need checking in your slicer.

STL has no units; this app displays coordinates as millimetres without scaling them. Robust repair may change surfaces or fill intentional openings. Separate shells are retained by default, although MeshFix may modify/remove unrecoverable geometry; shell-count reductions are reported. Correcting normals or unioning nested shells may remove intentional cavity semantics, so review hollow models carefully. Self-intersection checks are reported as **Unchecked** when invalid topology prevents a trustworthy check. Orange highlights show boundary/non-manifold edges only, capped at 20,000 edges. Boundary groups can include branched boundaries, not only simple holes.

Limits: 512 MB input, 6 million triangles. Operations on inputs below 50 MB have a five-minute timeout; larger inputs have thirty minutes. Large models use a display copy targeting 300,000 triangles to keep the viewer responsive. The preview is labelled **Simplified**; diagnostic counts and exports use the complete repaired surface. Cleanup and robust repair use full-resolution input. Rebuild intentionally creates a new surface at octree depth 11 (nominal finest cells approximately 1.1 times the longest dimension / 2048), with adaptive resolution and no guaranteed dimensional tolerance. Rebuild outputs above 5 million triangles are reduced toward 4 million. Use it only when geometry changes are acceptable. Complex meshes can need substantial memory or manual modelling work. The large-file limits are guardrails, not performance guarantees.

## Build and develop

Requires macOS 14+, Xcode command-line tools (Swift 5.9+), and [uv](https://docs.astral.sh/uv/).

```sh
./scripts/build.sh
open 'dist/STL Medic.app'
```

The build installs pinned CPython 3.12.12 and dependencies, compiles an optimized native executable, bundles a relocatable interpreter, creates an icon, and signs the app locally. Build on the target architecture (Apple Silicon or Intel); the included build is Apple Silicon. No cloud services are used.

Open `Package.swift` in Xcode to edit the Swift sources, or use:

```sh
swift build
swift run STLMedic
```

The development executable finds `.venv` and `Engine` in the current project directory. Use the packaged `.app` for Finder document association and deployment.

```sh
uv pip install --python .venv/bin/python pytest==9.2.0
.venv/bin/python -m pytest Tests -q
```

The geometry tests cover STL encodings, holes, degenerate/duplicate faces, isolated vertices, non-manifold edges and bow-tie vertices, winding, separate parts, overlap detection and union, welding, malformed files, structured failures, and export/source preservation.

Local validation: **22 tests passed**; release app and embedded demo-repair smoke test passed; app signature verified. The demo was repaired through the native UI, exported using **Save & open in Bambu Studio**, and successfully sliced in the installed Bambu Studio (192 layers). The verified export is at `build/verification/Demo-repaired.stl`. Winding correction uses a sparse graph traversal to handle large meshes without building a Python object graph. These checks validate the workflows for those fixtures; real models still need inspection.

The repair engine can also be used directly:

```sh
.venv/bin/python Engine/engine.py analyze --input model.stl --output /tmp/inspection
.venv/bin/python Engine/engine.py repair --input model.stl --output /tmp/repaired
```

Results are written to `result.json`; native engine logs go to stdout/stderr. Requests run in separate processes so a native repair failure does not crash the UI. The application keeps previews and operation logs under a temporary `STLMedic-*` directory. JSON reports include local filesystem paths.

## Downloads and source

Download the Apple Silicon development build from [stlmedic.com](https://stlmedic.com/#get-app). The website links the matching source archive and checksums alongside the application ZIP. The app currently requires macOS 14 or later and is ad-hoc signed; it is not Developer ID signed or notarized.

Application source: [hourigan/stlmedic](https://github.com/hourigan/stlmedic). The marketing website is maintained separately in [hourigan/stlmedic-website](https://github.com/hourigan/stlmedic-website).

## License

Copyright (C) 2026 Justin Hourigan. STL Medic’s original application code is licensed under **AGPL-3.0-or-later**. See [LICENSE](LICENSE) and [LICENSE-NOTICE.md](LICENSE-NOTICE.md). Third-party components retain their original licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The corresponding source archive includes the app sources, build scripts, pinned Python dependency sources, PyMeshLab with its MeshLab/VCG/pybind11 submodules, and the bundled Qt component sources. The app download also includes the license and source links. Bambu Studio is a separate application; this project is not affiliated with Bambu Lab.
