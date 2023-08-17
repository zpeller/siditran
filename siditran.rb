#!/usr/bin/env ruby

require_relative 'sdt_bot'

require 'dotenv'
Dotenv.load

class NullLogger
	def self.method_missing *args; end
end

def init_logger
	if ENV["DEBUG"] == "1"
		require 'logger' 
		logger = Logger.new(STDOUT)
		logger.level = eval "Logger::#{ENV['DEBUG_LEVEL']}"
		logger.datetime_format = "%Y-%m-%dT%H:%M:%S"
		logger.formatter = proc { |severity, time, progname, msg|
			"#{time.strftime logger.datetime_format} #{severity} [#{progname}:#{__FILE__}:#{__LINE__}] #{msg}\n"
#		caller_locations(1, 1)
		}
	else
		logger=NullLogger
	end
	return logger
end

DISCORD_TOKEN = ENV["DISCORD_TOKEN"]

logger = init_logger

bot = SdtBot.new(DISCORD_TOKEN, logger)
bot.setup_events
bot.setup_bot_slash_commands
#bot.setup_responder
bot.run

#SdtBot.new(DISCORD_TOKEN, logger).run

