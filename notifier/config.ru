# frozen_string_literal: true

# config.ru — Rack entry point for the notifier (HTTP + WebSocket).

require_relative 'config/boot'
require_relative 'app/web/app'
require_relative 'app/web/pg_listener'

# Only the Falcon web process loads this file; the Karafka container boots from
# `karafka.rb`. Starting the listener here means it lives in the same process
# that owns the WebSocket sessions.
Notifier::Web::PgListener.start!

run Notifier::Web::App
