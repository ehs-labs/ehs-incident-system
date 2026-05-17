require "sinatra/base"
require "sinatra/json"
require "async/websocket/adapters/rack"

require_relative "ws_server"
require_relative "jwt_validator"

module Notifier
  module Web
    class App < Sinatra::Base
      configure do
        set :show_exceptions, :after_handler
        set :raise_errors, false
        disable :static
      end

      # ------------------------------------------------------------------- HC
      get "/healthz" do
        json status: "ok", time: Time.now.utc.iso8601
      end

      # ------------------------------------------------------------------- WS
      # wss://notifier.../ws?token=<jwt>
      get "/ws" do
        token = params["token"] or halt 401, "missing token"
        user_id = JwtValidator.user_id_from(token) or halt 401, "invalid token"

        Async::WebSocket::Adapters::Rack.open(env, protocols: ["ehs.v1"]) do |ws|
          WsServer.handle(ws, user_id: user_id)
        end || halt(400, "websocket upgrade required")
      end
    end
  end
end
