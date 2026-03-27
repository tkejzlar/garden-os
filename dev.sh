#!/bin/bash
# GardenOS — start backend + frontend dev servers
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

cleanup() {
  echo ""
  echo "Shutting down..."
  kill $PUMA_PID $VITE_PID 2>/dev/null
  wait $PUMA_PID $VITE_PID 2>/dev/null
  echo "Done."
}
trap cleanup EXIT INT TERM

# Backend: Puma + Sinatra on :4567
echo "Starting Sinatra (Puma) on :4567..."
bundle exec puma -C config/puma.rb config.ru &
PUMA_PID=$!

# Wait for backend to be ready
for i in $(seq 1 10); do
  curl -s http://localhost:4567/health >/dev/null 2>&1 && break
  sleep 1
done

# Frontend: Vite dev server on :5173
echo "Starting Vite on :5173..."
npx vite --host &
VITE_PID=$!

echo ""
echo "═══════════════════════════════════════"
echo "  GardenOS running:"
echo "  Frontend:  http://localhost:5173"
echo "  Backend:   http://localhost:4567"
echo "  Press Ctrl+C to stop"
echo "═══════════════════════════════════════"
echo ""

wait
