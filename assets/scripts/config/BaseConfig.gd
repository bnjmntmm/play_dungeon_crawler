@tool
class_name BaseConfig
extends Resource

## UUID: is the unique Identifier for Objects. Will be used to identify in spawner classes and Levelconfig
@export var uuid : String

## Position: the position is the location where the specific object is placed
## [b]Maybe irrelevant[/b]

## ~ Now irrelevant since the TileMapLayer safes position - J
##@export var position : Vector2

## Sprite: this is the relevant sprite to be displayed for the specific object
## we need a way to identify it, add it to our tileset and place it when a person adds a new drawn sprite
@export var sprite : Texture2D
