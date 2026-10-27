#!/usr/bin/env bash
# dwmstatus.sh - status bar for dwm with a running cat
# The cat runs faster the harder your CPU is working.
# Deps: xorg-xsetroot, brightnessctl, wireplumber (wpctl), networkmanager (nmcli)

TRACK=10          # how far the cat runs before looping
pos=0
frame=0
cpu=0
prev_total=0
prev_idle=0

bat="" ram="" vol="" bri="" ssid="offline"
last_slow=0
last_wifi=0

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
	local b cap st icon
	for b in /sys/class/power_supply/BAT*; do
		[[ -r $b/capacity ]] || continue
		read -r cap < "$b/capacity"
		read -r st < "$b/status"
		case $st in
			Charging) icon="+" ;;
			Full)     icon="=" ;;
			*)        icon="-" ;;
		esac
		bat="BAT ${cap}%${icon}"
		break
	done

	# memory
	ram=$(free -m | awk '/^Mem:/ {printf "%.1fG", $3/1024}')

	# volume (PipeWire)
	local v
	v=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
	if [[ -z $v ]]; then
		vol=""
	elif [[ $v == *MUTED* ]]; then
		vol="VOL mute"
	else
		vol="VOL $(awk '{printf "%d%%", $2*100}' <<< "$v")"
	fi

	# brightness
	local br
	br=$(brightnessctl -m 2>/dev/null | cut -d, -f4)
	if [[ -n $br ]]; then bri="BRI $br"; else bri=""; fi
}

read_wifi() {
	ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
	[[ -z $ssid ]] && ssid="offline"
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
	if ((now - last_wifi >= 10)); then read_wifi; last_wifi=$now; fi

	read_cpu
	draw_cat
	printf -v clock '%(%a %b %d  %I:%M %p)T' -1

	out=" ${CAT} | CPU ${cpu}% | RAM ${ram} | WIFI ${ssid}"
	[[ -n $bri ]] && out+=" | ${bri}"
	[[ -n $vol ]] && out+=" | ${vol}"
	[[ -n $bat ]] && out+=" | ${bat}"
	out+=" | ${clock} "
	xsetroot -name "$out"

	# advance the cat
	frame=$((frame + 1))
	pos=$(((pos + 1) % (TRACK + 1)))

	# faster cat under load: 500ms idle -> 100ms at ~100% CPU
	ms=$((500 - cpu * 4))
	((ms < 100)) && ms=100
	printf -v delay '0.%03d' "$ms"
	sleep "$delay"
done
