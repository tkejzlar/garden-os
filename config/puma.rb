# config/puma.rb
threads_count = ENV.fetch("PUMA_THREADS", 5).to_i
threads threads_count, threads_count

port ENV.fetch("PORT", 4567)

environment ENV.fetch("RACK_ENV", "development")

# Workers for production (0 = single process for dev)
workers ENV.fetch("WEB_CONCURRENCY", 0).to_i

preload_app! if ENV.fetch("WEB_CONCURRENCY", 0).to_i > 0
