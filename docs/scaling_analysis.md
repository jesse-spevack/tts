# Scalability Analysis: Podcast Publishing API

**Last Updated:** 2025-01-01
**Architecture:** Single Cloud Run service with Cloud Tasks async processing

---

## Overview

This document analyzes the scalability characteristics of the podcast publishing API architecture, identifying bottlenecks, capacity limits, and recommended configurations for different usage scales.

---

## Architecture Scalability Analysis

### **TTS Processing (The Bottleneck)**

**Single biggest constraint: Google Cloud TTS rate limits**

According to Google Cloud TTS documentation:
- **Standard quota**: 300 requests/minute per project
- **Chirp 3 HD voices**: Often lower limits (100-300 req/min)
- **Character limits**: 5000 bytes per request

The `ChunkedSynthesizer` already handles chunking, so let's calculate capacity:

**Per Episode:**
- Average article: ~5,000 words = ~30,000 characters
- Chunks needed: ~6-10 chunks (at 5000 chars each)
- TTS requests per episode: ~6-10 API calls
- Processing time: ~30-60 seconds per episode

**Theoretical Maximum (TTS Limited):**
```
300 requests/min ÷ 8 requests/episode = ~37 episodes/minute
= ~2,220 episodes/hour
= ~53,280 episodes/day
```

**Reality Check:**
With Cloud Run timeout (600s) and sequential processing:
- **Actual throughput**: ~1-2 episodes/minute
- **Daily capacity**: ~2,000-3,000 episodes/day

---

### **Cloud Run Service Limits**

**Current Configuration:**
```bash
--max-instances 1      # ← THE LIMITING FACTOR
--memory 2Gi
--timeout 600s
```

**What this means:**
- ✅ **ONE concurrent episode processing** at a time
- ✅ **Multiple publish requests** can queue (Cloud Tasks handles this)
- ❌ **Cannot process episodes in parallel** (single instance)

**If we change to `--max-instances 10`:**
- ✅ 10 episodes processing simultaneously
- ✅ 10x throughput (~20 episodes/minute)
- ⚠️ Still limited by TTS quota (300 req/min project-wide)

---

### **Cloud Tasks Queue Limits**

**Current Configuration:**
```bash
--max-attempts=3
--max-retry-duration=1h
```

**Google Cloud Tasks Limits:**
- **Max queue size**: 100,000 tasks (essentially unlimited for this use case)
- **Dispatch rate**: 500 tasks/second (way more than needed)
- **Max concurrent dispatches**: Configurable (default: 1000)

**What this means:**
- ✅ Can **queue thousands of episodes** without issue
- ✅ Will **dispatch to workers** as fast as workers can handle
- ✅ **No bottleneck** at the queue layer

---

### **Google Cloud Storage Limits**

**Operations:**
- **Upload rate**: 1,000 writes/second per bucket (no issue)
- **Download rate**: Unlimited reads
- **Storage**: Unlimited

**What this means:**
- ✅ **Not a bottleneck** at any realistic scale

---

## Scalability by User Count

### **Current Setup (Wave 1: Single User)**

```
Max throughput: 1-2 episodes/minute
Daily capacity: 2,000+ episodes
Users: 1 (personal use)
```

**Verdict:** Massive overkill for personal use

---

### **10 Users (Light Usage)**

**Assumptions:**
- Each user publishes ~2 episodes/day
- Total: 20 episodes/day
- Peak: 5 episodes/hour

**Bottlenecks:**
- None

**Configuration:**
```bash
--max-instances 1
--min-instances 0
--memory 2Gi
```

**Changes Needed:**
- None for Wave 1
- Add user isolation (Wave 2)

**Monthly Cost:** ~$5-10

**Verdict:** Works perfectly with current setup

---

### **100 Users (Medium Usage)**

**Assumptions:**
- Each user publishes ~1 episode/day
- Total: 100 episodes/day
- Peak: 20 episodes/hour (~1 every 3 minutes)

**Bottlenecks:**
- None (well within capacity)

**Configuration:**
```bash
--max-instances 2
--min-instances 0
--memory 2Gi
```

**Changes Needed:**
- Add user isolation (Wave 2) ✅ Already planned
- Add rate limiting per user (prevent one user from hogging queue)

**Monthly Cost:** ~$10-30

**Verdict:** Easy to support

---

### **1,000 Users (Heavy Usage)**

**Assumptions:**
- Each user publishes ~0.5 episodes/day
- Total: 500 episodes/day
- Peak: 100 episodes/hour (~1.7 per minute)

**Bottlenecks:**
- **Still fine** with current architecture
- Might hit TTS quota during peak bursts

**Configuration:**
```bash
--max-instances 5
--min-instances 0
--memory 2Gi

# Cloud Tasks queue config
gcloud tasks queues update episode-processing \
  --max-dispatches-per-second 5 \
  --max-concurrent-dispatches 5
```

**Changes Needed:**
- Increase max instances: `--max-instances 5`
- Add user rate limiting (e.g., 10 episodes/day per user)
- Consider TTS quota increase request from Google
- Add monitoring for TTS quota usage

**Monthly Cost:** ~$50-200

**Verdict:** Supportable with minor config changes

---

### **10,000 Users (Enterprise Scale)**

**Assumptions:**
- Each user publishes ~0.1 episodes/day
- Total: 1,000 episodes/day
- Peak: 200 episodes/hour (~3-4 per minute)

**Bottlenecks:**
- **TTS quota** becomes real constraint
- **Cloud Run costs** start to matter

**Configuration:**
```bash
--max-instances 20
--min-instances 1  # Keep one instance warm
--memory 2Gi

# Cloud Tasks queue config
gcloud tasks queues update episode-processing \
  --max-dispatches-per-second 10 \
  --max-concurrent-dispatches 10
```

**Changes Needed:**
1. **Request TTS quota increase** from Google (300 → 1000+ req/min)
2. **Add Redis for rate limiting** (track per-user quotas)
3. **Add database** (replace JSON manifest with PostgreSQL)
4. **Add monitoring** (Cloud Monitoring + alerting)
5. **Add CDN** (for MP3 delivery)

**Monthly Costs (estimate):**
- Cloud Run: $50-100
- TTS: $200-500 (depending on article length)
- Cloud Tasks: $0 (free tier)
- Cloud Storage: $10-20
- Cloud SQL (PostgreSQL): $50-100
- Redis (Memorystore): $30-50
- **Total: ~$400-800/month**

**Verdict:** Architecture still works, but needs production-grade additions

---

### **100,000+ Users (Massive Scale)**

**At this point, you'd need:**
1. **Multiple GCP projects** (TTS quota is per-project)
2. **Sharding** (distribute users across projects)
3. **Load balancer** (route to multiple API services)
4. **Database** (Postgres or Firestore for user/episode data)
5. **CDN** (Cloud CDN for serving MP3s and RSS feeds)
6. **Monitoring/Alerting** (Datadog, New Relic, etc.)
7. **Auto-scaling** (based on queue depth)

**Architecture:**
```
                    ┌─────────────────┐
                    │   Load Balancer │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
         │ Project │    │ Project │    │ Project │
         │   #1    │    │   #2    │    │   #3    │
         └─────────┘    └─────────┘    └─────────┘
         Users 1-33K    Users 34-66K   Users 67-100K
```

**Monthly Costs:** $5,000-15,000+

---

## Simultaneous TTS Requests

**Question:** How many TTS requests can run at the same time?

**Answer:** Depends on configuration.

### **Current Setup (max-instances: 1)**
```
Simultaneous episodes processing: 1
Simultaneous TTS requests: 1 episode × 8 chunks = 8 requests
```

The `ChunkedSynthesizer` uses a thread pool for parallel chunk processing:
```ruby
# From lib/tts/chunked_synthesizer.rb
ThreadPool.new(max_size: 5) do |chunk|
  # Process chunk
end
```

With 1 instance:
- **1 episode** processing
- **Up to 5 TTS API calls** in parallel (thread pool)
- **Limited by thread pool size**, not Cloud Run

### **Increased Instances (max-instances: 10)**
```
Simultaneous episodes: 10
Thread pool per instance: 5
Theoretical max TTS calls: 10 × 5 = 50 concurrent
```

**BUT:** Google Cloud TTS has **concurrent request limits**:
- **Standard**: ~100 concurrent requests per project
- **Chirp 3 HD**: Likely lower (~50 concurrent)

**So the real limit is:**
```
Max simultaneous TTS requests: ~50-100 (Google's limit)
Max simultaneous episodes: ~10-20 instances
Max thread pool size: 5 per instance
```

---

## Recommended Configurations by Scale

### **Personal Use (1 User, Wave 1)**
```bash
# Cloud Run deployment
--max-instances 1
--min-instances 0
--memory 2Gi
--timeout 600s
```

**Capacity:**
- Episodes/hour: 60-120
- Daily capacity: 1,500-3,000

**Cost:** ~$0-5/month (free tier)

---

### **10-100 Users (Wave 2)**
```bash
# Cloud Run deployment
--max-instances 3
--min-instances 0
--memory 2Gi
--timeout 600s

# Cloud Tasks queue config
gcloud tasks queues update episode-processing \
  --max-dispatches-per-second 2 \
  --max-concurrent-dispatches 3
```

**Capacity:**
- Episodes/hour: 180-360
- Daily capacity: 4,500-9,000

**Cost:** ~$10-30/month

---

### **1,000 Users (Production)**
```bash
# Cloud Run deployment
--max-instances 10
--min-instances 1  # Keep one warm
--memory 2Gi
--timeout 600s

# Cloud Tasks queue config
gcloud tasks queues update episode-processing \
  --max-dispatches-per-second 5 \
  --max-concurrent-dispatches 10

# Request TTS quota increase to 1000 req/min from Google
```

**Capacity:**
- Episodes/hour: 600-1,200
- Daily capacity: 15,000-30,000

**Cost:** ~$200-500/month

**Additional Requirements:**
- User rate limiting (10 episodes/day per user)
- Monitoring and alerting
- Database for user management

---

### **10,000+ Users (Enterprise)**

**Architecture Changes Required:**
- Multiple GCP projects (shard by user)
- Database (PostgreSQL on Cloud SQL)
- Redis (Cloud Memorystore for rate limiting)
- Monitoring (Cloud Monitoring + Datadog)
- CDN (Cloud CDN for MP3 delivery)
- Load balancer for API routing

**Configuration:**
```bash
# Per-project Cloud Run deployment
--max-instances 20
--min-instances 2
--memory 2Gi
--timeout 600s

# Multiple projects for TTS quota distribution
```

**Capacity:**
- Episodes/hour: 2,000-4,000 (across projects)
- Daily capacity: 50,000-100,000

**Cost:** $1,000-5,000/month

---

## Capacity Summary Table

| Max Instances | Episodes/Hour | Daily Capacity | Users (1 ep/day) | Monthly Cost |
|---------------|---------------|----------------|------------------|--------------|
| 1 (current)   | 60-120        | 1,500-3,000    | 1,000-3,000      | $5-20        |
| 3             | 180-360       | 4,500-9,000    | 5,000-10,000     | $20-50       |
| 10            | 600-1,200     | 15,000-30,000  | 15,000-30,000    | $50-200      |
| 20 (+ quota)  | 1,200-2,400   | 30,000-60,000  | 30,000-60,000    | $200-500     |

---

## Key Bottlenecks

### **1. TTS API Quota (Primary Bottleneck)**

**Limit:** 300 requests/minute per project (default)

**Impact:**
- Caps throughput at ~37 episodes/minute (theoretical)
- In practice: ~20-30 episodes/minute with optimal configuration

**Mitigation:**
1. Request quota increase from Google Cloud (can go to 1000+ req/min)
2. Implement intelligent chunking to minimize requests
3. Use multiple GCP projects for sharding at massive scale

**When it matters:** 1,000+ users with moderate usage

---

### **2. Cloud Run Concurrency (Secondary Bottleneck)**

**Limit:** Set by `--max-instances` configuration

**Impact:**
- With `max-instances: 1` → only 1 episode processes at a time
- With `max-instances: 10` → 10 concurrent episodes

**Mitigation:**
1. Increase `--max-instances` based on expected load
2. Set `--min-instances` to keep warm instances for low latency
3. Monitor instance utilization and adjust

**When it matters:** 100+ users with bursty traffic

---

### **3. Cost Optimization**

**Trade-off:** Higher concurrency = higher costs

**TTS Costs (Primary):**
- Google Cloud TTS: ~$4 per 1 million characters
- Average article: 30,000 characters = $0.12 per episode
- 1,000 episodes/day = $120/day = $3,600/month

**Cloud Run Costs (Secondary):**
- Compute time: $0.00002400 per vCPU-second
- Memory: $0.00000250 per GiB-second
- 60-second episode processing = ~$0.003 per episode
- 1,000 episodes/day = $3/day = $90/month

**Total at 1,000 episodes/day:** ~$3,700/month (mostly TTS)

---

## Monitoring Recommendations

### **Essential Metrics (All Scales)**

1. **TTS Quota Usage**
   - Monitor via Cloud Monitoring API quotas
   - Alert at 80% of quota limit

2. **Cloud Tasks Queue Depth**
   - Monitor pending tasks
   - Alert if queue grows beyond expected (e.g., >100 tasks)

3. **Processing Success Rate**
   - Track successful vs failed episodes
   - Alert on error rate >5%

4. **Processing Duration**
   - P50, P95, P99 latencies
   - Alert if P95 >120 seconds (indicates TTS slowness)

### **Production Metrics (1,000+ Users)**

5. **Per-User Rate Limits**
   - Track episodes/day per user
   - Alert on abuse patterns

6. **Cost Tracking**
   - TTS character count per episode
   - Daily/monthly cost projections

7. **Instance Utilization**
   - Cloud Run instance count over time
   - Auto-scaling effectiveness

---

## Recommendations by Phase

### **Wave 1 (Personal Use)**
```bash
# Configuration
--max-instances 1
--min-instances 0
```

**Reasoning:**
- Saves money (free tier)
- Perfect for personal use
- Easy to increase later

**No additional changes needed.**

---

### **Wave 2 (Multi-User, 10-100 Users)**
```bash
# Configuration
--max-instances 3
--min-instances 0

# Cloud Tasks
--max-dispatches-per-second 2
--max-concurrent-dispatches 3
```

**Changes Needed:**
1. Add user isolation (GCS path prefixes)
2. Add per-user rate limiting (10 episodes/day)
3. Basic monitoring (Cloud Logging)

**Estimated Cost:** ~$10-30/month

---

### **Production (1,000+ Users)**
```bash
# Configuration
--max-instances 10
--min-instances 1

# Cloud Tasks
--max-dispatches-per-second 5
--max-concurrent-dispatches 10
```

**Changes Needed:**
1. Request TTS quota increase from Google
2. Add database (PostgreSQL) for user/episode management
3. Add Redis for distributed rate limiting
4. Add monitoring and alerting
5. Consider CDN for MP3 delivery

**Estimated Cost:** ~$200-500/month

---

### **Enterprise (10,000+ Users)**

**Architecture Changes:**
- Multi-project sharding (distribute TTS quota)
- Load balancer for API routing
- Database with read replicas
- CDN for all static content
- Dedicated monitoring/alerting infrastructure

**Estimated Cost:** $1,000-5,000+/month

---

## Key Takeaways

### **✅ Good News**

1. **Architecture scales well** to ~10,000 users without major changes
2. **Bottleneck is clear**: TTS quota (can be increased by Google)
3. **Cloud Tasks handles queueing** perfectly (no bottleneck)
4. **Cloud Run scales automatically** (just adjust max-instances)
5. **No database needed** until ~1,000+ users

### **⚠️ Constraints**

1. **TTS quota**: 300 req/min (hard limit, requires Google approval to increase)
2. **Single instance**: Current config processes 1 episode at a time
3. **No rate limiting**: One user could spam and block others (fix in Wave 2)
4. **No monitoring**: Can't see bottlenecks until users complain

### **💡 Scaling Path**

1. **0-100 users**: Current architecture works perfectly
2. **100-1,000 users**: Increase max-instances, add rate limiting
3. **1,000-10,000 users**: Request TTS quota increase, add database
4. **10,000+ users**: Multi-project sharding, full production infrastructure

---

## Future Optimizations

### **Short Term (Wave 2)**
- Eliminate temporary MP3 files (save disk I/O)
- Add user-specific rate limiting
- Add basic cost tracking logs

### **Medium Term (Production)**
- Cache TTS results (deduplicate identical content)
- Implement smart chunking (optimize for TTS quota)
- Add webhook notifications for completion

### **Long Term (Enterprise)**
- Multi-region deployment (lower latency)
- Voice selection per user (premium feature)
- Background music mixing (premium feature)
- Transcript generation (speech-to-text)

---

## Conclusion

The single-service Cloud Run + Cloud Tasks architecture is **well-suited for scaling from 1 to 10,000+ users** with minimal architectural changes. The primary bottleneck is Google Cloud TTS API quota, which can be increased through Google support requests.

**Current configuration** (max-instances: 1) supports:
- **Personal use**: Unlimited capacity
- **10-100 users**: No changes needed
- **1,000 users**: Increase to max-instances: 5-10
- **10,000+ users**: Requires TTS quota increase + production infrastructure

**Cost remains reasonable** even at scale, with TTS charges being the primary driver (~$0.12 per episode).
