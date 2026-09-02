# Installation Guide - SSMTTM Fixes & Improvements

## What's Included

This package contains fixes and improvements for your SSMTTM Godot project:

### 📝 Modified Files (replace these in your project)
- `title_screen.tscn` - Updated UI layout
- `title_screen.gd` - Updated script references
- `settings.tscn` - Updated settings panel layout
- `settings.gd` - Updated script references

### ✨ New Files (add these to your project)
- `TileMapUtils.gd` - Utility script for tilemap operations
- `TILEMAP_GUIDE.md` - Complete tilemap reference guide
- `FIXES_SUMMARY.md` - Detailed summary of all changes
- `INSTALLATION.md` - This file

---

## Installation Steps

### Step 1: Backup Your Current Project
```bash
# Before making any changes, backup your project
cp -r your-project-folder your-project-folder-backup
```

### Step 2: Replace Modified Files

#### Replace Title Screen Files:
1. **Title Screen Scene**:
   - Navigate to `ui/title_screen/` in your project
   - Replace `title_screen.tscn` with the new version
   - Replace `title_screen.gd` with the new version

2. **Settings Files**:
   - Navigate to `ui/settings/` in your project
   - Replace `settings.tscn` with the new version
   - Replace `settings.gd` with the new version

### Step 3: Add New Files

1. **Add TileMapUtils.gd**:
   - Copy `TileMapUtils.gd` to your project root (same level as `project.godot`)
   - Or place it in a `utils/` folder: `utils/TileMapUtils.gd`

2. **Add Documentation**:
   - Copy `TILEMAP_GUIDE.md` to your project root
   - Copy `FIXES_SUMMARY.md` to your project root
   - These are for reference, not loaded by Godot

### Step 4: Reload Godot Project

1. Close your project in Godot (if open)
2. Reopen the project
3. Godot will automatically detect and import the new files

### Step 5: Verify Changes

✅ **Test Title Screen**:
- Open the title screen scene
- Verify Settings button appears in top-right corner
- Click Settings button → should open settings panel

✅ **Test Settings Panel**:
- Settings panel should open cleanly
- Back button should be in top-right corner
- No overlap with sliders

✅ **Test TileMapUtils** (Optional):
- Open a tilemap scene (like `world_boracay.tscn`)
- In a script, add:
  ```gdscript
  # At top of your script
  extends Node2D
  
  func _ready():
      var tilemap = $TileMap
      # This should work without errors
      TileMapUtils.fill_rect(tilemap, Rect2i(0, 0, 5, 5), 1, Vector2i(0, 0), 0)
  ```

---

## File Locations in Your Project

```
your-project/
├── ui/
│   ├── title_screen/
│   │   ├── title_screen.tscn          ← REPLACE
│   │   └── title_screen.gd            ← REPLACE
│   ├── settings/
│   │   ├── settings.tscn              ← REPLACE
│   │   └── settings.gd                ← REPLACE
│   └── lobby/
├── TileMapUtils.gd                    ← ADD NEW
├── TILEMAP_GUIDE.md                   ← ADD NEW (reference only)
├── FIXES_SUMMARY.md                   ← ADD NEW (reference only)
├── project.godot
├── assets/
└── ... (rest of your project)
```

---

## What Changed

### UI Layout Changes ✨

**Before:**
- Settings button in bottom of main menu
- Back button in middle of settings panel
- Potential overlap issues

**After:**
- Settings button in top-right corner of title screen
- Back button in top-right corner of settings panel
- Clean, consistent UI
- No overlap with content

### Code References Updated 📝

```gdscript
// OLD: settings_button: Button = $VBox/SettingsButton
// NEW: settings_button: Button = $SettingsButtonTopRight

// OLD: back_button: Button = $VBox/BackButton
// NEW: back_button: Button = $BackButton
```

### New Tilemap Utilities 🎮

Added `TileMapUtils.gd` with functions for:
- Filling rectangular areas
- Drawing lines
- Creating circles
- Clearing layers
- Pattern-based filling
- Region analysis

---

## Troubleshooting

### Issue: "Node not found" error in console
**Solution:**
- Make sure you replaced BOTH the `.tscn` AND `.gd` files
- Close and reopen Godot
- Check file paths match exactly

### Issue: TileMapUtils not found
**Solution:**
- Verify `TileMapUtils.gd` is in project root
- Godot needs to save/load for new resources to register
- Try: Project → Tools → Reload current scene

### Issue: Settings button not showing
**Solution:**
- Check `title_screen.tscn` was properly replaced
- Verify the node name is `SettingsButtonTopRight`
- Try deleting `.godot/` folder and reloading project

### Issue: Offset or size seems wrong
**Solution:**
- The button is positioned with `offset_left = -100.0, offset_top = 10.0`
- Adjust these values if button is off-screen:
  - Increase `offset_top` to move down
  - Decrease `offset_left` (make it less negative) to move right
- Open the `.tscn` file in a text editor to adjust raw values

---

## Optional Customization

### Change Button Styling

Edit the button nodes to customize appearance:

```gdscript
# In title_screen.tscn or settings.tscn
[node name="SettingsButtonTopRight" type="Button" parent="."]
# Add these lines to customize:
# theme_override_colors/font_color = Color.WHITE
# theme_override_font_sizes/font_size = 12
# custom_minimum_size = Vector2(90, 30)
```

### Change Button Position

In `.tscn` file, find the button's offset properties:
```
offset_left = -100.0   # Distance from right edge (negative)
offset_top = 10.0      # Distance from top
offset_right = -10.0   # Additional right offset
offset_bottom = 40.0   # Height of button
```

Adjust these to reposition the button.

---

## After Installation

### ✅ Next Steps:

1. **Explore TileMapUtils**: Read `TILEMAP_GUIDE.md` for examples
2. **Test the UI**: Play through title → settings → back workflow
3. **Use tilemaps**: Try the utility functions in your world scenes
4. **Customize**: Adjust colors, fonts, positions to match your game style

### 📚 Learn More:

- **Tilemap Guide**: See `TILEMAP_GUIDE.md` for comprehensive reference
- **Changes Summary**: See `FIXES_SUMMARY.md` for detailed changes
- **Godot Docs**: https://docs.godotengine.org/

---

## Reverting Changes

If you need to go back to the original files:

```bash
# Option 1: Use your backup
cp -r your-project-folder-backup/ui/title_screen your-project-folder/ui/

# Option 2: Git revert (if using git)
git checkout HEAD -- ui/title_screen/ ui/settings/
```

---

## Support

If you encounter issues:

1. **Check the console** for error messages (Debug → Output)
2. **Verify file paths** - exact case matters on Linux/Mac
3. **Reload Godot** - sometimes resources need a fresh load
4. **Check file permissions** - files should be readable/writable

---

## Version Information

- **Godot Version**: 4.x (requires version 4.0+)
- **Project Type**: 2D
- **Python**: Not required
- **Dependencies**: None (pure GDScript)

---

Good luck with your SSMTTM project! 🎮✨

For questions, refer to:
- `FIXES_SUMMARY.md` - Overview of changes
- `TILEMAP_GUIDE.md` - Complete tilemap reference
- `TileMapUtils.gd` - Inline code documentation
