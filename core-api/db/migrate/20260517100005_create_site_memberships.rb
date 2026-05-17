class CreateSiteMemberships < ActiveRecord::Migration[7.2]
  def change
    create_table :site_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :site, null: false, foreign_key: true
      t.timestamps

      t.index %i[user_id site_id], unique: true
    end
  end
end
