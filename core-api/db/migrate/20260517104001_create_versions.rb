# PaperTrail's standard versions table. Captures create/update/destroy events
# for any model that declares `has_paper_trail`. The `whodunnit` column is set
# from the API base controller (PaperTrail.request.whodunnit), so every
# version row carries the acting user's id as a string.
class CreateVersions < ActiveRecord::Migration[7.2]
  # PaperTrail's index name is long; allow ActiveRecord to pick a shorter one.
  TEXT_BYTES = 1_073_741_823

  def change
    create_table :versions do |t|
      t.string   :item_type, null: false, limit: 191
      t.bigint   :item_id,   null: false
      t.string   :event,     null: false
      t.string   :whodunnit
      t.text     :object,         limit: TEXT_BYTES
      t.text     :object_changes, limit: TEXT_BYTES
      t.datetime :created_at
    end

    add_index :versions, %i[item_type item_id], name: "index_versions_on_item_type_and_item_id"
  end
end
