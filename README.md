```
┌┐┌┌┬┐┌─┐
│││ │ └─┐   note to self
┘└┘ ┴ └─┘
```

Quick markdown notes from your terminal. Zero friction, zero setup.

```
nts "OAuth tokens expire after 1hr not 2hr" -l work,auth -b "the IdP changed defaults"
```

A markdown file is created with frontmatter, tagged, and saved to `~/nts/`. If you skip `-b`, your `$EDITOR` opens. Notes are plain `.md` files — move them to Obsidian, Hugo, or `grep` them.

## Install

```
npm install -g @igorsheg/nts
```

Or build from source (requires [Zig](https://ziglang.org/) 0.14+):

```
git clone https://github.com/igorsheg/nts && cd nts && make install
```

## What makes it different

**Auto-context.** Create a note inside a git repo and nts captures where you are — project, branch, commit, even the files you're touching:

```yaml
context:
  project: auth-service
  branch: fix/PROJ-123-oauth-refresh
  issue: PROJ-123
  commit: a1b2c3d
  dirty: true
  files:
    - src/auth/token.go
```

Weeks later: `nts list -p auth-service` shows everything you learned in that repo.

**Fuzzy everything.** Every command takes a query. Type enough to be unique:

```
nts show redis                → shows Redis Caching Strategy
nts edit lars                 → opens 1:1 with Lars in $EDITOR
nts append standup "update"   → appends to today's standup
```

Ambiguous? It tells you:

```
error: ambiguous match for "redis", found 2 notes:
  redis-caching-strategy    Redis Caching Strategy
  redis-monitoring-setup    Redis Monitoring Setup
use the full slug to be specific
```

**Interactive picker.** `nts show` or `nts edit` with no args opens an inline fuzzy finder:

```
> red
▸ redis-caching-strategy  Redis Caching Strategy  [tech, redis]
  1/21
```

**Agent-native.** Every command supports `--json` with HATEOAS envelopes — agents get structured output with next actions:

```json
{
  "ok": true,
  "command": "nts new -t \"OAuth fix\"",
  "result": { "title": "OAuth fix", "path": "/Users/you/nts/oauth-fix.md" },
  "next_actions": [
    { "command": "nts show oauth-fix", "description": "Show this note" },
    { "command": "nts append oauth-fix <text>", "description": "Append to this note" }
  ]
}
```

## Commands

Run `nts --help` for the full reference, or `nts <command> --help` for any subcommand.

```
nts "Title"              create a note (shorthand for nts new)
nts list                 list notes
nts show <slug>          show a note (glamour-rendered in TTY)
nts search <query>       fuzzy + full-text search
nts edit <slug>          re-open in $EDITOR
nts append <slug> "text" add to an existing note
nts config               show/modify configuration
```

## Shell completions

```bash
# zsh
echo 'source <(nts completion zsh)' >> ~/.zshrc

# bash
echo 'source <(nts completion bash)' >> ~/.bashrc

# fish
nts completion fish > ~/.config/fish/completions/nts.fish
```

Tab-completes note slugs with titles as descriptions.

## License

MIT
