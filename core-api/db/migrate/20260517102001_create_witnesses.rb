class CreateWitnesses < ActiveRecord::Migration[7.2]
  def change
    create_table :witnesses do |t|
      t.references :incident, null: false, foreign_key: true, index: true

      t.string :name,      null: false, limit: 120
      t.string :email
      t.string :phone
      t.text   :statement

      # Soft-delete (preserve audit history)
      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
    end
  end
end
