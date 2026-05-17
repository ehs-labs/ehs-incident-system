class UsersConsumer < Karafka::BaseConsumer
  # CDC consumer for users.v1 (log-compacted). Decrypts PII fields with
  # ehs-envelope and writes/upserts into users_mirror. Tombstones (event=nil
  # or deleted=true) drop the row from the mirror.
  def consume
    messages.each do |message|
      event = message.payload

      # Tombstone with nil payload (raw_payload was nil)
      if event.nil?
        tombstone_user_id = message.key
        Notifier::Models::UserMirror.where(user_id: tombstone_user_id).delete if tombstone_user_id
        next
      end

      user_id = event.fetch("user_id")

      if event["deleted"]
        Notifier::Models::UserMirror.where(user_id: user_id).delete
        next
      end

      Notifier::Models::UserMirror.upsert(
        user_id:          user_id,
        org_id:           event["org_id"],
        role:             event["role"].to_s,
        name:             FIELD_CIPHER.decrypt(event["name_enc"]),
        email:            FIELD_CIPHER.decrypt(event["email_enc"]),
        telegram_chat_id: FIELD_CIPHER.decrypt(event["telegram_chat_id_enc"]),
        prefs:            event["prefs"] || {},
        # AvroTurf decodes timestamp-millis as a Ruby Time, so pass through directly.
        updated_at:       coerce_time(event.fetch("updated_at"))
      )

    rescue StandardError => e
      Karafka.logger.error("[UsersConsumer] failed offset=#{message.offset}: #{e.class}: #{e.message}")
      raise
    end
  end

  private

  # Avro's `timestamp-millis` logical type is decoded to a Ruby Time by
  # AvroTurf; older payloads that used a plain `long` come through as Integer.
  # Be defensive so we accept both during the rollout.
  def coerce_time(value)
    case value
    when Time    then value
    when Integer then Time.at(value / 1000.0)
    else              Time.now.utc
    end
  end
end
