# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:delivery_log) do
      primary_key :id
      String      :event_id,   null: false, size: 64
      String      :user_id,    null: false, size: 64
      String      :channel,    null: false, size: 32 # email | telegram | in_app
      String      :event_type, null: false, size: 64
      String      :title,      null: false
      String      :body,       text: true
      String      :link
      String      :state, null: false, default: 'pending', size: 16 # pending|sent|failed
      Integer     :attempt_count, null: false, default: 0
      String      :last_error
      DateTime    :sent_at
      DateTime    :failed_at
      DateTime    :read_at
      DateTime    :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime    :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      # Idempotency — one delivery row per (event, user, channel)
      index %i[event_id user_id channel], unique: true
      index %i[user_id channel created_at]
      index %i[user_id read_at]
    end
  end
end
