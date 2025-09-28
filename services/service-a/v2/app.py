from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
import random
import time

app = FastAPI(title="service-a", version="v2")

instrumentator = Instrumentator()


@app.on_event("startup")
async def startup() -> None:
    instrumentator.instrument(app).expose(app, include_in_schema=False)


@app.get("/", summary="Respond with the v2 experience")
async def greet() -> dict[str, str]:
    # Simulate a small error rate to demonstrate canary risk detection
    if random.random() < 0.05:
        raise HTTPException(status_code=500, detail="Synthetic canary failure")

    processing_delay = random.uniform(0.1, 0.3)
    time.sleep(processing_delay)
    return {
        "service": "service-a",
        "version": "v2",
        "message": "Hello from service-a v2",
        "processing_delay": processing_delay,
    }


@app.get("/beta-insights", summary="New beta-only feature")
async def beta_insights() -> dict[str, float]:
    jitter = random.uniform(0.0, 1.0)
    time.sleep(jitter / 4)
    return {"beta_score": round(0.75 + jitter / 4, 3)}


@app.get("/healthz", summary="Kubernetes liveness/readiness probe")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}
