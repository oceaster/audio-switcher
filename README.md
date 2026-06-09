# audio-switcher

Toggle between audio output sinks on Linux (PipeWire / PulseAudio).

## Install

```bash
sudo cp audio-switcher /usr/local/bin/audio-switcher
sudo chmod +x /usr/local/bin/audio-switcher
```

## Usage

| Command | Action |
|---------|--------|
| `audio-switcher` | Toggle to next configured sink |
| `audio-switcher -l` | List all available sinks |
| `audio-switcher -m` | Interactive picker |
| `audio-switcher -c` | Re-run device setup |

First run automatically launches the setup wizard to choose which sinks to cycle between. Preferences are stored in `~/.config/audio-switcher/config`.

## Dependencies

- `bash`
- `pactl` (PipeWire or PulseAudio)
- `notify-send` (optional, for desktop notifications)

## How It Works

- Dynamically discovers sinks via `pactl` — no hardcoded device names
- Config stores patterns (`@substring` or exact sink names) so it survives device re-plugging
- Uses `flock` to prevent concurrent invocations from racing
- Polls the default sink after switching instead of guessing with `sleep`
- Moves all active playback streams to the new sink
- Unmutes the target sink on switch
