#!/bin/bash
python -m http.server 8080 &
celery -A app.workers.celery_app worker --loglevel=info --concurrency=2