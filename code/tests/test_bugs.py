"""Testy jednostkowe oczekiwanego zachowania dla znanych błędów.

Odpowiednik jednostkowy dla ``epc-simulator-tests/bugReports.robot``, ale
w odwrotnej konwencji:

    * test asertuje POPRAWNE (oczekiwane) zachowanie,
    * test FAILUJE   => błąd nadal ISTNIEJE (kod do naprawienia),
    * test PRZECHODZI => błąd został NAPRAWIONY.

To klasyczne podejście „red" — dopóki aplikacja zawiera błąd, test świeci na
czerwono i dokumentuje, jak system powinien się zachowywać.

W przeciwieństwie do wersji Robot testy są w pełni deterministyczne: nie używają
``sleep`` ani rzeczywistej pętli generatora ruchu w tle — błędy zależne od czasu
(BUG-3, BUG-10) sprawdzamy na poziomie ich przyczyny źródłowej.
"""

import pytest
from pydantic import ValidationError


class TestBug1StopTrafficWithoutSession:
    """BUG-1: DELETE /traffic na bearerze bez aktywnego transferu powinien
    zwrócić błąd 4xx — nie można zatrzymać sesji, która nigdy nie ruszyła."""

    def test_stop_without_active_traffic_should_fail(self, attached_ue):
        resp = attached_ue.delete("/ues/1/bearers/9/traffic")
        assert resp.status_code >= 400, (
            "stop bez aktywnej sesji powinien zwrócić 4xx, "
            f"a zwrócił {resp.status_code}"
        )


class TestBug2StatsWithoutHistory:
    """BUG-2: GET /traffic dla bearera bez historii transferu powinien zwrócić
    404 — brak danych transferu dla tego bearera."""

    def test_get_stats_no_history_should_return_404(self, attached_ue):
        resp = attached_ue.get("/ues/1/bearers/9/traffic")
        assert resp.status_code == 404, (
            f"oczekiwano 404 dla bearera bez historii, otrzymano {resp.status_code}"
        )


class TestBug3StaleStatsAfterStop:
    """BUG-3: po zatrzymaniu transferu protocol i target_bps powinny zostać
    zresetowane do null (a tx_bps/rx_bps do 0)."""

    def test_protocol_and_bps_cleared_after_stop(self, attached_ue):
        attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 10}
        )
        attached_ue.delete("/ues/1/bearers/9/traffic")
        body = attached_ue.get("/ues/1/bearers/9/traffic").json()
        assert body["protocol"] is None, "protocol powinien być null po stopie"
        assert body["target_bps"] is None, "target_bps powinien być null po stopie"


class TestBug4BooleanUeId:
    """BUG-4: ue_id=true nie powinno być akceptowane — wartości boolowskie nie
    są poprawnymi identyfikatorami UE."""

    def test_boolean_true_rejected_by_model(self):
        with pytest.raises(ValidationError):
            from epc.models import AttachUERequest

            AttachUERequest(ue_id=True)

    def test_boolean_true_rejected_by_api(self, client):
        resp = client.post("/ues", json={"ue_id": True})
        assert resp.status_code == 422, (
            f"bool jako ue_id powinien dać 422, otrzymano {resp.status_code}"
        )


class TestBug5BearerCountCountsTraffic:
    """BUG-5: bearer_count w /ues/stats powinien zliczać skonfigurowane bearery,
    analogicznie do tego jak ue_count zlicza wszystkie UE."""

    def test_bearer_count_reflects_configured_bearers(self, attached_ue):
        # UE ma 2 skonfigurowane bearery (domyślny 9 + dodany 1), zero transferu.
        attached_ue.post("/ues/1/bearers", json={"bearer_id": 1})
        body = attached_ue.get("/ues/stats").json()
        assert body["bearer_count"] == 2, (
            f"oczekiwano bearer_count=2, otrzymano {body['bearer_count']}"
        )


class TestBug8DeleteBearerWithActiveTraffic:
    """BUG-8: usunięcie bearera z aktywnym trafficiem powinno zwrócić błąd
    (wymóg uprzedniego stopu)."""

    def test_delete_bearer_with_traffic_should_fail(self, attached_ue):
        attached_ue.post("/ues/1/bearers", json={"bearer_id": 1})
        attached_ue.post(
            "/ues/1/bearers/1/traffic", json={"protocol": "tcp", "Mbps": 10}
        )
        resp = attached_ue.delete("/ues/1/bearers/1")
        assert resp.status_code >= 400, (
            "usunięcie bearera z aktywnym trafficiem powinno zwrócić 4xx, "
            f"a zwróciło {resp.status_code}"
        )


class TestBug10DurationAccumulates:
    """BUG-10: restart transferu na tym samym bearerze powinien zresetować
    start_ts, aby duration mierzyło wyłącznie bieżącą sesję.

    Sprawdzamy przyczynę źródłową deterministycznie: po restarcie start_ts
    powinien być nową wartością, różną od poprzedniej sesji."""

    def test_start_ts_reset_on_restart(self, attached_ue, repo):
        attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 10}
        )
        first_start_ts = repo.get_ue(1).stats[9].start_ts
        assert first_start_ts is not None
        attached_ue.delete("/ues/1/bearers/9/traffic")

        attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 10}
        )
        second_start_ts = repo.get_ue(1).stats[9].start_ts
        assert second_start_ts != first_start_ts, (
            "start_ts powinien zostać zresetowany przy restarcie sesji"
        )


class TestBug13NoBandwidthLimit:
    """BUG-13: limit 100 Mbps powinien być egzekwowany — każda wartość Mbps > 100
    powinna być odrzucona."""

    def test_model_rejects_over_limit(self):
        from epc.models import StartTrafficRequest

        with pytest.raises(ValidationError):
            StartTrafficRequest(protocol="tcp", Mbps=10000)

    def test_api_rejects_over_limit(self, attached_ue):
        resp = attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 10000}
        )
        assert resp.status_code >= 400, (
            f"Mbps > 100 powinno dać 4xx, otrzymano {resp.status_code}"
        )


class TestBug16NegativeMbps:
    """T-016: start transferu z ujemną wartością Mbps powinien być odrzucony —
    przepustowość ujemna jest spoza zakresu. Zero pozostaje obsługiwane osobno
    (odrzucane przez menedżera ruchu z komunikatem "not configured")."""

    def test_model_rejects_negative_mbps(self):
        from epc.models import StartTrafficRequest

        with pytest.raises(ValidationError):
            StartTrafficRequest(protocol="tcp", Mbps=-1)

    def test_api_rejects_negative_mbps(self, attached_ue):
        resp = attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": -1}
        )
        assert resp.status_code >= 400, (
            f"ujemne Mbps powinno dać 4xx, otrzymano {resp.status_code}"
        )

    def test_api_still_accepts_zero_via_not_configured(self, attached_ue):
        # 0 nie jest błędem walidacji modelu — odrzuca je menedżer ruchu.
        resp = attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 0}
        )
        assert resp.status_code == 400
        assert "not configured" in resp.text


class TestBug27AggregatedStatsDefaultUnit:
    """T-027: /ues/stats powinno przyjmować parametr unit (domyślnie kbps) i
    raportować wartości pod kluczami total_tx_<unit> / total_rx_<unit>."""

    def test_explicit_kbps_unit(self, attached_ue):
        body = attached_ue.get("/ues/stats", params={"unit": "kbps"}).json()
        assert "total_tx_kbps" in body
        assert "total_rx_kbps" in body

    def test_default_unit_is_kbps(self, attached_ue):
        body = attached_ue.get("/ues/stats").json()
        assert "total_tx_kbps" in body
        assert "total_rx_kbps" in body


class TestBug32IdempotentStop:
    """T-032 (regresja po fixie BUG-1): dwukrotny stop na bearerze, który miał
    transfer, powinien być idempotentny — drugi stop też zwraca 200.

    Jednocześnie BUG-1 musi nadal działać: stop bearera, który nigdy nie miał
    transferu, pozostaje błędem (sprawdzane w TestBug1StopTrafficWithoutSession)."""

    def test_second_stop_is_idempotent(self, attached_ue):
        attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 10}
        )
        first = attached_ue.delete("/ues/1/bearers/9/traffic")
        assert first.status_code == 200
        second = attached_ue.delete("/ues/1/bearers/9/traffic")
        assert second.status_code == 200, (
            f"drugi stop powinien być idempotentny (200), otrzymano {second.status_code}"
        )
        assert second.json()["status"] == "traffic_stopped"


class TestBug35StopAllBearers:
    """T-035: DELETE /ues/{ue_id}/traffic (bez bearer ID) powinno zakończyć
    transfer na wszystkich bearerach UE i zwrócić sukces (200)."""

    def test_stop_all_returns_success(self, attached_ue):
        attached_ue.post(
            "/ues/1/bearers/9/traffic", json={"protocol": "tcp", "Mbps": 10}
        )
        resp = attached_ue.delete("/ues/1/traffic")
        assert resp.status_code == 200, (
            f"stop-all powinno zwrócić 200, otrzymano {resp.status_code}"
        )


class TestBug59AttachUeIdZero:
    """T-059: wg specyfikacji zakres UE to 0-100, więc attach UE o ID 0 powinien
    się powieść."""

    def test_model_accepts_ue_id_zero(self):
        from epc.models import AttachUERequest

        assert AttachUERequest(ue_id=0).ue_id == 0

    def test_api_accepts_ue_id_zero(self, client):
        resp = client.post("/ues", json={"ue_id": 0})
        assert resp.status_code == 200, (
            f"UE ID 0 powinno być zaakceptowane wg spec, otrzymano {resp.status_code}"
        )
        assert resp.json() == {"status": "attached", "ue_id": 0}
