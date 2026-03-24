package search

import (
	"os"
	"strings"
	"time"

	"github.com/blevesearch/bleve/v2"
	"github.com/igorsheg/nts/internal/note"
)

type Index struct {
	idx bleve.Index
}

type bleveDoc struct {
	Title   string    `json:"title"`
	Body    string    `json:"body"`
	Labels  string    `json:"labels"`
	Date    time.Time `json:"date"`
	Path    string    `json:"path"`
	ModTime int64     `json:"mod_time"`
}

func OpenIndex(path string) (*Index, error) {
	idx, err := bleve.Open(path)
	if err == bleve.ErrorIndexPathDoesNotExist {
		mapping := bleve.NewIndexMapping()

		docMapping := bleve.NewDocumentMapping()

		modTimeField := bleve.NewNumericFieldMapping()
		modTimeField.Store = true
		modTimeField.Index = false
		docMapping.AddFieldMappingsAt("mod_time", modTimeField)

		mapping.DefaultMapping = docMapping
		idx, err = bleve.New(path, mapping)
	}
	if err != nil {
		return nil, err
	}
	return &Index{idx: idx}, nil
}

func (ix *Index) IndexNote(n *note.Note) error {
	info, err := os.Stat(n.Path)
	if err != nil {
		return err
	}
	doc := bleveDoc{
		Title:   n.Title,
		Body:    n.Body,
		Labels:  strings.Join(n.Labels, " "),
		Date:    n.Date,
		Path:    n.Path,
		ModTime: info.ModTime().Unix(),
	}
	return ix.idx.Index(n.Path, doc)
}

func (ix *Index) IndexChanged(notes []*note.Note) (int, error) {
	batch := ix.idx.NewBatch()
	indexed := 0

	for _, n := range notes {
		existing, _ := ix.idx.Document(n.Path)
		if existing != nil && n.Body == "" {
			continue
		}

		body := n.Body
		if body == "" {
			b, err := note.ParseBodyOnly(n.Path)
			if err != nil {
				continue
			}
			body = b
		}

		var mtime int64
		if info, err := os.Stat(n.Path); err == nil {
			mtime = info.ModTime().Unix()
		}

		doc := bleveDoc{
			Title:   n.Title,
			Body:    body,
			Labels:  strings.Join(n.Labels, " "),
			Date:    n.Date,
			Path:    n.Path,
			ModTime: mtime,
		}
		if err := batch.Index(n.Path, doc); err != nil {
			return 0, err
		}
		indexed++
	}

	if indexed > 0 {
		if err := ix.idx.Batch(batch); err != nil {
			return 0, err
		}
	}

	return indexed, nil
}

func (ix *Index) Search(query string, limit int) ([]*Result, error) {
	q := bleve.NewQueryStringQuery(query)
	req := bleve.NewSearchRequestOptions(q, limit, 0, false)
	res, err := ix.idx.Search(req)
	if err != nil {
		return nil, err
	}

	results := make([]*Result, len(res.Hits))
	for i, hit := range res.Hits {
		results[i] = &Result{
			Note:  &note.Note{Path: hit.ID},
			Score: int(hit.Score * 1000),
		}
	}
	return results, nil
}

func (ix *Index) Close() error {
	return ix.idx.Close()
}
