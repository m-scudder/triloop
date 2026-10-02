# Local Coach model (Debug)

Athevia can use a local OpenAI-compatible model endpoint in Debug builds. If the
local endpoint is unavailable or returns an invalid Coach response, the app
falls back to the existing Supabase/OpenAI path.

## Xcode scheme

In **Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables**,
add:

- `ATHEVIA_COACH_LOCAL_ENABLED=1`
- `ATHEVIA_COACH_LOCAL_URL=http://127.0.0.1:11434/v1/chat/completions`
- `ATHEVIA_COACH_LOCAL_MODEL=<the model name exposed by the local server>`

The default URL is already the Ollama OpenAI-compatible chat-completions
endpoint, so `ATHEVIA_COACH_LOCAL_URL` may be omitted when using that endpoint.

## Runtime flow

1. The deterministic Coach parser still handles supported plan changes first.
2. If AI is required and local mode is enabled, the Debug app calls the local
   OpenAI-compatible endpoint.
3. The response must pass `CoachLLMResponseGuard`.
4. Invalid or unavailable local inference falls back to Supabase/OpenAI.
5. Release builds do not compile the local transport path.

The local model receives the same sanitized Coach payload used by the remote
provider: no athlete scope ID, workout UUIDs, provider/source labels, GPS route,
or workout step trees.
