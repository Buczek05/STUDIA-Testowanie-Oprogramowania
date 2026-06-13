"""Testy jednostkowe menedżera ruchu (epc/traffic.py).

Skupiamy się na logice zarządzania zadaniami (rejestr ``tasks``), a nie na
faktycznym, czasozależnym naliczaniu bajtów w pętli w tle.
"""

import pytest

from epc.models import BearerConfig
from epc.traffic import TrafficGeneratorManager, get_traffic_manager


@pytest.fixture
def manager(repo):
    repo.attach_ue(1)
    return TrafficGeneratorManager(repo)


def _configured_bearer(bearer_id=9):
    return BearerConfig(bearer_id=bearer_id, protocol="tcp", target_bps=8000, active=True)


class TestStartStop:
    def test_start_registers_task(self, manager):
        manager.start(1, _configured_bearer())
        assert manager.is_running(1, 9) is True

    def test_start_twice_raises(self, manager):
        manager.start(1, _configured_bearer())
        with pytest.raises(ValueError, match="already running"):
            manager.start(1, _configured_bearer())

    def test_start_unconfigured_bearer_no_bps(self, manager):
        bearer = BearerConfig(bearer_id=9, protocol="tcp")  # brak target_bps
        with pytest.raises(ValueError, match="not configured"):
            manager.start(1, bearer)

    def test_start_unconfigured_bearer_no_protocol(self, manager):
        bearer = BearerConfig(bearer_id=9, target_bps=8000)  # brak protokołu
        with pytest.raises(ValueError, match="not configured"):
            manager.start(1, bearer)

    def test_stop_removes_task(self, manager):
        manager.start(1, _configured_bearer())
        manager.stop(1, 9)
        assert manager.is_running(1, 9) is False

    def test_stop_unknown_is_noop(self, manager):
        manager.stop(1, 5)  # brak wyjątku
        assert manager.is_running(1, 5) is False

    def test_stop_all(self, manager):
        manager.start(1, _configured_bearer(9))
        repo = manager.repo
        repo.add_bearer(1, 3)
        manager.start(1, _configured_bearer(3))
        manager.stop_all()
        assert manager.is_running(1, 9) is False
        assert manager.is_running(1, 3) is False
        assert manager.tasks == {}

    def test_is_running_false_initially(self, manager):
        assert manager.is_running(1, 9) is False


class TestSingleton:
    def test_get_traffic_manager_returns_singleton(self, repo):
        m1 = get_traffic_manager(repo)
        m2 = get_traffic_manager(repo)
        assert m1 is m2
