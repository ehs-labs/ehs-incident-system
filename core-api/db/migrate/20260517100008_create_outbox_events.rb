class CreateOutboxEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :outbox_events do |t|
      t.string :event_id,   null: false             # ULID; used for idempotency
      t.string :event_type, null: false             # IncidentSubmitted, etc.
      t.string :topic,      null: false             # incidents.v1, ...
      t.string :partition_key, null: false          # typically org_id

      # Avro-encoded payload as bytea; alternatively store JSON for inspection.
      # We store both: jsonb for human-readability + the encoded bytes for replay.
      t.jsonb  :payload,    null: false, default: {}
      t.binary :encoded_payload, null: true         # populated by shipper if pre-encoded

      t.datetime :published_at                      # NULL = pending; set when shipper succeeds
      t.integer  :attempt_count, null: false, default: 0
      t.string   :last_error

      t.timestamps

      # NULLS FIRST so unpublished rows sort to the front of the shipper's query
      t.index :published_at
      t.index :event_id, unique: true
      t.index :event_type
    end
  end
end
