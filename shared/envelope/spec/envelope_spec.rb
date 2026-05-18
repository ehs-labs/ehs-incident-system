require "base64"
require_relative "../lib/ehs/envelope"

RSpec.describe Ehs::Envelope do
  let(:key_v1) { Base64.strict_encode64(SecureRandom.bytes(32)) }
  let(:key_v2) { Base64.strict_encode64(SecureRandom.bytes(32)) }

  describe "round-trip" do
    let(:cipher) { described_class.new(keys: { "v1" => key_v1 }, active_version: "v1") }

    it "encrypts and decrypts a string back to the original" do
      ct = cipher.encrypt("alice@example.com")
      expect(ct).to start_with("v1:")
      expect(cipher.decrypt(ct)).to eq("alice@example.com")
    end

    it "produces different ciphertexts for the same plaintext (random nonce)" do
      a = cipher.encrypt("hello")
      b = cipher.encrypt("hello")
      expect(a).not_to eq(b)
      expect(cipher.decrypt(a)).to eq("hello")
      expect(cipher.decrypt(b)).to eq("hello")
    end

    it "passes through nil" do
      expect(cipher.encrypt(nil)).to be_nil
      expect(cipher.decrypt(nil)).to be_nil
    end
  end

  describe "key rotation" do
    it "can decrypt v1 ciphertext while producing v2 ciphertext" do
      writer = described_class.new(keys: { "v1" => key_v1 }, active_version: "v1")
      old_ct = writer.encrypt("old-data")

      rotator = described_class.new(
        keys: { "v1" => key_v1, "v2" => key_v2 },
        active_version: "v2"
      )

      expect(rotator.decrypt(old_ct)).to eq("old-data")

      new_ct = rotator.encrypt("new-data")
      expect(new_ct).to start_with("v2:")
      expect(rotator.decrypt(new_ct)).to eq("new-data")
    end

    it "rejects ciphertext encrypted with an unknown key version" do
      v1_only = described_class.new(keys: { "v1" => key_v1 }, active_version: "v1")
      v2_ct   = described_class.new(keys: { "v2" => key_v2 }, active_version: "v2").encrypt("x")
      expect { v1_only.decrypt(v2_ct) }.to raise_error(Ehs::Envelope::UnknownKeyVersion)
    end

    # Rotation-drill scenarios — mirror the four phases in docs/flows/key-rotation.md.

    it "encrypts as v1 when only v1 key is present" do
      cipher = described_class.new(keys: { "v1" => key_v1 }, active_version: "v1")
      ct = cipher.encrypt("phase1-plaintext")
      expect(ct).to start_with("v1:")
      expect(cipher.decrypt(ct)).to eq("phase1-plaintext")
    end

    it "encrypts as v2 when keyring has v2 marked active" do
      cipher = described_class.new(
        keys: { "v1" => key_v1, "v2" => key_v2 },
        active_version: "v2"
      )
      ct = cipher.encrypt("phase2-plaintext")
      expect(ct).to start_with("v2:")
      expect(cipher.decrypt(ct)).to eq("phase2-plaintext")
    end

    it "decrypts v1 ciphertext when keyring holds both v1 and v2" do
      v1_cipher = described_class.new(keys: { "v1" => key_v1 }, active_version: "v1")
      ct_v1 = v1_cipher.encrypt("old-pii")

      dual_cipher = described_class.new(
        keys: { "v1" => key_v1, "v2" => key_v2 },
        active_version: "v2"
      )
      expect(dual_cipher.decrypt(ct_v1)).to eq("old-pii")
    end

    it "decrypts v2 ciphertext when keyring holds both v1 and v2" do
      dual_cipher = described_class.new(
        keys: { "v1" => key_v1, "v2" => key_v2 },
        active_version: "v2"
      )
      ct_v2 = dual_cipher.encrypt("new-pii")
      expect(dual_cipher.decrypt(ct_v2)).to eq("new-pii")
    end

    it "raises a clear error on a v1 ciphertext when only v2 is in the keyring (v1 retired)" do
      v1_cipher = described_class.new(keys: { "v1" => key_v1 }, active_version: "v1")
      ct_v1 = v1_cipher.encrypt("stale-pii")

      v2_only = described_class.new(keys: { "v2" => key_v2 }, active_version: "v2")
      expect { v2_only.decrypt(ct_v1) }.to raise_error(Ehs::Envelope::UnknownKeyVersion, "v1")
    end
  end

  describe "integrity" do
    it "rejects a tampered ciphertext (auth tag mismatch)" do
      cipher = described_class.new(keys: { "v1" => key_v1 }, active_version: "v1")
      ct = cipher.encrypt("important")
      parts = ct.split(":")
      raw = Base64.strict_decode64(parts[2])
      raw[0] = raw[0].ord == 0 ? 1.chr : 0.chr   # flip one byte
      parts[2] = Base64.strict_encode64(raw)
      tampered = parts.join(":")

      expect { cipher.decrypt(tampered) }.to raise_error(Ehs::Envelope::MalformedCiphertext)
    end
  end

  describe "input validation" do
    it "raises when active_version is missing from keys" do
      expect {
        described_class.new(keys: { "v1" => key_v1 }, active_version: "v9")
      }.to raise_error(Ehs::Envelope::Error)
    end

    it "raises when a key is the wrong length" do
      expect {
        described_class.new(keys: { "v1" => "short" }, active_version: "v1")
      }.to raise_error(Ehs::Envelope::InvalidKeyLength)
    end
  end
end
