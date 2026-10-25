;;;; The packages of trove: TROVE.TEXT turns texts into terms;
;;;; TROVE.INDEX keeps documents and their postings in segments;
;;;; TROVE.SEARCH parses queries and ranks what they match. TROVE has the
;;;; sample archive, and exports what a user of the others needs, so that
;;;; TROVE: is the only prefix to know.

(defpackage #:trove.text
  (:use #:common-lisp)
  (:export
   #:token
   #:token-text
   #:token-start
   #:token-end
   #:token-position
   #:map-tokens
   #:do-tokens
   #:tokenize
   #:stem
   #:*english-stop-words*
   #:analyzer
   #:make-analyzer
   #:analyzer-stop-words
   #:analyzer-stemming-p
   #:word-term
   #:map-terms
   #:analyze))

(defpackage #:trove.index
  (:use #:common-lisp #:trove.text)
  (:export
   ;; Documents
   #:*fields*
   #:document
   #:make-document
   #:document-id
   #:document-title
   #:document-body
   #:document-published
   #:field-text
   ;; Postings and segments
   #:index-vector
   #:make-index-vector
   #:postings
   #:postings-documents
   #:postings-frequencies
   #:postings-starts
   #:postings-positions
   #:postings-count
   #:document-positions
   #:do-postings
   #:segment
   #:segment-number
   #:segment-level
   #:segment-size
   #:segment-live-count
   #:segment-deleted-count
   #:segment-documents
   #:segment-document
   #:segment-postings
   #:live-p
   #:field-length
   #:live-field-length
   #:merge-segments
   ;; The index
   #:index-error
   #:document-exists
   #:document-exists-id
   #:replace-document
   #:index
   #:make-index
   #:index-analyzer
   #:index-flush-size
   #:index-merge-factor
   #:index-segments
   #:index-generation
   #:index-statistics
   #:document-count
   #:find-location
   #:get-document
   #:map-documents
   #:add-document
   #:add-documents
   #:delete-document
   #:update-document
   #:flush
   #:commit))

(defpackage #:trove.search
  (:use #:common-lisp #:trove.text #:trove.index)
  (:export
   #:query-syntax-error
   #:query
   #:term-query
   #:phrase-query
   #:boolean-query
   #:all-query
   #:query-field
   #:query-term
   #:query-terms
   #:query-must
   #:query-should
   #:query-must-not
   #:parse-query
   #:matching-numbers
   #:*field-weights*
   #:score
   #:hit
   #:hit-id
   #:hit-score
   #:hit-title
   #:hit-document
   #:search-index
   #:count-matches
   #:snippet))

(defpackage #:trove
  (:use #:common-lisp #:trove.text #:trove.index #:trove.search)
  (:export
   ;; From TROVE.TEXT
   #:tokenize
   #:stem
   #:make-analyzer
   #:analyze
   ;; From TROVE.INDEX
   #:document
   #:make-document
   #:document-id
   #:document-title
   #:document-body
   #:document-published
   #:index
   #:make-index
   #:index-segments
   #:index-generation
   #:index-statistics
   #:document-count
   #:get-document
   #:map-documents
   #:add-document
   #:add-documents
   #:delete-document
   #:update-document
   #:commit
   #:document-exists
   #:replace-document
   ;; From TROVE.SEARCH
   #:query-syntax-error
   #:parse-query
   #:hit
   #:hit-id
   #:hit-score
   #:hit-title
   #:hit-document
   #:search-index
   #:count-matches
   #:snippet
   ;; The sample archive
   #:make-sample-index
   #:sample-documents
   #:sample-history-documents))
