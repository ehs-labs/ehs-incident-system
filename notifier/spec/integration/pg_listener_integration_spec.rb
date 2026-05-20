# frozen_string_literal: true

# Integration-style spec — exercises PgListener against a real Postgres
# connection over LISTEN/NOTIFY. The listener thread runs in-process; we send a
# NOTIFY from the shared DB connection and assert WsServer.push fires within 1s.
# Pattern: hold a Mutex+ConditionVariable to wait for the stubbed push call.

require 'spec_helper'
require_relative '../../app/web/ws_server'
require_relative '../../app/web/pg_listener'

RSpec.describe 'Notifier::Web::PgListener integration', :integration do
  it 'delivers a NOTIFY payload to WsServer.push within 1s' do
    received = Queue.new
    allow(Notifier::Web::WsServer).to receive(:push) { |uid, log| received << [uid, log] }

    listener_db = Sequel.connect(ENV.fetch('DATABASE_URL'), max_connections: 1)
    listener_thread = Thread.new do
      listener_db.listen(Notifier::Web::PgListener::CHANNEL, loop: true) do |_chan, _pid, raw|
        Notifier::Web::PgListener.handle(raw)
      end
    rescue Sequel::DatabaseDisconnectError
      # expected on teardown
    end

    # Give LISTEN a moment to register before NOTIFY fires.
    sleep 0.1

    payload = JSON.generate(user_id: '99', log: { title: 'hello', body: 'world' })
    DB.notify(:delivery_log_appended, payload: payload)

    uid, log = nil
    Timeout.timeout(1) { uid, log = received.pop }

    expect(uid).to eq('99')
    expect(log).to eq({ title: 'hello', body: 'world' })
  ensure
    listener_thread&.kill
    listener_db&.disconnect
  end
end
