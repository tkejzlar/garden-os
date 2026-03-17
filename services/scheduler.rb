require "rufus-scheduler"
require_relative "weather_service"
require_relative "notification_service"
require_relative "ai_advisory_service"
require_relative "task_generator"
require_relative "../models/plant"
require_relative "../db/seeds/seed_varieties"

class GardenScheduler
  def self.start!
    scheduler = Rufus::Scheduler.new

    # Daily AI advisory — run for each garden
    scheduler.cron "30 6 * * *" do
      require_relative "../models/garden"
      Garden.all.each do |garden|
        puts "[#{Time.now}] Running AI advisory for #{garden.name}..."
        AIAdvisoryService.run_daily!(garden_id: garden.id)
      end
    end

    scheduler.cron "0 7 * * *" do
      puts "[#{Time.now}] Sending morning brief..."
      NotificationService.send_morning_brief!
    end

    # Task generation — run for each garden
    scheduler.cron "0 */6 * * *" do
      require_relative "../models/garden"
      Garden.all.each do |garden|
        puts "[#{Time.now}] Generating tasks for #{garden.name}..."
        TaskGenerator.generate_all!(garden_id: garden.id)
      end
    end

    scheduler.cron "0 */6 * * *" do
      puts "[#{Time.now}] Checking weather..."
      weather = WeatherService.fetch_current
      if weather && weather[:frost_risk]
        tender_outside = Plant.where(
          lifecycle_stage: %w[hardening_off planted_out producing]
        ).all.select do |p|
          Varieties.for(p.crop_type)&.dig("frost_tender")
        end

        if tender_outside.any?
          min_temp = weather[:forecast].map { |f| f[:low] }.compact.min
          NotificationService.send!(
            **NotificationService.frost_alert_payload(
              min_temp: min_temp,
              when_str: "within 48h",
              tender_count: tender_outside.count
            )
          )
        end
      end
    end

    puts "Scheduler started."
    scheduler
  end
end
