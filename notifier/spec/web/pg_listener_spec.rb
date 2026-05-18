require "spec_helper"
require_relative "../../app/web/ws_server"
require_relative "../../app/web/pg_listener"

RSpec.describe Notifier::Web::PgListener do
  describe ".handle" do
    it "pushes the log payload to WsServer for the named user" do
      payload = JSON.generate(user_id: "42", log: { title: "T", body: "B" })
      expect(Notifier::Web::WsServer).to receive(:push).with("42", { title: "T", body: "B" })
      described_class.handle(payload)
    end

    it "swallows and logs malformed JSON without raising" do
      expect(Notifier::Web::WsServer).not_to receive(:push)
      expect { described_class.handle("not-json{") }.not_to raise_error
    end

    it "swallows and logs payloads missing expected keys without raising" do
      # JSON parses fine but :user_id is nil; downstream WsServer.push runs but
      # the listener must not crash regardless.
      allow(Notifier::Web::WsServer).to receive(:push)
      expect { described_class.handle('{"unrelated":true}') }.not_to raise_error
    end
  end
end
