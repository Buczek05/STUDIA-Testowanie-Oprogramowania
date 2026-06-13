from pydantic import BaseModel, Field, field_validator, model_validator


class BearerConfig(BaseModel):
    bearer_id: int = Field(ge=1, le=9)
    protocol: str | None = Field(default=None, pattern="^(tcp|udp)$")
    target_bps: int | None = None  # bits per second
    active: bool = False


class ThroughputStats(BaseModel):
    bearer_id: int
    ue_id: int
    bytes_tx: int = 0  # uplink (MS->SS)
    bytes_rx: int = 0  # downlink (SS->MS)
    start_ts: float | None = None
    last_update_ts: float | None = None
    protocol: str | None = None
    target_bps: int | None = None


class UEState(BaseModel):
    ue_id: int = Field(ge=1, le=100)
    bearers: dict[int, BearerConfig] = {}
    stats: dict[int, ThroughputStats] = {}

    @model_validator(mode="before")
    def init_defaults(cls, values):
        if values.get("bearers") is None:
            values["bearers"] = {}
        if values.get("stats") is None:
            values["stats"] = {}
        return values


# Request body schemas (REST API)
class AttachUERequest(BaseModel):
    ue_id: int = Field(ge=1, le=100)

    # BUG-4 fix: reject bool values for ue_id (bool is a subclass of int in
    # Python and would otherwise be silently accepted)
    # (fixes test_bugs.py::TestBug4BooleanUeId::test_boolean_true_rejected_by_model
    #  and ::test_boolean_true_rejected_by_api)
    @field_validator("ue_id", mode="before")
    @classmethod
    def reject_bool(cls, v):
        if isinstance(v, bool):
            raise ValueError("ue_id must be an integer, not a boolean")
        return v
    # *******************************************************************************************************

class AddBearerRequest(BaseModel):
    bearer_id: int = Field(ge=1, le=9)
    # *******************************************************************************************************
    @field_validator("bearer_id", mode="before")
    @classmethod
    def reject_bool(cls, v):
        if isinstance(v, bool):
            raise ValueError("bearer_id must be an integer, not a boolean")
        return v
    # *******************************************************************************************************

class StartTrafficRequest(BaseModel):
    protocol: str = Field(pattern="^(tcp|udp)$")
    Mbps: float | None = None
    kbps: float | None = None
    bps: float | None = None

    @model_validator(mode="after")
    def exactly_one_throughput(self):
        provided = [v for v in [self.Mbps, self.kbps, self.bps] if v is not None]
        if len(provided) != 1:
            raise ValueError("Provide exactly one throughput value (Mbps, kbps, or bps)")
        # BUG-13 fix: enforce a 100 Mbps bandwidth limit regardless of unit used
        # (fixes test_bugs.py::TestBug13NoBandwidthLimit::test_model_rejects_over_limit
        #  and ::test_api_rejects_over_limit)
        if self.target_bps() > 100_000_000:
            raise ValueError("Bandwidth exceeds 100 Mbps limit")
        # *************************************************************************

        return self
    def target_bps(self) -> int:
        if self.Mbps is not None:
            return int(self.Mbps * 1_000_000)
        if self.kbps is not None:
            return int(self.kbps * 1_000)
        return int(self.bps or 0)


# Response Schemas
class StatusResponse(BaseModel):
    status: str


class AttachResponse(StatusResponse):
    ue_id: int


class DetachResponse(StatusResponse):
    ue_id: int


class BearerAddResponse(StatusResponse):
    ue_id: int
    bearer_id: int


class BearerDeleteResponse(StatusResponse):
    ue_id: int
    bearer_id: int


class TrafficStartResponse(StatusResponse):
    ue_id: int
    bearer_id: int
    target_bps: int


class TrafficStopResponse(StatusResponse):
    ue_id: int
    bearer_id: int


class TrafficStatsResponse(BaseModel):
    ue_id: int
    bearer_id: int
    protocol: str | None = None
    target_bps: int | None = None
    tx_bps: int
    rx_bps: int
    duration: float


class UEDisplayResponse(UEState):
    pass


class UEListResponse(BaseModel):
    ues: list[int]


class AggregatedStatsResponse(BaseModel):
    scope: str  # 'all' or f'ue:{id}'
    ue_count: int
    bearer_count: int
    total_tx_bps: int
    total_rx_bps: int
    details: dict[str, dict[str, int]] | None = None  # per ue optional
