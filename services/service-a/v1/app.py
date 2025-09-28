from fastapi import FastAPI, Request
from prometheus_fastapi_instrumentator import Instrumentator
import random
import time

app = FastAPI(title="service-a", version="v1")


@app.on_event("startup")
async def startup() -> None:
    """Register Prometheus instrumentation as soon as the app boots."""
    Instrumentator().instrument(app).expose(app, include_in_schema=False)


@app.get("/", summary="Greet the caller")
async def greet() -> dict[str, str]:
    return {
        "service": "service-a",
        "version": "v1",
        "message": "Hello from service-a v1",
    }


@app.get("/fortunes", summary="Return a random fortune")
async def fortune() -> dict[str, str]:
    fortunes = [
        "Green deployments for the win!",
        "Chaos reveals resilience",
        "Metrics keep outages short",
    ]
    # Introduce a tiny processing delay to make latency visible in Grafana.
    time.sleep(random.uniform(0.05, 0.15))
    return {"fortune": random.choice(fortunes)}


@app.get("/healthz", summary="Kubernetes liveness/readiness probe")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}
