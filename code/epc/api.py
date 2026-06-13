import time
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from .models import (
    AddBearerRequest,
    AggregatedStatsResponse,
    AttachResponse,
    AttachUERequest,
    BearerAddResponse,
    BearerDeleteResponse,
    DetachResponse,
    StartTrafficRequest,
    StatusResponse,
    TrafficStartResponse,
    TrafficStatsResponse,
    TrafficStopResponse,
    UEDisplayResponse,
    UEListResponse,
)
from .db import EPCRepository
from .traffic import get_traffic_manager

router = APIRouter()

_repo_singleton: EPCRepository | None = None


def get_repo() -> EPCRepository:
    global _repo_singleton
    if _repo_singleton is None:
        _repo_singleton = EPCRepository()
    return _repo_singleton


@router.get("/ues/stats", response_model=AggregatedStatsResponse)
def get_ues_stats(
    repo: Annotated[EPCRepository, Depends(get_repo)],
    ue_id: int | None = None,
    include_details: bool = False,
):
    if ue_id is not None and not repo.ue_exists(ue_id):
        raise HTTPException(status_code=400, detail="UE not found")
    ues = [ue_id] if ue_id is not None else list(repo.list_ues())
    total_tx = 0
    total_rx = 0
    bearer_count = 0
    details: dict[str, dict[str, int]] = {}
    tm = get_traffic_manager(repo)
    for uid in ues:
        try:
            state = repo.get_ue(uid)
        except ValueError:
            if ue_id is not None:
                raise HTTPException(status_code=400, detail="UE not found")
            continue
        # BUG-5 fix: count configured bearers, not just ones with stats
        # (fixes test_bugs.py::TestBug5BearerCountCountsTraffic::test_bearer_count_reflects_configured_bearers)
        bearer_count += len(state.bearers)
        
        # ************************************************************************
        for b_id, stats in state.stats.items():
            end_ts = time.time() if (stats.start_ts and tm.is_running(uid, b_id)) else stats.last_update_ts
            duration = (end_ts - stats.start_ts) if (stats.start_ts and end_ts is not None) else 0
            tx_bps = int(stats.bytes_tx * 8 / duration) if duration > 0 else 0
            rx_bps = int(stats.bytes_rx * 8 / duration) if duration > 0 else 0
            total_tx += tx_bps
            total_rx += rx_bps
            if include_details:
                details.setdefault(str(uid), {})[str(b_id)] = tx_bps
    scope = f"ue:{ue_id}" if ue_id is not None else "all"
    return AggregatedStatsResponse(
        scope=scope,
        ue_count=len(ues),
        bearer_count=bearer_count,
        total_tx_bps=total_tx,
        total_rx_bps=total_rx,
        details=details if include_details else None,
    )


@router.get("/ues", response_model=UEListResponse)
def list_ues(repo: Annotated[EPCRepository, Depends(get_repo)]):
    return UEListResponse(ues=list(repo.list_ues()))


@router.post("/ues", response_model=AttachResponse)
def attach_ue(body: AttachUERequest, repo: Annotated[EPCRepository, Depends(get_repo)]):
    try:
        repo.attach_ue(body.ue_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return AttachResponse(status="attached", ue_id=body.ue_id)


@router.get("/ues/{ue_id}", response_model=UEDisplayResponse)
def get_ue(ue_id: int, repo: Annotated[EPCRepository, Depends(get_repo)]):
    try:
        state = repo.get_ue(ue_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return UEDisplayResponse(**state.model_dump())


@router.delete("/ues/{ue_id}", response_model=DetachResponse)
def detach_ue(ue_id: int, repo: Annotated[EPCRepository, Depends(get_repo)]):
    try:
        repo.detach_ue(ue_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return DetachResponse(status="detached", ue_id=ue_id)


# --- Bearers ---

@router.post("/ues/{ue_id}/bearers", response_model=BearerAddResponse)
def add_bearer(
    ue_id: int,
    body: AddBearerRequest,
    repo: Annotated[EPCRepository, Depends(get_repo)],
):
    try:
        repo.add_bearer(ue_id, body.bearer_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return BearerAddResponse(status="bearer_added", ue_id=ue_id, bearer_id=body.bearer_id)


@router.delete("/ues/{ue_id}/bearers/{bearer_id}", response_model=BearerDeleteResponse)
def delete_bearer(
    ue_id: int,
    bearer_id: int,
    repo: Annotated[EPCRepository, Depends(get_repo)],
):
    try:
        state = repo.get_ue(ue_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    if bearer_id not in state.bearers:
        raise HTTPException(status_code=400, detail="Bearer not found")
    tm = get_traffic_manager(repo)
    # BUG-8 fix: refuse to delete a bearer with active traffic instead of
    # silently stopping it first
    # (fixes test_bugs.py::TestBug8DeleteBearerWithActiveTraffic::test_delete_bearer_with_traffic_should_fail)
    if tm.is_running(ue_id, bearer_id):
        raise HTTPException(status_code=400, detail="Stop traffic before deleting bearer")
    # *************************************************************************************
    try:
        repo.delete_bearer(ue_id, bearer_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return BearerDeleteResponse(status="bearer_deleted", ue_id=ue_id, bearer_id=bearer_id)


# --- Traffic (start/stop/stats) ---

@router.post("/ues/{ue_id}/bearers/{bearer_id}/traffic", response_model=TrafficStartResponse)
def start_traffic(
    ue_id: int,
    bearer_id: int,
    body: StartTrafficRequest,
    repo: Annotated[EPCRepository, Depends(get_repo)],
):
    target_bps = body.target_bps()
    try:
        state = repo.get_ue(ue_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    bearer = state.bearers.get(bearer_id)
    if not bearer:
        raise HTTPException(status_code=400, detail="Bearer not found")
    bearer.protocol = body.protocol.lower()
    bearer.target_bps = target_bps
    bearer.active = True
    repo.update_bearer(ue_id, bearer)
    from .models import ThroughputStats

    # BUG-10 fix: always start a fresh measurement session so start_ts resets
    # on restart instead of keeping the value from a previous session
    # (fixes test_bugs.py::TestBug10DurationAccumulates::test_start_ts_reset_on_restart)
    fresh_stats = ThroughputStats(
        bearer_id=bearer_id,
        ue_id=ue_id,
        start_ts=time.time(),
        last_update_ts=time.time(),
        protocol=bearer.protocol,
        target_bps=target_bps,
    )
    repo.update_stats(ue_id, fresh_stats)
    #***************************************************************************************
    tm = get_traffic_manager(repo)
    try:
        tm.start(ue_id, bearer)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return TrafficStartResponse(
        status="traffic_started",
        ue_id=ue_id,
        bearer_id=bearer_id,
        target_bps=target_bps,
    )


@router.delete("/ues/{ue_id}/bearers/{bearer_id}/traffic", response_model=TrafficStopResponse)
def stop_traffic(
    ue_id: int,
    bearer_id: int,
    repo: Annotated[EPCRepository, Depends(get_repo)],
):
    try:
        state = repo.get_ue(ue_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    bearer = state.bearers.get(bearer_id)
    if not bearer:
        raise HTTPException(status_code=400, detail="Bearer not found")
    tm = get_traffic_manager(repo)
    # BUG-1 fix: stopping traffic that was never started is an error, not a no-op
    # (fixes test_bugs.py::TestBug1StopTrafficWithoutSession::test_stop_without_active_traffic_should_fail)
    if not tm.is_running(ue_id, bearer_id):
        raise HTTPException(status_code=400, detail="Traffic not running for this bearer")
    # *********************************************************************************************************
    tm.stop(ue_id, bearer_id)
    bearer.active = False
    repo.update_bearer(ue_id, bearer)

    # BUG-3 fix: clear stale protocol/target_bps (and counters/timestamps) after stop
    # (fixes test_bugs.py::TestBug3StaleStatsAfterStop::test_protocol_and_bps_cleared_after_stop)
    stats = state.stats.get(bearer_id)
    if stats:
        stats.protocol = None
        stats.target_bps = None
        stats.bytes_tx = 0
        stats.bytes_rx = 0
        stats.start_ts = None
        stats.last_update_ts = None
        repo.update_stats(ue_id, stats)
    #*******************************************************************************************************
    return TrafficStopResponse(status="traffic_stopped", ue_id=ue_id, bearer_id=bearer_id)


@router.get("/ues/{ue_id}/bearers/{bearer_id}/traffic", response_model=TrafficStatsResponse)
def get_traffic_stats(
    ue_id: int,
    bearer_id: int,
    repo: Annotated[EPCRepository, Depends(get_repo)],
):
    try:
        state = repo.get_ue(ue_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    # BUG-2 fix: no traffic history for this bearer -> 404 instead of 200 with zeros
    # (fixes test_bugs.py::TestBug2StatsWithoutHistory::test_get_stats_no_history_should_return_404)
    stats = state.stats.get(bearer_id)
    if not stats:
        raise HTTPException(status_code=404, detail="No traffic history for this bearer")
    # *******************************************************************************************************
    tm = get_traffic_manager(repo)
    end_ts = time.time() if (stats.start_ts and tm.is_running(ue_id, bearer_id)) else stats.last_update_ts
    duration = (end_ts - stats.start_ts) if (stats.start_ts and end_ts is not None) else 0
    tx_bps = int(stats.bytes_tx * 8 / duration) if duration > 0 else 0
    rx_bps = int(stats.bytes_rx * 8 / duration) if duration > 0 else 0
    return TrafficStatsResponse(
        ue_id=ue_id,
        bearer_id=bearer_id,
        protocol=stats.protocol,
        target_bps=stats.target_bps,
        tx_bps=tx_bps,
        rx_bps=rx_bps,
        duration=duration,
    )


# --- Reset ---

@router.post("/reset", response_model=StatusResponse)
def reset_all(repo: Annotated[EPCRepository, Depends(get_repo)]):
    get_traffic_manager(repo).stop_all()
    repo.reset_all()
    return StatusResponse(status="reset")
