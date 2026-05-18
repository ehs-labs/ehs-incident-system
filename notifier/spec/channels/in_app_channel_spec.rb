require "spec_helper"

RSpec.describe Channels::InAppChannel do
  let(:user)    { Notifier::Models::UserMirror.new(user_id: "7", name: "U", email: "u@x", org_id: "1", role: "WORKER", updated_at: Time.now.utc) }
  let(:payload) { { title: "T", body: "B" } }
  let(:log)     { double("DeliveryLog", values: payload) }

  before do
    allow(DB).to receive(:notify)
  end

  it "no-ops the WS push when the web server module is not loaded, but still emits NOTIFY and marks sent" do
    hide_const("Notifier::Web::WsServer") if defined?(Notifier::Web::WsServer)
    expect(DB).to receive(:notify).with(:delivery_log_appended, hash_including(:payload))
    expect(log).to receive(:mark_sent!).with(:in_app)
    described_class.deliver(user: user, log: log)
  end

  it "pushes via the WS server when it IS loaded and also emits NOTIFY" do
    ws_stub = Module.new { def self.push(_user_id, _payload); end }
    stub_const("Notifier::Web::WsServer", ws_stub)
    expect(Notifier::Web::WsServer).to receive(:push).with(user.user_id, payload)
    expect(DB).to receive(:notify).with(:delivery_log_appended, hash_including(:payload))
    expect(log).to receive(:mark_sent!).with(:in_app)
    described_class.deliver(user: user, log: log)
  end

  it "emits NOTIFY with a JSON payload carrying user_id and log values" do
    expect(DB).to receive(:notify) do |channel, opts|
      expect(channel).to eq(:delivery_log_appended)
      parsed = JSON.parse(opts[:payload], symbolize_names: true)
      expect(parsed[:user_id]).to eq("7")
      expect(parsed[:log]).to eq(payload)
    end
    allow(log).to receive(:mark_sent!)
    described_class.deliver(user: user, log: log)
  end
end
