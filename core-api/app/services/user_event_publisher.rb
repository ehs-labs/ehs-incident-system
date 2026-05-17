require "ulid"

# UserEventPublisher emits CDC-style UserUpserted events to the log-compacted
# `users.v1` Kafka topic. The notifier service maintains a users_mirror table
# from this stream and decrypts the PII fields with the shared envelope cipher.
#
# Unlike domain events that flow through EventBus (envelope + subject payload),
# UserUpserted is a flat CDC record — see schemas/events/v1/UserUpserted.avsc.
# We therefore write to outbox_events directly with the matching payload shape.
#
# The Kafka message key is `user_id` (NOT org_id) so log-compaction can drop
# superseded versions of the same user. Triggered by User AR after_commit hooks.
module UserEventPublisher
  EVENT_TYPE = "UserUpserted"
  TOPIC      = "users.v1"

  ROLE_TO_AVRO = {
    "worker"       => "WORKER",
    "investigator" => "INVESTIGATOR",
    "admin"        => "ADMIN"
  }.freeze

  module_function

  # Build and persist an outbox row for the given user. The shipper job will
  # Avro-encode and produce to Kafka asynchronously.
  def publish_upsert!(user)
    OutboxEvent.create!(
      event_id:      ULID.generate,
      event_type:    EVENT_TYPE,
      topic:         TOPIC,
      partition_key: user.id.to_s,
      payload:       payload_for(user).deep_stringify_keys
    )
  end

  def payload_for(user)
    {
      user_id:              user.id.to_s,
      org_id:               user.organization_id.to_s,
      role:                 ROLE_TO_AVRO.fetch(user.role.to_s, "WORKER"),
      name_enc:             FieldCipher.encrypt(user.name.to_s),
      email_enc:            FieldCipher.encrypt(user.email.to_s),
      telegram_chat_id_enc: nil, # populated when telegram linking lands
      prefs:                {},  # consumer falls back to default_prefs per event_type
      deleted:              user.respond_to?(:deleted?) && user.deleted?,
      updated_at:           ((user.updated_at || Time.current).to_f * 1000).to_i
    }
  end
end
