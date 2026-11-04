import json
import subprocess
import sys
first, second, invalid = [json.loads(line) for line in subprocess.check_output([sys.argv[1]], text=True).splitlines()]
assert first["text"] == "Primary"
assert second["text"] == "第二字幕\nEnglish"
assert first["command_id"] == 3 and second["command_id"] == 7
assert first["track_id"] == "2" and second["track_id"] == "4"
assert first["subtitle_delay_seconds"] == second["subtitle_delay_seconds"] == "0.500"
assert invalid["text"] == "" and invalid["sequence"] == 9
assert second["start_seconds"] == "1" and second["end_seconds"] == "3"
print("Both native subtitle channels decode correctly; invalid timelines are empty")
