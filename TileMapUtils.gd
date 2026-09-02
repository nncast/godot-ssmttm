## TileMapUtils - Helper script for working with TileMaps in Godot 4
## Provides utilities for creating tilemaps programmatically, managing layers, and manipulating tiles

extends Node


class_name TileMapUtils


## Creates a filled rectangle of tiles on a specific layer
static func fill_rect(tilemap: TileMap, rect: Rect2i, source_id: int, atlas_coords: Vector2i, layer: int = 0) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			tilemap.set_cell(layer, Vector2i(x, y), source_id, atlas_coords)


## Creates a line of tiles between two points
static func draw_line(tilemap: TileMap, from: Vector2i, to: Vector2i, source_id: int, atlas_coords: Vector2i, layer: int = 0) -> void:
	var points = get_bresenham_line(from, to)
	for point in points:
		tilemap.set_cell(layer, point, source_id, atlas_coords)


## Gets points along a line using Bresenham's algorithm
static func get_bresenham_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var dx = abs(to.x - from.x)
	var dy = abs(to.y - from.y)
	var sx = sign(to.x - from.x)
	var sy = sign(to.y - from.y)
	var err = dx - dy
	var current = from
	
	while current != to:
		points.append(current)
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			current.x += sx
		if e2 < dx:
			err += dx
			current.y += sy
	
	points.append(to)
	return points


## Creates a circle/ellipse of tiles
static func fill_circle(tilemap: TileMap, center: Vector2i, radius: int, source_id: int, atlas_coords: Vector2i, layer: int = 0) -> void:
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			if center.distance_to(Vector2i(x, y)) <= radius:
				tilemap.set_cell(layer, Vector2i(x, y), source_id, atlas_coords)


## Clears all tiles on a specific layer
static func clear_layer(tilemap: TileMap, layer: int = 0) -> void:
	tilemap.clear_layer(layer)


## Gets the atlas coordinates for a tile in the tileset
## Useful for finding specific tiles by their visual position in the spritesheet
static func get_atlas_coords_at_offset(offset_x: int, offset_y: int, tile_size: Vector2i = Vector2i(16, 16)) -> Vector2i:
	return Vector2i(offset_x * tile_size.x, offset_y * tile_size.y)


## Gets all cells in a rectangular region
static func get_cells_in_rect(tilemap: TileMap, rect: Rect2i, layer: int = 0) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var pos = Vector2i(x, y)
			if tilemap.get_cell_source_id(layer, pos) >= 0:
				cells.append(pos)
	return cells


## Fills a rectangular area with different tiles based on a pattern
static func fill_pattern(tilemap: TileMap, rect: Rect2i, pattern: Array, source_id: int, layer: int = 0) -> void:
	var pattern_width = int(sqrt(pattern.size()))
	var pattern_height = int(sqrt(pattern.size()))
	
	var idx = 0
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			if pattern[idx % pattern.size()] != -1:
				tilemap.set_cell(layer, Vector2i(x, y), source_id, pattern[idx % pattern.size()])
			idx += 1


## Example: Creates a simple beach tilemap
static func create_beach_tilemap(tilemap: TileMap, width: int = 50, height: int = 50, water_source: int = 1, sand_source: int = 2, beach_tile: Vector2i = Vector2i(0, 0)) -> void:
	# Clear existing tiles
	clear_layer(tilemap, 0)
	
	# Fill top half with water (layer 0)
	fill_rect(tilemap, Rect2i(0, 0, width, height / 2), water_source, beach_tile, 0)
	
	# Fill bottom half with sand (layer 1)
	fill_rect(tilemap, Rect2i(0, height / 2, width, height / 2), sand_source, beach_tile, 1)


## Sets a custom modulate color for a tile
static func set_tile_modulate(tilemap: TileMap, pos: Vector2i, color: Color, layer: int = 0) -> void:
	# Note: TileMap doesn't support per-tile modulate directly
	# This would require using a separate overlay CanvasLayer or TileMap for effects
	pass


## Gets information about all tiles in a region
static func get_region_info(tilemap: TileMap, rect: Rect2i, layer: int = 0) -> Dictionary:
	var info = {
		"total_cells": 0,
		"filled_cells": 0,
		"empty_cells": 0,
		"source_ids": {},
		"tiles": []
	}
	
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			info["total_cells"] += 1
			var pos = Vector2i(x, y)
			var source_id = tilemap.get_cell_source_id(layer, pos)
			
			if source_id >= 0:
				info["filled_cells"] += 1
				if source_id not in info["source_ids"]:
					info["source_ids"][source_id] = 0
				info["source_ids"][source_id] += 1
				info["tiles"].append({"pos": pos, "source_id": source_id})
			else:
				info["empty_cells"] += 1
	
	return info
