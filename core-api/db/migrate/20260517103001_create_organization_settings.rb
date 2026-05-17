class CreateOrganizationSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :organization_settings do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :sla_overrides, null: false, default: {}
      t.timestamps
    end
  end
end
