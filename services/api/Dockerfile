# syntax=docker/dockerfile:1
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Run as an unprivileged user; only /app/storage is writable at runtime.
RUN groupadd --system safar \
    && useradd --system --gid safar --home-dir /app --shell /usr/sbin/nologin safar \
    && mkdir -p /app/storage \
    && chown -R safar:safar /app/storage

COPY --chown=safar:safar alembic.ini ./
COPY --chown=safar:safar migrations ./migrations
COPY --chown=safar:safar app ./app
COPY --chown=safar:safar scripts ./scripts

USER safar

EXPOSE 8000

# Migrations run before the server starts; the app never creates schema in production.
CMD ["sh", "-c", "python -m alembic upgrade head && python -m uvicorn app.main:app --host 0.0.0.0 --port 8000"]
