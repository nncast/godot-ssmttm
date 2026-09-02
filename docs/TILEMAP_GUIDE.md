# Godot Tilemap Guide - Complete Reference

## Overview

Tilemaps in Godot 4 are powerful for creating 2D grid-based levels. This guide covers both programmatic and editor-based approaches.

## Key Concepts

### 1. **Tileset vs TileMap**
- **TileSet**: A resource that defines available tiles (like a spritesheet catalog)
- **TileMap**: A Node that uses a TileSet to render a grid of tiles

### 2. **TileSet Layers**
Tilesets can have multiple layers, useful for:
- Terrain variation (grass, sand, water)
- Collision layers
- Physics/interaction layers

### 3. **Spritesheet Setup**
When you have a spritesheet (like 16x16 grid of 16-pixel tiles):

```
21_Beach_16x16.png (spritesheet containing multiple tiles)
├── Tile at (0,0) - First tile in top-left
├── Tile at (1,0) - Second tile in top-left row
└── ... etc
```

## Setting Up a TileSet from Spritesheet

### Editor Method (Recommended):
1. **Import the spritesheet**:
   - Drag PNG into assets folder
   - Godot auto-imports it

2. **Create TileSet**:
   - Right-click in FileSystem → New Resource → TileSet
   - Save as `.tres` file

3. **Add Texture Source**:
   - In TileSet editor, click "Select" next to "Texture"
   - Choose your spritesheet PNG

4. **Configure Atlas**:
   - Godot automatically splits your spritesheet based on tile size
   - Set texture region size (usually 16×16 for pixel art)
   - Margins/separation if tiles have spacing

5. **Define Individual Tiles**:
   - Click each tile region to define properties
   - Add collision shapes if needed
   - Set custom data for gameplay logic

## Using TileMaps in Code

### Basic Programmatic Setup:

```gdscript
extends Node2D

func _ready():
    # Get reference to tilemap
    var tilemap = $TileMap
    
    # Set a single tile
    # set_cell(layer: int, coords: Vector2i, source_id: int, atlas_coords: Vector2i)
    tilemap.set_cell(0, Vector2i(5, 5), 1, Vector2i(0, 0))
    
    # Fill an area with tiles
    for x in range(10):
        for y in range(10):
            tilemap.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0))
```

### Key Parameters:
- **layer**: Which layer (0 = base, 1 = overlay, etc.)
- **coords**: Position in grid (Vector2i)
- **source_id**: Which texture source in tileset
- **atlas_coords**: Position within the spritesheet (in tile units, not pixels)

## Working with Multiple Layers

Tilemaps support multiple layers for depth and organization:

```gdscript
# Create ground layer (layer 0)
for x in range(width):
    for y in range(height):
        tilemap.set_cell(0, Vector2i(x, y), terrain_source, grass_tile)

# Add water layer on top (layer 1)
# Only where water should be
for x in range(10):
    for y in range(5):
        tilemap.set_cell(1, Vector2i(x, y), water_source, water_tile)

# Add objects/props (layer 2)
tilemap.set_cell(2, Vector2i(15, 10), props_source, tree_tile)
```

### Layer Management:
```gdscript
# Clear a specific layer
tilemap.clear_layer(0)

# Get cell data from a layer
var source_id = tilemap.get_cell_source_id(0, Vector2i(5, 5))
var atlas_coords = tilemap.get_cell_atlas_coords(0, Vector2i(5, 5))
```

## Beach/Boracay Example

For your Boracay beach scene:

```gdscript
extends TileMap

func _ready():
    # Assuming:
    # - Source ID 1: Beach tileset (21_Beach_16x16.png)
    # - Source ID 2: Water tileset
    # - Tile size: 16x16
    
    var width = 80
    var height = 60
    var water_line = 30  # Beach starts here
    
    # Fill water (top part)
    for x in range(width):
        for y in range(water_line):
            # Use different water tiles for variation
            var water_variant = randi() % 3
            set_cell(0, Vector2i(x, y), 2, Vector2i(water_variant, 0))
    
    # Fill sand (bottom part)  
    for x in range(width):
        for y in range(water_line, height):
            # Sand with some variation
            var sand_variant = randi() % 2
            set_cell(1, Vector2i(x, y), 1, Vector2i(sand_variant, 0))
    
    # Add palm trees/props
    place_trees()

func place_trees():
    var positions = [
        Vector2i(10, 25),
        Vector2i(30, 25),
        Vector2i(50, 26),
    ]
    
    for pos in positions:
        # Source ID 3 might be props/objects
        set_cell(2, pos, 3, Vector2i(0, 0))  # tree_tile
```

## Collision Shapes in Tilemaps

Collisions are defined in the TileSet editor, not the TileMap:

1. **In TileSet editor**:
   - Select a tile
   - Physics layer > Add collision shape
   - Draw collision polygon or use built-ins

2. **In code** (if using PhysicsBody):
   ```gdscript
   # TileMap has built-in physics layer support
   # Just enable "Physics Layer 0" in TileSet editor
   ```

## Performance Tips

1. **Limit visible tiles**: Use viewport culling (automatic in Godot)
2. **Pre-generate vs dynamic**: 
   - Pre-generate if static
   - Use dynamic generation for infinite/procedural worlds
3. **Use layers wisely**: Multiple layers = more memory
4. **Spritesheet organization**: Keep related tiles together in spritesheet

## Common Issues & Solutions

### Issue: Tiles not appearing
- ✓ Check source_id matches TileSet source
- ✓ Check atlas_coords are within spritesheet bounds
- ✓ Verify TileSet texture is properly set
- ✓ Check layer isn't hidden

### Issue: Gaps between tiles
- ✓ In TileSet editor, check "Disable Polygon Clearing"
- ✓ Ensure spritesheet tiles have no gaps
- ✓ Verify texture filter mode (should be nearest for pixel art)

### Issue: Performance lag with large maps
- ✓ Reduce layer count if not needed
- ✓ Use chunk-based loading for huge worlds
- ✓ Consider using AutoLoad/background processes
- ✓ Profile with Godot debugger

## Asset Organization

Recommended folder structure:
```
assets/
├── tilemap/
│   ├── 21_Beach_16x16.png
│   ├── beach_tileset.tres
│   ├── water_tileset.tres
│   └── terrain_tileset.tres
└── sprites/
    ├── player.png
    └── enemies/
```

## Working with Your Spritesheet

If you have a spritesheet like `21_Beach_16x16.png`:

1. **Identify tile size**: Usually 16x16 for this naming
2. **Count columns**: Spritesheet width ÷ 16 = columns
3. **Count rows**: Spritesheet height ÷ 16 = rows
4. **Map tiles**:
   ```
   Tile at grid position (2, 1):
   - Column index: 2
   - Row index: 1
   - In code: Vector2i(2, 1)
   ```

## Advanced: Procedural Generation

```gdscript
func generate_beach_procedurally(seed_value: int):
    seed(seed_value)
    
    for x in range(map_width):
        for y in range(map_height):
            # Use noise for natural-looking variation
            var noise = Noise.new()
            var noise_value = noise.get_noise_2d(x, y)
            
            if noise_value < 0.3:
                set_cell(0, Vector2i(x, y), water_source, water_tile)
            elif noise_value < 0.6:
                set_cell(0, Vector2i(x, y), sand_source, sand_tile)
            else:
                set_cell(0, Vector2i(x, y), grass_source, grass_tile)
```

## Tilemap vs Custom Grid

| Feature | TileMap | Custom Grid |
|---------|---------|------------|
| Performance | Excellent | Good |
| Ease of use | Easy | Moderate |
| Built-in collisions | Yes | No |
| Physics | Native support | Manual |
| Editor tools | Great | None |
| Flexibility | Good | Excellent |

**Use TileMap for**: Most games, structured levels, static backgrounds
**Use Custom Grid for**: Advanced effects, non-grid gameplay, special effects

## Next Steps

1. **Import your spritesheet**: Place PNG in assets/tilemap/
2. **Create TileSet**: Use editor to define tiles
3. **Create TileMap**: Add TileMap node to scene
4. **Test**: Use included `TileMapUtils.gd` for programmatic creation
5. **Polish**: Add collisions, physics, animations

---

Happy tiling! 🎮
