# Low-Poly 30 Years' War Unit Pack for Godot 4

Files:
- pikeman_lowpoly.obj
- musketeer_lowpoly.obj
- army_units.mtl
- army_atlas.png

Triangle counts:
- Pikeman: 128 tris
- Musketeer: 132 tris

Design notes:
- Single shared material / atlas
- UVs collapsed to flat color regions in atlas
- Intended for top-down RTS / wargame use
- Geometry kept intentionally simple for mass instancing

Suggested Godot 4 import:
- Import as Mesh
- Disable tangent generation if not needed
- Use StandardMaterial3D or a lightweight custom shader
- For army variation, multiply albedo by INSTANCE_CUSTOM or vertex color in shader
- Best paired with MultiMeshInstance3D for large formations

Recommended gameplay scale:
- Base height approx. 1.5 world units excluding long pike
- Pikes intentionally oversized for silhouette readability from top-down camera