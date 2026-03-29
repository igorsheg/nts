#!/usr/bin/env bash
set -euo pipefail

NTS="${NTS:-./zig-out/bin/nts}"

echo "=== seeding nts corpus ==="

# work meetings
$NTS new -t "Q1 Planning with Product" -l work,meeting -b "## Attendees
- Sarah (PM)
- Mike (Eng Lead)
- Igor

## Decisions
- Prioritize search infra over new features
- Ship v2 API by end of March
- Hire 2 more backend engineers

## Action Items
- [ ] Igor: draft RFC for search redesign
- [ ] Sarah: update roadmap in Linear
- [ ] Mike: schedule architecture review"

$NTS new -t "1:1 with Lars" -l work,meeting,1on1 -b "## Topics
- Career growth discussion
- Project handoff for auth service
- PTO request for April

## Notes
Lars wants to move toward more system design work. Suggested he lead the
caching layer redesign. He's excited about it.

Flagged that the auth service migration is behind by ~2 weeks. Root cause
is the OAuth provider changing their token format without notice."

$NTS new -t "Incident Retro: Payment Service Outage" -l work,incident,meeting -b "## Timeline
- 14:23 UTC: First alert from Datadog
- 14:25 UTC: On-call acknowledged
- 14:31 UTC: Identified connection pool exhaustion
- 14:45 UTC: Rolled back deployment
- 15:02 UTC: Full recovery confirmed

## Root Cause
Connection pool max was set to 10 in the new deployment config.
Previous default was 50. Config change was not reviewed.

## Action Items
- [ ] Add connection pool size to deployment checklist
- [ ] Set up config diff alerts in CI
- [ ] Add circuit breaker to payment gateway client"

$NTS new -t "Sprint Retrospective Week 12" -l work,meeting,retro -b "## What went well
- Shipped notification service on time
- Good cross-team collaboration on the API redesign
- New monitoring dashboards caught 3 issues before users did

## What could improve
- Too many context switches between projects
- PR review turnaround is 2+ days on average
- Flaky tests in CI are demoralizing

## Actions
- Dedicate Wed/Thu as focus days (no meetings)
- Set up PR review roulette bot
- Create a flaky test quarantine process"

# technical notes
$NTS new -t "PostgreSQL Query Optimization Notes" -l tech,postgres,performance -b "## Key learnings from today

\`EXPLAIN ANALYZE\` is your best friend. Always use it with \`BUFFERS\` option.

### Index strategies
- B-tree for equality and range queries
- GIN for full-text search and JSONB
- GiST for geometric and range types
- BRIN for naturally ordered data (timestamps)

### Common pitfalls
1. Using \`SELECT *\` when you only need 2 columns
2. Not using partial indexes for filtered queries
3. Forgetting to VACUUM after bulk deletes
4. Using \`OFFSET\` for pagination (use keyset pagination instead)

### Query that fixed our slow dashboard
\`\`\`sql
CREATE INDEX CONCURRENTLY idx_orders_status_created
ON orders (status, created_at DESC)
WHERE status IN ('pending', 'processing');
\`\`\`
Went from 1200ms to 3ms."

$NTS new -t "Go Error Handling Patterns" -l tech,golang,patterns -b "## Sentinel errors vs custom types

Prefer custom error types when callers need to inspect:
\`\`\`go
type NotFoundError struct {
    Resource string
    ID       string
}
func (e *NotFoundError) Error() string {
    return fmt.Sprintf(\"%s %s not found\", e.Resource, e.ID)
}
\`\`\`

## Wrapping with context
Always wrap with \`fmt.Errorf(\"doing X: %w\", err)\` — the verb \`%w\` preserves
the error chain for \`errors.Is()\` and \`errors.As()\`.

## Don't log and return
Pick one. Logging AND returning propagates the same error message
multiple times up the stack. Log at the top, wrap everywhere else."

$NTS new -t "Docker Multi-stage Build Optimization" -l tech,docker,devops -b "## Before: 1.2GB image

\`\`\`dockerfile
FROM golang:1.22
COPY . .
RUN go build -o app .
\`\`\`

## After: 12MB image

\`\`\`dockerfile
FROM golang:1.22 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags='-s -w' -o app .

FROM scratch
COPY --from=builder /src/app /app
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
ENTRYPOINT [\"/app\"]
\`\`\`

Key: use scratch base, disable CGO, strip debug symbols.
Don't forget CA certs if you make HTTPS calls."

$NTS new -t "Kubernetes Debugging Cheatsheet" -l tech,k8s,devops -b "## Pod won't start
\`\`\`bash
kubectl describe pod <name>    # check Events section
kubectl logs <name> --previous # logs from crashed container
kubectl get events --sort-by=.metadata.creationTimestamp
\`\`\`

## Network debugging
\`\`\`bash
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash
nslookup my-service.my-namespace.svc.cluster.local
curl -v http://my-service:8080/health
\`\`\`

## Resource issues
\`\`\`bash
kubectl top pods              # actual CPU/memory usage
kubectl describe node         # check Allocatable vs Allocated
\`\`\`

## Quick rollback
\`\`\`bash
kubectl rollout undo deployment/my-app
kubectl rollout status deployment/my-app
\`\`\`"

$NTS new -t "TypeScript Strict Mode Migration" -l tech,typescript -b "## Steps we followed
1. Enable \`strict: true\` in tsconfig
2. Fix \`noImplicitAny\` errors first (biggest batch)
3. Then \`strictNullChecks\` (most impactful for correctness)
4. Finally \`strictFunctionTypes\`

## Patterns that helped
- Use \`unknown\` instead of \`any\` for external data
- Discriminated unions for state machines
- \`satisfies\` operator for type-safe object literals
- Branded types for IDs: \`type UserId = string & { __brand: 'UserId' }\`

## Stats
- 847 errors after enabling strict
- Took 3 engineers 2 weeks
- Found 12 actual bugs in the process
- Worth it."

$NTS new -t "Redis Caching Strategy" -l tech,redis,architecture -b "## Cache-aside pattern
1. Check cache first
2. On miss, read from DB
3. Write to cache with TTL
4. On write to DB, invalidate cache

## Key naming convention
\`{service}:{entity}:{id}\` e.g. \`user-svc:profile:12345\`

## TTL guidelines
- User sessions: 30 min
- API responses: 5 min
- Feature flags: 1 min
- Static config: 1 hour

## Gotchas
- Cache stampede: use mutex/singleflight on cache miss
- Hot keys: use local in-memory cache (L1) in front of Redis (L2)
- Serialization: use msgpack over JSON (2-3x smaller, faster)"

# personal / ideas
$NTS new -t "Book Notes: Designing Data-Intensive Applications" -l reading,tech -b "## Chapter 5: Replication

Three main approaches:
1. **Single-leader**: all writes go through one node
2. **Multi-leader**: writes accepted on multiple nodes
3. **Leaderless**: any node accepts reads and writes

Key insight: replication lag is not a bug, it's a fundamental
tradeoff. You can have consistency OR availability during
network partitions (CAP theorem), but the real question is
how much inconsistency your application can tolerate.

## Chapter 7: Transactions

ACID is not as precise as people think:
- Atomicity: not about concurrency, about abort-ability
- Consistency: actually a property of the application, not DB
- Isolation: the complex one (serializable, snapshot, read committed)
- Durability: also not absolute (disk can fail)

The default isolation level in most DBs (read committed) does NOT
prevent write skew. You need serializable for that."

$NTS new -t "Side Project Ideas" -l ideas,personal -b "## CLI tool for time tracking
- Track time from terminal: \`tt start \"working on nts\"\`
- Auto-stop after idle
- Weekly report generation
- Integrate with calendar for meeting time

## Local-first recipe manager
- Markdown files for recipes
- Auto-scale ingredients
- Meal planning with shopping list generation
- Sync via git

## Home automation dashboard
- Raspberry Pi + e-ink display
- Show weather, calendar, todo list
- Update every 15 minutes
- Low power consumption"

$NTS new -t "Workout Log Template" -l fitness,personal -b "## Push Day - March 2026

### Bench Press
- 135 x 10 (warmup)
- 185 x 8
- 205 x 6
- 205 x 5

### Overhead Press
- 95 x 10
- 115 x 8
- 125 x 6

### Notes
Felt strong today. Sleep was good (7.5 hrs).
Increase bench to 210 next session."

$NTS new -t "Trip Planning: Japan 2026" -l travel,personal -b "## Itinerary Draft

### Tokyo (5 days)
- Shibuya, Shinjuku, Akihabara
- Tsukiji outer market (morning)
- TeamLab Borderless
- Day trip to Kamakura

### Kyoto (4 days)
- Fushimi Inari (early morning, avoid crowds)
- Arashiyama bamboo grove
- Kinkaku-ji
- Nishiki market

### Osaka (3 days)
- Dotonbori street food
- Osaka Castle
- Day trip to Nara (deer park)

## Budget
- Flights: ~1200 USD RT
- JR Pass (14 day): ~400 USD
- Hotels: ~150 USD/night
- Food: ~50 USD/day
- Total: ~4500 USD"

$NTS new -t "Garden Planning Spring 2026" -l personal,garden -b "## Vegetable beds
- Tomatoes (Roma, Cherry)
- Peppers (Bell, Jalapeño)
- Basil, Cilantro, Parsley
- Zucchini (only 2 plants this year, learned my lesson)

## Timeline
- March: start seeds indoors
- April: harden off seedlings
- May: transplant after last frost
- June-Sept: harvest season

## Notes from last year
- Tomatoes need more calcium (blossom end rot)
- Companion plant basil with tomatoes
- Marigolds around perimeter for pest control"

$NTS new -t "Home Network Setup" -l tech,homelab -b "## Current setup
- ISP: 1Gbps fiber
- Router: UniFi Dream Machine Pro
- Switch: UniFi 24-port PoE
- APs: 2x UniFi U6 Pro

## VLANs
- VLAN 1: Management (10.0.1.0/24)
- VLAN 10: Trusted devices (10.0.10.0/24)
- VLAN 20: IoT devices (10.0.20.0/24)
- VLAN 30: Guest network (10.0.30.0/24)

## DNS
- Pi-hole on Raspberry Pi 4
- Upstream: Cloudflare (1.1.1.1)
- Local DNS for homelab services

## TODO
- [ ] Set up WireGuard VPN
- [ ] Move Pi-hole to Docker
- [ ] Add UPS for network rack"

# architecture / design notes
$NTS new -t "API Versioning Strategy" -l tech,architecture,api -b "## Options considered

### URL versioning: /v1/users
- Pros: explicit, easy to route, cacheable
- Cons: breaks hypermedia, URL is not the resource

### Header versioning: Accept: application/vnd.api+json;version=2
- Pros: clean URLs, content negotiation
- Cons: harder to test, invisible in logs

### Query param: /users?version=2
- Pros: easy to implement
- Cons: pollutes query string, caching issues

## Decision
URL versioning (/v1/, /v2/) for public APIs. It's the most
discoverable, the most debuggable, and what developers expect.

Header versioning for internal service-to-service APIs where
we control both sides."

$NTS new -t "Event-Driven Architecture Notes" -l tech,architecture -b "## When to use events vs direct calls

Events when:
- Publisher doesn't care about result
- Multiple consumers need the same data
- Temporal decoupling is valuable
- You need audit trail / replay

Direct calls when:
- You need synchronous response
- Strong consistency required
- Simple request/response fits
- < 3 services involved

## Event schema evolution
- Always add fields, never remove
- Use schema registry (Confluent, AWS Glue)
- Version events: UserCreatedV1, UserCreatedV2
- Consumer must handle unknown fields gracefully

## Gotchas
- Exactly-once is a lie. Design for at-least-once + idempotency
- Event ordering only guaranteed within a partition
- Dead letter queues are essential, not optional
- Monitor consumer lag religiously"

$NTS new -t "GraphQL vs REST Decision" -l tech,architecture,api -b "## Our context
- Mobile app with varying screen sizes
- Multiple frontend teams
- Backend team of 8

## Why we chose GraphQL
1. Mobile needs different data shapes per screen
2. Over-fetching was killing our cellular performance
3. Frontend teams can iterate without backend changes
4. Type generation from schema is excellent DX

## What we'd do differently
- Don't expose your entire DB schema through GraphQL
- Use DataLoader from day 1 (N+1 queries killed us)
- Set up query complexity limits early
- Persisted queries for production (security + perf)"

$NTS new -t "Monitoring and Observability Stack" -l tech,devops,monitoring -b "## Three pillars

### Metrics (Prometheus + Grafana)
- RED method for services: Rate, Errors, Duration
- USE method for resources: Utilization, Saturation, Errors
- Custom business metrics: signups/min, orders/hr

### Logging (Loki)
- Structured JSON logs
- Correlation IDs across services
- Log levels: DEBUG in dev, INFO in prod
- Don't log PII

### Tracing (Jaeger)
- OpenTelemetry SDK in all services
- Sample 10% in prod, 100% in staging
- Trace context propagation via W3C headers

## Alert philosophy
- Page only for user-impacting issues
- Everything else goes to Slack
- Every alert must have a runbook link
- Review alert fatigue monthly"

$NTS new -t "Database Migration Checklist" -l tech,postgres,checklist -b "## Before migration
- [ ] Test migration on staging with prod-sized data
- [ ] Measure migration duration
- [ ] Plan rollback strategy
- [ ] Notify on-call and stakeholders
- [ ] Schedule during low-traffic window

## During migration
- [ ] Run in transaction if possible
- [ ] Monitor replication lag
- [ ] Watch for lock contention
- [ ] Keep terminal open with rollback ready

## After migration
- [ ] Verify application health
- [ ] Check query performance
- [ ] Validate data integrity
- [ ] Update documentation
- [ ] Run ANALYZE on affected tables

## Dangerous operations
- Adding NOT NULL without default: locks table
- Changing column type: full table rewrite
- Adding index: use CONCURRENTLY
- Dropping column: ensure no app references remain"

echo ""
echo "=== corpus seeded ==="
echo ""
