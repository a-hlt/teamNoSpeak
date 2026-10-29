import { useState, useEffect } from 'react';

function App() {
  const [stats, setStats] = useState(null);
  const [channels, setChannels] = useState([]);
  const [users, setUsers] = useState([]);
  const [logs, setLogs] = useState([]);
  const [activeTab, setActiveTab] = useState('users');

  const [selectedUser, setSelectedUser] = useState(null);
  const [msgInput, setMsgInput] = useState('');
  const [pokeInput, setPokeInput] = useState('');
  const [targetChannelId, setTargetChannelId] = useState('');

  const refreshData = () => {
    fetch('/api/stats')
      .then((res) => res.json())
      .then((d) => setStats(d))
      .catch((err) => console.error(err));

    fetch('/api/channels')
      .then((res) => res.json())
      .then((d) => setChannels(d))
      .catch((err) => console.error(err));

    fetch('/api/users')
      .then((res) => res.json())
      .then((d) => setUsers(d))
      .catch((err) => console.error(err));

    fetch('/api/logs')
      .then((res) => res.json())
      .then((d) => setLogs(d))
      .catch((err) => console.error(err));
  };

  useEffect(() => {
    refreshData();
    const interval = setInterval(refreshData, 3000);
    return () => clearInterval(interval);
  }, []);

  const handleKick = (user) => {
    fetch('/api/mod/kick', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_id: user.id, nickname: user.nickname }),
    }).then(() => refreshData());
  };

  const handlePoke = (user) => {
    const text = pokeInput || 'Avertissement du modérateur';
    fetch('/api/mod/poke', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_id: user.id, message: text }),
    }).then(() => {
      setPokeInput('');
      refreshData();
    });
  };

  const handleSendMessage = (user) => {
    if (!msgInput) return;
    fetch('/api/mod/message', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_id: user.id, message: msgInput }),
    }).then(() => {
      setMsgInput('');
      alert(`Message privé envoyé à ${user.nickname}`);
      refreshData();
    });
  };

  const handleMove = (user) => {
    if (!targetChannelId) return;
    fetch('/api/mod/move', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_id: user.id, channel_id: parseInt(targetChannelId) }),
    }).then(() => refreshData());
  };

  return (
    <div className="dashboard-container">
      {/* Header */}
      <header className="header">
        <div className="header-title">
          <div>
            <h1>🎧 TeamSpeak 3 Moderator Hub</h1>
            <p className="header-subtitle">Gestionnaire de Serveur Vocal et Modération</p>
          </div>
        </div>
        {stats && (
          <div className="status-badge">
            <div className="status-dot"></div>
            <span>{stats.status} ({stats.slots_used} / {stats.max_slots} Joueurs)</span>
          </div>
        )}
      </header>

      {/* Metrics Row */}
      {stats && (
        <div className="metrics-grid">
          <div className="metric-card">
            <div className="metric-label">Nom du Serveur</div>
            <div className="metric-value">{stats.server_name}</div>
          </div>
          <div className="metric-card">
            <div className="metric-label">Salons Actifs</div>
            <div className="metric-value">{stats.channels_count}</div>
          </div>
          <div className="metric-card">
            <div className="metric-label">Uptime Serveur</div>
            <div className="metric-value">{stats.uptime}</div>
          </div>
        </div>
      )}

      {/* Tab Navigation */}
      <nav className="tabs-nav">
        <button
          className={`tab-btn ${activeTab === 'users' ? 'active' : ''}`}
          onClick={() => setActiveTab('users')}
        >
          👥 Joueurs en Ligne ({users.length})
        </button>
        <button
          className={`tab-btn ${activeTab === 'channels' ? 'active' : ''}`}
          onClick={() => setActiveTab('channels')}
        >
          🔊 Salons Vocaux ({channels.length})
        </button>
        <button
          className={`tab-btn ${activeTab === 'logs' ? 'active' : ''}`}
          onClick={() => setActiveTab('logs')}
        >
          📜 Logs & Evénements ({logs.length})
        </button>
      </nav>

      {/* Content Container */}
      <main className="content-card">
        {/* USERS TAB */}
        {activeTab === 'users' && (
          <div>
            <h3 style={{ margin: '0 0 16px 0', fontSize: '1.2rem', color: '#38bdf8' }}>
              Joueurs Connectés (Actions de Modération)
            </h3>

            {users.length > 0 ? (
              <table className="custom-table">
                <thead>
                  <tr>
                    <th>Joueur</th>
                    <th>Salon Vocal</th>
                    <th>État Micro</th>
                    <th>Modération</th>
                  </tr>
                </thead>
                <tbody>
                  {users.map((u) => {
                    const ch = channels.find((c) => c.id === u.channel_id);
                    const isSelected = selectedUser?.id === u.id;
                    return (
                      <tr key={u.id}>
                        <td style={{ fontWeight: '600' }}>👤 {u.nickname} <span style={{ color: '#64748b', fontSize: '0.8rem' }}>(ID #{u.id})</span></td>
                        <td style={{ color: '#fde047' }}>🔊 {ch ? ch.name : `Salon #${u.channel_id}`}</td>
                        <td>
                          {u.muted ? (
                            <span style={{ color: '#ef4444', fontWeight: '500' }}>🔇 Mute</span>
                          ) : (
                            <span style={{ color: '#10b981', fontWeight: '500' }}>🎙️ Actif</span>
                          )}
                        </td>
                        <td>
                          <button
                            className="btn btn-primary"
                            onClick={() => setSelectedUser(isSelected ? null : u)}
                          >
                            {isSelected ? 'Fermer Panneau' : '⚡ Gérer Joueur'}
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            ) : (
              <div style={{ padding: '40px', textAlign: 'center', color: '#94a3b8', background: 'rgba(15, 23, 42, 0.5)', borderRadius: '12px' }}>
                Aucun joueur humain connecté sur le serveur TeamSpeak 3 pour le moment.
              </div>
            )}

            {/* MODERATION DRAWER */}
            {selectedUser && (
              <div className="mod-drawer">
                <h4 style={{ margin: '0 0 12px 0', color: '#38bdf8' }}>
                  🛠️ Modération avancée sur : <span style={{ color: '#f8fafc' }}>{selectedUser.nickname}</span>
                </h4>

                <div className="mod-grid">
                  <div className="mod-control-group">
                    <label className="mod-label">✉️ Message Privé (Chat Client)</label>
                    <input
                      className="form-input"
                      type="text"
                      placeholder="Tapez votre message..."
                      value={msgInput}
                      onChange={(e) => setMsgInput(e.target.value)}
                    />
                    <button className="btn btn-primary" onClick={() => handleSendMessage(selectedUser)}>
                      Envoyer Message
                    </button>
                  </div>

                  <div className="mod-control-group">
                    <label className="mod-label">🔔 Notification Popup (Poke)</label>
                    <input
                      className="form-input"
                      type="text"
                      placeholder="Raison de l'avertissement..."
                      value={pokeInput}
                      onChange={(e) => setPokeInput(e.target.value)}
                    />
                    <button className="btn btn-warning" onClick={() => handlePoke(selectedUser)}>
                      Poper Notification
                    </button>
                  </div>

                  <div className="mod-control-group">
                    <label className="mod-label">🔁 Déplacer dans un autre Salon</label>
                    <select
                      className="form-input"
                      value={targetChannelId}
                      onChange={(e) => setTargetChannelId(e.target.value)}
                    >
                      <option value="">Sélectionner un Salon...</option>
                      {channels.map((c) => (
                        <option key={c.id} value={c.id}>{c.name}</option>
                      ))}
                    </select>
                    <button className="btn btn-primary" onClick={() => handleMove(selectedUser)}>
                      Déplacer le Joueur
                    </button>
                  </div>

                  <div className="mod-control-group">
                    <label className="mod-label">❌ Expulser du Serveur</label>
                    <button className="btn btn-danger" style={{ marginTop: 'auto' }} onClick={() => handleKick(selectedUser)}>
                      Expulser (Kick)
                    </button>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}

        {/* CHANNELS TAB */}
        {activeTab === 'channels' && (
          <div>
            <h3 style={{ margin: '0 0 16px 0', fontSize: '1.2rem', color: '#38bdf8' }}>
              Salons Vocaux TeamSpeak 3
            </h3>
            <div className="channels-grid">
              {channels.map((c) => (
                <div key={c.id} className="channel-card">
                  <div className="channel-name">🔊 {c.name}</div>
                  <div className="channel-count">{c.users_count} Membres</div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* LOGS TAB */}
        {activeTab === 'logs' && (
          <div>
            <h3 style={{ margin: '0 0 16px 0', fontSize: '1.2rem', color: '#38bdf8' }}>
              Console de Logs Système & Modération
            </h3>
            <div className="console-box">
              {logs.map((l) => (
                <div key={l.id} className="log-row">
                  <span className="log-time">[{l.time}]</span>
                  <span className="log-tag">[SYSTEM]</span>
                  <span className="log-msg">{l.message}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

export default App;
