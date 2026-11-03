# syntax=docker/dockerfile:1.7
#
# Multi-stage build:
#   builder  - installs hash-locked dependencies into a virtualenv (has pip, build tools)
#   runtime  - slim image with only the virtualenv; runs as a non-root user
#
# Build:  docker build --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t matterhub:dev app/
#
# The base image tag is tracked by Dependabot (.github/dependabot.yml). In the pipeline
# the image is scanned by Trivy and fails the build on fixable HIGH/CRITICAL CVEs.

ARG PYTHON_VERSION=3.13

FROM python:${PYTHON_VERSION}-slim AS builder
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1
WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH

# Dependencies first so this layer is cached until requirements.txt changes.
COPY requirements.txt .
RUN pip install --require-hashes --no-deps -r requirements.txt

COPY pyproject.toml README.md ./
COPY src ./src
RUN pip install --no-deps .


FROM python:${PYTHON_VERSION}-slim AS runtime
ARG APP_VERSION=0.0.0-dev
ARG GIT_SHA=unknown

LABEL org.opencontainers.image.title="matterhub" \
      org.opencontainers.image.description="MatterHub legal matter tracking API" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.licenses="MIT"

# Apply OS security patches published since the base image was built.
# hadolint ignore=DL3005,DL3008
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 10001 matterhub \
    && useradd --system --uid 10001 --gid matterhub --no-create-home \
       --home-dir /nonexistent --shell /usr/sbin/nologin matterhub

COPY --from=builder /opt/venv /opt/venv

ENV PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    MATTERHUB_APP_VERSION=${APP_VERSION} \
    MATTERHUB_GIT_SHA=${GIT_SHA}

# Numeric UID so Kubernetes can verify runAsNonRoot.
USER 10001:10001
WORKDIR /tmp
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"]

ENTRYPOINT ["matterhub"]
CMD ["serve"]
