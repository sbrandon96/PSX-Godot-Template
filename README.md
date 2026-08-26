# PSX-Godot-Template

A reusable, deliberately boring foundation for PSX-style 3D games in **Godot 4.7+**.

This repository is a **GitHub Template**, not a game. It encodes the technical
decisions of PSX-era rendering — internal resolution, renderer choice, texture
filtering, shader pipeline — so that each new project starts from a known-good,
runnable baseline instead of a blank scene.

Horror, combat, inventory, story and level content are **not** part of this
template. They belong to the games built from it.

## Locked Technical Decisions

| Parameter            | Decision                                    |
| -------------------- | ------------------------------------------- |
| Engine               | Godot 4.7+                                  |
| Renderer             | Compatibility (`gl_compatibility`) — locked |
| Language             | GDScript only                               |
| Primary export       | Web (HTML5 / WebGL 2.0)                     |
| Target hardware      | Desktop browsers. Mobile out of scope.      |
| Internal resolution  | 320x240, point-scaled                       |
| Texture budget       | 64x64 individual, 128x128 atlas             |
| Lighting model       | Baked vertex colours + one real-time shadowed light |

The renderer choice is **not** revisitable. Godot 4 web export supports only the
Compatibility method. Changing it invalidates the entire toolset.

## Creating a Game From This Template

1. Click **Use this template** → **Create a new repository**.
2. Clone your new repository.
3. Open it in Godot 4.7 or newer.
4. Let the import finish.
5. Press **F5**. You should see the PSX test environment.

Do **not** fork this repository to make a game. Games are independent
repositories. The template is a starting point, not a synchronised framework.

## Repository Layout
