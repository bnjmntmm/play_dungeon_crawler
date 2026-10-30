class_name AnimalConfig
extends BaseConfig

## Health: (or Hunger) is the stat how much an animal has to be fed, before they are not attacking anymore
@export var health : int

## Damage: How much damage the attack of the specific animal does
@export var damage: int

## Speed: movement speed of the animal
@export var speed: float

## Attack Speed: How fast can this specific Animal attack the player when in range
@export var attack_speed: float

## Detection Range: how near / far the animal detects the player around itself
@export var detection_range : float

## Sound: The sfx the animal uses
@export var sound : AudioStreamWAV
