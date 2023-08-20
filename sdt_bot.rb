require 'discordrb'
require_relative 'sdt_config'
require_relative 'translator'
require_relative 'flags_langs'

DISCORD_EMBED_THUMBNAIL_URL='https://media.discordapp.net/attachments/785041781472624664/826870778091274320/discord-avatar-512_1.png?width=369&height=369'

class TranslationResult
	attr_accessor :content, :embeds, :detected_language
	def initialize
		@content = nil
		@embeds = []
		@detected_language = nil
	end
end

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
							ignore_bots: false,
							)
		@bot.debug= :debug
	end

	def run async=false
		@bot.run async
	end

	def setup_events
		@bot.ready do |event| handle_on_ready_event(event) end
		@bot.message do |event| handle_on_message_event(event) end
		@bot.reaction_add do |event| handle_on_reaction_event(event) end
	end

	def setup_bot_slash_commands
		setup_command_autotrans
		setup_command_help
		setup_command_languages
		setup_command_translate
	end

	private

	def handle_on_ready_event(event)
		@bot.debug("Ready event, bot connected as #{event.bot.name} (orig bot name: #{@bot.name})")

		@bot.listening= "#{@command_prefix}help"

		@bot.debug("Try to change nick to #{@name}")
		@bot.servers.each do |id, server|
			server.bot.nick=@bot.name
		end
		list_members(event.bot.servers)
	end

	def list_members(servers)
		servers.each do |server_id, server|
			@bot.debug("#{server.name} (id: #{server_id}): #{server.member_count} users")
			server.members.each do |member|
#				@bot.debug(member.inspect)
				@bot.debug("id:#{member.id} nick:#{member.nick} username:#{member.username} display:#{member.display_name}")
#				@bot.debug("id:#{member.id} nick:#{member.nick} username:#{member.username} display:#{member.display_name}, max role: #{member.highest_role.inspect}")
			end
		end
	end

	def handle_cross_channel_translation(event)
		@bot.debug("content: #{event.message.content}")
		@bot.debug("Attachments: #{event.message.attachments}")
		@bot.debug("Embeds: #{event.message.embeds}")

		cross_channel = get_text_channel(event.server, ENV.fetch('XTRANS_DST'))

		if event.message.content.match?('^https?://')
			webhook = cross_channel.create_webhook(event.author.name)

			begin
				webhook.execute(content: event.message.content, username: "#{event.author.display_name} (by #{bot.name} autotranslator)", avatar_url: event.author.avatar_url, wait: true)
			ensure
				webhook.delete()
			end
			return
		end

		if event.message.embeds.length > 0
			@bot.debug("Embeds: #{event.message.embeds[0].inspect}")
#					print_embed(event.message.embeds[0])
		end

		translation_result = translate_message_elements(event.message, 'de')
#				cross_channel = discord.utils.get(@bot.get_all_channels(), name=ENV.fetch('XTRANS_DST'))

		webhook = cross_channel.create_webhook(event.author.name)

		begin
			if not translation_result.content and translation_result.embeds.length == 0
				webhook_embeds = copy_embed(event.message.embeds)
				if event.message.attachments.length > 0
					webhook_embeds += copy_attachments(event.message.attachments)
				end
				webhook.execute(content: '', embeds: webhook_embeds, username: "#{event.message.author.display_name} (by #{bot.name} autotranslator)", avatar_url: event.author.avatar_url, wait: true)
			else
				if event.message.attachments.length > 0
					translation_result.embeds += copy_attachments(event.message.attachments)
				end
				webhook.execute(content: translation_result.content, embeds: translation_result.embeds, username: "#{event.author.display_name} (by #{bot.name} autotranslator)", avatar_url: event.author.avatar_url, wait: true)
			end
		ensure
			webhook.delete()
		end
	end

	def handle_on_message_event(event)
#		@bot.debug(event.inspect)
		@bot.debug(event.message)
		@bot.debug("#{event.channel}:#{event.author}:#{event.message.content}")

		if event.author.bot_account?
			@bot.debug("Message from bot, ignored")
			return
		end

		if event.channel.pm?
			embed = base_embed("Can't respond to direct messages", "Sorry, currently I can't respond to direct messages or commands on direct channels. Just send any command to me on a public channel where I'm available, try /help first!\n\nMy answers will be visible to you only, or they will disappear in a minute or two, so we will not disturb the channel.", thumbnail_url: nil)
			event.channel.send_embed('', [embed])
			return
		end

		if not event.server
			@bot.debug("No guild info, abort processing")
			return
		end

		if event.message.content.length > 0 and @command_prefix == event.message.content[0]
			@bot.debug("Bot command, abort processing")
			return
		end

		# XXX Temporary cross send
		if ENV.fetch("ENABLE_XTRANS") == "1" and event.channel.name == ENV.fetch("XTRANS_SRC")
			handle_cross_channel_translation(event)
		end


		target_lang = @autotrans_config.get_channel_autotrans_status(event.server.name, event.channel.name)
		return if target_lang == nil

		sample_text = event.message.content
		event.message.embeds.each do |embed|
			@bot.debug("Embed: #{embed.title}:#{embed.description}")
			sample_text += ' ' + embed.title if embed.title.length > 0
			sample_text += ' ' + embed.description if embed.description.length > 0
			if embed.fields
				embed.fields.each do |field|
					sample_text += ' ' + field.name if field.name.length > 0
					text += ' ' + field.value if field.value.length > 0
					break
				end
			end
			break
		end

		if sample_text.length == 0
			@bot.debug("Text too short, not translating")
			return
		end

		detected_lang = @translator.detect_language(sample_text)

		if detected_lang.confidence < 0.75
			@bot.debug("Detected lang confidence (#{detected_lang.confidence}) too low, not translating")
			return
		end

		return if detected_lang.language_code == target_lang

		translation_result = translate_message_elements(event.message, target_lang)

		if not translation_result.content and translation_result.embeds.length == 0
			@bot.debug("Nothing translated")
			return
		end

		webhook = event.channel.create_webhook(event.author.name)

		begin
			webhook.execute(content: translation_result.content, embeds: translation_result.embeds, username: "#{event.author.display_name} (by #{bot.name} autotranslator [#{detected_lang.language_code}->#{target_lang}])", avatar_url: event.author.avatar_url, wait: true)
		ensure
			webhook.delete()
		end
	end

	def handle_on_reaction_event(event)
#		@bot.debug(event.inspect)
		@bot.debug(event.message)

		if not FLAGS_LANGS.include?(event.emoji.name)
			@bot.debug("Unsupported language emoji: '#{event.emoji.name}'")
			return
		end

		@bot.debug("emoji: #{FLAGS_LANGS[event.emoji.name]}")

		target_lang = FLAGS_LANGS[event.emoji.name]['langs'][0]
		if not @supported_languages.include?(target_lang)
			@bot.debug("Target lang (#{target_lang}) not supported")
			return
		end

#		channel = bot.get_channel(event.message.channel_id)
		if not event.channel
			@bot.debug("Most likely DM. event.message user_id: #{event.message.user_id}")
#				user = bot.fetch_user(event.message.user_id)
			@bot.debug("user: #{user}")
			channel = @bot.pm(event.user)
		else
			channel = event.channel
		end

#			message = await channel.fetch_message(event.message.message_id)
		@bot.debug("target lang: #{target_lang}, msg: #{event.message.content}")

		translation_result = translate_message_elements(event.message, target_lang, true)
		if not translation_result.content and (not translation_result.embeds or translation_result.embeds.length == 0)
			@bot.debug("Nothing to translate")
			return
		end

		@bot.debug(translation_result.inspect)
		if translation_result.content and translation_result.content.length > 0
			event.channel.send_temporary_message(content="[#{translation_result.detected_language}->#{target_lang}] #{translation_result.content}", 120.0, false, translation_result.embeds, nil, nil, event.message)
		else
			event.channel.send_temporary_message(translation_result.content, 120.0, false, translation_result.embeds, nil, nil, event.message)
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
#				@interaction.delete_message(@id)
#
#			Thread.new do
#				Thread.current[:discordrb_name] = "#{@current_thread}-temp-msg"
#				message = event.respond(embeds: [embed], ephemeral: false, wait: true)
#				@bot.debug(message.inspect)
#			 await ctx.respond(embed=embed, ephemeral=True, delete_after=60.0)
#				sleep(60)
#				message.delete
#			end

		end
	end

	def setup_command_autotrans
		@guild_ids.each do |server_id|
			@bot.register_application_command(:autotrans, 'Automatic translation options', server_id: server_id) do |group| 
				group.subcommand(:status, 'Get automatic translation status')
				group.subcommand(:on, 'Turn automatic translation on for the current channel (admins only!)') do |subcmd|
					subcmd.string('target_lang', 'Language code, eg: en', required: true)
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

		# Turn autotrans on
		bot.application_command(:autotrans).subcommand(:on) do |event|
			if not event.user.highest_role.permissions.manage_channels
				embed = base_embed("No permission", "You don't have the necessary permission ('Manage channels', or 'Administrator') to change automatic translation settings for the channel", thumbnail_url: nil)
				event.respond(embeds: [embed], ephemeral: true, wait: false)
				return
			end
				
#			@bot.debug("mmax role perm: #{event.user.highest_role.permissions.inspect}")
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

		# Turn autotrans off
		bot.application_command(:autotrans).subcommand(:off) do |event|
			if not event.user.highest_role.permissions.manage_channels
				embed = base_embed("No permission", "You don't have the necessary permission ('Manage channels', or 'Administrator') to change automatic translation settings for the channel", thumbnail_url: nil)
				event.respond(embeds: [embed], ephemeral: true, wait: false)
				return
			end
				
			@autotrans_config.delete_channel_autotrans_status(event.server.name, event.channel.name)
			embed = base_embed("Autotranslate off", "Automatic translation turned off on channel #{event.channel.name}")
			event.respond(embeds: [embed], ephemeral: false, wait: false)
		end
	end

	def setup_command_languages
		@guild_ids.each do |server_id|
			@bot.register_application_command(:languages, "#{@bot.name} supported languages", server_id: server_id)
		end

		@bot.application_command(:languages) do |event|
			@bot.debug("languages command execution")

			embed = base_embed("Languages", "**Supported languages (Google translate)**")

			@supported_languages.map {|language_code, language_display_name| "#{language_display_name} (#{language_code})"}.join(', ').gsub(/(.{1,260})(,+|$)/, "\\1|").split('|').each do |list_segment|
					embed.add_field(name: "", value: list_segment, inline: false)
			end
				
			event.respond(embeds: [embed], ephemeral: true, wait: false)
		end
	end

	def setup_command_translate
		@guild_ids.each do |server_id|
			@bot.register_application_command(:translate, "Translate text to a chosen language, eg. /translate es Hello", server_id: server_id) do |cmd|
				cmd.string('target_lang', 'Language code, eg: en', required: true)
				cmd.string('text', 'Text to translate (max 250 characters)', required: true)
			end
		end

		@bot.application_command(:translate) do |event|
			target_lang = event.options['target_lang']
			text = event.options['text']
			@bot.debug("Translate command execution, lang: #{target_lang} text: #{text}")

			if @supported_languages.include?(target_lang)
				response = @translator.translate_text(text, target_lang)
				@bot.debug(response)
				msg = response.translations[0].translated_text
				detected_lang = response.translations[0].detected_language_code

				embed = base_embed("", "[trans:#{detected_lang}->#{target_lang}] #{msg}", thumbnail_url:nil)
			else
				@bot.debug("Translate target lang '#{target_lang}' not supported")
				embed = base_embed("Translation failed", "Translation is not supported to #{target_lang}", thumbnail_url: nil)
			end
			event.respond(embeds: [embed], ephemeral: true, wait: false)
		end
	end

	def translate_message_elements(message, target_lang, prefer_embed=false)
		translation_result = TranslationResult.new

		if message.embeds.length == 0
			text = message.content
		else
			@bot.debug("Embeds exist")
			# Single image urls often appear as message.content, while they are not real text, so we ignore 
			# those if we also have embeds
			if message.content.length > 0 and not message.content.start_with?('http://') and not message.content.start_with?('https://')
				text = [message.content]
				@bot.debug("message.content: #{text}")
			else
				text = []
			end
		end

		message.embeds.each do |embed|
			@bot.debug("Embed: #{embed.title}:#{embed.description}")
			text += [embed.title] if embed.title and embed.title.length > 0 
			text += [embed.description] if embed.description and embed.description.length > 0 
			if embed.fields
				embed.fields.each do |field|
					@bot.debug("Embed field: #{field.name}:#{field.value}")
					text += [field.name] if field.name and field.name.length > 0 
					text += [field.value] if field.value and field.value.length > 0 
				end
			end
		end

		@bot.debug("text: #{text}")
		if text.length == 0
			@bot.debug("Message too short, not translating")
			return translation_result
		end

		response = @translator.translate_text(text, target_lang)

		translation_result.detected_language = response.translations[0].detected_language_code

		@bot.debug("embeds: #{message.embeds}")

		if message.embeds.length == 0
			dst_text = response.translations[0].translated_text
			if prefer_embed
				translation_result.embeds = [base_embed("[#{translation_result.detected_language}->#{target_lang}]", dst_text, thumbnail_url: nil)]
			else
				translation_result.content = dst_text
			end
		else
			if message.content.length > 0
				translation_result.content = response.translations[0].translated_text
				response.translations.shift
			end

			embeds = copy_embed(message.embeds)

			@bot.debug("orig: #{message.embeds.inspect}\nnew:  #{embeds}")

			embeds.each do |embed|
				@bot.debug("Changing embed: #{embed.title}:#{embed.description}")
				if embed.title.length > 0
					translation = response.translations.shift
					embed.title = translation.translated_text
				end
				if embed.description.length > 0
					translation = response.translations.shift
					embed.description = translation.translated_text
				end
				if embed.fields
					embed.fields.each do |field|
						@bot.debug("Changing embed field: #{field.name}:#{field.value}")
						if field.name.length > 0
							translation = response.translations.shift
							field.name = translation.translated_text
						end
						if field.value.length > 0
							translation = response.translations.shift
							field.value = translation.translated_text
						end
					end
				end
			end
			translation_result.embeds = embeds
		end
		return translation_result
	end

	def base_embed(title, description, color:0x1bd3f3, thumbnail_url:DISCORD_EMBED_THUMBNAIL_URL)
		@bot.debug("BASE_EMBED called, color: #{color} url: #{thumbnail_url}")
		return Discordrb::Webhooks::Embed.new(title: title, description: description, color: color,
			thumbnail: thumbnail_url ? Discordrb::Webhooks::EmbedThumbnail.new(url: thumbnail_url) : nil )
	end

	def copy_attachments(source_attachments)
		attachments=[]
		source_attachments.each do |attachment|
			embed = Discordrb::Webhooks::Embed.new
			embed.image = Discordrb::Webhooks::EmbedImage.new(url: attachment.url)
			attachments += [embed]
		end
		return attachments
	end

	def copy_embed(source_embeds)
		copy_embeds = []
		source_embeds.each do |source_embed|
			copy_embed = Discordrb::Webhooks::Embed.new(
				title: source_embed.title,
				description: source_embed.description,
				url: source_embed.url,
				timestamp: source_embed.timestamp,
				color: source_embed.color,
				colour: source_embed.colour,
				footer: source_embed.footer,
				image: source_embed.image,
				thumbnail: source_embed.thumbnail ? Discordrb::Webhooks::EmbedThumbnail.new(url: source_embed.thumbnail.url) : nil,
#				video: source_embed.video ? Discordrb::EmbedVideo.new : nil,
				video: nil,
				provider: nil, # XXX source_embed.provider,
				author: source_embed.author,
			)
			if source_embed.fields
				source_embed.fields.each do |field|
					copy_embed.add_field(name: field.name, value: field.value, inline: field.inline)
				end
			end
			copy_embeds += [copy_embed]
		end
		return copy_embeds
	end

	def get_text_channel(server, channel_name)
		return server.text_channels.filter {|channel| channel.name == channel_name}[0]
	end
end
