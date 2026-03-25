```
┌┐┌┌┬┐┌─┐
│││ │ └─┐   note to self
┘└┘ ┴ └─┘
```

Quick markdown notes from your terminal.

```
nts "OAuth tokens expire after 1hr not 2hr"
```

That's it. A markdown file is created with frontmatter, your `$EDITOR` opens, and the note is saved to `~/nts/`. If you pass `-b`, the editor is skipped entirely.

Notes are plain `.md` files. No database, no sync, no lock-in. Move them to Obsidian, Hugo, or `grep` them — they're yours.

## Install

```
npm install -g @igorsheg/nts
```

Or build from source:

```
git clone https://github.com/igorsheg/nts
cd nts && make install
```

## Usage

```
nts "Title of my note"                  # create, open editor
nts "Fix auth bug" -l work -b "..."     # create with body, skip editor
nts list                                # list notes
nts list -l work                        # filter by label
nts search "oauth token"                # fuzzy + full-text search
nts show oauth                          # show a note
nts edit oauth                          # re-open in editor
nts append oauth "new finding"          # add to existing note
echo "piped" | nts new -t "Title"       # stdin
nts list --json                         # structured output
```

## Query resolution

Every command takes a query. Resolution is deterministic:

```
exact slug      →  matches
single fuzzy    →  matches
multiple fuzzy  →  fails, shows candidates
```

Writes (`edit`, `append`) never silently pick the wrong note.

```
$ nts append redis "update"
error: ambiguous match for "redis", found 2 notes:
  redis-caching-strategy    Redis Caching Strategy
  redis-monitoring-setup    Redis Monitoring Setup
use the full slug to be specific
```

## Auto-context

When you create a note inside a git repo, nts captures the project, branch, and directory automatically:

```yaml
---
title: "OAuth tokens expire after 1hr"
date: 2026-03-25T14:30:00+02:00
tags: [work, auth]
context:
  project: auth-service
  branch: fix/oauth
  directory: ~/work/auth-service/src
---
```

Filter by project later:

```
nts list -p auth-service
nts search "token" -p auth-service
```

## Frontmatter

Standard YAML frontmatter. Compatible with Jekyll, Hugo, Obsidian, Astro, Zola.

```yaml
---
title: "My Note"
date: 2026-03-25T14:30:00+02:00
tags: [work, meeting]
context:
  project: my-project
  branch: main
  directory: ~/work/my-project
---
```

## For scripts and agents

```bash
# create and get the slug back
SLUG=$(nts new -t "Finding" -b "details" --json | jq -r '.path' | xargs basename | sed 's/.md//')

# read it back
nts show "$SLUG" --json

# append to it
nts append "$SLUG" "new info"

# list as JSON
nts list --json | jq '.[] | select(.labels | index("work"))'
```

## Config

Stored at `~/.config/nts/config.json`.

```
nts config                          # show config
nts config --set notes_dir=~/notes  # change notes directory
nts config --set editor=nvim        # change editor
```

Falls back to `$EDITOR`, then `vi`.

## License

MIT
