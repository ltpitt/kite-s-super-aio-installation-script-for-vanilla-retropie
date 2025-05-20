#!/bin/sh
# emu name to /dev/shm/runcommand.log
echo "on-start: $2" >&2
if [ "$2" = "pcsx-rearmed" ] || [ "$2" = "mame4all" ] || [ "$2" = "wolf4sdl" ] || [ "$2" = "wolf4sdl-spear" ] || [ "$2" = "gngeo" ]
then
sudo killall > /dev/null 2>&1 xboxdrv
sudo /opt/retropie/supplementary/xboxdrv/bin/xboxdrv > /dev/null 2>&1 \
	--evdev /dev/input/by-id/usb-Arduino_LLC_Arduino_Leonardo_HIDAF-if02-event-joystick \
	--silent \
	--detach-kernel-driver \
	--force-feedback \
	--deadzone-trigger 15% \
	--deadzone 4000 \
	--mimic-xpad \
        --device-name "XBOX 360 Controller (xboxdrv)" \
	--evdev-absmap ABS_HAT0X=dpad_x,ABS_HAT0Y=dpad_y \
	--evdev-keymap BTN_THUMB2=x,BTN_THUMB=a,BTN_TRIGGER=b,BTN_PINKIE=back,BTN_BASE=lb,BTN_BASE3=rb,BTN_TOP=y,BTN_TOP2=start \
	--dpad-only \
	--ui-axismap lt=void,rt=void \
	--ui-buttonmap tl=void,tr=void,guide=void \
	&
fi
