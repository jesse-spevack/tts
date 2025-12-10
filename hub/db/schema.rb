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

ActiveRecord::Schema[8.1].define(version: 2025_12_10_181709) do
  create_table "episode_usages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "episode_count", default: 0, null: false
    t.date "period_start", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "period_start"], name: "index_episode_usages_on_user_id_and_period_start", unique: true
    t.index ["user_id"], name: "index_episode_usages_on_user_id"
  end

  create_table "episodes", force: :cascade do |t|
    t.integer "audio_size_bytes"
    t.string "author", null: false
    t.text "content_preview"
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.integer "duration_seconds"
    t.text "error_message"
    t.string "gcs_episode_id"
    t.integer "podcast_id", null: false
    t.text "source_text"
    t.integer "source_type", default: 0, null: false
    t.string "source_url"
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["gcs_episode_id"], name: "index_episodes_on_gcs_episode_id"
    t.index ["podcast_id"], name: "index_episodes_on_podcast_id"
    t.index ["source_type"], name: "index_episodes_on_source_type"
    t.index ["status"], name: "index_episodes_on_status"
    t.index ["user_id"], name: "index_episodes_on_user_id"
  end

  create_table "llm_usages", force: :cascade do |t|
    t.decimal "cost_cents", precision: 10, scale: 4
    t.datetime "created_at", null: false
    t.integer "episode_id", null: false
    t.integer "input_tokens", null: false
    t.string "model_id", null: false
    t.integer "output_tokens", null: false
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["episode_id"], name: "index_llm_usages_on_episode_id"
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

  create_table "sent_messages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_type", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "message_type"], name: "index_sent_messages_on_user_id_and_message_type", unique: true
    t.index ["user_id"], name: "index_sent_messages_on_user_id"
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
    t.string "voice_preference"
    t.index ["auth_token"], name: "index_users_on_auth_token"
    t.index ["auth_token_expires_at"], name: "index_users_on_auth_token_expires_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "episode_usages", "users"
  add_foreign_key "episodes", "podcasts"
  add_foreign_key "episodes", "users"
  add_foreign_key "llm_usages", "episodes"
  add_foreign_key "podcast_memberships", "podcasts"
  add_foreign_key "podcast_memberships", "users"
  add_foreign_key "sent_messages", "users"
  add_foreign_key "sessions", "users"
end
