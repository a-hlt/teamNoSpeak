from flask import Flask, jsonify, request
import os
import signal
import sys
from datetime import datetime
import ts3.query

app = Flask(__name__)

PORT = int(os.environ.get("PORT", 5000))
TS3_HOST = os.environ.get("TS3_HOST", "webserver")
TS3_PORT = int(os.environ.get("TS3_PORT", 10011))
TS3_USER = os.environ.get("TS3_USER", "serveradmin")
TS3_PASS = os.environ.get("TS3_PASS", "adminpass123")

def query_ts3(command_func):
    try:
        with ts3.query.TS3Connection(TS3_HOST, TS3_PORT) as conn:
            try:
                conn.login(client_login_name=TS3_USER, client_login_password=TS3_PASS)
            except Exception:
                pass
            conn.use(sid=1)
            return command_func(conn)
    except Exception as e:
        print(f"Erreur connexion TS3 ServerQuery: {e}")
        return None

@app.route("/api/health", methods=['GET'])
def health():
    return jsonify({"status": "ok"}), 200

@app.route("/api/stats", methods=['GET'])
def get_stats():
    res = query_ts3(lambda conn: conn.serverinfo().parsed[0])
    if res:
        # Ne compter que les vrais clients humains (exclure Query)
        clients = query_ts3(lambda conn: conn.clientlist().parsed) or []
        human_clients = [c for c in clients if c.get("client_type") == "0"]
        return jsonify({
            "server_name": res.get("virtualserver_name", "TeamSpeak 3 Server"),
            "status": "EN LIGNE",
            "uptime": f"{int(res.get('virtualserver_uptime', 0)) // 3600}h",
            "slots_used": len(human_clients),
            "max_slots": int(res.get("virtualserver_maxclients", 32)),
            "channels_count": int(res.get("virtualserver_channelsonline", 0))
        }), 200

    return jsonify({
        "server_name": "TeamSpeak 3 Server",
        "status": "EN LIGNE",
        "uptime": "1h",
        "slots_used": 0,
        "max_slots": 32,
        "channels_count": 0
    }), 200

@app.route("/api/channels", methods=['GET'])
def get_channels():
    res = query_ts3(lambda conn: conn.channellist().parsed)
    clients = query_ts3(lambda conn: conn.clientlist().parsed) or []
    if res:
        formatted = []
        for ch in res:
            cid = ch.get("cid")
            # Compter uniquement les vrais utilisateurs humains par canal
            users_in_ch = len([c for c in clients if c.get("cid") == cid and c.get("client_type") == "0"])
            formatted.append({
                "id": int(cid),
                "name": ch.get("channel_name", "Salon"),
                "users_count": users_in_ch,
                "type": "public"
            })
        return jsonify(formatted), 200

    return jsonify([]), 200

@app.route("/api/users", methods=['GET'])
def get_users():
    res = query_ts3(lambda conn: conn.clientlist().parsed)
    if res:
        formatted = []
        for cl in res:
            # Filtrer strictement les clients ServerQuery (client_type != 0)
            if cl.get("client_type") != "0":
                continue
            
            clid = cl.get("clid")
            # Recuperer l'etat du micro (muted) via clientinfo
            info_res = query_ts3(lambda conn: conn.clientinfo(clid=clid).parsed[0]) or {}
            is_muted = info_res.get("client_input_muted") == "1" or info_res.get("client_output_muted") == "1"

            formatted.append({
                "id": int(clid),
                "nickname": cl.get("client_nickname", "Joueur"),
                "channel_id": int(cl.get("cid", 0)),
                "ping": "15ms",
                "status": "online",
                "muted": is_muted
            })
        return jsonify(formatted), 200

    return jsonify([]), 200

@app.route("/api/logs", methods=['GET'])
def get_logs():
    res = query_ts3(lambda conn: conn.logview(lines=15).parsed)
    if res:
        logs = []
        for idx, entry in enumerate(res):
            msg = entry.get("l", str(entry))
            logs.append({
                "id": idx + 1,
                "time": datetime.now().strftime("%H:%M:%S"),
                "level": "INFO",
                "message": msg
            })
        return jsonify(logs), 200

    return jsonify([]), 200

# Action 1: Expulser un utilisateur (Kick)
@app.route("/api/mod/kick", methods=['POST'])
def kick_user():
    data = request.json or {}
    user_id = data.get("user_id")
    nickname = data.get("nickname", "Utilisateur")
    
    if user_id:
        res = query_ts3(lambda conn: conn.clientkick(clid=user_id, reasonid=5, reasonmsg="Expulse par le moderateur (Web Dashboard)"))
        if res:
            return jsonify({"success": True, "message": f"{nickname} a ete kick"}), 200

    return jsonify({"error": "Erreur lors du kick"}), 400

# Action 2: Envoyer un Poke (Notification popup)
@app.route("/api/mod/poke", methods=['POST'])
def poke_user():
    data = request.json or {}
    user_id = data.get("user_id")
    msg = data.get("message", "Avertissement du moderateur")
    
    if user_id:
        res = query_ts3(lambda conn: conn.clientpoke(clid=user_id, msg=msg))
        if res:
            return jsonify({"success": True}), 200

    return jsonify({"error": "Erreur lors du poke"}), 400

# Action 3: Envoyer un Message Prive
@app.route("/api/mod/message", methods=['POST'])
def send_private_message():
    data = request.json or {}
    user_id = data.get("user_id")
    msg = data.get("message", "Message du moderateur")
    
    if user_id:
        res = query_ts3(lambda conn: conn.sendtextmessage(targetmode=1, target=user_id, msg=msg))
        if res:
            return jsonify({"success": True}), 200

    return jsonify({"error": "Erreur lors de l'envoi"}), 400

# Action 4: Deplacer un utilisateur de canal (Move)
@app.route("/api/mod/move", methods=['POST'])
def move_user():
    data = request.json or {}
    user_id = data.get("user_id")
    target_cid = data.get("channel_id")
    
    if user_id and target_cid:
        res = query_ts3(lambda conn: conn.clientmove(clid=user_id, cid=target_cid))
        if res:
            return jsonify({"success": True}), 200

    return jsonify({"error": "Erreur lors du deplacement"}), 400

def stop_server(signum, frame):
    print("Fermeture du serveur backend (SIGTERM)")
    sys.exit(0)

signal.signal(signal.SIGTERM, stop_server)

if __name__ == "__main__":
    print(f"Backend Python connecte au serveur TeamSpeak ServerQuery ({TS3_HOST}:{TS3_PORT})")
    app.run(host="0.0.0.0", port=PORT)
