import os
import random
from locust import HttpUser, between, task, tag, events

TARGET_HOST = os.getenv("TARGET_HOST", "http://localhost:8080")
CANARY_ENDPOINT = os.getenv("CANARY_ENDPOINT", "/")
FORTUNE_ENDPOINT = os.getenv("FORTUNE_ENDPOINT", "/fortunes")
BETA_ENDPOINT = os.getenv("BETA_ENDPOINT", "/beta-insights")
AGGREGATE_ENDPOINT = os.getenv("AGGREGATE_ENDPOINT", "/aggregate")


@events.init.add_listener
def on_locust_init(environment, **_kwargs):
    environment.runner.environment.host = TARGET_HOST


class GatewayTraffic(HttpUser):
    wait_time = between(0.2, 1.0)

    @task(5)
    def hit_root(self):
        self.client.get(CANARY_ENDPOINT)

    @task(3)
    def pull_fortune(self):
        self.client.get(FORTUNE_ENDPOINT)

    @task(1)
    @tag("beta")
    def beta_feature(self):
        # Only a subset of users exercise the beta endpoint; mimic feature-flag rollout
        if random.random() < 0.3:
            self.client.get(BETA_ENDPOINT)

    @task(2)
    def aggregate_call(self):
        self.client.get(f"/service-b{AGGREGATE_ENDPOINT}")
