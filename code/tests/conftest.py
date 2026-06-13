"""Wspólne fixture'y testowe dla symulatora EPC.

Kluczowe problemy z izolacją, którymi się tu zajmujemy:

* ``epc.api._repo_singleton`` oraz ``epc.traffic.traffic_manager`` to globalne
  singletony. Bez resetu stan przeciekałby między testami.
* Repozytorium trzyma dane w pliku SQLite. Każdy test dostaje świeży plik
  w katalogu tymczasowym (``tmp_path``).
* Generator ruchu działa w tle (osobny wątek + pętla asyncio). Po każdym
  teście zatrzymujemy wszystkie zadania, żeby nie modyfikowały bazy po fakcie.
"""

import importlib

import pytest
from fastapi.testclient import TestClient

import epc.api as api_module
import epc.traffic as traffic_module
from epc.db import EPCRepository


@pytest.fixture
def repo(tmp_path):
    """Świeże repozytorium na dedykowanym pliku SQLite."""
    db_path = tmp_path / "test_epc.db"
    return EPCRepository(db_path=str(db_path))


@pytest.fixture(autouse=True)
def _reset_singletons():
    """Zeruje globalne singletony przed i po każdym teście."""
    api_module._repo_singleton = None
    traffic_module.traffic_manager = None
    yield
    # Sprzątanie: zatrzymaj ewentualny działający ruch w tle.
    if traffic_module.traffic_manager is not None:
        traffic_module.traffic_manager.stop_all()
    api_module._repo_singleton = None
    traffic_module.traffic_manager = None


@pytest.fixture
def client(repo):
    """TestClient z repozytorium podmienionym na izolowaną instancję testową."""
    from main import app
    from epc.api import get_repo

    app.dependency_overrides[get_repo] = lambda: repo
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def attached_ue(client):
    """Klient z już podłączonym UE o id=1 (wraz z domyślnym bearerem 9)."""
    resp = client.post("/ues", json={"ue_id": 1})
    assert resp.status_code == 200
    return client
