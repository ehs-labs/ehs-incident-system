require_relative "spec_helper"

RSpec.describe "users.v1 envelope encryption" do
  # Build a dedicated cipher instance for the smoke tests so we are not coupled
  # to the FIELD_CIPHER constant constructed at boot time. This also lets us
  # exercise wrong-key behaviour without mutating global state.
  let(:key) { ENV.fetch("FIELD_CIPHER_KEY") }
  let(:cipher) { Ehs::Envelope.new(keys: { "v1" => key }, active_version: "v1") }

  it "encrypts to the versioned wire format" do
    ct = cipher.encrypt("denis@example.com")
    expect(ct).to match(/\Av1:/)
    # Four colon-separated parts: version, nonce, ciphertext, auth tag
    expect(ct.split(":").size).to eq(4)
  end

  it "decrypts back to the original plaintext with the correct key" do
    plain = "denis@example.com"
    ct = cipher.encrypt(plain)
    expect(cipher.decrypt(ct)).to eq(plain)
  end

  it "raises on decryption with the wrong key" do
    plain = "denis@example.com"
    ct = cipher.encrypt(plain)

    wrong_key = Base64.strict_encode64(([1] * 32).pack("C*"))
    bad_cipher = Ehs::Envelope.new(keys: { "v1" => wrong_key }, active_version: "v1")

    expect { bad_cipher.decrypt(ct) }.to raise_error(Ehs::Envelope::MalformedCiphertext)
  end

  it "returns nil for nil plaintext" do
    expect(cipher.encrypt(nil)).to be_nil
  end

  it "returns nil for nil wire value" do
    expect(cipher.decrypt(nil)).to be_nil
  end
end
