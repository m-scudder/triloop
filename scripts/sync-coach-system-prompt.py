from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
prompt = (ROOT / "config" / "coach-system-prompt.txt").read_text().rstrip("\n")

swift = f'''import Foundation

enum CoachSystemPrompt {{
    static let instructions = #"""
{prompt}
"""#
}}
'''

ts = (
    "// Generated from config/coach-system-prompt.txt.\n"
    "// Run scripts/sync-coach-system-prompt.py after editing the canonical prompt.\n"
    f"export const COACH_SYSTEM_PROMPT = {json.dumps(prompt)};\n"
)

(ROOT / "Athevia" / "Data" / "Coach" / "CoachSystemPrompt.swift").write_text(swift)
(ROOT / "supabase" / "functions" / "_shared" / "coach-system-prompt.ts").write_text(ts)
print("Synced Coach system prompt to Swift and Supabase Edge Function.")
