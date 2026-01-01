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

ActiveRecord::Schema[8.1].define(version: 2026_01_01_045328) do
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
    t.datetime "deleted_at"
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
    t.index ["deleted_at"], name: "index_episodes_on_deleted_at"
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

  create_table "page_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "path", null: false
    t.string "referrer"
    t.string "referrer_host"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.string "visitor_hash", null: false
    t.index ["created_at", "visitor_hash"], name: "index_page_views_on_created_at_and_visitor_hash"
    t.index ["created_at"], name: "index_page_views_on_created_at"
    t.index ["path"], name: "index_page_views_on_path"
    t.index ["referrer_host"], name: "index_page_views_on_referrer_host"
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

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_period_end", null: false
    t.integer "status", default: 0, null: false
    t.string "stripe_price_id", null: false
    t.string "stripe_subscription_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true
    t.index ["user_id"], name: "index_subscriptions_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.integer "account_type", default: 0, null: false
    t.boolean "admin", default: false, null: false
    t.string "auth_token"
    t.datetime "auth_token_expires_at"
    t.datetime "created_at", null: false
    t.string "email_address"
    t.string "stripe_customer_id"
    t.datetime "updated_at", null: false
    t.string "voice_preference"
    t.index ["auth_token"], name: "index_users_on_auth_token"
    t.index ["auth_token_expires_at"], name: "index_users_on_auth_token_expires_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id", unique: true
  end

  add_foreign_key "episode_usages", "users"
  add_foreign_key "episodes", "podcasts"
  add_foreign_key "episodes", "users"
  add_foreign_key "llm_usages", "episodes"
  add_foreign_key "podcast_memberships", "podcasts"
  add_foreign_key "podcast_memberships", "users"
  add_foreign_key "sent_messages", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "subscriptions", "users"
end
