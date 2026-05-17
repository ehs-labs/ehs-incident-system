class CreateOrganizations < ActiveRecord::Migration[7.2]
  def change
    create_table :organizations do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.timestamps

      t.index :slug, unique: true
    end
  end
end
