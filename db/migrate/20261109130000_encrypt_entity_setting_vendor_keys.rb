# M3 (OWASP review 2026-11): each firm's own third-party credentials (WhatsApp token, Digio client secret, OpenAI /
# Anthropic / Gemini / OpenRouter API keys) were stored in entity_settings as plain text, so any database copy (a
# developer laptop, a leaked backup) let someone use a firm's accounts at its expense. EntitySetting now `encrypts`
# them with the app's existing Active Record encryption keys (as ZohoSignConnection already does).
#
# Done in one migration, not a rake task run after deploy: the columns are widened and the existing values encrypted
# before the new code serves a request, so there is no window where the app finds a plain value it can't decrypt.
# Tiny data (production copy 2026-11-09: 3 WhatsApp tokens, 12 Digio secrets, 1 Anthropic key).
#
# string → text: an encrypted value is the base64 of the ciphertext plus a JSON header — about 4/3 of the key plus
# ~60 characters — so a 255-character string column would overflow on longer keys.
class EncryptEntitySettingVendorKeys < ActiveRecord::Migration[8.1]
  COLUMNS = %w[whatsapp_token digio_client_secret openai_api_key anthropic_api_key gemini_api_key openrouter_api_key].freeze

  def up
    # Widen the string columns (whatsapp_token is already text)
    (COLUMNS - ["whatsapp_token"]).each { |column| change_column :entity_settings, column, :text }

    # An empty string can't be decrypted once the column is encrypted (ActiveRecord::Encryption::Errors::Decryption),
    # and '' and NULL both mean "no key" (SupportAgent's SQL tests IS NOT NULL AND != ''), so blanks become NULL
    COLUMNS.each do |column|
      quoted = connection.quote_column_name(column)
      execute("UPDATE entity_settings SET #{quoted} = NULL WHERE #{quoted} = ''")
    end

    # Encrypt each existing plain value with the same encryptor and keys `encrypts` uses (non-deterministic)
    each_value do |id, column, value|
      next if encrypted?(value)

      write_value(id, column, ActiveRecord::Encryption.encryptor.encrypt(value))
    end
  end

  def down
    each_value do |id, column, value|
      next unless encrypted?(value)

      write_value(id, column, ActiveRecord::Encryption.encryptor.decrypt(value))
    end
    (COLUMNS - ["whatsapp_token"]).each { |column| change_column :entity_settings, column, :string }
  end

  private

  # Every non-blank value of the listed columns: [id, column, value]
  def each_value
    COLUMNS.each do |column|
      quoted = connection.quote_column_name(column)
      connection.select_rows("SELECT id, #{quoted} FROM entity_settings WHERE #{quoted} IS NOT NULL AND #{quoted} <> ''").each do |id, value|
        yield id, column, value
      end
    end
  end

  # A value written by Active Record encryption is a JSON envelope with "p" (payload) and "h" (headers)
  def encrypted?(value)
    parsed = JSON.parse(value.to_s)
    parsed.is_a?(Hash) && parsed.key?("p") && parsed.key?("h")
  rescue JSON::ParserError
    false
  end

  # (not "write": that is ActiveRecord::Migration#write, used for the progress lines)
  def write_value(id, column, value)
    execute("UPDATE entity_settings SET #{connection.quote_column_name(column)} = #{connection.quote(value)} WHERE id = #{id.to_i}")
  end
end
