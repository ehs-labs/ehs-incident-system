# ============================================================================
# FieldCipher — AES-256-GCM envelope cipher used to encrypt PII before it
# crosses the users.v1 Kafka topic boundary. The same key is mounted into
# the notifier service so it can decrypt on consume.
#
# Wire format: "v<key_version>:<nonce_b64>:<ciphertext_b64>:<tag_b64>"
# Defined in shared/envelope/lib/ehs/envelope.rb.
# ============================================================================

require "ehs/envelope"

module FieldCipher
  ACTIVE_VERSION = ENV.fetch("FIELD_CIPHER_ACTIVE_VERSION", "v1").freeze

  # Lazily build the cipher so app boot doesn't fail when running rake tasks
  # that don't need it (e.g. assets:precompile in CI without the key wired).
  def self.instance
    @instance ||= Ehs::Envelope.new(
      keys:           { ACTIVE_VERSION => ENV.fetch("FIELD_CIPHER_KEY") },
      active_version: ACTIVE_VERSION
    )
  end

  def self.encrypt(plaintext)
    instance.encrypt(plaintext)
  end

  def self.decrypt(wire)
    instance.decrypt(wire)
  end

  def self.reset!
    @instance = nil
  end
end
