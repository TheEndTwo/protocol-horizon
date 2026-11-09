# Menu background — temporary art for stage 1

`backgrounds/mine_archival.jpg`: adapted from **View of the Utah Copper Company open-pit mine workings at Carr Fork, as seen from the railroad, Bingham Canyon, Utah**, Andreas Feininger / FSA-OWI, Library of Congress, digital ID `fsac.1a34853`.

- Catalog: https://www.loc.gov/item/2017878851/
- Original JPEG: https://tile.loc.gov/storage-services/service/pnp/fsac/1a34000/1a34800/1a34853v.jpg
- Rights advisory verified via LoC JSON API: **No known restrictions on publication**.
- Wikimedia licensing: https://commons.wikimedia.org/wiki/File:Bingham_Canyon_mine_1942.jpg — US federal FSA/OWI photograph, public domain in the United States.
- Changes: removed film frame; reduced saturation and adjusted brightness. Text and buttons are separate Godot nodes, not baked into this image.

This real historical copper mine is an atmospheric stand-in, not the canonical Fe site or final commissioned illustration. No image-generation tool is available in this workspace; the owner will add final bespoke artwork later. This placeholder is not an approved visual match to the references.

UI SVG emblem, gradients and nine-slice textures were newly authored for this project, not extracted from reference screenshots. Runtime theme uses StyleBoxTexture; reference images remain excluded from runtime.

Gameplay SVG placeholders in `placeholders/` are original simple project-authored assets with no external textures. Replace them and named portraits/items through `data/art_overrides.json`; see `docs/TEXTURE_GUIDE.md`.
