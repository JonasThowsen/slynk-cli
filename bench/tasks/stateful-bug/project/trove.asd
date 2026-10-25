;;;; trove.asd

(defsystem "trove"
  :description "A full-text search index for the newsroom archive: segments, merging, and ranked queries."
  :version "0.9.0"
  :license "MIT"
  :depends-on ("alexandria")
  :pathname "src/"
  :serial t
  :components ((:file "package")
               (:module "text"
                :serial t
                :components ((:file "tokenizer")
                             (:file "stemmer")
                             (:file "analyzer")))
               (:module "index"
                :serial t
                :components ((:file "documents")
                             (:file "postings")
                             (:file "segments")
                             (:file "merge")
                             (:file "index")))
               (:module "search"
                :serial t
                :components ((:file "query")
                             (:file "matching")
                             (:file "scoring")
                             (:file "search")
                             (:file "snippets")))
               (:file "words")
               (:file "sample"))
  :in-order-to ((test-op (test-op "trove/tests"))))

(defsystem "trove/tests"
  :description "Tests for trove."
  :depends-on ("trove" "fiveam")
  :pathname "tests/"
  :serial t
  :components ((:file "package")
               (:file "text")
               (:file "index")
               (:file "search")
               (:file "sample"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :fiveam :run! :trove)
               (error "trove's tests failed"))))
