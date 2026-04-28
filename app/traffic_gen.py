"""Continuous traffic generator for the OTLP demo app."""
import asyncio
import os
import random
import sys

import httpx

URL = os.getenv("APP_URL", "http://llm-app:8000")
RPS = float(os.getenv("APP_RPS", "5"))
MODELS = ["gpt-4o", "claude-3-5-sonnet", "mistral-large"]
PROVIDERS = {"gpt-4o": "openai", "claude-3-5-sonnet": "anthropic", "mistral-large": "mistral"}
TENANTS = ["acme", "globex", "initech"]


async def hit(client):
    model = random.choice(MODELS)
    payload = {
        "model": model,
        "provider": PROVIDERS[model],
        "tenant_id": random.choice(TENANTS),
    }
    endpoint = "/rag" if random.random() < 0.6 else "/chat"
    if endpoint == "/rag":
        payload["index_id"] = random.choice(["kb-products", "kb-faq", "kb-policies"])
    try:
        await client.post(URL + endpoint, json=payload, timeout=30.0)
    except Exception as e:
        print(f"[traffic-gen] {endpoint} failed: {e}", flush=True)


async def main():
    print(f"[traffic-gen] {URL} @ {RPS} rps", flush=True)
    async with httpx.AsyncClient() as client:
        # warm up: wait for /health
        for _ in range(30):
            try:
                r = await client.get(URL + "/health", timeout=2)
                if r.status_code == 200:
                    break
            except Exception:
                pass
            await asyncio.sleep(2)
        while True:
            tasks = [hit(client) for _ in range(int(RPS))]
            await asyncio.gather(*tasks)
            await asyncio.sleep(1)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
