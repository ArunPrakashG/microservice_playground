import os
from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
import httpx

SERVICE_A_URL = os.getenv("SERVICE_A_URL", "http://service-a.canary-playground.svc.cluster.local")

app = FastAPI(title="service-b", version="v1")
Instrumentator().instrument(app).expose(app, include_in_schema=False)


@app.get("/", summary="Return the baseline response")
async def root() -> dict[str, str]:
    return {
        "service": "service-b",
        "message": "Greetings from service-b",
    }


@app.get("/aggregate", summary="Call service-a and return combined data")
async def aggregate() -> dict[str, object]:
    async with httpx.AsyncClient(timeout=1.5) as client:
        try:
            response = await client.get(f"{SERVICE_A_URL}/fortunes")
            response.raise_for_status()
        except httpx.HTTPError as exc:  # pragma: no cover - network errors
            raise HTTPException(status_code=502, detail=f"service-a call failed: {exc}") from exc

    payload = response.json()
    return {
        "service": "service-b",
        "service_a_payload": payload,
    }


@app.get("/healthz", summary="Probe endpoint")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}
