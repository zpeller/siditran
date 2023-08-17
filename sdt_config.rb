require 'json'

class SdtConfig
	def initialize(config_filename, logger)
		@logger = logger
		@config_filename = config_filename
		if File.file?(@config_filename) and File.writable?(@config_filename)
			@config = JSON.load_file(@config_filename)
		else
			@config = {}
			save_config
		end
		@logger.debug(@config)
	end

	def get_channel_autotrans_status(server, channel)
		return nil if not @config.has_key?(server)
		return nil if not @config[server].has_key?(channel)
		return nil if @config[server][channel] == ""
		return @config[server][channel]
	end

	def list_autotrans_channels(server)
		return {} if not @config.has_key?(server)
		return @config[server]
	end

	def set_channel_autotrans_status(server, channel, target_lang = "en")
		@config[server]={} if not @config.has_key?(server)
		if target_lang == "" or target_lang == nil
			@config[server][channel] = ""
		else
			@config[server][channel] = target_lang
		end

		save_config

		return @config[server][channel]
	end

	def delete_channel_autotrans_status(server, channel)
		return if not @config.has_key?(server)
		return if not @config[server].has_key?(channel)
		@config[server].delete(channel)
		save_config
	end

	private def save_config
		@logger.info("saving autotrans config '#{@config_filename}':\n#{@config}")
		File.open(@config_filename, 'w') do |f|
			f.write(JSON.pretty_generate(@config, {indent: '	', array_nl: "\n"}) )
		end
	end
end

