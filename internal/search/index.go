package search

import (
	"strings"
	"time"

	"github.com/blevesearch/bleve/v2"
	"github.com/igorsheg/nts/internal/note"
)

type Index struct {
	idx bleve.Index
}

type bleveDoc struct {
	Title  string    `json:"title"`
	Body   string    `json:"body"`
	Labels string    `json:"labels"`
	Date   time.Time `json:"date"`
	Path   string    `json:"path"`
}

func OpenIndex(path string) (*Index, error) {
	idx, err := bleve.Open(path)
	if err == bleve.ErrorIndexPathDoesNotExist {
		mapping := bleve.NewIndexMapping()
		idx, err = bleve.New(path, mapping)
	}
	if err != nil {
		return nil, err
	}
	return &Index{idx: idx}, nil
}

func (ix *Index) IndexNote(n *note.Note) error {
	doc := bleveDoc{
		Title:  n.Title,
		Body:   n.Body,
		Labels: strings.Join(n.Labels, " "),
		Date:   n.Date,
		Path:   n.Path,
	}
	return ix.idx.Index(n.Path, doc)
}

func (ix *Index) IndexAll(notes []*note.Note) error {
	batch := ix.idx.NewBatch()
	for _, n := range notes {
		doc := bleveDoc{
			Title:  n.Title,
			Body:   n.Body,
			Labels: strings.Join(n.Labels, " "),
			Date:   n.Date,
			Path:   n.Path,
		}
		if err := batch.Index(n.Path, doc); err != nil {
			return err
		}
	}
	return ix.idx.Batch(batch)
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
