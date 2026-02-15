from fastapi import FastAPI

from app.api import alerts, auth, events, ingest, instances

app = FastAPI(title="AgentCompanion API", version="0.1.0")

app.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(instances.router, prefix="/api/v1/instances", tags=["instances"])
app.include_router(ingest.router, prefix="/api/v1", tags=["ingest"])
app.include_router(events.router, prefix="/api/v1/events", tags=["events"])
app.include_router(alerts.router, prefix="/api/v1", tags=["alerts", "security"])


@app.get("/health")
async def health():
    return {"status": "ok"}
