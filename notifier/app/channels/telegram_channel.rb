require "telegram/bot"

module Channels
  module TelegramChannel
    module_function

    def deliver(user:, log:)
      token = ENV["TELEGRAM_BOT_TOKEN"]
      if token.nil? || token.empty?
        log.mark_failed!(:telegram, "TELEGRAM_BOT_TOKEN not configured")
        return
      end

      Telegram::Bot::Client.run(token) do |bot|
        bot.api.send_message(
          chat_id: user.telegram_chat_id,
          text:    "*#{log.title}*\n#{log.body}\n#{ENV.fetch('APP_HOST', 'http://localhost:5173')}#{log.link}",
          parse_mode: "Markdown"
        )
      end

      log.mark_sent!(:telegram)
    rescue StandardError => e
      log.mark_failed!(:telegram, e.message)
      raise
    end
  end
end
