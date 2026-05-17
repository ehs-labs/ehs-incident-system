class CreateSites < ActiveRecord::Migration[7.2]
  def change
    create_table :sites do |t|
      t.references :organization, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :timezone, null: false, default: "UTC"
      t.timestamps

      t.index %i[organization_id name], unique: true
    end
  end
end
