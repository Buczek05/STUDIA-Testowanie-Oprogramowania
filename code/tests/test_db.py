"""Testy jednostkowe warstwy repozytorium (epc/db.py)."""

import pytest

from epc.models import BearerConfig, ThroughputStats


class TestAttachDetach:
    def test_attach_creates_ue_with_default_bearer(self, repo):
        repo.attach_ue(1)
        state = repo.get_ue(1)
        assert state.ue_id == 1
        assert 9 in state.bearers  # domyślny bearer 9 tworzony automatycznie

    def test_attach_duplicate_raises(self, repo):
        repo.attach_ue(1)
        with pytest.raises(ValueError, match="already attached"):
            repo.attach_ue(1)

    def test_ue_exists(self, repo):
        assert repo.ue_exists(1) is False
        repo.attach_ue(1)
        assert repo.ue_exists(1) is True

    def test_detach_removes_ue(self, repo):
        repo.attach_ue(1)
        repo.detach_ue(1)
        assert repo.ue_exists(1) is False

    def test_detach_unknown_raises(self, repo):
        with pytest.raises(ValueError, match="UE not found"):
            repo.detach_ue(99)

    def test_get_unknown_ue_raises(self, repo):
        with pytest.raises(ValueError, match="UE not found"):
            repo.get_ue(42)

    def test_list_ues_sorted(self, repo):
        for uid in (5, 2, 8):
            repo.attach_ue(uid)
        assert list(repo.list_ues()) == [2, 5, 8]

    def test_list_ues_empty(self, repo):
        assert list(repo.list_ues()) == []


class TestBearers:
    def test_add_bearer(self, repo):
        repo.attach_ue(1)
        repo.add_bearer(1, 3)
        assert 3 in repo.get_ue(1).bearers

    def test_add_duplicate_bearer_raises(self, repo):
        repo.attach_ue(1)
        repo.add_bearer(1, 3)
        with pytest.raises(ValueError, match="already exists"):
            repo.add_bearer(1, 3)

    def test_add_bearer_to_unknown_ue_raises(self, repo):
        with pytest.raises(ValueError, match="UE not found"):
            repo.add_bearer(1, 3)

    def test_delete_bearer(self, repo):
        repo.attach_ue(1)
        repo.add_bearer(1, 3)
        repo.delete_bearer(1, 3)
        assert 3 not in repo.get_ue(1).bearers

    def test_delete_default_bearer_9_forbidden(self, repo):
        repo.attach_ue(1)
        with pytest.raises(ValueError, match="Cannot remove default bearer"):
            repo.delete_bearer(1, 9)

    def test_delete_missing_bearer_raises(self, repo):
        repo.attach_ue(1)
        with pytest.raises(ValueError, match="Bearer not found"):
            repo.delete_bearer(1, 5)

    def test_delete_bearer_also_removes_stats(self, repo):
        repo.attach_ue(1)
        repo.add_bearer(1, 3)
        repo.update_stats(1, ThroughputStats(bearer_id=3, ue_id=1, bytes_tx=100))
        repo.delete_bearer(1, 3)
        assert 3 not in repo.get_ue(1).stats

    def test_update_bearer(self, repo):
        repo.attach_ue(1)
        bearer = BearerConfig(bearer_id=9, protocol="tcp", target_bps=8000, active=True)
        repo.update_bearer(1, bearer)
        stored = repo.get_ue(1).bearers[9]
        assert stored.protocol == "tcp"
        assert stored.active is True


class TestStatsAndReset:
    def test_update_stats_persisted(self, repo):
        repo.attach_ue(1)
        repo.update_stats(1, ThroughputStats(bearer_id=9, ue_id=1, bytes_tx=42, bytes_rx=7))
        stats = repo.get_ue(1).stats[9]
        assert stats.bytes_tx == 42
        assert stats.bytes_rx == 7

    def test_reset_all_clears_everything(self, repo):
        repo.attach_ue(1)
        repo.attach_ue(2)
        repo.reset_all()
        assert list(repo.list_ues()) == []

    def test_reset_all_on_empty(self, repo):
        repo.reset_all()  # nie powinno rzucać wyjątku
        assert list(repo.list_ues()) == []


class TestPersistence:
    def test_data_survives_new_repo_instance(self, repo):
        # Dane zapisane w pliku SQLite są widoczne dla nowej instancji repozytorium.
        from epc.db import EPCRepository

        repo.attach_ue(1)
        repo.add_bearer(1, 2)
        repo2 = EPCRepository(db_path=repo._path)
        assert repo2.ue_exists(1)
        assert 2 in repo2.get_ue(1).bearers
