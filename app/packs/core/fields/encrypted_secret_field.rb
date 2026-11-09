require "administrate/field/base"

# M3 (OWASP 2026-11): a firm's third-party credential (WhatsApp token, Digio secret, LLM API keys), stored encrypted
# (EntitySetting `encrypts`). Shown masked like ObfuscatedField — last 3 characters — with a hint saying why, so an
# admin doesn't read the stars as a broken or empty value. The edit form is unchanged (super users only).
class EncryptedSecretField < Administrate::Field::Base
  def to_s
    data
  end

  # "******abc" for a set value, "" when there is none
  def masked
    value = data.to_s
    value.empty? ? "" : value.last(3).rjust(value.length, "*")
  end
end
