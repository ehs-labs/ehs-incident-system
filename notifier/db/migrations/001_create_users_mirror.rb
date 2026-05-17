Sequel.migration do
  change do
    create_table(:users_mirror) do
      String      :user_id, primary_key: true, size: 64
      String      :org_id,  null: false, size: 64
      String      :role,    null: false, size: 32
      String      :name,    null: false                  # decrypted in memory before write
      String      :email,   null: false
      String      :telegram_chat_id
      column      :prefs, "jsonb", default: '{}'
      DateTime    :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :org_id
      index :email
    end
  end
end
