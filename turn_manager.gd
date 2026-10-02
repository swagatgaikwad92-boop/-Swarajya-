extends RefCounted
## Runs everything that happens when the player ends a turn.

const Rules = preload("res://scripts/core/rules.gd")
const AIPlayer = preload("res://scripts/ai/ai_player.gd")


## Returns the log lines produced during this turn change.
static func end_player_turn(s: Dictionary) -> Array:
	var before: int = int(s.get("log_count", 0))
	var player: String = s["player"]
	Rules.add_log(s, "You end your turn.")
	for fid in s["factions"]:
		if fid != player:
			AIPlayer.run_faction(s, fid)
			Rules.check_end(s)
			if s["status"] != "playing":
				break
	if s["status"] == "playing":
		Rules.process_economy(s)
		Rules.process_walls(s)
		Rules.process_armies(s)
		s["stats"]["turns_played"] = int(s["stats"]["turns_played"]) + 1
		s["turn"] = int(s["turn"]) + 1
		Rules.sync_calendar(s)
		Rules.tick_diplomacy(s)
		if Rules.is_monsoon(s):
			Rules.add_log(s, "Monsoon quarter: supply is harder and sieges slower outside fort networks.")
		Rules.check_end(s)
		Rules.queue_event(s)
	var fresh: int = mini(int(s.get("log_count", 0)) - before, s["log"].size())
	var report: Array = []
	var lines: Array = s["log"]
	for i in range(lines.size() - fresh, lines.size()):
		report.append(lines[i])
	return report
