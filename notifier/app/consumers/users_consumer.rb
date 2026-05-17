class UsersConsumer < Karafka::BaseConsumer
  # CDC consumer for users.v1 (log-compacted). Decrypts PII fields with
  # ehs-envelope and writes/upserts into users_mirror. Tombstones (deleted=true)
  # drop the row from the mirror.
  def consume
    messages.each do |message|
      event   = message.payload
      user_id = event.fetch("user_id")

      if event["deleted"]
        Notifier::Models::UserMirror.where(user_id: user_id).delete
        next
      end

      Notifier::Models::UserMirror.upsert(
        user_id: user_id,
        org_id:  event["org_id"],
        role:    event["role"],
        name:    FIELD_CIPHER.decrypt(event["name_enc"]),
        email:   FIELD_CIPHER.decrypt(event["email_enc"]),
        telegram_chat_id: FIELD_CIPHER.decrypt(event["telegram_chat_id_enc"]),
        prefs:   event["prefs"],
        updated_at: Time.at(event.fetch("updated_at") / 1000)
      )
    end
  end
end
