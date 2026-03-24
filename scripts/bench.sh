#!/usr/bin/env bash
set -euo pipefail

NTS="./nts"
COUNT="${1:-500}"

echo "=== generating $COUNT notes ==="

for i in $(seq 1 "$COUNT"); do
  tags="bench"
  case $((i % 5)) in
    0) tags="bench,work" ;;
    1) tags="bench,tech" ;;
    2) tags="bench,personal" ;;
    3) tags="bench,architecture" ;;
    4) tags="bench,devops" ;;
  esac

  project="project-$((i % 10))"

  $NTS new -t "Bench Note $i - $(head -c 20 /dev/urandom | base64 | tr -d '/+=' | head -c 12)" \
    -l "$tags" \
    -b "This is benchmark note number $i.

## Section One
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod
tempor incididunt ut labore et dolore magna aliqua. Project $project is
referenced here for search testing.

## Section Two
$(head -c 200 /dev/urandom | base64 | tr -d '/+=' | fold -w 80 | head -5)

## Code Example
\`\`\`go
func handler$i(w http.ResponseWriter, r *http.Request) {
    data, err := fetchData(r.Context())
    if err != nil {
        http.Error(w, err.Error(), 500)
        return
    }
    json.NewEncoder(w).Encode(data)
}
\`\`\`

Keywords: benchmark testing performance optimization goroutine channel
mutex semaphore database query index cache invalidation $project" > /dev/null 2>&1
done

echo "=== $COUNT notes generated ==="
echo "total notes: $(ls /Users/igors/nts/*.md | wc -l | tr -d ' ')"
