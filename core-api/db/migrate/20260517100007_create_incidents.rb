class CreateIncidents < ActiveRecord::Migration[7.2]
  def change
    create_table :incidents do |t|
      t.references :organization, null: false, foreign_key: true, index: true
      t.references :site,         null: false, foreign_key: true, index: true
      t.references :reporter,     null: false, foreign_key: { to_table: :users }, index: true
      t.references :assignee,     null: true,  foreign_key: { to_table: :users }, index: true

      t.string :incident_type,  null: false              # collision, slip, near-miss, ...
      t.integer :severity,      null: false              # 1=catastrophic .. 5=negligible
      t.datetime :occurred_at,  null: false
      t.string :location,       null: false              # free-text within the site

      t.string :summary, null: false                     # one-line headline
      t.text   :description                              # full narrative
      t.text   :root_cause                               # filled during investigation

      # AASM state column. Values: draft, submitted, investigating, pending_closure, closed
      t.string :state, null: false, default: "draft"

      # Search corpus (populated by pg_search trigger or AR callback)
      # Type :tsvector requires pg adapter; using execute for portability.
      t.column :tsv, :tsvector

      # Lifecycle timestamps
      t.datetime :submitted_at
      t.datetime :triaged_at
      t.datetime :closed_at
      t.datetime :sla_breached_at

      t.timestamps

      t.index %i[organization_id state occurred_at]
      t.index %i[organization_id assignee_id]
      t.index %i[organization_id severity]
    end

    # GIN index on tsvector. New empty table -> zero-downtime risk;
    # strong_migrations can't introspect raw execute so wrap explicitly.
    safety_assured do
      execute "CREATE INDEX index_incidents_on_tsv ON incidents USING GIN(tsv);"
    end
  end
end
