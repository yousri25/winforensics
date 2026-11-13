#!/usr/bin/env bash
# Removes the launcher and menu entry. Asks before deleting the VM and the config.
set -u
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/winforensics"

rm -f "$HOME/.local/bin/winforensics" "$HOME/.local/share/applications/winforensics.desktop"
echo "Removed launcher and menu entry."

if [ -f "$CONF_DIR/compose.yaml" ] && [ -f "$CONF_DIR/config.env" ]; then
    read -r -p "Delete the Windows VM and its disk (everything inside it)? [y/N] " a
    if [ "${a:-N}" = "y" ] || [ "${a:-N}" = "Y" ]; then
        args=(--project-name winforensics --env-file "$CONF_DIR/config.env" --file "$CONF_DIR/compose.yaml")
        if [ -f "$CONF_DIR/compose.iso.yaml" ]; then args+=(--file "$CONF_DIR/compose.iso.yaml"); fi
        docker compose "${args[@]}" down --volumes
    fi
fi

read -r -p "Delete the config folder $CONF_DIR (contains your password)? [y/N] " a
if [ "${a:-N}" = "y" ] || [ "${a:-N}" = "Y" ]; then rm -rf "$CONF_DIR"; fi
echo "Your shared folder was not touched."
