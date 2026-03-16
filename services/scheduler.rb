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

    scheduler.cron "30 6 * * *" do
      puts "[#{Time.now}] Running AI advisory..."
      AIAdvisoryService.run_daily!
    end

    scheduler.cron "0 7 * * *" do
      puts "[#{Time.now}] Sending morning brief..."
      NotificationService.send_morning_brief!
    end

    scheduler.cron "0 */6 * * *" do
      puts "[#{Time.now}] Generating tasks..."
      TaskGenerator.generate_all!
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
