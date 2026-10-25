(in-package #:trove/tests)

(in-suite :trove)

(test sample-documents
  (let ((documents (sample-documents :seed 3 :count 5 :first-number 41)))
    (is (equal '("doc-000041" "doc-000042" "doc-000043" "doc-000044" "doc-000045")
               (mapcar #'document-id documents)))
    (is (every (lambda (document) (plusp (length (document-body document)))) documents))
    (is (equal (mapcar #'document-title documents)
               (mapcar #'document-title (sample-documents :seed 3 :count 5 :first-number 41)))
        "the same seed gives the same articles")))

(test small-sample-archive
  (multiple-value-bind (index history) (make-sample-index :days 12 :articles-per-day 50
                                                          :merge-factor 3)
    (let ((expected (sample-history-documents history)))
      (is (= (length expected) (document-count index)))
      (is (every (lambda (document)
                   (let ((found (get-document index (document-id document))))
                     (and found (string= (document-title found) (document-title document)))))
                 expected)
          "the index has the current version of each article")
      (is (equal (ids (make-sample-index :days 12 :articles-per-day 50 :merge-factor 3)
                      "harbour storm")
                 (ids index "harbour storm"))
          "the same seed gives the same archive"))))
