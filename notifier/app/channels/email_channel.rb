# frozen_string_literal: true

require 'mail'

module Channels
  module EmailChannel
    module_function

    def deliver(user:, log:)
      Mail.deliver do
        to       user.email
        from     ENV.fetch('SMTP_FROM', 'no-reply@ehs.local')
        subject  log.title
        body     "#{log.body}\n\nOpen: #{ENV.fetch('APP_HOST', 'http://localhost:5173')}#{log.link}"

        delivery_method :smtp,
                        address: ENV.fetch('SMTP_HOST', 'mailcatcher'),
                        port: Integer(ENV.fetch('SMTP_PORT', '1025')),
                        user_name: ENV['SMTP_USER'],
                        password: ENV['SMTP_PASSWORD'],
                        authentication: ENV['SMTP_USER'] ? :plain : nil,
                        enable_starttls_auto: ENV['SMTP_PORT']&.to_i == 587
      end

      log.mark_sent!(:email)
    rescue StandardError => e
      log.mark_failed!(:email, e.message)
      raise
    end
  end
end
