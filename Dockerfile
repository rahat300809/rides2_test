# =====================================================================
# DIU Ride - Production Dockerfile (Backend + Web SPA)
# =====================================================================
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8001 \
    HOST=0.0.0.0

WORKDIR /app

# Install curl for container healthchecks
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Install Python requirements
COPY server/requirements.txt ./server/requirements.txt
RUN pip install --no-cache-dir -r ./server/requirements.txt

# Copy backend source code and prebuilt web bundle
COPY server/ ./server/

WORKDIR /app/server

# Expose ports: 8001 (production reverse proxy / systemd parity), 8080 (standard)
EXPOSE 8001 8080

# Health check endpoint
HEALTHCHECK --interval=20s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://127.0.0.1:${PORT}/ride/health || curl -f http://127.0.0.1:${PORT}/api/rides || exit 1

# Launch Uvicorn with environment variables
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT} --workers 1"]
