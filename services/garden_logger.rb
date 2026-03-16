require "logger"
require "json"
require "fileutils"

module GardenLogger
  LOG_DIR = File.join(File.dirname(__FILE__), "..", "log")
  GAPS_DIR = File.join(File.dirname(__FILE__), "..", "docs", "gaps")

  def self.logger
    @logger ||= begin
      FileUtils.mkdir_p(LOG_DIR)
      log = Logger.new(File.join(LOG_DIR, "garden.log"), 5, 1_048_576) # 5 rotated files, 1MB each
      log.level = Logger::DEBUG
      log.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
      log
    end
  end

  def self.info(msg)  = logger.info(msg)
  def self.warn(msg)  = logger.warn(msg)
  def self.error(msg) = logger.error(msg)
  def self.debug(msg) = logger.debug(msg)

  # Write a gap file when something goes wrong — structured error tracking
  def self.record_gap!(category:, summary:, detail: nil, context: {})
    FileUtils.mkdir_p(GAPS_DIR)
    timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
    filename = "#{timestamp}-#{category}.yml"
    filepath = File.join(GAPS_DIR, filename)

    content = {
      "category" => category,
      "summary" => summary,
      "detail" => detail,
      "context" => JSON.parse(JSON.generate(context)),  # stringify symbol keys
      "timestamp" => Time.now.iso8601,
      "status" => "open"
    }

    require "yaml"
    File.write(filepath, YAML.dump(content))
    logger.error("GAP RECORDED: #{category} — #{summary} (#{filepath})")
    filepath
  end
end
