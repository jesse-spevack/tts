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

ActiveRecord::Schema[8.1].define(version: 2026_04_24_100000) do
  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

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

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.string "source", default: "user", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id", "source", "revoked_at"], name: "index_api_tokens_on_user_id_and_source_and_revoked_at"
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "credit_balances", force: :cascade do |t|
    t.integer "balance", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_credit_balances_on_user_id", unique: true
  end

  create_table "credit_transactions", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "balance_after", null: false
    t.datetime "created_at", null: false
    t.integer "episode_id"
    t.string "stripe_session_id"
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["episode_id"], name: "index_credit_transactions_on_episode_id"
    t.index ["stripe_session_id"], name: "index_credit_transactions_on_stripe_session_id", unique: true
    t.index ["transaction_type"], name: "index_credit_transactions_on_transaction_type"
    t.index ["user_id", "episode_id"], name: "idx_credit_transactions_usage_unique", unique: true, where: "transaction_type = 'usage'"
    t.index ["user_id"], name: "index_credit_transactions_on_user_id"
  end

  create_table "deactivations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deactivated_at", null: false
    t.string "reason"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_deactivations_on_user_id"
  end

  create_table "device_codes", force: :cascade do |t|
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "device_code", null: false
    t.datetime "expires_at", null: false
    t.string "token_digest"
    t.datetime "updated_at", null: false
    t.string "user_code", null: false
    t.integer "user_id"
    t.index ["device_code"], name: "index_device_codes_on_device_code", unique: true
    t.index ["user_code"], name: "index_device_codes_on_user_code", unique: true
    t.index ["user_id"], name: "index_device_codes_on_user_id"
  end

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
    t.integer "credit_cost"
    t.datetime "deleted_at"
    t.text "description", null: false
    t.integer "duration_seconds"
    t.text "error_message"
    t.string "gcs_episode_id"
    t.integer "mpp_payment_id"
    t.integer "podcast_id", null: false
    t.datetime "processing_completed_at"
    t.datetime "processing_started_at"
    t.text "source_text"
    t.integer "source_text_length"
    t.integer "source_type", default: 0, null: false
    t.string "source_url"
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "voice"
    t.index ["deleted_at"], name: "index_episodes_on_deleted_at"
    t.index ["gcs_episode_id"], name: "index_episodes_on_gcs_episode_id"
    t.index ["mpp_payment_id"], name: "index_episodes_on_mpp_payment_id"
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

  create_table "mpp_payments", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.string "challenge_id"
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.string "deposit_address"
    t.integer "narration_id"
    t.boolean "needs_review", default: false, null: false
    t.text "refund_error"
    t.string "status", default: "pending", null: false
    t.string "stripe_payment_intent_id"
    t.string "tx_hash"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["stripe_payment_intent_id"], name: "index_mpp_payments_on_stripe_payment_intent_id"
    t.index ["tx_hash"], name: "index_mpp_payments_on_tx_hash", unique: true
    t.index ["user_id"], name: "index_mpp_payments_on_user_id"
  end

  create_table "narrations", force: :cascade do |t|
    t.integer "audio_size_bytes"
    t.string "author"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.text "error_message"
    t.datetime "expires_at", null: false
    t.string "gcs_episode_id"
    t.integer "mpp_payment_id", null: false
    t.datetime "processing_completed_at"
    t.datetime "processing_started_at"
    t.text "source_text"
    t.integer "source_type", null: false
    t.string "source_url"
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "voice"
    t.index ["expires_at"], name: "index_narrations_on_expires_at"
    t.index ["mpp_payment_id"], name: "index_narrations_on_mpp_payment_id", unique: true
    t.index ["status"], name: "index_narrations_on_status"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.integer "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.integer "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.integer "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.integer "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
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

  create_table "processing_estimates", force: :cascade do |t|
    t.integer "base_seconds", null: false
    t.datetime "created_at", null: false
    t.integer "episode_count", null: false
    t.integer "microseconds_per_character", null: false
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

  create_table "tts_usages", force: :cascade do |t|
    t.integer "character_count", null: false
    t.integer "cost_cents", null: false
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "source", default: "actual", null: false
    t.datetime "updated_at", null: false
    t.integer "usable_id", null: false
    t.string "usable_type", null: false
    t.string "voice_id", null: false
    t.string "voice_tier", null: false
    t.index ["usable_type", "usable_id"], name: "index_tts_usages_on_usable", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.integer "account_type", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.boolean "admin", default: false, null: false
    t.string "auth_token"
    t.datetime "auth_token_expires_at"
    t.datetime "created_at", null: false
    t.string "email_address"
    t.boolean "email_episode_confirmation", default: true, null: false
    t.boolean "email_episodes_enabled", default: false, null: false
    t.string "email_ingest_token"
    t.boolean "internal", default: false, null: false
    t.string "stripe_customer_id"
    t.datetime "updated_at", null: false
    t.string "voice_preference"
    t.index ["active"], name: "index_users_on_active"
    t.index ["auth_token"], name: "index_users_on_auth_token"
    t.index ["auth_token_expires_at"], name: "index_users_on_auth_token_expires_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["email_ingest_token"], name: "index_users_on_email_ingest_token", unique: true
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id", unique: true
  end

  create_table "webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_id", null: false
    t.string "event_type"
    t.json "payload_summary"
    t.string "provider", null: false
    t.datetime "received_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "event_id"], name: "index_webhook_events_on_provider_and_event_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "credit_balances", "users"
  add_foreign_key "credit_transactions", "episodes"
  add_foreign_key "credit_transactions", "users"
  add_foreign_key "deactivations", "users"
  add_foreign_key "device_codes", "users"
  add_foreign_key "episode_usages", "users"
  add_foreign_key "episodes", "mpp_payments"
  add_foreign_key "episodes", "podcasts"
  add_foreign_key "episodes", "users"
  add_foreign_key "llm_usages", "episodes"
  add_foreign_key "narrations", "mpp_payments"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id"
  add_foreign_key "podcast_memberships", "podcasts"
  add_foreign_key "podcast_memberships", "users"
  add_foreign_key "sent_messages", "users"
  add_foreign_key "sessions", "users"
end
