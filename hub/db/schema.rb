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

ActiveRecord::Schema[8.1].define(version: 2025_11_21_004036) do
  create_table "episodes", force: :cascade do |t|
    t.integer "audio_size_bytes"
    t.string "author", null: false
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.integer "duration_seconds"
    t.text "error_message"
    t.string "gcs_episode_id"
    t.integer "podcast_id", null: false
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["gcs_episode_id"], name: "index_episodes_on_gcs_episode_id"
    t.index ["podcast_id"], name: "index_episodes_on_podcast_id"
    t.index ["status"], name: "index_episodes_on_status"
  end

  create_table "podcast_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "podcast_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["podcast_id"], name: "index_podcast_memberships_on_podcast_id"
    t.index ["user_id", "podcast_id"], name: "index_podcast_memberships_on_user_id_and_podcast_id", unique: true
    t.index ["user_id"], name: "index_podcast_memberships_on_user_id"
  end

  create_table "podcasts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "podcast_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["podcast_id"], name: "index_podcasts_on_podcast_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "auth_token"
    t.datetime "auth_token_expires_at"
    t.datetime "created_at", null: false
    t.string "email_address"
    t.integer "tier", default: 0
    t.datetime "updated_at", null: false
    t.index ["auth_token"], name: "index_users_on_auth_token"
    t.index ["auth_token_expires_at"], name: "index_users_on_auth_token_expires_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "episodes", "podcasts"
  add_foreign_key "podcast_memberships", "podcasts"
  add_foreign_key "podcast_memberships", "users"
  add_foreign_key "sessions", "users"
end
