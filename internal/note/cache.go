package note

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/igorsheg/nts/internal/gitctx"
)

type CachedMeta struct {
	Title   string         `json:"title"`
	Labels  []string       `json:"labels"`
	Date    time.Time      `json:"date"`
	Context gitctx.Context `json:"context"`
	ModTime int64          `json:"mod_time"`
}

type Cache struct {
	Entries map[string]CachedMeta `json:"entries"`
	path    string
}

func LoadCache(path string) *Cache {
	c := &Cache{
		Entries: make(map[string]CachedMeta),
		path:    path,
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return c
	}

	if json.Unmarshal(data, c) != nil {
		c.Entries = make(map[string]CachedMeta)
	}
	return c
}

func (c *Cache) Save() error {
	if err := os.MkdirAll(filepath.Dir(c.path), 0o755); err != nil {
		return err
	}
	data, err := json.Marshal(c)
	if err != nil {
		return err
	}
	return os.WriteFile(c.path, data, 0o644)
}

func ParseAllCached(dir string, cachePath string) ([]*Note, error) {
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		return nil, nil
	}

	cache := LoadCache(cachePath)

	var mdPaths []string
	err := filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || filepath.Ext(path) != ".md" {
			return nil
		}
		abs, err := filepath.Abs(path)
		if err != nil {
			return err
		}
		mdPaths = append(mdPaths, abs)
		return nil
	})
	if err != nil {
		return nil, err
	}

	existing := make(map[string]struct{}, len(mdPaths))
	var stalePaths []string
	var notes []*Note

	for _, p := range mdPaths {
		existing[p] = struct{}{}

		info, err := os.Stat(p)
		if err != nil {
			return nil, err
		}
		mtime := info.ModTime().UnixNano()

		if cached, ok := cache.Entries[p]; ok && cached.ModTime == mtime {
			notes = append(notes, &Note{
				Title:   cached.Title,
				Labels:  cached.Labels,
				Date:    cached.Date,
				Body:    "",
				Dir:     filepath.Dir(p),
				Path:    p,
				Context: cached.Context,
			})
		} else {
			stalePaths = append(stalePaths, p)
		}
	}

	if len(stalePaths) > 0 {
		type parseResult struct {
			note *Note
			err  error
		}

		paths := make(chan string, len(stalePaths))
		results := make(chan parseResult, len(stalePaths))

		var wg sync.WaitGroup
		for i := 0; i < runtime.NumCPU(); i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				for path := range paths {
					n, err := Parse(path)
					results <- parseResult{n, err}
				}
			}()
		}

		for _, p := range stalePaths {
			paths <- p
		}
		close(paths)

		go func() { wg.Wait(); close(results) }()

		for r := range results {
			if r.err != nil {
				return nil, r.err
			}
			notes = append(notes, r.note)

			info, err := os.Stat(r.note.Path)
			if err != nil {
				return nil, err
			}
			cache.Entries[r.note.Path] = CachedMeta{
				Title:   r.note.Title,
				Labels:  r.note.Labels,
				Date:    r.note.Date,
				Context: r.note.Context,
				ModTime: info.ModTime().UnixNano(),
			}
		}
	}

	for p := range cache.Entries {
		if _, ok := existing[p]; !ok {
			delete(cache.Entries, p)
		}
	}

	_ = cache.Save()

	sort.Slice(notes, func(i, j int) bool {
		return notes[i].Path < notes[j].Path
	})

	return notes, nil
}

func ParseBodyOnly(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	inFrontmatter := false
	var body strings.Builder

	for scanner.Scan() {
		line := scanner.Text()
		if line == "---" {
			if !inFrontmatter {
				inFrontmatter = true
				continue
			}
			for scanner.Scan() {
				body.WriteString(scanner.Text())
				body.WriteByte('\n')
			}
			break
		}
	}

	if err := scanner.Err(); err != nil {
		return "", err
	}

	return strings.TrimSpace(body.String()), nil
}
