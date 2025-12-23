# Simple Analytics Design

Track page views and referrers to understand landing page traffic before redesigning.

## Goals

- Answer: "Is anyone visiting the landing page?"
- Know where visitors come from (Google, Twitter, direct, etc.)
- Estimate unique visitors
- Measure before/after when redesigning later

## Data Model

**page_views table:**

| Column | Type | Purpose |
|--------|------|---------|
| `path` | string | URL path visited (e.g., `/`, `/how_it_sounds`) |
| `referrer` | string, nullable | Full referrer URL |
| `referrer_host` | string, nullable | Extracted host for grouping (e.g., `google.com`) |
| `visitor_hash` | string | SHA256(IP + User-Agent + daily salt) for unique visitor estimation |
| `user_agent` | string | Browser info for bot filtering |
| `created_at` | datetime | When the visit happened |

**Indexes:**
- `created_at` - time-range queries
- `path` - per-page filtering
- `referrer_host` - referrer reports

**users table addition:**
- `admin` boolean, default false

## Tracking Mechanism

Controller concern `Trackable` included in `ApplicationController`.

**Skips tracking for:**
- Logged-in users
- Bot requests (user agent contains "bot", "crawler", "spider")
- Non-GET requests

**Visitor hash:**
- SHA256 of IP + User-Agent + daily salt
- Daily salt rotates, so same visitor gets new hash each day (privacy-friendly)

**Performance:**
- Uses `insert` to skip validations/callbacks
- Runs on `PagesController` actions only (home, how_it_sounds, terms)

## Admin View

Route: `/admin/analytics`

**Access control:** `current_user&.admin?` check

**Dashboard shows:**

1. **Summary stats (7 and 30 days):**
   - Total page views
   - Unique visitors (distinct visitor_hash count)
   - Views per page breakdown

2. **Top referrers table:**
   - Grouped by referrer_host
   - Count and percentage
   - "Direct" row for null referrers

3. **Daily trend:**
   - Page views per day, last 30 days
   - Simple text table (no charts)

## Not Included

- Real-time updates
- Charts or visualization libraries
- Filtering UI (use Rails console)
- Export functionality
- Funnel tracking
- Data retention/cleanup jobs
- Admin management UI

## Making a User Admin

```bash
# Rails console
User.find_by(email: "your@email.com").update!(admin: true)
```
