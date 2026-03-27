#!/bin/bash
# GardenOS — build + deploy
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "═══════════════════════════════════════"
echo "  GardenOS Production Deploy"
echo "═══════════════════════════════════════"
echo ""

# 1. Install dependencies
echo "→ Installing Ruby gems..."
bundle install --quiet

echo "→ Installing npm packages..."
npm ci --silent 2>/dev/null || npm install --silent

# 2. Type check
echo "→ TypeScript check..."
npx tsc --noEmit

# 3. Build frontend
echo "→ Building React SPA..."
npx vite build

# 4. Run migrations
echo "→ Running database migrations..."
RACK_ENV=production ruby -e "require_relative 'config/database'; Sequel::Migrator.run(DB, 'db/migrations')"

# 5. Verify
echo "→ Verifying Ruby syntax..."
ruby -c app.rb > /dev/null

echo ""
echo "✓ Build complete!"
echo ""
echo "  Static files: dist/"
echo "  Start server:  RACK_ENV=production bundle exec puma -C config/puma.rb config.ru"
echo ""
echo "  Or with PORT:  PORT=8080 RACK_ENV=production bundle exec puma -C config/puma.rb config.ru"
echo ""
