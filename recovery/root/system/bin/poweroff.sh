#!/system/bin/sh
# TWRP poweroff hook.
# Called by TWRP's tw_reboot(rb_poweroff) immediately before shutdown.
# Do NOT call "twrp reboot poweroff" from here: that would run this hook again.

# Self-ignore guard: only once per boot.
if [ -f /tmp/.twrp_poweroff_done ]; then
    exit 0
fi
: > /tmp/.twrp_poweroff_done

# Restore the TWRP config we want for the next session.
twrp set tw_enable_adb 1
twrp set tw_enable_fastboot 0
twrp set tw_mount_system_ro 1
twrp set tw_never_show_system_ro_page 1
twrp set tw_no_screen_timeout 1

exit 0
