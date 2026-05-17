class CreateCorrectiveActions < ActiveRecord::Migration[7.2]
  def change
    create_table :corrective_actions do |t|
      t.references :incident,   null: false, foreign_key: true, index: true
      t.references :assignee,   null: false, foreign_key: { to_table: :users }, index: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }, index: true

      t.string  :title,       null: false, limit: 200
      t.text    :description

      t.datetime :due_date,   null: false

      # AASM column. Values: open, in_progress, done, verified, cancelled.
      t.string :state, null: false, default: "open"

      t.datetime :completed_at
      t.datetime :verified_at

      # Set by OverdueActionScanJob when a CorrectiveActionOverdue event has
      # been emitted. Used to de-duplicate notifications within a 24h window.
      t.datetime :overdue_notified_at

      t.timestamps

      t.index :due_date
      t.index :state
      t.index %i[incident_id state]
    end
  end
end
