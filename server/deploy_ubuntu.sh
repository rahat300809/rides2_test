#!/bin/bash
set -e

echo "========================================================"
echo "🚀 [DIU Ride] Starting Ubuntu Production Deployment"
echo "========================================================"

APP_DIR="/home/rahat/diu_ride"
SERVICE_NAME="diu-ride.service"

if [ -d "$APP_DIR" ]; then
    cd "$APP_DIR"
else
    echo "Using current directory: $(pwd)"
fi

echo "📥 1. Pulling latest production code from git..."
git pull origin main

echo "🐳 2. Checking Docker deployment capability..."
if command -v docker &> /dev/null && (docker compose version &> /dev/null || command -v docker-compose &> /dev/null); then
    echo "Using Docker Compose for full project containerization..."
    # If systemd service is active, stop it to free port 8001
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Stopping systemd service to transition to Docker..."
        echo rahat | sudo -S systemctl stop "$SERVICE_NAME" || true
    fi
    if docker compose version &> /dev/null; then
        echo rahat | sudo -S docker compose up -d --build
    else
        echo rahat | sudo -S docker-compose up -d --build
    fi
    echo "⏱️ Waiting for Docker container health..."
    sleep 3
    echo rahat | sudo -S docker ps --filter "name=diu_ride_app"
else
    echo "Docker not found, using Python systemd service fallback..."
    if [ -d "/home/rahat/diu_ride_env" ]; then
        /home/rahat/diu_ride_env/bin/pip install -r server/requirements.txt
    else
        pip install -r server/requirements.txt
    fi

    echo "🔄 Restarting systemd service..."
    if command -v sudo &> /dev/null; then
        echo rahat | sudo -S systemctl restart "$SERVICE_NAME"
    else
        systemctl restart "$SERVICE_NAME"
    fi

    sleep 2
    systemctl status "$SERVICE_NAME" --no-pager || true
fi

echo "🌐 3. Testing local endpoint health..."
curl -s http://127.0.0.1:8001/ride/health || curl -s http://127.0.0.1:8001/health || true

echo ""
echo "========================================================"
echo "✅ [DIU Ride] Deployment Succeeded!"
echo "Public URL: https://servertest.eu.cc/ride"
echo "Local Port: http://192.168.0.114:8001/ride"
echo "API Base:   https://servertest.eu.cc/ride/api"
echo "WebSocket:  wss://servertest.eu.cc/ride/ws"
echo "========================================================"
