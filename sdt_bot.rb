require 'discordrb'
require_relative 'sdt_config'
require_relative 'translator'
require_relative 'flags_langs'

DISCORD_EMBED_THUMBNAIL_URL='https://media.discordapp.net/attachments/785041781472624664/826870778091274320/discord-avatar-512_1.png?width=369&height=369'

class SdtBot
#	attr_reader :bot
	attr_accessor :bot

	class NullLogger; def self.method_missing *args; end; end

	def initialize(discord_token, logger = nil)
		@logger = logger ? logger : NullLogger

		@command_prefix = '/'
		@name = ENV.fetch('BOT_NAME')
		@guild_ids = ENV.fetch('GUILD_IDS').split

		@autotrans_config = SdtConfig.new(ENV.fetch('AUTOTRANS_CONFIG_FILE'), @logger)
		@translator = Translator.new(@logger)
		@supported_languages = @translator.get_supported_languages
#		@supported_languages = {}

		@bot = Discordrb::Bot.new(
							token: ENV.fetch('DISCORD_TOKEN', nil), 
							log_mode: :verbose, 
#							name: @name, 
							name: 'SiDiTran',
							fancy_log: true, 
							ignore_bots: true,
							)
		@bot.debug= :debug
	end

	def run async=false
		@bot.run async
	end

	def setup_events
		setup_on_ready
		setup_on_message
	end

	def setup_bot_slash_commands
		setup_command_help
#		setup_command_translate
		setup_command_autotrans
		setup_command_languages
	end

	private

	def setup_on_ready
		@bot.ready do |event|
			@bot.debug("Ready event, bot connected as #{@bot.name}")

			@bot.listening= "#{@command_prefix}help"

			@bot.debug("Try to change nick to #{@name}")
			@bot.servers.each do |id, server|
				server.bot.nick=@bot.name
			end
		end
	end

	def setup_on_message
		@bot.message(start_with: 'xxx') do |event|
			@bot.debug(event.inspect)
		  event.respond 'Pong!'
		end
	end

	def setup_command_help
		@guild_ids.each do |server_id|
			@bot.register_application_command(:help, "#{@bot.name} commands list", server_id: server_id)
		end

		@bot.application_command(:help) do |event|
			@bot.debug("help command execution")
			embed = base_embed("Help", "All the commands of #{@bot.name}")
			@bot.debug(embed.inspect)

			embed.add_field(name: "#{@command_prefix}help", value: "Show this help command", inline: true)
			embed.add_field(name: "#{@command_prefix}translate [language] [text]",
											value: "Translate any text to any language", inline: false)
			embed.add_field(name: "#{@command_prefix}autotrans", 
											value: "List/set/unset automatic translation for the current channel.", inline: false)
			embed.add_field(name: "#{@command_prefix}languages", value: "List of supported languages", inline: false)

#			event.respond(content: text)
			event.respond(embeds: [embed], ephemeral: true, wait: false)


# #<Thread:0x00007f0d07434598 /home/zpeller/devel/discord/siditran-rb/sdt_bot.rb:98 run> terminated with exception (report_on_exception is true):
# /home/zpeller/devel/discord/siditran-rb/venv_siditran/rubygems/gems/discordrb-3.5.0/lib/discordrb/data/interaction.rb:775:in `delete': undefined method `delete_message' for nil:NilClass (NoMethodError)
#
#        @interaction.delete_message(@id)
#
#			Thread.new do
#        Thread.current[:discordrb_name] = "#{@current_thread}-temp-msg"
#				message = event.respond(embeds: [embed], ephemeral: false, wait: true)
#				@bot.debug(message.inspect)
#       await ctx.respond(embed=embed, ephemeral=True, delete_after=60.0)
#				sleep(60)
#				message.delete
#			end

		end
	end

	def setup_command_autotrans
		@guild_ids.each do |server_id|
			@bot.register_application_command(:autotrans, 'Automatic translation options', server_id: server_id) do |group| 
				group.subcommand(:status, 'Get automatic translation status')
				group.subcommand(:on, 'Turn automatic translation on for the current channel (admins only!)') do |sub|
					sub.string('target_lang', 'Language code, eg: en', required: true)
				end
				group.subcommand(:off, 'Turn automatic translation off for the current channel (admins only!)')
			end
		end

		# Status
		bot.application_command(:autotrans).subcommand(:status) do |event|
			autotrans_lang = @autotrans_config.get_channel_autotrans_status(event.server.name, event.channel.name)
			if not autotrans_lang
        embed = base_embed("Automatic translation status", "Automatic translation is turned off on channel ##{event.channel.name}")
			else
        embed = base_embed("Automatic translation status", "Automatic translation set to #{@supported_languages[autotrans_lang]} (#{autotrans_lang}) on channel ##{event.channel.name}")
			end

			autotrans_channels = @autotrans_config.list_autotrans_channels(event.server.name)
			channel_list = autotrans_channels.map {|channel_name, lang_code| "##{channel_name}:#{lang_code}" }.join(', ')
			embed.add_field(name: "Autotranslate channels", value: channel_list, inline: false)

			event.respond(embeds: [embed], ephemeral: true, wait: false)
		end

		# XXX BAN permission!
		# Turn autotrans on
		bot.application_command(:autotrans).subcommand(:on) do |event|
			target_lang = event.options['target_lang']
			if @supported_languages.has_key?(target_lang)
				@autotrans_config.set_channel_autotrans_status(event.server.name, event.channel.name, target_lang.downcase)
				embed = base_embed("Autotranslate on", "Automatic translation language changed to #{@supported_languages[target_lang]} (#{target_lang})")
			else
				@bot.debug("Illegal autotranslate lang: #{target_lang}")
				embed = base_embed("Autotranslate command failed", "Unsupported language: '#{target_lang}'. Use /languages to obtain a list of supported languages.")

			end
			event.respond(embeds: [embed], ephemeral: false, wait: false)
		end

		# XXX BAN permission!
		# Turn autotrans off
		bot.application_command(:autotrans).subcommand(:off) do |event|
			@autotrans_config.delete_channel_autotrans_status(event.server.name, event.channel.name)
			embed = base_embed("Autotranslate off", "Automatic translation turned off on channel #{event.channel.name}")
			event.respond(embeds: [embed], ephemeral: false, wait: false)
		end
	end

	def base_embed(title, description, color=0x1bd3f3, thumbnail_url=DISCORD_EMBED_THUMBNAIL_URL)
		return Discordrb::Webhooks::Embed.new(title: title, description: description, color: color,
                      thumbnail: Discordrb::Webhooks::EmbedThumbnail.new(url: thumbnail_url) )
	end


	def setup_command_languages
		@guild_ids.each do |server_id|
			@bot.register_application_command(:languages, "#{@bot.name} supported languages", server_id: server_id)
		end

		@bot.application_command(:languages) do |event|
			@bot.debug("languages command execution")

			embed = base_embed("Languages", "**Supported languages (Google translate)**")

			lang_list = ""
			@supported_languages.map {|language_code, language_display_name| "#{language_display_name} (#{language_code})"}.join(', ').gsub(/(.{1,260})(,+|$)/, "\\1|").split('|').each do |list_segment|
					embed.add_field(name: "", value: list_segment, inline: false)
			end
				
			event.respond(embeds: [embed], ephemeral: true, wait: false)
		end
	end

end
