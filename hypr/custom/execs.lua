

-- Bloqueo por inactividad ACTIVO: hypridle corre. Se quito el listener de
-- suspension de hypridle.conf para no perder el acceso remoto.


-- Honour `end4-locker off` across restarts. end-4 launches hypridle from its
-- own hyprland/execs.lua, so without this the lock comes back on every login
-- and "home mode" silently expires overnight.
-- Deliberately NOT the string step 3 removes, so the two do not fight.
hl.on("hyprland.start", function()
    hl.exec_cmd("sleep 3; [ -f \"${XDG_STATE_HOME:-$HOME/.local/state}/end4-locker-off\" ] && pkill -x hypridle")
end)

-- SDDM's session activates xdg-desktop-portal over D-Bus seconds before
-- Hyprland exists, so the portal caches an environment with no WAYLAND_DISPLAY,
-- XDG_CURRENT_DESKTOP or QT_QPA_PLATFORM -- and it never re-reads it. Every app
-- the portal launches inherits that empty environment.
--
-- How it shows up: qBittorrent's "Open destination folder" does nothing. It
-- calls portal OpenURI.OpenFile with a directory fd (the correct API), the
-- portal launches Dolphin, and Dolphin aborts with "could not connect to
-- display" because Qt cannot initialise a platform plugin. The portal still
-- answers Response 0, because spawning the process did succeed -- it has no way
-- to know the child died 50ms later. Nothing is logged where you would look.
--
-- The unit already declares After=graphical-session.target, but that only
-- orders inside a systemd transaction; D-Bus activation bypasses it entirely.
-- Measured 2026-10-13: portal at 13:01:37, Hyprland at 13:01:42, and five
-- "Choosing gtk.portal ... as a last-resort fallback" lines because the portal
-- could not tell which desktop it was on.
--
-- Restarting it once the session has published its environment is blunt but
-- reliable: we do not control whoever asks for the portal that early.
hl.on("hyprland.start", function()
    hl.exec_cmd("sleep 2; systemctl --user restart xdg-desktop-portal.service xdg-desktop-portal-gtk.service")
end)

-- graphical-session.target is reached ONLY by uwsm here: its
-- wayland-session@hyprland.desktop.target pulls it in. Neither /usr/bin/Hyprland
-- nor /usr/bin/start-hyprland mentions the target at all (checked with strings:
-- zero hits in both), so on the plain "Hyprland" session nothing activates it
-- and everything with WantedBy=graphical-session.target stays dead:
--
--   wayvnc.service          remote VNC
--   hypr-rdp.service        remote RDP
--   plasma-dolphin.service  the FileManager1 provider
--   app-{Enpass,blueman,nm-applet,kdeconnect,remmina,alarm-clock}@autostart
--
-- graphical-session.target cannot be started by hand -- it sets
-- RefuseManualStart=yes, and `systemctl --user start graphical-session.target`
-- answers "Operation refused, unit may be requested by dependency only".
-- So we start ~/.config/systemd/user/hyprland-session.target instead, which
-- BindsTo + Before it and pulls it up as a dependency. Same pattern as
-- sway-session.target.
--
-- Harmless under uwsm: the target is already active by then, so it is a no-op.
--
-- NOTE: this does NOT bring back ~/.config/uwsm/env-hyprland.d/*.sh. Only uwsm
-- sources those. Without it, move what you need into env= in the Lua config.
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprland-session.target")
end)
