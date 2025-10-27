# ===========================
# Stage 1 — Downloader (preload HF model)
# ===========================
FROM --platform=$BUILDPLATFORM python:3.11-slim AS downloader

ARG MODEL_ID="deepseek-ai/deepseek-embed"
ARG HF_REVISION="main"

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "huggingface_hub[cli]==0.24.6"

# Pre-download model files into a deterministic path
RUN huggingface-cli download "${MODEL_ID}" \
      --revision "${HF_REVISION}" \
      --local-dir "/models/${MODEL_ID}" \
      --exclude "*.msgpack.index" "*.h5" || true

# ===========================
# Stage 2 — Runtime (TEI)
# ===========================
FROM --platform=$TARGETPLATFORM ghcr.io/huggingface/text-embeddings-inference:0.4

# Build-time args -> baked as runtime ENV so the container is self-describing
ARG MODEL_ID="deepseek-ai/deepseek-embed"
ARG HF_REVISION="main"

# Runtime ENV
ENV MODEL_ID="${MODEL_ID}" \
    HF_REVISION="${HF_REVISION}" \
    HF_HUB_OFFLINE=1 \
    # Honor user-provided endpoints, else stay offline
    EMBEDDINGS_HF_ENDPOINT="" \
    HF_ENDPOINT="" \
    HUGGINGFACE_ENDPOINT="" \
    HUGGINGFACE_HUB_ENDPOINT="" \
    HUGGING_FACE_HUB_BASE_URL="" \
    # TEI runtime binary path (used by the entrypoint)
    TEXT_EMBEDDINGS_BIN="/usr/bin/text-embeddings-router" \
    # Use the locally baked model path by default
    MODEL_LOCAL_PATH="/models/${MODEL_ID}"

# Bring preloaded weights
COPY --from=downloader /models /models

# Drop in the endpoint-resolver entrypoint you gave earlier
COPY ./embeddings-entrypoint.sh /usr/local/bin/embeddings-entrypoint
RUN chmod +x /usr/local/bin/embeddings-entrypoint

EXPOSE 80

# Basic healthcheck (TEI exposes /health)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=5 \
  CMD curl -fsS http://127.0.0.1/health || exit 1

# Run via your entrypoint; default args use local model path
ENTRYPOINT ["/usr/local/bin/embeddings-entrypoint"]
CMD ["--model-id", "/models/${MODEL_ID}", "--hostname", "0.0.0.0"]
