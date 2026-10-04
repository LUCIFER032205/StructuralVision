# Backend image for a cloud VM (see DEPLOY_GUIDE.md). Build context: project/backend.
# Model weights aren't in git, so docker-compose mounts project/models at /app/models.
FROM python:3.12-slim-bookworm

# opencv (pulled in by ultralytics) needs these shared libs
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend
COPY requirements.txt .
# CPU-only torch first: the default PyPI wheel on x86 bundles ~2 GB of CUDA we'd never use
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu \
 && pip install --no-cache-dir -r requirements.txt

COPY . .
EXPOSE 8000
# One worker: each worker loads its own copy of the model
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
