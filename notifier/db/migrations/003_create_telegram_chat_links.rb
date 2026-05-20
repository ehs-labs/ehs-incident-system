# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:telegram_chat_links) do
      primary_key :id
      String      :user_id, null: false, size: 64, unique: true
      String      :telegram_chat_id, null: false
      String      :link_token,      null: false, size: 64
      DateTime    :linked_at,       null: false, default: Sequel::CURRENT_TIMESTAMP

      index :telegram_chat_id, unique: true
      index :link_token, unique: true
    end
  end
end
