import time

import pytest

pytestmark = pytest.mark.stress

RESET_BURST_COUNT = 50
ATTACH_BURST_COUNT = 100

PAYLOAD_10MB = 10_000_000
PAYLOAD_100MB = 100_000_000


class TestNoRateLimiting:
    def test_reset_endpoint_has_no_rate_limiting(self, client):
        start = time.perf_counter()
        codes = [client.post("/reset").status_code for _ in range(RESET_BURST_COUNT)]
        elapsed = time.perf_counter() - start

        rps = RESET_BURST_COUNT / elapsed if elapsed else float("inf")
        print(
            f"\nST-001: {RESET_BURST_COUNT} x POST /reset w {elapsed:.2f}s "
            f"-> {rps:.0f} req/s"
        )

        non_200 = [c for c in codes if c != 200]
        assert not non_200, (
            f"{len(non_200)}/{RESET_BURST_COUNT} żądań zwróciło kod != 200 "
            "— wykryto rate limiting (oczekiwano jego braku)"
        )


class TestNoRequestSizeLimit:
    @pytest.mark.parametrize(
        "size",
        [
            pytest.param(PAYLOAD_10MB, id="10MB"),
            pytest.param(PAYLOAD_100MB, id="100MB"),
        ],
    )
    def test_attach_accepts_oversized_payload(self, client, size):
        body = {"ue_id": 1, "padding": "A" * size}

        start = time.perf_counter()
        resp = client.post("/ues", json=body)
        elapsed = time.perf_counter() - start
        print(f"\nPayload {size} B -> HTTP {resp.status_code} w {elapsed:.2f}s")

        assert resp.status_code < 500, (
            f"serwer zwrócił {resp.status_code} (5xx) — możliwy crash/OOM "
            "zamiast kontrolowanej obsługi"
        )

    def test_no_413_ingress_guard_documents_oom_vector(self, client):
        body = {"ue_id": 1, "padding": "A" * PAYLOAD_100MB}
        resp = client.post("/ues", json=body)

        assert resp.status_code != 413, (
            "serwer odrzucił payload kodem 413 — limit rozmiaru istnieje "
            "(nieoczekiwane dla tej wersji symulatora)"
        )
        assert resp.status_code < 500, (
            f"serwer zwrócił {resp.status_code} (5xx) przy dużym payloadzie"
        )


class TestThroughput:
    def test_attach_100_ues_sequentially(self, client):
        start = time.perf_counter()
        for ue_id in range(1, ATTACH_BURST_COUNT + 1):
            resp = client.post("/ues", json={"ue_id": ue_id})
            assert resp.status_code == 200, (
                f"attach UE {ue_id} zwrócił {resp.status_code}"
            )
        elapsed = time.perf_counter() - start

        rps = ATTACH_BURST_COUNT / elapsed if elapsed else float("inf")
        print(
            f"\nST-004: {ATTACH_BURST_COUNT} attachow w {elapsed:.2f}s "
            f"-> {rps:.0f} req/s"
        )

        listed = client.get("/ues").json()["ues"]
        assert len(listed) == ATTACH_BURST_COUNT, (
            f"lista UE powinna zawierać {ATTACH_BURST_COUNT} elementów, "
            f"ma {len(listed)}"
        )

    def test_reset_wipes_all_state_under_full_load(self, client):
        for ue_id in range(1, ATTACH_BURST_COUNT + 1):
            client.post("/ues", json={"ue_id": ue_id})

        start = time.perf_counter()
        resp = client.post("/reset")
        elapsed = time.perf_counter() - start
        print(f"\nST-005: reset {ATTACH_BURST_COUNT} UE w {elapsed:.3f}s")

        assert resp.status_code == 200
        assert client.get("/ues").json()["ues"] == [], (
            "po resecie lista UE powinna być pusta"
        )
