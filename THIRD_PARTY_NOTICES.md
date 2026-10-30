# Third-party components

This development build bundles CPython and open-source geometry libraries. License files ship with the Python distribution and installed `.dist-info/licenses` or equivalent directories in `Contents/Resources/Python`.

| Component | Upstream | License |
| --- | --- | --- |
| CPython | https://www.python.org/ | Python Software Foundation license and bundled notices |
| NumPy | https://numpy.org/ | BSD-3-Clause and bundled notices |
| SciPy | https://scipy.org/ | BSD-3-Clause and bundled notices (including numerical libraries) |
| Trimesh | https://github.com/mikedh/trimesh | MIT |
| NetworkX | https://networkx.org/ | BSD-3-Clause |
| Manifold | https://github.com/elalish/manifold | Apache-2.0 |
| fast-simplification | https://github.com/pyvista/fast-simplification | MIT and bundled notices |
| PyMeshLab / MeshLab | https://github.com/cnr-isti-vclab/PyMeshLab | GPL-3.0-or-later and bundled third-party notices |
| PyMeshFix / MeshFix | https://github.com/pyvista/pymeshfix | AGPL-3.0-or-later; includes MeshFix/TMesh notices |

**Distribution:** PyMeshFix is a copyleft dependency. This prototype does not establish a proprietary licensing strategy. Review and fulfill the applicable AGPL/MeshFix source and licensing obligations before distributing this app, or replace that backend with an appropriately licensed engine. Upstream source locations above identify the pinned components in `requirements.txt`; shipping notices alone does not fulfill corresponding-source obligations.
