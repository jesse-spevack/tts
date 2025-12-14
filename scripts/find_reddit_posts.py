#!/usr/bin/env python3
"""
Find relevant Reddit posts for Very Normal TTS marketing.
Searches target subreddits for posts from the last 24-48 hours matching relevant keywords.

Prioritizes:
1. Recommendation requests (people actively seeking suggestions)
2. High engagement posts (more comments = active discussion)
3. Direct product fit (read-later, TTS, article consumption)
"""

import argparse
import json
import re
import time
from datetime import datetime, timezone
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

# Configuration
SUBREDDITS = [
    # Productivity & Knowledge Management (high priority)
    "productivity",
    "getdisciplined",
    "Notion",
    "ObsidianMD",
    "PKMS",
    "selfhosted",
    # Podcast & Audio (high priority)
    "podcasts",
    "audiobooks",
    "pocketcasts",
    # Digital Wellness
    "nosurf",
    # Tech & Apps
    "androidapps",
    "iosapps",
    # Learning
    "GetStudying",
    "learnprogramming",
]

# Patterns that indicate someone is asking for recommendations (HIGH VALUE)
RECOMMENDATION_PATTERNS = [
    r"recommend",
    r"suggestion",
    r"looking for",
    r"what do you use",
    r"how do you",
    r"best.*(app|tool|way)",
    r"alternative.?to",
    r"replacement for",
    r"instead of",
    r"similar to",
    r"any.*(app|tool|way)",
    r"help me find",
    r"what.*(app|tool|service)",
    r"does anyone know",
    r"is there.*(app|tool|way)",
]

# Topic keywords - what the post is about
TOPIC_KEYWORDS = [
    # Read later / bookmarks (DIRECT FIT)
    (r"read.?later", 10),
    (r"reading.?backlog", 10),
    (r"saved.?articles", 10),
    (r"too many bookmarks", 8),
    (r"never.?read", 5),
    (r"instapaper", 10),
    (r"omnivore", 10),
    (r"wallabag", 8),
    (r"readwise", 8),
    # Text to speech (DIRECT FIT)
    (r"text.?to.?speech", 15),
    (r"\btts\b", 10),
    (r"listen.?to.?articles", 15),
    (r"articles?.?to.?audio", 15),
    (r"articles?.?to.?podcast", 15),
    (r"read.?aloud", 10),
    # Podcasts
    (r"running out of podcasts", 12),
    (r"need.?more.?podcasts", 12),
    (r"podcast.?recommend", 8),
    (r"commute.?listen", 8),
    (r"listen.?while", 6),
    (r"listen.?during", 6),
    # Newsletters
    (r"newsletter.?overload", 10),
    (r"too many newsletters", 10),
    (r"substack", 8),
    (r"email.?newsletters", 6),
    # Content consumption
    (r"information.?overload", 8),
    (r"content.?consumption", 6),
    (r"reduce.?screen.?time", 8),
    (r"less.?scrolling", 5),
    (r"rss.?feed", 6),
    (r"rss.?reader", 6),
    # Specific alternatives (HIGH VALUE - active seekers)
    (r"omnivore.?(alternative|shut|closing)", 20),
    (r"pocket.?(alternative|shut|closing)", 20),
    (r"pocket.?replacement", 20),
    # Competitors (for context/comparison)
    (r"elevenlabs", 8),
    (r"elevenreader", 10),
    (r"speechify", 10),
    (r"naturalreader", 8),
    (r"voice.?dream", 8),
]

# Words that indicate FALSE POSITIVES - exclude these
EXCLUDE_PATTERNS = [
    r"pocketid",           # Auth tool, not Pocket app
    r"pocket.?money",      # Finance
    r"pocket.?knife",      # Physical item
    r"pocket.?pc",         # Gaming device
    r"in.?my.?pocket",     # Idiom
    r"pick.?pocket",       # Crime
    r"pocket.?dimension",  # Gaming/fiction
]

HOURS_LOOKBACK_DEFAULT = 24
USER_AGENT = "VeryNormalTTS-RedditSearch/1.0"


def fetch_subreddit_posts(subreddit: str, limit: int = 100) -> list[dict]:
    """Fetch recent posts from a subreddit using Reddit's JSON API."""
    url = f"https://www.reddit.com/r/{subreddit}/new.json?limit={limit}"
    headers = {"User-Agent": USER_AGENT}

    try:
        req = Request(url, headers=headers)
        with urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            return data.get("data", {}).get("children", [])
    except HTTPError as e:
        if e.code == 403:
            print(f"  ⚠️  r/{subreddit}: Private or quarantined")
        elif e.code == 404:
            print(f"  ⚠️  r/{subreddit}: Not found")
        else:
            print(f"  ⚠️  HTTP error fetching r/{subreddit}: {e.code}")
        return []
    except URLError as e:
        print(f"  ⚠️  URL error fetching r/{subreddit}: {e.reason}")
        return []
    except Exception as e:
        print(f"  ⚠️  Error fetching r/{subreddit}: {e}")
        return []


def is_within_timeframe(post: dict, hours: int) -> bool:
    """Check if post was created within the specified hours."""
    created_utc = post.get("data", {}).get("created_utc", 0)
    post_time = datetime.fromtimestamp(created_utc, tz=timezone.utc)
    now = datetime.now(timezone.utc)
    age_hours = (now - post_time).total_seconds() / 3600
    return age_hours <= hours


def should_exclude(text: str) -> bool:
    """Check if post matches exclusion patterns (false positives)."""
    for pattern in EXCLUDE_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            return True
    return False


def is_recommendation_request(text: str) -> bool:
    """Check if post is asking for recommendations."""
    for pattern in RECOMMENDATION_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            return True
    return False


def calculate_topic_score(text: str) -> tuple[int, list[str]]:
    """Calculate relevance score based on topic keywords. Returns (score, matched_keywords)."""
    score = 0
    matched = []
    for pattern, points in TOPIC_KEYWORDS:
        if re.search(pattern, text, re.IGNORECASE):
            score += points
            matched.append(pattern)
    return score, matched


def calculate_opportunity_score(post: dict) -> tuple[int, dict]:
    """
    Calculate overall opportunity score for a post.
    Returns (score, details_dict).

    Scoring factors:
    - Topic relevance (keyword matches)
    - Is recommendation request (2x multiplier)
    - Engagement (comments boost score)
    - Recency bonus
    """
    data = post.get("data", {})
    title = data.get("title", "")
    selftext = data.get("selftext", "")
    combined = f"{title} {selftext}".lower()

    # Check for exclusions first
    if should_exclude(combined):
        return 0, {"excluded": True}

    # Base topic score
    topic_score, matched_keywords = calculate_topic_score(combined)
    if topic_score == 0:
        return 0, {"no_match": True}

    # Recommendation request multiplier (these are gold!)
    is_rec_request = is_recommendation_request(combined)
    if is_rec_request:
        topic_score = int(topic_score * 2)

    # Engagement bonus (comments are more valuable than upvotes for discussion)
    num_comments = data.get("num_comments", 0)
    if num_comments >= 20:
        engagement_bonus = 30
    elif num_comments >= 10:
        engagement_bonus = 20
    elif num_comments >= 5:
        engagement_bonus = 10
    elif num_comments >= 2:
        engagement_bonus = 5
    else:
        engagement_bonus = 0

    # Small upvote bonus
    score = data.get("score", 0)
    if score >= 50:
        upvote_bonus = 10
    elif score >= 20:
        upvote_bonus = 5
    elif score >= 5:
        upvote_bonus = 2
    else:
        upvote_bonus = 0

    total_score = topic_score + engagement_bonus + upvote_bonus

    details = {
        "topic_score": topic_score,
        "is_recommendation": is_rec_request,
        "engagement_bonus": engagement_bonus,
        "upvote_bonus": upvote_bonus,
        "matched_keywords": matched_keywords,
    }

    return total_score, details


def format_time_ago(created_utc: float) -> str:
    """Format timestamp as human-readable time ago."""
    post_time = datetime.fromtimestamp(created_utc, tz=timezone.utc)
    now = datetime.now(timezone.utc)
    delta = now - post_time

    hours = delta.total_seconds() / 3600
    if hours < 1:
        minutes = int(delta.total_seconds() / 60)
        return f"{minutes}m ago"
    elif hours < 24:
        return f"{int(hours)}h ago"
    else:
        days = int(hours / 24)
        return f"{days}d ago"


def get_relevance_tier(score: int, details: dict) -> str:
    """Get relevance tier label based on score."""
    if details.get("is_recommendation") and score >= 30:
        return "🔥 EXCELLENT - Recommendation request with good engagement"
    elif score >= 40:
        return "🔥 EXCELLENT - High relevance and engagement"
    elif score >= 25:
        return "⭐ GREAT - Strong opportunity"
    elif score >= 15:
        return "👍 GOOD - Worth engaging"
    else:
        return "📌 MAYBE - Lower priority"


def suggest_approach(post: dict, details: dict) -> str:
    """Suggest an engagement approach based on post content."""
    data = post.get("data", {})
    title = data.get("title", "").lower()
    matched = details.get("matched_keywords", [])

    # Check for specific patterns in order of priority
    if any(re.search(r"pocket|omnivore", k) for k in matched):
        if "alternative" in title or "replacement" in title or "shut" in title:
            return "Direct recommendation - mention as Pocket/Omnivore alternative with audio focus"
        return "Share experience with article-to-audio as workflow enhancement"

    if any(re.search(r"text.?to.?speech|tts|listen.?to.?article", k) for k in matched):
        return "Share experience converting articles/essays to podcast feed"

    if any(re.search(r"podcast.?recommend|running out", k) for k in matched):
        return "Suggest turning saved articles/essays into personal podcast content"

    if any(re.search(r"read.?later|backlog|saved", k) for k in matched):
        return "Share how converting to audio helped actually consume saved content"

    if any(re.search(r"newsletter|substack", k) for k in matched):
        return "Mention converting newsletter content to audio for easier consumption"

    if any(re.search(r"screen.?time|scrolling", k) for k in matched):
        return "Position as screen-free way to consume written content"

    if any(re.search(r"commute|listen.?while", k) for k in matched):
        return "Suggest adding article content to commute listening rotation"

    return "Share personal experience with article-to-audio workflow"


def main():
    parser = argparse.ArgumentParser(description="Find relevant Reddit posts for Very Normal TTS")
    parser.add_argument("--hours", type=int, default=HOURS_LOOKBACK_DEFAULT,
                        help=f"Hours to look back (default: {HOURS_LOOKBACK_DEFAULT})")
    parser.add_argument("--min-score", type=int, default=10,
                        help="Minimum opportunity score to show (default: 10)")
    parser.add_argument("--top", type=int, default=10,
                        help="Show top N results (default: 10)")
    args = parser.parse_args()

    print("=" * 70)
    print("🔍 Reddit Post Finder for Very Normal TTS")
    print(f"   Searching last {args.hours} hours across {len(SUBREDDITS)} subreddits")
    print(f"   Minimum score: {args.min_score} | Showing top: {args.top}")
    print("=" * 70)
    print()

    all_opportunities = []

    for subreddit in SUBREDDITS:
        print(f"📡 Scanning r/{subreddit}...")
        posts = fetch_subreddit_posts(subreddit)

        found_count = 0
        for post in posts:
            if not is_within_timeframe(post, args.hours):
                continue

            score, details = calculate_opportunity_score(post)
            if score >= args.min_score:
                found_count += 1
                all_opportunities.append({
                    "subreddit": subreddit,
                    "post": post,
                    "score": score,
                    "details": details,
                })

        if found_count > 0:
            print(f"   ✓ Found {found_count} opportunities")
        time.sleep(1)  # Rate limiting

    print()
    print("=" * 70)

    if not all_opportunities:
        print("📊 No opportunities found matching criteria.")
        print()
        print("Try:")
        print("  --hours 48     (expand time window)")
        print("  --min-score 5  (lower threshold)")
        return

    # Sort by score (highest first)
    all_opportunities.sort(key=lambda x: x["score"], reverse=True)

    # Take top N
    top_opportunities = all_opportunities[:args.top]

    print(f"📊 TOP {len(top_opportunities)} OPPORTUNITIES (of {len(all_opportunities)} found)")
    print("=" * 70)

    for i, item in enumerate(top_opportunities, 1):
        data = item["post"]["data"]
        title = data.get("title", "No title")
        permalink = data.get("permalink", "")
        url = f"https://reddit.com{permalink}"
        upvotes = data.get("score", 0)
        num_comments = data.get("num_comments", 0)
        created = data.get("created_utc", 0)

        score = item["score"]
        details = item["details"]
        subreddit = item["subreddit"]

        tier = get_relevance_tier(score, details)
        approach = suggest_approach(item["post"], details)

        rec_badge = " 🎯 REC REQUEST" if details.get("is_recommendation") else ""

        print()
        print(f"{'─' * 70}")
        print(f"#{i} | Score: {score} | r/{subreddit}{rec_badge}")
        print(f"{'─' * 70}")
        print(f"📝 {title}")
        print(f"🔗 {url}")
        print(f"⏰ {format_time_ago(created)} | ⬆️ {upvotes} | 💬 {num_comments} comments")
        print(f"🎯 {tier}")
        print(f"💡 {approach}")

        # Show matched keywords (cleaned up)
        keywords = details.get("matched_keywords", [])
        if keywords:
            # Clean up regex patterns for display
            clean_keywords = [re.sub(r'[\\?.+*\[\]()^$]', '', k) for k in keywords[:4]]
            print(f"🔑 Matched: {', '.join(clean_keywords)}")

    print()
    print("=" * 70)
    print("✅ Scan complete!")
    print()

    # Summary stats
    rec_count = sum(1 for x in all_opportunities if x["details"].get("is_recommendation"))
    high_score = sum(1 for x in all_opportunities if x["score"] >= 25)
    print(f"📈 Stats: {rec_count} recommendation requests, {high_score} high-value opportunities")
    print()


if __name__ == "__main__":
    main()
