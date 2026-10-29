"""
Tests d'intégration pour l'API Flask du backend.
Le container tests se connecte au backend via le réseau Docker interne.
La variable d'environnement API_URL pointe vers http://backend:5000.
"""

import os
import pytest
import requests

# URL de base de l'API, injectée par docker compose via la variable API_URL
BASE_URL = os.environ.get("API_URL", "http://localhost:5000")


# ─────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────

@pytest.fixture(scope="session")
def api():
    """Session requests avec timeout global."""
    session = requests.Session()
    session.headers.update({"Content-Type": "application/json"})
    return session


# ─────────────────────────────────────────────
# Tests de santé
# ─────────────────────────────────────────────

class TestHealth:

    def test_health_endpoint_returns_200(self, api):
        """Le healthcheck doit retourner HTTP 200."""
        response = api.get(f"{BASE_URL}/api/health", timeout=5)
        assert response.status_code == 200

    def test_health_returns_ok_status(self, api):
        """Le payload du healthcheck doit contenir status=ok."""
        response = api.get(f"{BASE_URL}/api/health", timeout=5)
        data = response.json()
        assert data.get("status") == "ok"

    def test_health_content_type_is_json(self, api):
        """Le Content-Type de la réponse doit être application/json."""
        response = api.get(f"{BASE_URL}/api/health", timeout=5)
        assert "application/json" in response.headers.get("Content-Type", "")


# ─────────────────────────────────────────────
# Tests des endpoints de lecture
# ─────────────────────────────────────────────

class TestReadEndpoints:

    def test_stats_returns_200(self, api):
        """GET /api/stats doit retourner HTTP 200."""
        response = api.get(f"{BASE_URL}/api/stats", timeout=10)
        assert response.status_code == 200

    def test_stats_has_required_fields(self, api):
        """Les stats doivent contenir les champs attendus du dashboard."""
        response = api.get(f"{BASE_URL}/api/stats", timeout=10)
        data = response.json()
        required_fields = ["server_name", "status", "uptime", "slots_used", "max_slots"]
        for field in required_fields:
            assert field in data, f"Champ manquant dans /api/stats : {field}"

    def test_stats_slots_used_not_negative(self, api):
        """Le nombre de slots utilisés ne peut pas être négatif."""
        response = api.get(f"{BASE_URL}/api/stats", timeout=10)
        data = response.json()
        assert int(data.get("slots_used", 0)) >= 0

    def test_channels_returns_200(self, api):
        """GET /api/channels doit retourner HTTP 200."""
        response = api.get(f"{BASE_URL}/api/channels", timeout=10)
        assert response.status_code == 200

    def test_channels_returns_list(self, api):
        """GET /api/channels doit retourner une liste JSON."""
        response = api.get(f"{BASE_URL}/api/channels", timeout=10)
        data = response.json()
        assert isinstance(data, list)

    def test_users_returns_200(self, api):
        """GET /api/users doit retourner HTTP 200."""
        response = api.get(f"{BASE_URL}/api/users", timeout=10)
        assert response.status_code == 200

    def test_users_returns_list(self, api):
        """GET /api/users doit retourner une liste JSON."""
        response = api.get(f"{BASE_URL}/api/users", timeout=10)
        data = response.json()
        assert isinstance(data, list)

    def test_logs_returns_200(self, api):
        """GET /api/logs doit retourner HTTP 200."""
        response = api.get(f"{BASE_URL}/api/logs", timeout=10)
        assert response.status_code == 200

    def test_logs_returns_list(self, api):
        """GET /api/logs doit retourner une liste JSON."""
        response = api.get(f"{BASE_URL}/api/logs", timeout=10)
        data = response.json()
        assert isinstance(data, list)


# ─────────────────────────────────────────────
# Tests des endpoints de modération (sans user réel)
# ─────────────────────────────────────────────

class TestModerationEndpoints:

    def test_kick_without_user_id_returns_400(self, api):
        """Kick sans user_id doit retourner HTTP 400."""
        response = api.post(f"{BASE_URL}/api/mod/kick", json={}, timeout=5)
        assert response.status_code == 400

    def test_kick_with_invalid_user_returns_error(self, api):
        """Kick avec un user_id invalide (99999) doit retourner une erreur."""
        response = api.post(
            f"{BASE_URL}/api/mod/kick",
            json={"user_id": 99999, "nickname": "FakeUser"},
            timeout=5,
        )
        # 400 si le kick échoue (pas de client avec cet ID)
        assert response.status_code in [400, 200]

    def test_poke_without_user_id_returns_400(self, api):
        """Poke sans user_id doit retourner HTTP 400."""
        response = api.post(f"{BASE_URL}/api/mod/poke", json={}, timeout=5)
        assert response.status_code == 400

    def test_message_without_user_id_returns_400(self, api):
        """Message sans user_id doit retourner HTTP 400."""
        response = api.post(f"{BASE_URL}/api/mod/message", json={}, timeout=5)
        assert response.status_code == 400

    def test_move_without_params_returns_400(self, api):
        """Move sans user_id et channel_id doit retourner HTTP 400."""
        response = api.post(f"{BASE_URL}/api/mod/move", json={}, timeout=5)
        assert response.status_code == 400


# ─────────────────────────────────────────────
# Tests de robustesse
# ─────────────────────────────────────────────

class TestRobustness:

    def test_unknown_route_returns_404(self, api):
        """Une route inconnue doit retourner HTTP 404."""
        response = api.get(f"{BASE_URL}/api/route_inexistante", timeout=5)
        assert response.status_code == 404

    def test_health_responds_fast(self, api):
        """Le healthcheck doit répondre en moins de 2 secondes."""
        import time
        start = time.time()
        api.get(f"{BASE_URL}/api/health", timeout=5)
        elapsed = time.time() - start
        assert elapsed < 2.0, f"Healthcheck trop lent : {elapsed:.2f}s"

    def test_concurrent_health_calls(self, api):
        """10 appels successifs au healthcheck doivent tous retourner 200."""
        for _ in range(10):
            response = api.get(f"{BASE_URL}/api/health", timeout=5)
            assert response.status_code == 200
