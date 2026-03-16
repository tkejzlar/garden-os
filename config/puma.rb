# config/puma.rb
# Needs multiple threads so poll requests work while AI runs in background
threads 5, 5
port ENV.fetch("PORT", 4567)
