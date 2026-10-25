(in-package #:trove/tests)

(in-suite :trove)

(test add-and-get
  (let ((index (small-index)))
    (is (= 6 (document-count index)))
    (is (string= "Ferry delayed by the tide" (document-title (get-document index "a3"))))
    (is (null (get-document index "nothing")))
    (signals document-exists (add-document index (article "a3" "Again" "")))
    (handler-bind ((document-exists #'replace-document))
      (add-document index (article "a3" "Ferry on time" "The ferry left on time.")))
    (commit index)
    (is (string= "Ferry on time" (document-title (get-document index "a3"))))
    (is (= 6 (document-count index)))))

(test buffered-documents-wait-for-a-flush
  (let ((index (make-index :flush-size 3)))
    (add-documents index (subseq (articles) 0 2))
    (is (null (ids index "storm")) "the buffer is not searched")
    (is (null (get-document index "a1")))
    (add-document index (third (articles)))
    (is (equal '("a1" "a2" "a3") (sort (ids index "storm") #'string<)) "a full buffer is flushed")
    (add-document index (fourth (articles)))
    (is (= 1 (getf (index-statistics index) :buffered)))
    (commit index)
    (is (= 0 (getf (index-statistics index) :buffered)))
    (is (= 4 (document-count index)))))

(test deletions-take-effect-at-commit
  (let ((index (small-index)))
    (is (delete-document index "a2"))
    (is (not (delete-document index "nothing")))
    (is (member "a2" (ids index "gale") :test #'string=))
    (is (= 6 (document-count index)))
    (commit index)
    (is (null (ids index "gale")))
    (is (null (get-document index "a2")))
    (is (= 5 (document-count index)))))

(test deletions-wait-past-a-flush
  ;; A full buffer is flushed before the commit; the deletion still waits.
  (let ((index (small-index :flush-size 2)))
    (delete-document index "a1")
    (add-documents index (list (article "b1" "Bridge closed" "The bridge closed for repairs.")
                               (article "b2" "Bridge open" "The bridge opened again.")))
    (is (= 0 (getf (index-statistics index) :buffered)))
    (is (member "a1" (ids index "idle") :test #'string=))
    (commit index)
    (is (null (ids index "idle")))
    (is (equal '("b1" "b2") (sort (ids index "bridge") #'string<)))))

(test updates
  (let ((index (small-index)))
    (update-document index (article "a1" "Harbour cranes back at work" "Work resumed at the harbour."))
    (is (equal '("a1") (ids index "idle")) "the old version until the commit")
    (commit index)
    (is (null (ids index "idle")))
    (is (equal '("a1") (ids index "resumed")))
    (is (string= "Harbour cranes back at work" (document-title (get-document index "a1"))))
    (is (= 6 (document-count index)))))

(test updates-in-one-batch
  (let ((index (small-index)))
    (update-document index (article "a4" "Crane delayed" "The new crane is late."))
    (update-document index (article "a4" "Crane arrives" "The new crane came today."))
    (add-document index (article "c1" "Choir concert" "The choir sang in the church."))
    (delete-document index "c1")
    (commit index)
    (is (string= "Crane arrives" (document-title (get-document index "a4"))))
    (is (null (ids index "late")))
    (is (equal '("a4") (ids index "came")))
    (is (null (get-document index "c1")))
    (is (null (ids index "choir")))
    (is (= 6 (document-count index)))))

(test merging
  (let ((index (make-index :flush-size 1 :merge-factor 2)))
    (dolist (document (articles))
      (add-document index document))
    (commit index)
    ;; Six flushes of one document make segments of 4 and 2.
    (is (equal '(0 1 1) (getf (index-statistics index) :levels)))
    (is (equal '(4 2) (mapcar #'segment-size (index-segments index))))
    (is (= 6 (document-count index)))
    (is (equal (ids (small-index) "harbour OR coast") (ids index "harbour OR coast"))
        "a search gives the same however the index is cut")))

(test merging-drops-deleted-documents
  (let ((index (small-index :flush-size 2 :merge-factor 2)))
    (delete-document index "a2")
    (delete-document index "a5")
    (commit index)
    (is (= 4 (document-count index)))
    (is (plusp (getf (index-statistics index) :deleted)))
    ;; The flush of d1 and d2 merges up to a segment of level 2 with
    ;; every document so far, and the one of d3 and d4 stays at level 0.
    (add-documents index (list (article "d1" "One" "one") (article "d2" "Two" "two")))
    (commit index)
    (add-documents index (list (article "d3" "Three" "three") (article "d4" "Four" "four")))
    (commit index)
    (is (equal '(1 0 1) (getf (index-statistics index) :levels)))
    (is (= 0 (getf (index-statistics index) :deleted)))
    (is (= 8 (document-count index)))
    (is (null (get-document index "a2")))
    (is (string= "Ferry delayed by the tide" (document-title (get-document index "a3"))))
    (is (equal '("a1") (ids index "idle")))))
