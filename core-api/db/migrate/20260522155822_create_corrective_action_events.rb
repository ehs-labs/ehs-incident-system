class CreateCorrectiveActionEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :corrective_action_events do |t|
      t.references :corrective_action, null: false, foreign_key: { on_delete: :cascade }
      t.string     :event_name, null: false
      t.references :actor,      null: false, foreign_key: { to_table: :users }
      t.text       :note
      t.datetime   :created_at, null: false
    end

    add_index :corrective_action_events, [ :corrective_action_id, :created_at ],
              name: "idx_ca_events_by_action_created"
  end
end
