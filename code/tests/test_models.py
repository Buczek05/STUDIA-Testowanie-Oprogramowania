"""Testy jednostkowe modeli Pydantic (epc/models.py)."""

import pytest
from pydantic import ValidationError

from epc.models import (
    AddBearerRequest,
    AttachUERequest,
    BearerConfig,
    StartTrafficRequest,
    ThroughputStats,
    UEState,
)


class TestBearerConfig:
    def test_valid_bearer(self):
        b = BearerConfig(bearer_id=5, protocol="tcp", target_bps=1000)
        assert b.bearer_id == 5
        assert b.protocol == "tcp"
        assert b.active is False  # domyślnie nieaktywny

    @pytest.mark.parametrize("bid", [0, 10, -1, 100])
    def test_bearer_id_out_of_range(self, bid):
        with pytest.raises(ValidationError):
            BearerConfig(bearer_id=bid)

    @pytest.mark.parametrize("proto", ["http", "TCP", "icmp", ""])
    def test_invalid_protocol(self, proto):
        with pytest.raises(ValidationError):
            BearerConfig(bearer_id=1, protocol=proto)

    @pytest.mark.parametrize("proto", ["tcp", "udp"])
    def test_valid_protocols(self, proto):
        assert BearerConfig(bearer_id=1, protocol=proto).protocol == proto


class TestUEState:
    @pytest.mark.parametrize("uid", [0, 1, 50, 100])
    def test_valid_ue_id(self, uid):
        assert UEState(ue_id=uid).ue_id == uid

    @pytest.mark.parametrize("uid", [101, -1, -5])
    def test_ue_id_out_of_range(self, uid):
        with pytest.raises(ValidationError):
            UEState(ue_id=uid)

    def test_defaults_empty_collections(self):
        s = UEState(ue_id=1)
        assert s.bearers == {}
        assert s.stats == {}

    def test_none_collections_normalized(self):
        # walidator 'before' zamienia None na pusty słownik
        s = UEState(ue_id=1, bearers=None, stats=None)
        assert s.bearers == {}
        assert s.stats == {}

    def test_round_trip_json(self):
        s = UEState(ue_id=7)
        s.bearers[9] = BearerConfig(bearer_id=9)
        restored = UEState.model_validate_json(s.model_dump_json())
        assert restored.ue_id == 7
        assert 9 in restored.bearers


class TestStartTrafficRequest:
    def test_exactly_one_mbps(self):
        req = StartTrafficRequest(protocol="tcp", Mbps=10)
        assert req.target_bps() == 10_000_000

    def test_exactly_one_kbps(self):
        req = StartTrafficRequest(protocol="udp", kbps=500)
        assert req.target_bps() == 500_000

    def test_exactly_one_bps(self):
        req = StartTrafficRequest(protocol="tcp", bps=12345)
        assert req.target_bps() == 12345

    def test_zero_throughput_values_provided(self):
        # 0 to wartość != None, więc liczy się jako "podane"
        req = StartTrafficRequest(protocol="tcp", bps=0)
        assert req.target_bps() == 0

    def test_no_throughput_raises(self):
        with pytest.raises(ValidationError):
            StartTrafficRequest(protocol="tcp")

    def test_multiple_throughput_raises(self):
        with pytest.raises(ValidationError):
            StartTrafficRequest(protocol="tcp", Mbps=1, kbps=1)

    def test_all_three_raises(self):
        with pytest.raises(ValidationError):
            StartTrafficRequest(protocol="tcp", Mbps=1, kbps=1, bps=1)

    def test_invalid_protocol(self):
        with pytest.raises(ValidationError):
            StartTrafficRequest(protocol="ftp", Mbps=1)

    def test_mbps_truncated_to_int(self):
        # 1.5 Mbps -> 1_500_000 bps (int)
        assert StartTrafficRequest(protocol="tcp", Mbps=1.5).target_bps() == 1_500_000


class TestRequestSchemas:
    @pytest.mark.parametrize("uid", [-1, 101])
    def test_attach_ue_range(self, uid):
        with pytest.raises(ValidationError):
            AttachUERequest(ue_id=uid)

    @pytest.mark.parametrize("bid", [0, 10])
    def test_add_bearer_range(self, bid):
        with pytest.raises(ValidationError):
            AddBearerRequest(bearer_id=bid)


class TestThroughputStats:
    def test_defaults(self):
        s = ThroughputStats(bearer_id=1, ue_id=1)
        assert s.bytes_tx == 0
        assert s.bytes_rx == 0
        assert s.start_ts is None
