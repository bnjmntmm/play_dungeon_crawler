# Dungeon Crawler Station

A small top-down dungeon crawler made in Godot 4.7.
It is a set-up to show some elements of game development.
Visitors aged 12 and up make an enemy, build a room, and then play the result.
It runs on three networked PCs at the [PLAY festival][play] in Hamburg.

The project is developed during the [Games Master][games-master] programme at [HAW Hamburg][haw] and is shown at the HAW showcase.
About ten students run the stations during the festival.

## The game

The player carries a cake to a grandmother.
This is a nod to Little Red Riding Hood.
The cake is the health bar.
It has three slices.

Animals in the rooms ambush the player.
They are not killed.
They are fed.
The player throws baguette pieces.
Once an animal has been fed enough, it stops attacking and sits down.

Rooms lock their doors when the player enters.
The doors open when every animal is pacified.
The door the player came through stays shut, so there is no going back.
The player always enters from below and has to reach the top door.

The last room holds a table.
Put the cake on the table and the door back to the start room opens.

## Controls

Movement uses gamepad axes only.
There are no keyboard bindings.
A virtual joystick appears when no pad is connected, and hides itself when one is.

There is no throw button.
The player throws a baguette automatically at the nearest aggressive animal.
This happens whenever the cooldown is over.

## Running the game

1. Install [Godot 4.7][godot].
   Use the standard build, not .NET.
2. Open `project.godot`.
3. Press F5.
   The main scene is `scenes/start_room/start_room.tscn`.

A run builds five rooms from everything in `custom_data/`.
The number can be changed in `GameManager.MAX_ROOMS_TO_GENERATE`.
Then it goes to the end room.
Exhaustion sends the player back to the start room.

### Selecting a specific room

To browse rooms without playing, run `scenes/gallery/gallery.tscn`.
Or visit the gallery from the main game through the south exit.
Left and right step through the saved levels.
Up returns to the start room.
The gallery never ends the run and keeps every animal passive.
It has a search bar.
It matches the level's display name or the word code.
Type on the keyboard attached at the play station.

## The three stations

| Station | Job | Result |
| --- | --- | --- |
| Art station | Draw an enemy in Krita. Export it as PNG into the visitor's folder. | `<name>.png` in `custom_data/<code>/animal/` |
| Game dev station | Give the enemy stats. Place animals and obstacles into a room. | `animal_<code>.tres` and `level_<code>.tres` in the visitor's folder |
| Play station | Play and browse the rooms that were built. | nothing, read only |

The room editor is a grid.
The visitor places animals and obstacles on it.
It works like Mario Maker.
The palette holds animals and obstacles only.

The enemy editor scans every `custom_data/<code>/animal/` folder.
So the art station and the game dev station work on the same folder.
The art station only drops in the PNG.
Stats and placement happen at the game dev station.

Images can be any size.
The game scales each one to 16 pixels wide.
So the drawings stay consistent next to the tiles.
The file must be a PNG with transparency.
Pixel art stays sharp because the pixel filter is off.
Example drawings are 128x128.

Saving an enemy writes `animal_<code>.tres` into `custom_data/<code>/animal/`.

The art station is the file host.
The other two stations read from its shared `custom_data` folder over the local network.

## Visitor generated data

Every visitor gets one folder under `custom_data/`.
The folder name is a generated word code, for example `roter_fuchs_42`.
It is not the visitor's name.
So no personal names end up in the repository or on screen.
See `feature/level_editor/level_code.gd` and `feature/station/kid_folders.gd`.

```text
custom_data/<code>/
  animal/    animal_<code>.tres   the enemy config
             <name>.png           the original drawing
  obstacle/  obstacle_<code>.tres optional, generated from PNGs in this folder
  level/     level_<code>.tres    the room
```

A level points to the animal and obstacle configs by grid position.
Change the enemy and every room that uses it changes too.

## The editors

The editors are `EditorScript`s.
They run inside the Godot editor, not in the exported game.
To open one, double click the script in the FileSystem panel.
Then press Ctrl+Shift+X (File > Run).
A window pops up.
Nothing needs enabling in Project Settings.

There are two editors:

- `feature/editor tool/editor_tool.gd` is the enemy editor.
  Pick a drawing.
  Set health, damage, speed, attack speed, and detection range.
  Choose a speed effect, name the enemy, and save.
- `feature/level_editor/level_editor_tool.gd` is the room editor.
  Place animals and obstacles on the grid and save under a level name.

`feature/station/station.tscn` combines both as two tabs.

Saving writes into `custom_data/`.
The game reads that folder once at startup (`GameManager.reset_run()`) or by using the refresh button.

## Network setup

`LAN_Share_Setup_Simple.bat` sets up the three PCs.
Run it as administrator on each machine.
Pick the station from the menu:

| Choice | Machine | IP |
| --- | --- | --- |
| 1 | Art station (host) | 192.168.10.50 |
| 2 | Game dev station | 192.168.10.51 |
| 3 | Play station | 192.168.10.52 |

The host shares its `custom_data` folder as the SMB share `custom_data`.
The other two machines make a folder link named `custom_data`.
It points at `\\192.168.10.50\custom_data`.
So Godot sees the same paths on every machine.
Nothing is copied.
If the art station is off, the other machines have no data.

The script sets a static IPv4 address on the wired adapter.
It opens firewall port 445 for `192.168.10.0/24` only.
It enables guest SMB without a password.
It saves a rollback file in `%ProgramData%\LANShareSetup\rollback.tmp`.
Run the same BAT again to undo every change.

Both scripts need Windows.
The Godot project itself runs anywhere.

## Project layout

```
assets/          tilesets, sprites, config classes (AnimalConfig, LevelConfig, BaseConfig)
autoloads/       GameManager (run state, level loading), MusicManager, Enums
custom_data/     all visitor content
feature/         editor tool (enemy), level_editor, station (combined view)
scenes/          start_room, level_gen, gallery, player, projectile, ui, util
```

`GameManager` is an autoload.
It holds the run state: the loaded level, the room counter, the score, and the list of live animals.
Scenes talk to it through signals, not direct references.

`LevelGen` clears the tilemap and fills it from the level config.
It reports back when done.
Doors are re-checked on every room change, so they start shut again.

[play]: https://www.playfestival.de/
[games-master]: https://gamesmaster-hamburg.de/
[haw]: https://www.haw-hamburg.de/master-games/
[godot]: https://godotengine.org/download
