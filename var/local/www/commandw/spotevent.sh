#!/bin/bash
#
# moOde audio player (C) 2014 Tim Curtis
# http://moodeaudio.org
#
# This Program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3, or (at your option)
# any later version.
#
# This Program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
if [[ $PLAYER_EVENT != "started" ]] && [[ $PLAYER_EVENT != "stopped" ]]; then
	#echo "Exit: "$PLAYER_EVENT >> /home/pi/spotevent.log
	exit 0
fi
#echo "Event: "$PLAYER_EVENT >> /home/pi/spotevent.log

SQLDB=/var/local/www/db/moode-sqlite3.db
RESULT=$(sqlite3 $SQLDB "SELECT value FROM cfg_system WHERE param IN ('alsavolume_max','alsavolume','amixname','mpdmixer','camilladsp_volume_sync','rsmafterspot','inpactive','multiroom_tx')")
readarray -t arr <<<"$RESULT"
ALSAVOLUME_MAX=${arr[0]}
ALSAVOLUME=${arr[1]}
AMIXNAME=${arr[2]}
MPDMIXER=${arr[3]}
CDSP_VOLSYNC=${arr[4]}
RSMAFTERSPOT=${arr[5]}
INPACTIVE=${arr[6]}
MULTIROOM_TX=${arr[7]}
RX_ADDRESSES=$(sudo moodeutl -d | grep rx_addresses | cut -d'|' -f2)

if [[ $INPACTIVE == '1' ]]; then
	exit 1
fi

if [[ $PLAYER_EVENT == "started" ]]; then
	/usr/bin/mpc stop > /dev/null
	# Allow time for UI update
	sleep 1

	$(sqlite3 $SQLDB "UPDATE cfg_system SET value='1' WHERE param='spotactive'")

	# Local
	if [[ $CDSP_VOLSYNC == "on" ]]; then
		# Save knob level then set camilladsp volume to 100% (0dB)
		$(sqlite3 $SQLDB "UPDATE cfg_system SET value='$VOLKNOB' WHERE param='volknob_mpd'")
		/var/www/vol.sh 100
	elif [[ $ALSAVOLUME != "none" ]]; then
		/var/www/util/sysutil.sh set-alsavol "$AMIXNAME" $ALSAVOLUME_MAX
	fi

	# Multiroom receivers
	if [[ $MULTIROOM_TX == "On" ]]; then
		for IP_ADDR in $RX_ADDRESSES; do
			RESULT=$(curl -G -S -s --data-urlencode "cmd=trx-control.php -set-alsavol $ALSAVOLUME_MAX" http://$IP_ADDR/command/)
			if [[ $RESULT != "" ]]; then
				RESULT=$(curl -G -S -s --data-urlencode "cmd=trx-control.php -set-alsavol $ALSAVOLUME_MAX" http://$IP_ADDR/command/)
				if [[ $RESULT != "" ]]; then
					echo $(date +%F" "%T)"spotevent.sh: trx-control.php -set-alsavol failed: $IP_ADDR" >> /home/pi/renderer_error.log
				fi
			fi
		done
	fi
fi

if [[ $PLAYER_EVENT == "stopped" ]]; then
	$(sqlite3 $SQLDB "UPDATE cfg_system SET value='0' WHERE param='spotactive'")

	# Local
	# Restore 0dB hardware volume when mpd configured as below
	if [[ $CDSP_VOLSYNC == "on" ]]; then
		# Restore knob level to saved MPD level and reset saved MPD level to 0
		$(sqlite3 $SQLDB "UPDATE cfg_system SET value='$VOLKNOB_MPD' WHERE param='volknob'")
		$(sqlite3 $SQLDB "UPDATE cfg_system SET value='0' WHERE param='volknob_mpd'")
		# NOTE: Without the sleep sometimes CamillaDSP volume is left at 100%
		sleep 2
	elif [[ $MPDMIXER == "software" || $MPDMIXER == "none" ]]; then
		if [[ $ALSAVOLUME != "none" ]]; then
			/var/www/util/sysutil.sh set-alsavol "$AMIXNAME" $ALSAVOLUME_MAX
		fi
	fi

	# Restore knob volume
	/var/www/vol.sh -restore

	# Multiroom receivers
	if [[ $MULTIROOM_TX == "On" ]]; then
		for IP_ADDR in $RX_ADDRESSES; do
			RESULT=$(curl -G -S -s --data-urlencode "cmd=vol.sh -restore" http://$IP_ADDR/command/)
			if [[ $RESULT != "" ]]; then
				RESULT=$(curl -G -S -s --data-urlencode "cmd=vol.sh -restore" http://$IP_ADDR/command/)
				if [[ $RESULT != "" ]]; then
					echo $(date +%F" "%T)" spotevent.sh vol.sh -restore failed: $IP_ADDR" >> /home/pi/renderer_error.log
				fi
			fi
		done
	fi

	if [[ $RSMAFTERSPOT == "Yes" ]]; then
		/usr/bin/mpc play > /dev/null
	fi
fi
