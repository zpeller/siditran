# Importing the necessary translation and language detection libraries

require_relative 'flags_langs'
require 'google/cloud/translate/v3'

class Translator
	def initialize(logger)
		@logger = logger

		project_id = ENV.fetch("GOOGLE_TRANSLATE_PROJECT_ID")
		location = ENV.fetch("GOOGLE_TRANSLATE_LOCATION")

		@translation_parent = "projects/#{project_id}/locations/#{location}"
		@translation_client = ::Google::Cloud::Translate::V3::TranslationService::Client.new
	end

	def translate_text(text, target_language_code = "en")

		@logger.debug("translate text called")

		contents = text.kind_of?(Array) ? text : [text]

		response = @translation_client.translate_text(
			request={
				"parent": @translation_parent,
				"contents": contents,
				"mime_type": "text/plain",  # mime types: text/plain, text/html
				"target_language_code": target_language_code,
			}
		)

		response.translations.each { |translation|
			@logger.info("Translated text: #{translation.translated_text}")
		}
#		for translation in response.translations:
#			@logger.info(f"Translated text: {translation.translated_text}")

		return response
	end

	def get_supported_languages()
		# Supported language codes: https://cloud.google.com/translate/docs/languages
		response = @translation_client.get_supported_languages(
				request={
					"display_language_code": "en", 
					"parent": @translation_parent
				})
#		p response

		@logger.debug("Supported Languages:")
		response.languages.each { |language| @logger.debug("Language Code: #{language.language_code}") }

		supported_languages={}
		supported_languages = response.languages.map { |l| [l.language_code, l.display_name] }.to_h

		return supported_languages
	end

	def detect_language(source_text)
		# Detail on supported types can be found here:
		# https://cloud.google.com/translate/docs/supported-formats
		response = @translation_client.detect_language(
				request = {
					"content": source_text,
					"parent": @translation_parent,
					"mime_type": "text/plain",  # mime types: text/plain, text/html
				}
		)

		# Display list of detected languages sorted by detection confidence.
		# The most probable language is first.
		response.languages.each { |language| 
			@logger.info("Language code: #{language.language_code} Confidence: #{language.confidence}")
		}

		return response.languages[0]
	end

end
