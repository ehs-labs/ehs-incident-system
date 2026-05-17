require "base64"
require "openssl"
require "securerandom"

require_relative "envelope/version"

module Ehs
  # Envelope is a tiny library providing AES-256-GCM authenticated encryption
  # for PII fields shared between services via Kafka.
  #
  # Wire format:
  #
  #   v<key_version>:<nonce_b64>:<ciphertext_b64>:<tag_b64>
  #
  # The version prefix lets us rotate keys: producer writes with v2; consumers
  # are temporarily configured with both v1 and v2 keys; once all messages are
  # rewritten (one-shot replay job), v1 is retired.
  #
  # Usage:
  #
  #   cipher = Ehs::Envelope.new(
  #     keys: { "v1" => ENV.fetch("FIELD_CIPHER_KEY") },
  #     active_version: "v1"
  #   )
  #
  #   ct = cipher.encrypt("alice@example.com")        # => "v1:abc...:xyz...:tag..."
  #   pt = cipher.decrypt(ct)                          # => "alice@example.com"
  module Envelope
    class Error < StandardError; end
    class UnknownKeyVersion < Error; end
    class MalformedCiphertext < Error; end
    class InvalidKeyLength < Error; end

    KEY_LEN   = 32      # AES-256 → 32 bytes
    NONCE_LEN = 12      # 96-bit nonce recommended for GCM
    TAG_LEN   = 16

    class Cipher
      def initialize(keys:, active_version:)
        @keys = keys.transform_values { |k| coerce_key(k) }
        raise Error, "active_version #{active_version.inspect} not in keys" unless @keys.key?(active_version)

        @active_version = active_version
      end

      # Encrypts `plaintext` with the active key and returns the wire-format string.
      def encrypt(plaintext)
        return nil if plaintext.nil?

        key   = @keys[@active_version]
        nonce = SecureRandom.bytes(NONCE_LEN)
        cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
        cipher.key = key
        cipher.iv  = nonce
        cipher.auth_data = ""

        ct  = cipher.update(plaintext.to_s) + cipher.final
        tag = cipher.auth_tag

        [
          @active_version,
          Base64.strict_encode64(nonce),
          Base64.strict_encode64(ct),
          Base64.strict_encode64(tag)
        ].join(":")
      end

      # Decrypts a wire-format string. Raises if the embedded key version is unknown.
      def decrypt(wire)
        return nil if wire.nil?

        version, nonce_b64, ct_b64, tag_b64 = wire.split(":", 4)
        raise MalformedCiphertext, "expected 4 colon-separated parts" unless tag_b64

        key = @keys[version] or raise UnknownKeyVersion, version

        nonce = Base64.strict_decode64(nonce_b64)
        ct    = Base64.strict_decode64(ct_b64)
        tag   = Base64.strict_decode64(tag_b64)

        decipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
        decipher.key       = key
        decipher.iv        = nonce
        decipher.auth_tag  = tag
        decipher.auth_data = ""
        decipher.update(ct) + decipher.final
      rescue ArgumentError, OpenSSL::Cipher::CipherError => e
        raise MalformedCiphertext, e.message
      end

      private

      # Accepts either 32 raw bytes or a base64-encoded 32-byte key.
      def coerce_key(value)
        bytes = value.bytesize == KEY_LEN ? value : Base64.strict_decode64(value)
        raise InvalidKeyLength, "expected #{KEY_LEN} bytes, got #{bytes.bytesize}" unless bytes.bytesize == KEY_LEN

        bytes
      rescue ArgumentError => e
        raise InvalidKeyLength, "could not parse key: #{e.message}"
      end
    end

    # Convenience: build a Cipher from a hash of versioned keys.
    def self.new(keys:, active_version:)
      Cipher.new(keys: keys, active_version: active_version)
    end
  end
end
