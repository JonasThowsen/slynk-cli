# trove

The search index of the newsroom archive: articles in segments, merged
as they grow, and ranked queries over them.

- `src/text/`: the tokenizer, the Porter stemmer and the analyzer.
- `src/index/`: documents, postings, segments, merging, and the index:
  a buffer for new articles, flushed into a segment when it is full and
  at each commit, and deletions that take effect at the commit.
- `src/search/`: the query language (`harbour cranes`, `"harbour
  cranes"`, `title:storm`, `storm -ferry`, `a OR b`), matching, BM25
  ranking and snippets.
- `src/sample.lisp`: a sample archive with the shape of the real one,
  replayed day by day as the nightly import runs: the day's articles,
  corrections to earlier ones, withdrawals, and a commit.

```lisp
(defparameter *index* (trove:make-sample-index))   ; about a minute
(trove:search-index *index* "harbour cranes" :limit 5)
(trove:update-document *index* (trove:make-document "doc-000042" :title "..." :body "..."))
(trove:commit *index*)
```

The packages are `trove.text`, `trove.index` and `trove.search`;
`trove` exports what a user needs of them.

Run the tests with

```lisp
(asdf:test-system "trove")
```
