# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_22_155822) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "incident_id", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_comments_on_author_id"
    t.index ["incident_id"], name: "index_comments_on_incident_id"
  end

  create_table "corrective_action_events", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.bigint "corrective_action_id", null: false
    t.datetime "created_at", null: false
    t.string "event_name", null: false
    t.text "note"
    t.index ["actor_id"], name: "index_corrective_action_events_on_actor_id"
    t.index ["corrective_action_id", "created_at"], name: "idx_ca_events_by_action_created"
    t.index ["corrective_action_id"], name: "index_corrective_action_events_on_corrective_action_id"
  end

  create_table "corrective_actions", force: :cascade do |t|
    t.bigint "assignee_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.text "description"
    t.datetime "due_date", null: false
    t.bigint "incident_id", null: false
    t.datetime "overdue_notified_at"
    t.string "state", default: "open", null: false
    t.string "title", limit: 200, null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["assignee_id"], name: "index_corrective_actions_on_assignee_id"
    t.index ["created_by_id"], name: "index_corrective_actions_on_created_by_id"
    t.index ["due_date"], name: "index_corrective_actions_on_due_date"
    t.index ["incident_id", "state"], name: "index_corrective_actions_on_incident_id_and_state"
    t.index ["incident_id"], name: "index_corrective_actions_on_incident_id"
    t.index ["state"], name: "index_corrective_actions_on_state"
  end

  create_table "incidents", force: :cascade do |t|
    t.bigint "assignee_id"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "incident_type", null: false
    t.string "location"
    t.datetime "occurred_at"
    t.bigint "organization_id", null: false
    t.bigint "reporter_id", null: false
    t.text "root_cause"
    t.integer "severity", null: false
    t.bigint "site_id", null: false
    t.datetime "sla_breached_at"
    t.string "state", default: "draft", null: false
    t.datetime "submitted_at"
    t.string "summary", null: false
    t.datetime "triaged_at"
    t.tsvector "tsv"
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_incidents_on_assignee_id"
    t.index ["organization_id", "assignee_id"], name: "index_incidents_on_organization_id_and_assignee_id"
    t.index ["organization_id", "severity"], name: "index_incidents_on_organization_id_and_severity"
    t.index ["organization_id", "state", "occurred_at"], name: "index_incidents_on_organization_id_and_state_and_occurred_at"
    t.index ["organization_id"], name: "index_incidents_on_organization_id"
    t.index ["reporter_id"], name: "index_incidents_on_reporter_id"
    t.index ["site_id"], name: "index_incidents_on_site_id"
    t.index ["tsv"], name: "index_incidents_on_tsv", using: :gin
  end

  create_table "jwt_denylist", force: :cascade do |t|
    t.datetime "exp", null: false
    t.string "jti", null: false
    t.index ["jti"], name: "index_jwt_denylist_on_jti", unique: true
  end

  create_table "organization_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.jsonb "sla_overrides", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_organization_settings_on_organization_id", unique: true
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "outbox_events", force: :cascade do |t|
    t.integer "attempt_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.binary "encoded_payload"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.string "last_error"
    t.string "partition_key", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "published_at"
    t.string "topic", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_outbox_events_on_event_id", unique: true
    t.index ["event_type"], name: "index_outbox_events_on_event_type"
    t.index ["published_at"], name: "index_outbox_events_on_published_at"
  end

  create_table "site_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "site_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["site_id"], name: "index_site_memberships_on_site_id"
    t.index ["user_id", "site_id"], name: "index_site_memberships_on_user_id_and_site_id", unique: true
    t.index ["user_id"], name: "index_site_memberships_on_user_id"
  end

  create_table "sites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_sites_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_sites_on_organization_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "invitation_accepted_at"
    t.datetime "invitation_created_at"
    t.integer "invitation_limit"
    t.datetime "invitation_sent_at"
    t.string "invitation_token"
    t.integer "invitations_count", default: 0
    t.bigint "invited_by_id"
    t.string "invited_by_type"
    t.datetime "locked_at"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.string "telegram_chat_id"
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["invitations_count"], name: "index_users_on_invitations_count"
    t.index ["invited_by_type", "invited_by_id"], name: "index_users_on_invited_by"
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", limit: 191, null: false
    t.text "object"
    t.text "object_changes"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "witnesses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email"
    t.bigint "incident_id", null: false
    t.string "name", limit: 120, null: false
    t.string "phone"
    t.text "statement"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_witnesses_on_deleted_at"
    t.index ["incident_id"], name: "index_witnesses_on_incident_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "comments", "incidents"
  add_foreign_key "comments", "users", column: "author_id"
  add_foreign_key "corrective_action_events", "corrective_actions", on_delete: :cascade
  add_foreign_key "corrective_action_events", "users", column: "actor_id"
  add_foreign_key "corrective_actions", "incidents"
  add_foreign_key "corrective_actions", "users", column: "assignee_id"
  add_foreign_key "corrective_actions", "users", column: "created_by_id"
  add_foreign_key "incidents", "organizations"
  add_foreign_key "incidents", "sites"
  add_foreign_key "incidents", "users", column: "assignee_id"
  add_foreign_key "incidents", "users", column: "reporter_id"
  add_foreign_key "organization_settings", "organizations"
  add_foreign_key "site_memberships", "sites"
  add_foreign_key "site_memberships", "users"
  add_foreign_key "sites", "organizations"
  add_foreign_key "users", "organizations"
  add_foreign_key "witnesses", "incidents"
end
