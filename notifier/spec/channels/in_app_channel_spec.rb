require "spec_helper"

RSpec.describe Channels::InAppChannel do
  let(:user) { Notifier::Models::UserMirror.new(user_id: "7", name: "U", email: "u@x", org_id: "1", role: "WORKER", updated_at: Time.now.utc) }
  let(:log)  { double("DeliveryLog", to_h: { title: "T", body: "B" }) }

  it "no-ops the WS push when the web server module is not loaded and marks sent" do
    hide_const("Notifier::Web::WsServer") if defined?(Notifier::Web::WsServer)
    expect(log).to receive(:mark_sent!).with(:in_app)
    described_class.deliver(user: user, log: log)
  end

  it "pushes via the WS server when it IS loaded" do
    stub_const("Notifier::Web::WsServer", Class.new)
    expect(Notifier::Web::WsServer).to receive(:push).with(user.user_id, log.to_h)
    expect(log).to receive(:mark_sent!).with(:in_app)
    described_class.deliver(user: user, log: log)
  end
end
