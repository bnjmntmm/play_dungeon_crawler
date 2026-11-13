extends Node
## MusicManager (autoload) -- Godot 4.x
##
## Two BGM tracks that are always playing and crossfaded:
##   A = ambience (long track, e.g. 98.682s)
##   B = action   (shorter track, lines up with A in one or more stretches)
##
## Setup: Project Settings > Globals (Autoload) > add this script as "MusicManager".
## Optional: an audio bus called "Music" (falls back to "Master").
##
## Usage:
##   MusicManager.play_pair(preload("res://ambience.ogg"), preload("res://action.ogg"), [
##       {"a_start": 0.0,    "a_end": 35.888},   # action starts at 0 and lines up with A until 35.888
##       {"a_start": 53.834},                    # action restarts from 0 here, a_end = a_start + action length
##   ])
##   MusicManager.play_action()
##   MusicManager.play_ambience()
##
## SEGMENTS
## Each segment says: "A-time a_start..a_end lines up with B-time b_start.. (b_start defaults to 0)".
## Anything in A that isn't inside a segment is an intermezzo (B has nothing to play there).
##
## BEHAVIOUR
## The track being faded TO (or currently audible) is the leader and plays untouched.
## The other track follows it:
##   - Ambience leads: action follows while A is inside a segment. During an intermezzo action is
##     parked paused at its beginning, and it starts from 0 exactly when the next segment begins.
##   - Action leads: ambience seeks to the matching segment. When the action loops, ambience
##     jumps to the nearest segment, i.e. it skips its intermezzos while action is playing.
##   - Switching to action during an intermezzo starts the action from its beginning right away.
##     Ambience (fading out) is left alone until the fade is done, then silently resynced.

signal crossfade_finished(active_track: int)

const TRACK_A := 0
const TRACK_B := 1
const SILENT_DB := -80.0

## How far the follower may drift before we seek it (seconds).
@export var drift_tolerance := 0.03
## After a seek, wait this long before checking drift again.
@export var seek_cooldown := 0.15
## false = linear fade (constant loudness for matching music), true = equal-power.
@export var equal_power := false
@export var bus_name := &"Music"
## Which of the two tracks passed to play_pair() is which.
@export_enum("A:0", "B:1") var ambience_track := 0
@export_enum("A:0", "B:1") var action_track := 1

var _players: Array[AudioStreamPlayer] = []
var _segs: Array[Dictionary] = []       # {"a0", "a1", "b0"}
var _manual_offset := 0.0               # runtime nudge: B = mapped B + offset
var _blend := 0.0 : set = _set_blend    # 0.0 = only A audible, 1.0 = only B audible
var _leader := TRACK_A
var _tween: Tween
var _cooldown := 0.0
var _running := false
var _user_paused := false
var _held_idx := -1                     # follower currently parked during an intermezzo, or -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep playing across scenes and while paused
	var bus := bus_name if AudioServer.get_bus_index(bus_name) != -1 else &"Master"
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)
	set_segments([])
	_apply_blend()


# ---------------------------------------------------------------- public API

## Start a synced pair. If this exact pair is already playing, only the segments are updated,
## so it is safe to call from every scene's _ready().
func play_pair(stream_a: AudioStream, stream_b: AudioStream,
		segments: Array = [], start_track := TRACK_A) -> void:
	if _running and _players[0].stream == stream_a and _players[1].stream == stream_b:
		set_segments(segments)
		return

	_kill_tween()
	_players[0].stream = _make_loop(stream_a)
	_players[1].stream = _make_loop(stream_b)
	set_segments(segments)
	_manual_offset = 0.0
	_held_idx = -1
	_user_paused = false
	for p in _players:
		p.stream_paused = false
	_leader = start_track
	_blend = float(start_track)

	_players[0].play(0.0)
	_players[1].play(0.0)
	_running = true
	_cooldown = 0.0   # the first _process() frame parks/aligns the follower


func play_action(duration := 1.5) -> void:
	crossfade_to(action_track, duration)

func play_ambience(duration := 3.0) -> void:
	crossfade_to(ambience_track, duration)

func is_action() -> bool:
	return _leader == action_track

func toggle(duration := 2.0) -> void:
	if is_action():
		play_ambience(duration)
	else:
		play_action(duration)


## Fade to track A or B. The target track becomes the leader immediately.
func crossfade_to(track: int, duration := 2.0, curve := Tween.TRANS_SINE) -> void:
	_leader = track
	_cooldown = 0.0
	var target := float(track)
	_kill_tween()
	if duration <= 0.0 or not _running:
		_blend = target
		crossfade_finished.emit(track)
		return
	_tween = create_tween()
	_tween.tween_property(self, "_blend", target, duration).set_trans(curve)
	_tween.finished.connect(func(): crossfade_finished.emit(track))


## Segments: [{"a_start": s, "a_end": e (optional), "b_start": t (optional, default 0)}, ...]
## a_end defaults to a_start + (action length - b_start). An empty array means "line up
## the whole time from 0" (plain sync).
func set_segments(segments: Array) -> void:
	_segs.clear()
	var b_len := 0.0
	if _players.size() == 2 and _players[1].stream != null:
		b_len = _players[1].stream.get_length()
	for s in segments:
		var a0 := float(s["a_start"])
		var b0 := float(s.get("b_start", 0.0))
		var a1: float
		if s.has("a_end"):
			a1 = float(s["a_end"])
		else:
			assert(b_len > 0.0, "a_end needed when the action stream isn't loaded yet")
			a1 = a0 + (b_len - b0)
		_segs.append({"a0": a0, "a1": a1, "b0": b0})
	if _segs.is_empty():
		_segs.append({"a0": 0.0, "a1": INF, "b0": 0.0})
	_segs.sort_custom(func(x, y): return x["a0"] < y["a0"])


## Shift B relative to A at runtime (seconds), e.g. tuned by ear.
func set_manual_offset(seconds: float) -> void:
	_manual_offset = seconds

func add_manual_offset(seconds: float) -> void:
	_manual_offset += seconds


func stop(fade_time := 0.0) -> void:
	_kill_tween()
	if fade_time > 0.0 and _running:
		_tween = create_tween().set_parallel(true)
		for p in _players:
			_tween.tween_property(p, "volume_db", SILENT_DB, fade_time)
		_tween.chain().tween_callback(_stop_now)
	else:
		_stop_now()


func set_paused(paused: bool) -> void:
	_user_paused = paused
	_held_idx = -1
	for p in _players:
		p.stream_paused = paused


func is_playing() -> bool:
	return _running


## Current ambience (A) position in seconds.
func get_position() -> float:
	return _pos(_players[0])


# ------------------------------------------------------------------ internals

func _process(delta: float) -> void:
	if not _running or _user_paused:
		return
	_cooldown -= delta

	var li := _leader
	var leader := _players[li]
	var follower := _players[1 - li]
	if _held_idx == li:  # the leader was parked: release it, it plays from its beginning
		leader.stream_paused = false
		_held_idx = -1
	if follower.stream == null:
		return
	var f_len := follower.stream.get_length()
	if f_len <= 0.0:
		return

	var l_pos := _pos(leader)
	var target := 0.0
	var parked := false

	if li == TRACK_A:
		# Ambience leads. Map A-time -> B-time.
		var i := _find_segment(l_pos)
		if i >= 0:
			var s := _segs[i]
			target = s["b0"] + (l_pos - s["a0"]) + _manual_offset
		else:
			target = _segs[_next_segment(l_pos)]["b0"] + _manual_offset  # intermezzo: park at start
			parked = true
		target = fposmod(target, f_len)
	else:
		# Action leads. Ambience follows to the nearest matching spot.
		var f_pos := _pos(follower)
		# While ambience is still fading out inside an intermezzo, leave it alone.
		if _is_fading() and _find_segment(f_pos) == -1:
			return
		var best_d := INF
		for s in _segs:
			var rel := clampf(l_pos - s["b0"] - _manual_offset, 0.0, s["a1"] - s["a0"])
			var cand: float = s["a0"] + rel
			var d := absf(wrapf(cand - f_pos, -f_len * 0.5, f_len * 0.5))
			if d < best_d:
				best_d = d
				target = cand
		target = fposmod(target, f_len)

	if parked:
		if _held_idx == -1:
			follower.seek(target)
			follower.stream_paused = true
			_held_idx = 1 - li
		return
	if _held_idx != -1:  # segment begins: start the follower exactly in sync
		follower.stream_paused = false
		follower.seek(target)
		_held_idx = -1
		_cooldown = seek_cooldown
		return

	if _cooldown > 0.0:
		return
	var drift := wrapf(target - _pos(follower), -f_len * 0.5, f_len * 0.5)
	if absf(drift) > drift_tolerance:
		follower.seek(target)
		_cooldown = seek_cooldown


## Index of the segment containing this A-time, or -1 (intermezzo).
func _find_segment(a_pos: float) -> int:
	for i in _segs.size():
		if a_pos >= _segs[i]["a0"] and a_pos < _segs[i]["a1"]:
			return i
	return -1


## First segment starting after this A-time (wraps to the first one: A loops).
func _next_segment(a_pos: float) -> int:
	for i in _segs.size():
		if _segs[i]["a0"] > a_pos:
			return i
	return 0


func _is_fading() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## Position including time since the last audio mix (smooths get_playback_position()).
func _pos(p: AudioStreamPlayer) -> float:
	return p.get_playback_position() + AudioServer.get_time_since_last_mix()


func _set_blend(v: float) -> void:
	_blend = clampf(v, 0.0, 1.0)
	_apply_blend()


func _apply_blend() -> void:
	if _players.size() < 2:
		return
	var ga: float
	var gb: float
	if equal_power:
		ga = cos(_blend * PI * 0.5)
		gb = sin(_blend * PI * 0.5)
	else:
		ga = 1.0 - _blend
		gb = _blend
	_players[0].volume_db = maxf(linear_to_db(ga), SILENT_DB)
	_players[1].volume_db = maxf(linear_to_db(gb), SILENT_DB)


func _make_loop(stream: AudioStream) -> AudioStream:
	# Both streams loop at their own length (A: 98.682s, B: its own).
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


func _stop_now() -> void:
	for p in _players:
		p.stream_paused = false
		p.stop()
	_held_idx = -1
	_running = false
	_apply_blend()


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
