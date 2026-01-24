# Email-to-Podcast Feature Proposal

## Bottom Line Up Front

**Recommendation:** Use Action Mailbox with Resend's inbound email webhooks. Users email URLs to a personalized address (`{podcast_id}@in.verynormal.email`), which triggers the existing URL episode pipeline. This approach reuses proven infrastructure, requires minimal new code, and provides the best user experience.

---

## Problem Statement

Users want to send blog posts and essays to their podcast feed without opening the app. Email provides a frictionless workflow—forward an article, get it in your podcast.

---

## Approaches Considered

### Option A: Action Mailbox + Resend Inbound (Recommended)

Route inbound emails through Resend's webhook to Action Mailbox, extract URLs from the email body, and feed them into `CreatesUrlEpisode`.

| Pros | Cons |
|------|------|
| Rails-native pattern with built-in routing DSL | Requires DNS setup for inbound subdomain |
| Resend already configured; supports inbound webhooks | New attack surface (email spoofing, spam) |
| Personalized addresses (`{podcast_id}@`) eliminate auth complexity | Webhook endpoint needs signature verification |
| Reuses existing URL processing pipeline entirely | |
| Excellent testability via `ActionMailbox::TestHelper` | |

**Implementation:** Add `action_mailbox` routes, create `UrlSubmissionMailbox`, verify sender against podcast membership, extract first URL, call `CreatesUrlEpisode`.

### Option B: Dedicated Inbound Email Service (Postmark, Mailgun)

Use a specialized inbound email provider separate from Resend.

| Pros | Cons |
|------|------|
| Purpose-built for inbound with better spam filtering | Two email vendors to manage |
| More mature inbound parsing features | Additional cost and API integration |
| | Inconsistent with existing Resend setup |

### Option C: IMAP Polling

Poll a shared inbox periodically via a background job.

| Pros | Cons |
|------|------|
| No webhook infrastructure needed | Delayed processing (polling interval) |
| Simple to implement initially | Scaling issues with many users |
| | Complex email credential management |
| | No Rails convention support |

---

## Recommended Implementation Details

### Email Address Scheme
- Format: `{podcast_id}@in.verynormal.email`
- Example: `abc123@in.verynormal.email`
- Podcast ID acts as implicit authentication—only members know it

### Security Considerations
1. **Sender verification:** Check `From` address against podcast membership emails
2. **Webhook authentication:** Verify Resend webhook signatures (HMAC)
3. **Rate limiting:** Enforce existing episode limits per subscription tier
4. **URL validation:** Reuse `FetchesUrl` SSRF protections

### New Components
```
app/mailboxes/application_mailbox.rb    # Route by recipient address
app/mailboxes/url_submission_mailbox.rb # Extract URL, verify sender, create episode
app/services/extracts_url_from_email.rb # Parse email body for URLs
config/initializers/action_mailbox.rb   # Resend ingress config
```

### Database Changes
- Add `source_type: :email` enum value to Episode (for analytics)
- No new tables required

### Testing Strategy
```ruby
# test/mailboxes/url_submission_mailbox_test.rb
class UrlSubmissionMailboxTest < ActionMailbox::TestCase
  test "creates episode from forwarded article" do
    assert_enqueued_with(job: ProcessesUrlEpisodeJob) do
      receive_inbound_email_from_mail(
        to: "#{podcasts(:one).podcast_id}@in.verynormal.email",
        from: users(:one).email,
        body: "Check this out: https://example.com/article"
      )
    end
  end

  test "bounces email from non-member" do
    assert_no_enqueued_jobs do
      receive_inbound_email_from_mail(
        to: "#{podcasts(:one).podcast_id}@in.verynormal.email",
        from: "stranger@example.com",
        body: "https://example.com/article"
      )
    end
  end
end
```

### Resend Configuration
1. Configure inbound domain in Resend dashboard (`in.verynormal.email`)
2. Set webhook URL: `https://verynormal.email/rails/action_mailbox/resend/inbound_emails`
3. Add `RESEND_INBOUND_WEBHOOK_SECRET` for signature verification

---

## Out of Scope (Future Enhancements)
- Parsing full article text from email body (paste-style)
- Email attachments (PDF/document processing)
- Reply-based commands ("skip intro", "use voice X")
