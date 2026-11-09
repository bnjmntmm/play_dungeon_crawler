extends VBoxContainer
## Game Design station: kids build an animal first, then place it in their room.
## The header picks the kid folder once, so both tabs always save into the same one.

const SWITCH_DELAY: float = 1.2

@onready var kid_option: OptionButton = %KidOption
@onready var code_label: Label = %CodeLabel
@onready var next_button: Button = %NextButton
@onready var tabs: TabContainer = %Tabs
@onready var animal_editor: AnimalEditor = %Tier
@onready var level_editor: LevelEditor = %Raum

## Kid codes in dropdown order. Index 0 of the dropdown is "new animal".
var codes: PackedStringArray = []

func _ready() -> void:
	tabs.set_tab_title(animal_editor.get_index(), "1. Tier bauen")
	tabs.set_tab_title(level_editor.get_index(), "2. Raum bauen")
	animal_editor.initialize()
	animal_editor.code_edit.hide()
	level_editor.set_identity_visible(false)
	animal_editor.saved.connect(_on_animal_saved)
	level_editor.saved.connect(_fill_kid_option)
	kid_option.item_selected.connect(_on_kid_selected)
	tabs.tab_changed.connect(_on_tab_changed)
	next_button.pressed.connect(_on_next_button_pressed)
	_fill_kid_option("")
	_on_kid_selected(0)
	_on_tab_changed(tabs.current_tab)

## Refills the dropdown without reloading the editors, so unsaved work stays.
func _fill_kid_option(selected_code: String) -> void:
	kid_option.clear()
	kid_option.add_item("+ Neues Tier")
	codes.clear()
	for folder: Dictionary in KidFolders.list():
		codes.append(folder.code)
		var label: String = folder.name if folder.name == folder.code else "%s  (%s)" % [folder.name, folder.code]
		kid_option.add_item(label)
	kid_option.select(codes.find(selected_code) + 1)

func _on_kid_selected(index: int) -> void:
	var code: String = codes[index - 1] if index > 0 else LevelCode.create_unused(KidFolders.CUSTOM_DATA_PATH)
	code_label.text = "Ordner: %s" % code
	animal_editor.use_kid(code)
	level_editor.use_kid(code)
	level_editor.build_palette()

func _on_animal_saved(code: String) -> void:
	_fill_kid_option(code)
	level_editor.build_palette()
	level_editor.select_config_path(KidFolders.get_animal_path(code))
	await get_tree().create_timer(SWITCH_DELAY).timeout
	tabs.current_tab = level_editor.get_index()

func _on_tab_changed(tab: int) -> void:
	var is_room: bool = tabs.get_tab_control(tab) == level_editor
	next_button.text = "Zurück zum Tier" if is_room else "Weiter: Raum bauen"
	if is_room:
		level_editor.build_palette()

func _on_next_button_pressed() -> void:
	var is_room: bool = tabs.get_current_tab_control() == level_editor
	tabs.current_tab = (animal_editor if is_room else level_editor).get_index()
