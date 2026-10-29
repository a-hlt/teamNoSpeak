#!/bin/sh

# Capture SIGTERM et propage aux processus enfants
_term() {
    echo "[start.sh] SIGTERM recu, arret des services..."
    kill -TERM "$TS3_PID" 2>/dev/null
    kill -TERM "$NGINX_PID" 2>/dev/null
    wait "$TS3_PID"
    wait "$NGINX_PID"
    echo "[start.sh] Arret propre termine."
}
trap _term TERM INT

su teamspeak -c "cd /opt/teamspeak && ./ts3server_minimal_runscript.sh license_accepted=1 serveradmin_password=${TS3_ADMIN_PASSWORD:-adminpass123}" &
TS3_PID=$!

nginx -g "daemon off;" &
NGINX_PID=$!

wait "$TS3_PID" "$NGINX_PID"
