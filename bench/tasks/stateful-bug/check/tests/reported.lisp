;;;; The reported case, on the full sample archive: a correction of last
;;;; week's article, then the day's import and a commit. Then, on the same
;;;; index, another correction and a withdrawal before an import long
;;;; enough to merge their segment. After each commit every article must
;;;; be the version the history last gave it, once.

(in-package #:trove/tests)

(in-suite :trove)

(defun archive-problems (index expected)
  "Returns the ways INDEX differs from EXPECTED, a hash table from id to
the document it should have: at most a few, as texts."
  (let ((problems '())
        (seen (make-hash-table :test 'equal)))
    (flet ((problem (control &rest arguments)
             (when (< (length problems) 5)
               (push (apply #'format nil control arguments) problems))))
      (map-documents (lambda (document)
                       (let ((id (document-id document)))
                         (when (gethash id seen)
                           (problem "~A is in the index twice" id))
                         (setf (gethash id seen) t)
                         (let ((wanted (gethash id expected)))
                           (cond ((null wanted)
                                  (problem "~A is searchable but was withdrawn" id))
                                 ((string/= (document-title wanted) (document-title document))
                                  (problem "~A is searchable as ~S, not as ~S" id
                                           (document-title document) (document-title wanted)))))))
                     index)
      (maphash (lambda (id wanted)
                 (let ((found (get-document index id)))
                   (cond ((null found)
                          (problem "get-document ~A gives NIL, not ~S" id (document-title wanted)))
                         ((string/= (document-title found) (document-title wanted))
                          (problem "get-document ~A gives ~S, not ~S" id
                                   (document-title found) (document-title wanted))))))
               expected)
      (unless (= (document-count index) (hash-table-count expected))
        (problem "the index has ~D documents, not ~D"
                 (document-count index) (hash-table-count expected))))
    (nreverse problems)))

(defun corrected (document title)
  "Returns DOCUMENT with TITLE, as the archive desk corrects one."
  (make-document (document-id document) :title title
                                        :body (document-body document)
                                        :published (document-published document)))

(test reported-correction
  (multiple-value-bind (index history) (make-sample-index)
    (let ((expected (make-hash-table :test 'equal)))
      (dolist (document (sample-history-documents history))
        (setf (gethash (document-id document) expected) document))
      (is (null (archive-problems index expected)) "the archive as built: ~{~A~^; ~}"
          (archive-problems index expected))
      ;; The report's sequence.
      (let* ((old (get-document index "doc-204917"))
             (new (corrected old "Harbour cranes back at work after the storm"))
             (import (sample-documents :seed 2 :count 1500 :first-number 210401 :day 263)))
        (is (string= "New festival increase surgeries authors" (document-title old)))
        (update-document index new)
        (add-documents index import)
        (commit index)
        (setf (gethash "doc-204917" expected) new)
        (dolist (document import)
          (setf (gethash (document-id document) expected) document))
        (let ((found (get-document index "doc-204917")))
          (is-true (and found (string= (document-title new) (document-title found)))
                   "get-document gives ~A" found))
        (is (equal '("doc-204917") (ids index "title:\"cranes back at work\"")))
        (is (null (ids index "title:\"festival increase surgeries\"")))
        (is (null (archive-problems index expected)) "after the reported sequence: ~{~A~^; ~}"
            (archive-problems index expected)))
      ;; Another correction and a withdrawal in the segment the last commit
      ;; flushed, before an import that merges it.
      (let* ((old (get-document index "doc-211500"))
             (new (corrected old "Ferry timetable changed for the winter"))
             (import (sample-documents :seed 3 :count 7000 :first-number 211901 :day 264)))
        (update-document index new)
        (delete-document index "doc-211600")
        (add-documents index import)
        (commit index)
        (setf (gethash "doc-211500" expected) new)
        (remhash "doc-211600" expected)
        (dolist (document import)
          (setf (gethash (document-id document) expected) document))
        (is (equal '("doc-211500") (ids index "title:\"ferry timetable changed\"")))
        (is (null (get-document index "doc-211600")))
        (is (null (archive-problems index expected)) "after the second import: ~{~A~^; ~}"
            (archive-problems index expected))))))
