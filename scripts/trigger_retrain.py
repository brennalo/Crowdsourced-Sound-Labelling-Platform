"""
trigger_retrain.py

Manually trigger a retraining job outside of the active learning threshold.
Use when you want to force a retrain after adding new data or fixing labels.

Usage:
  python scripts/trigger_retrain.py --api-url https://your-api.run.app --token YOUR_JWT
"""

import argparse
import httpx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--api-url", required=True, help="Base URL of deployed FastAPI")
    parser.add_argument("--token", required=True, help="Admin JWT token")
    args = parser.parse_args()

    headers = {"Authorization": f"Bearer {args.token}"}

    # Hit the model router to see current active model
    response = httpx.get(f"{args.api_url}/model/active", headers=headers)
    if response.status_code == 200:
        model = response.json()
        print(f"[trigger] Current active model: {model['version_tag']} (acc={model.get('accuracy')})")
    else:
        print(f"[trigger] No active model found ({response.status_code})")

    confirm = input("\nTrigger a full retrain? (yes/no): ").strip().lower()
    if confirm != "yes":
        print("[trigger] Aborted.")
        return

    # Directly insert a retraining job via DB or call an internal endpoint
    # For simplicity this calls a protected admin endpoint
    response = httpx.post(
        f"{args.api_url}/model/trigger-retrain",
        headers=headers,
        timeout=30,
    )

    if response.status_code in (200, 201):
        job = response.json()
        print(f"[trigger] Retraining job queued: {job['id']}")
        print(f"[trigger] Status: {job['status']}")
        print(f"[trigger] Poll: GET {args.api_url}/model/retraining-jobs")
    else:
        print(f"[trigger] Failed: {response.status_code} {response.text}")


if __name__ == "__main__":
    main()
