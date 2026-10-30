#!/usr/bin/env bash
# dwmstatus - status text for dwm's top bar:
#   running cat | connectivity | volume | brightness | battery | clock
# The cat runs faster the harder your CPU works.
# Deps: xorg-xsetroot, brightnessctl, wireplumber (wpctl), networkmanager (nmcli)
# Icons come from a Nerd Font (JetBrainsMono Nerd Font, set in dwm's config.h).

TRACK=10          # how far the cat runs before looping
SEP="   "
pos=0
frame=0
cpu=0
prev_total=0
prev_idle=0

bat="" vol="" bri="" net="" bt=""
last_slow=0
last_net=0
last_res=0

# icons:  wifi   volume   mute   brightness   charging   clock
ICON_WIFI=""
ICON_VOL=""
ICON_MUTE=""
ICON_BRI=""
ICON_BOLT=""
ICON_CLOCK=""
BAT_ICONS=("" "" "" "" "")
ICON_BT=$'\uf293'   # bluetooth
ICON_CPU="" ICON_RAM="" ICON_DISK=""
SHOW_CAT=1 SHOW_RES=0
NCPU=$(nproc 2>/dev/null || echo 1)
res=""

# icon set, cat and CPU/RAM/disk options chosen with dwm-bar (Super+Shift+B)
load_style() {
	# shellcheck source=/dev/null
	[[ -r $HOME/.config/dwm-theme/bar-icons.sh ]] && . "$HOME/.config/dwm-theme/bar-icons.sh"
}
load_style

# CPU as busy threads / total, RAM and disk as used/total (shown when there is no second bar)
read_res() {
	local mt ma used d
	mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
	ma=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
	used=$((mt - ma))
	d=$(df -BG --output=used,size / 2>/dev/null | awk 'NR==2{gsub("G","");print $1"/"$2"G"}')
	printf -v res '%s%d.%d/%dG' "${ICON_RAM:+$ICON_RAM }" $((used / 1048576)) $((used * 10 / 1048576 % 10)) $(((mt + 524288) / 1048576))
	[[ -n $d ]] && res+="${SEP}${ICON_DISK:+$ICON_DISK }${d}"
}

read_cpu() {
	local _ user nice system idle iowait irq softirq steal
	read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
	local idle_all=$((idle + iowait))
	local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
	local dt=$((total - prev_total)) di=$((idle_all - prev_idle))
	if ((dt > 0)); then cpu=$((100 * (dt - di) / dt)); fi
	prev_total=$total
	prev_idle=$idle_all
}

read_slow() {
	# battery (omitted on machines without one)
	bat=""
	local b cap st icon idx
	for b in /sys/class/power_supply/BAT*; do
		[[ -r $b/capacity ]] || continue
		read -r cap < "$b/capacity"
		read -r st < "$b/status"
		idx=$((cap / 21)); ((idx > 4)) && idx=4
		icon=${BAT_ICONS[$idx]}
		[[ $st == Charging ]] && icon=$ICON_BOLT
		bat="${icon:+$icon }${cap}%"
		break
	done

	# volume (PipeWire)
	local v
	v=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
	if [[ -z $v ]]; then
		vol=""
	elif [[ $v == *MUTED* ]]; then
		vol="${ICON_MUTE:+$ICON_MUTE }muted"
	else
		vol="${ICON_VOL:+$ICON_VOL }$(awk '{printf "%d%%", $2*100}' <<< "$v")"
	fi

	# brightness
	local br
	br=$(brightnessctl -m 2>/dev/null | cut -d, -f4)
	if [[ -n $br ]]; then bri="${ICON_BRI:+$ICON_BRI }$br"; else bri=""; fi
}

# online = NetworkManager reports full connectivity
read_net() {
	local state=""
	if command -v nmcli >/dev/null 2>&1; then
		state=$(nmcli -t -g STATE general 2>/dev/null)
	fi
	if [[ -z $state ]]; then
		# no NetworkManager: any non-loopback interface that is up counts
		local i
		for i in /sys/class/net/*/operstate; do
			[[ $i == */lo/operstate ]] && continue
			if [[ -r $i && $(<"$i") == up ]]; then state=connected; break; fi
		done
	fi
	if [[ $state == connected ]]; then
		net="${ICON_WIFI:+$ICON_WIFI }online ✓"
	else
		net="${ICON_WIFI:+$ICON_WIFI }offline ✗"
	fi
}

# bluetooth: off / on / connected (omitted when there is no adapter or no bluetoothctl)
read_bt() {
	bt=""
	command -v bluetoothctl >/dev/null 2>&1 || return 0
	local info n
	info=$(timeout 2 bluetoothctl show 2>/dev/null) || return 0
	[[ -n $info ]] || return 0
	if [[ $info != *"Powered: yes"* ]]; then
		bt="${ICON_BT:+$ICON_BT }off"
		return 0
	fi
	n=$(timeout 2 bluetoothctl devices Connected 2>/dev/null | grep -c '^Device')
	if ((n > 0)); then bt="${ICON_BT:+$ICON_BT }connected"; else bt="${ICON_BT:+$ICON_BT }on"; fi
}

draw_cat() {
	local sprite lpad rpad
	if ((frame % 2)); then sprite="=^.^="; else sprite="=^-^="; fi
	printf -v lpad '%*s' "$pos" ''
	printf -v rpad '%*s' "$((TRACK - pos))" ''
	CAT="${lpad}${sprite}${rpad}"
}

while true; do
	printf -v now '%(%s)T' -1

	if ((now - last_slow >= 2)); then load_style; read_slow; last_slow=$now; fi
	if ((now - last_net >= 5)); then read_net; read_bt; last_net=$now; fi

	read_cpu
	draw_cat
	printf -v clock '%(%a %b %d  %I:%M %p)T' -1

	out=" "
	if ((SHOW_CAT)); then out+="${CAT}${SEP}"; fi
	if ((SHOW_RES)); then
		if ((now - last_res >= 5)); then read_res; last_res=$now; fi
		t=$((cpu * NCPU / 10))
		out+="${ICON_CPU:+$ICON_CPU }$((t / 10)).$((t % 10))/${NCPU}${SEP}${res}${SEP}"
	fi
	out+="${net}"
	[[ -n $bt ]] && out+="${SEP}${bt}"
	[[ -n $vol ]] && out+="${SEP}${vol}"
	[[ -n $bri ]] && out+="${SEP}${bri}"
	[[ -n $bat ]] && out+="${SEP}${bat}"
	out+="${SEP}${ICON_CLOCK:+$ICON_CLOCK }${clock} "
	# if X is gone (session ended) stop instead of looping forever
	xsetroot -name "$out" || exit 0

	# advance the cat
	frame=$((frame + 1))
	pos=$(((pos + 1) % (TRACK + 1)))

	# faster cat under load: 500ms idle -> 100ms at ~100% CPU
	ms=$((500 - cpu * 4))
	((ms < 100)) && ms=100
	printf -v delay '0.%03d' "$ms"
	sleep "$delay"
done
