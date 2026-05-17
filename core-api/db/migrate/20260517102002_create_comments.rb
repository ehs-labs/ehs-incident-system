class CreateComments < ActiveRecord::Migration[7.2]
  def change
    create_table :comments do |t|
      t.references :incident, null: false, foreign_key: true,                    index: true
      t.references :author,   null: false, foreign_key: { to_table: :users }, index: true

      t.text :body, null: false

      t.timestamps
    end
  end
end
