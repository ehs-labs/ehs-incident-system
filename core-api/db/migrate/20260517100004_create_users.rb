class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      # ----- Tenant + identity ----------------------------------------------
      t.references :organization, null: false, foreign_key: true, index: true
      t.string  :name, null: false

      # role: 0=worker, 1=investigator, 2=admin
      t.integer :role, null: false, default: 0

      # Soft-delete (preserve audit history)
      t.datetime :deleted_at

      # Telegram opt-in (stored only on this canonical user record; encrypted in events)
      t.string :telegram_chat_id

      # ----- Devise: database_authenticatable -------------------------------
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      # ----- Devise: recoverable --------------------------------------------
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      # ----- Devise: rememberable -------------------------------------------
      t.datetime :remember_created_at

      # ----- Devise: confirmable --------------------------------------------
      t.string   :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string   :unconfirmed_email

      # ----- Devise: lockable -----------------------------------------------
      t.integer  :failed_attempts, default: 0, null: false
      t.string   :unlock_token
      t.datetime :locked_at

      # ----- devise_invitable -----------------------------------------------
      t.string     :invitation_token
      t.datetime   :invitation_created_at
      t.datetime   :invitation_sent_at
      t.datetime   :invitation_accepted_at
      t.integer    :invitation_limit
      t.references :invited_by, polymorphic: true, index: true
      t.integer    :invitations_count, default: 0

      t.timestamps
    end

    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :confirmation_token,   unique: true
    add_index :users, :unlock_token,         unique: true
    add_index :users, :invitation_token,     unique: true
    add_index :users, :invitations_count
    add_index :users, :deleted_at
  end
end
