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

bat="" vol="" bri="" net=""
last_slow=0
last_net=0

# icons:  wifi   volume   mute   brightness   charging   clock
ICON_WIFI=""
ICON_VOL=""
ICON_MUTE=""
ICON_BRI=""
ICON_BOLT=""
ICON_CLOCK=""
BAT_ICONS=("" "" "" "" "")

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
		bat="${icon} ${cap}%"
		break
	done

	# volume (PipeWire)
	local v
	v=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
	if [[ -z $v ]]; then
		vol=""
	elif [[ $v == *MUTED* ]]; then
		vol="${ICON_MUTE} muted"
	else
		vol="${ICON_VOL} $(awk '{printf "%d%%", $2*100}' <<< "$v")"
	fi

	# brightness
	local br
	br=$(brightnessctl -m 2>/dev/null | cut -d, -f4)
	if [[ -n $br ]]; then bri="${ICON_BRI} $br"; else bri=""; fi
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
		net="${ICON_WIFI} online ✓"
	else
		net="${ICON_WIFI} offline ✗"
	fi
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

	if ((now - last_slow >= 2)); then read_slow; last_slow=$now; fi
	if ((now - last_net >= 5)); then read_net; last_net=$now; fi

	read_cpu
	draw_cat
	printf -v clock '%(%a %b %d  %I:%M %p)T' -1

	out=" ${CAT}${SEP}${net}"
	[[ -n $vol ]] && out+="${SEP}${vol}"
	[[ -n $bri ]] && out+="${SEP}${bri}"
	[[ -n $bat ]] && out+="${SEP}${bat}"
	out+="${SEP}${ICON_CLOCK} ${clock} "
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
