# config.ru — Rack entry point for the notifier (HTTP + WebSocket).

require_relative "config/boot"
require_relative "app/web/app"

run Notifier::Web::App
