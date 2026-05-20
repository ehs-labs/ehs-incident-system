# frozen_string_literal: true

require 'jwt'

module Notifier
  module Web
    # Validates JWTs minted by core-api. Same HS256 secret on both sides
    # (mounted from K8s Secret in prod, .env var in dev).
    module JwtValidator
      module_function

      def user_id_from(token)
        payload, _header = JWT.decode(
          token,
          secret,
          true,
          algorithm: 'HS256',
          verify_expiration: true
        )
        payload['sub'] || payload['user_id']
      rescue JWT::DecodeError
        nil
      end

      def secret
        ENV['JWT_SECRET'] ||
          (path = ENV['JWT_SECRET_FILE']) && File.read(path).strip ||
          raise('JWT_SECRET not configured')
      end
    end
  end
end
