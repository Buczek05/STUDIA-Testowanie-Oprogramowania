"""Testy kontraktowe warstwy HTTP (epc/api.py + main.py) przez TestClient."""

import pytest


class TestRoot:
    def test_root_health(self, client):
        resp = client.get("/")
        assert resp.status_code == 200
        assert resp.json() == {"message": "EPC Simulator running"}


class TestUELifecycle:
    def test_list_empty(self, client):
        resp = client.get("/ues")
        assert resp.status_code == 200
        assert resp.json() == {"ues": []}

    def test_attach_ue(self, client):
        resp = client.post("/ues", json={"ue_id": 1})
        assert resp.status_code == 200
        assert resp.json() == {"status": "attached", "ue_id": 1}

    def test_attach_then_list(self, client):
        client.post("/ues", json={"ue_id": 1})
        client.post("/ues", json={"ue_id": 2})
        assert client.get("/ues").json() == {"ues": [1, 2]}

    def test_attach_creates_default_bearer(self, attached_ue):
        state = attached_ue.get("/ues/1").json()
        assert "9" in state["bearers"]  # klucze JSON są stringami

    def test_attach_duplicate_returns_400(self, attached_ue):
        resp = attached_ue.post("/ues", json={"ue_id": 1})
        assert resp.status_code == 400
        assert resp.json()["detail"] == "UE already attached"

    @pytest.mark.parametrize("uid", [0, 101, -1])
    def test_attach_out_of_range_returns_422(self, client, uid):
        resp = client.post("/ues", json={"ue_id": uid})
        assert resp.status_code == 422

    def test_get_unknown_ue_returns_400(self, client):
        resp = client.get("/ues/50")
        assert resp.status_code == 400

    def test_detach(self, attached_ue):
        resp = attached_ue.delete("/ues/1")
        assert resp.status_code == 200
        assert resp.json() == {"status": "detached", "ue_id": 1}
        assert attached_ue.get("/ues").json() == {"ues": []}

    def test_detach_unknown_returns_400(self, client):
        resp = client.delete("/ues/77")
        assert resp.status_code == 400


class TestBearers:
    def test_add_bearer(self, attached_ue):
        resp = attached_ue.post("/ues/1/bearers", json={"bearer_id": 3})
        assert resp.status_code == 200
        assert resp.json() == {"status": "bearer_added", "ue_id": 1, "bearer_id": 3}

    def test_add_duplicate_bearer_returns_400(self, attached_ue):
        attached_ue.post("/ues/1/bearers", json={"bearer_id": 3})
        resp = attached_ue.post("/ues/1/bearers", json={"bearer_id": 3})
        assert resp.status_code == 400

    def test_add_bearer_out_of_range_returns_422(self, attached_ue):
        resp = attached_ue.post("/ues/1/bearers", json={"bearer_id": 99})
        assert resp.status_code == 422

    def test_add_bearer_to_unknown_ue_returns_400(self, client):
        resp = client.post("/ues/5/bearers", json={"bearer_id": 3})
        assert resp.status_code == 400

    def test_delete_bearer(self, attached_ue):
        attached_ue.post("/ues/1/bearers", json={"bearer_id": 3})
        resp = attached_ue.delete("/ues/1/bearers/3")
        assert resp.status_code == 200
        assert resp.json() == {"status": "bearer_deleted", "ue_id": 1, "bearer_id": 3}

    def test_delete_default_bearer_9_returns_400(self, attached_ue):
        resp = attached_ue.delete("/ues/1/bearers/9")
        assert resp.status_code == 400
        assert resp.json()["detail"] == "Cannot remove default bearer"

    def test_delete_missing_bearer_returns_400(self, attached_ue):
        resp = attached_ue.delete("/ues/1/bearers/5")
        assert resp.status_code == 400
        assert resp.json()["detail"] == "Bearer not found"


class TestTraffic:
    def test_start_traffic(self, attached_ue):
        resp = attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 1}
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["status"] == "traffic_started"
        assert body["target_bps"] == 1_000_000

    def test_start_traffic_invalid_payload_returns_422(self, attached_ue):
        # brak jednostki przepustowości -> walidacja modelu (422)
        resp = attached_ue.post("/ues/1/bearers/9/traffic", json={"protocol": "tcp"})
        assert resp.status_code == 422

    def test_start_traffic_multiple_units_returns_422(self, attached_ue):
        resp = attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 1, "kbps": 1}
        )
        assert resp.status_code == 422

    def test_start_traffic_unknown_bearer_returns_400(self, attached_ue):
        resp = attached_ue.post(
            "/ues/1/bearers/5/traffic", json={"protocol": "tcp", "Mbps": 1}
        )
        assert resp.status_code == 400

    def test_start_traffic_twice_returns_400(self, attached_ue):
        attached_ue.post("/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 1})
        resp = attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 1}
        )
        assert resp.status_code == 400
        assert resp.json()["detail"] == "Traffic already running"

    def test_stop_traffic(self, attached_ue):
        attached_ue.post("/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 1})
        resp = attached_ue.delete("/ues/1/bearers/9/traffic")
        assert resp.status_code == 200
        assert resp.json() == {
            "status": "traffic_stopped",
            "ue_id": 1,
            "bearer_id": 9,
        }

    def test_traffic_stats_shape_without_traffic(self, attached_ue):
        resp = attached_ue.get("/ues/1/bearers/9/traffic")
        assert resp.status_code == 404

    def test_traffic_stats_unknown_ue_returns_400(self, client):
        resp = client.get("/ues/9/bearers/9/traffic")
        assert resp.status_code == 400


class TestAggregatedStats:
    def test_stats_all_empty(self, client):
        resp = client.get("/ues/stats")
        assert resp.status_code == 200
        body = resp.json()
        assert body["scope"] == "all"
        assert body["ue_count"] == 0
        assert body["bearer_count"] == 0

    def test_stats_route_specificity(self, attached_ue):
        # '/ues/stats' musi być rozpoznane jako agregacja, a nie jako UE o id 'stats'.
        resp = attached_ue.get("/ues/stats")
        assert resp.status_code == 200
        assert resp.json()["scope"] == "all"

    def test_stats_filter_by_ue(self, attached_ue):
        resp = attached_ue.get("/ues/stats", params={"ue_id": 1})
        assert resp.status_code == 200
        assert resp.json()["scope"] == "ue:1"

    def test_stats_filter_unknown_ue_returns_400(self, client):
        resp = client.get("/ues/stats", params={"ue_id": 50})
        assert resp.status_code == 400

    def test_stats_with_details(self, attached_ue):
        resp = attached_ue.get(
            "/ues/stats", params={"ue_id": 1, "include_details": True}
        )
        assert resp.status_code == 200
        assert resp.json()["details"] is not None


class TestReset:
    def test_reset_clears_state(self, attached_ue):
        resp = attached_ue.post("/reset")
        assert resp.status_code == 200
        assert resp.json() == {"status": "reset"}
        assert attached_ue.get("/ues").json() == {"ues": []}


class TestStateTransitions:
    def test_full_lifecycle(self, client):
        # attach -> add bearer -> start -> read -> stop -> detach
        assert client.post("/ues", json={"ue_id": 2}).status_code == 200
        assert client.post("/ues/2/bearers", json={"bearer_id": 4}).status_code == 200
        assert client.post(
            "/ues/2/bearers/4/traffic", json={"protocol": "udp", "kbps": 100}
        ).status_code == 200
        assert client.get("/ues/2/bearers/4/traffic").status_code == 200
        assert client.delete("/ues/2/bearers/4/traffic").status_code == 200
        assert client.delete("/ues/2").status_code == 200
        assert client.get("/ues").json() == {"ues": []}
