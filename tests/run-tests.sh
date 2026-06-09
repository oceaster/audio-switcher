#!/bin/bash
# Test suite for audio-switcher — mocks pactl to verify logic.
set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly SCRIPT="$ROOT/audio-switcher"
readonly TMPD="/tmp/as-test-$$"
readonly SCN="$TMPD/scenario"
readonly PASSFILE="/tmp/as-counter-pass-$$" FAILFILE="/tmp/as-counter-fail-$$"

echo "" >&2
echo "══════════  audio-switcher test suite  ══════════" >&2

setup() {
	rm -rf "$TMPD"
	mkdir -p "$TMPD/bin" "$TMPD/home/.config"
	# Init counters only on first run
	[[ -f "$PASSFILE" ]] || echo 0 >"$PASSFILE"
	[[ -f "$FAILFILE" ]] || echo 0 >"$FAILFILE"
	export HOME="$TMPD/home"
	export XDG_CONFIG_HOME="$TMPD/home/.config"
	export PATH="$TMPD/bin:$PATH"
	export TMPDIR="$TMPD"
	export AUDIO_SWITCHER_NO_REEXEC=1
}

ok() {
	P=$(<"$PASSFILE"); echo $((P + 1)) >"$PASSFILE"
	printf '  \033[32mPASS\033[m %s\n' "$1" >&2
}
fail() {
	F=$(<"$FAILFILE"); echo $((F + 1)) >"$FAILFILE"
	printf '  \033[31mFAIL\033[m %s\n    %s\n' "$1" "$2" >&2
}

contains() {
	local name="$1" needle="$2" haystack="$3"
	echo "$haystack" | grep -qFe "$needle" && ok "$name" || fail "$name" "missing: $needle"
}
eq() {
	local name="$1" expected="$2" actual="$3"
	[[ "$expected" == "$actual" ]] && ok "$name" || fail "$name" "expected '$expected', got '$actual'"
}

# ── Mock pactl ──────────────────────────────────────────────
# Reads from $SCN. Each command block starts with ## CMD: <cmd> <args>
_mock() {
	cat >"$TMPD/bin/pactl" <<'PEOF'
#!/bin/bash
sc="${TMPDIR:-/tmp}/scenario"
c="${1:-}"; shift
k="$c"
for a in "$@"; do k="$k $a"; done
awk -v k="$k" '
BEGIN{out=0;err=0;m=0;ex=0}
/^## CMD:/{if(m&&out==0&&err==0)exit ex;out=0;err=0;m=0;l=$0;sub(/^## CMD: */,"",l);if(l==k)m=1;next}
m&&/^## OUT:/{out=1;next} m&&/^## ERR:/{err=1;next}
m&&/^## EXIT:/{ex=$2;exit ex} m&&out{print} m&&err{print >"/dev/stderr"}
END{exit ex}' "$sc"
PEOF
	chmod +x "$TMPD/bin/pactl"
}

# ── Scenarios ───────────────────────────────────────────────

s_2sinks() {  # Two sinks, default = headset
	cat >"$SCN" <<'EOF'
## CMD: info
## OUT:
Server String: test
## EXIT: 0
## CMD: list short sinks
## OUT:
0	alsa_output.hdmi	PipeWire	s16le 2ch 48000Hz	IDLE
1	alsa_output.usb-headset	PipeWire	s16le 2ch 48000Hz	IDLE
## EXIT: 0
## CMD: get-default-sink
## OUT:
alsa_output.usb-headset
## EXIT: 0
## CMD: list sinks
## OUT:
Sink #0
	Name: alsa_output.hdmi
	Description: HDMI Output
Sink #1
	Name: alsa_output.usb-headset
	Description: USB Headset
## EXIT: 0
## CMD: set-default-sink alsa_output.hdmi
## EXIT: 0
## CMD: list short sink-inputs
## OUT:
## EXIT: 0
## CMD: set-sink-mute alsa_output.hdmi 0
## EXIT: 0
EOF
}

s_onesink() {
	cat >"$SCN" <<'EOF'
## CMD: info
## OUT:
Server String: test
## EXIT: 0
## CMD: list short sinks
## OUT:
0	alsa_output.hdmi	PipeWire	s16le 2ch 48000Hz	IDLE
## EXIT: 0
## CMD: get-default-sink
## OUT:
alsa_output.hdmi
## EXIT: 0
## CMD: list sinks
## OUT:
Sink #0
	Name: alsa_output.hdmi
	Description: HDMI Output
## EXIT: 0
## CMD: set-default-sink alsa_output.hdmi
## EXIT: 0
## CMD: list short sink-inputs
## OUT:
## EXIT: 0
## CMD: set-sink-mute alsa_output.hdmi 0
## EXIT: 0
EOF
}

s_nosinks() {
	cat >"$SCN" <<'EOF'
## CMD: info
## OUT:
Server String: test
## EXIT: 0
## CMD: list short sinks
## OUT:
## EXIT: 0
## CMD: list sinks
## OUT:
## EXIT: 0
EOF
}

# ── Tests ────────────────────────────────────────────────────

t_help() {
	setup; _mock; s_2sinks
	local out; out=$("$SCRIPT" --help 2>&1)
	contains "help shows usage"    "Usage:" "$out"
	contains "help shows toggle"    "toggle" "$out"
	contains "help shows list"      "--list" "$out"
	contains "help shows focus"     "--focus" "$out"
}

t_list() {
	setup; _mock; s_2sinks
	local out; out=$("$SCRIPT" --list 2>&1)
	contains "list shows HDMI"  "HDMI" "$out"
	contains "list shows USB"   "USB" "$out"
	contains "list marks default" "→" "$out"
}

t_toggle() {
	setup; _mock; s_2sinks
	mkdir -p "$HOME/.config/audio-switcher"
	printf '@USB Headset\n@HDMI\n' >"$HOME/.config/audio-switcher/sinks"

	local out rc=0
	out=$("$SCRIPT" 2>&1) || rc=$?
	eq "toggle exit 0" "0" "$rc"
	contains "toggle switches" "HDMI" "$out"
}

t_toggle_single() {
	setup; _mock; s_onesink
	mkdir -p "$HOME/.config/audio-switcher"
	echo "@HDMI" >"$HOME/.config/audio-switcher/sinks"

	local out rc=0
	out=$("$SCRIPT" 2>&1) || rc=$?
	eq "single exit 0" "0" "$rc"
	contains "single switches" "HDMI" "$out"
}

t_autosetup() {
	setup; _mock; s_onesink
	local out rc=0
	# No config → setup auto-runs for single sink
	printf "1\n" | "$SCRIPT" 2>&1 >/dev/null || rc=$?
	eq "autosetup no crash" "0" "$rc"
}

t_badflag() {
	setup; _mock; s_2sinks
	local out rc=0
	out=$("$SCRIPT" --bogus 2>&1) || rc=$?
	eq "badflag exit 1" "1" "$rc"
	contains "badflag error" "Unknown" "$out"
}

t_lock() {
	setup; _mock; s_2sinks
	mkdir -p "$HOME/.config/audio-switcher"
	echo "@HDMI" >"$HOME/.config/audio-switcher/sinks"

	# Hold the lock
	local lf="$HOME/.config/audio-switcher/lock"
	touch "$lf"
	exec 9>"$lf"
	flock -n 9 || { echo "lock setup fail" >&2; exit 1; }

	local out rc=0
	out=$("$SCRIPT" --list 2>&1) || rc=$?
	exec 9>&-

	eq "lock exit 1" "1" "$rc"
	contains "lock blocked" "Another" "$out"
}

t_status() {
	setup; _mock; s_onesink
	mkdir -p "$HOME/.config/audio-switcher"
	echo "@HDMI" >"$HOME/.config/audio-switcher/sinks"

	local out; out=$("$SCRIPT" --status 2>&1)
	contains "status shows sink" "HDMI" "$out"
}

# ── Run ──────────────────────────────────────────────────────

setup

t_help
t_list
t_toggle
t_toggle_single
t_autosetup
t_badflag
t_lock
t_status

P=$(<"$PASSFILE"); F=$(<"$FAILFILE")
rm -f "$PASSFILE" "$FAILFILE"
echo "" >&2
echo "──────────────────────────────────────────────────" >&2
printf "  Results: \033[32m%d passed\033[m" "$P" >&2
((F > 0)) && printf ", \033[31m%d failed\033[m" "$F" >&2
echo "" >&2
echo "──────────────────────────────────────────────────" >&2

exit "$F"
