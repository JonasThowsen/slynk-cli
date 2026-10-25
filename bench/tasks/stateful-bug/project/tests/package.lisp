(defpackage #:trove/tests
  (:use #:common-lisp #:trove.text #:trove.index #:trove.search #:trove #:fiveam))

(in-package #:trove/tests)

(def-suite :trove :description "Tests for trove.")

(defparameter *articles*
  '(("a1" "Harbour cranes idle after the storm"
     "The cranes at the harbour stood idle after the storm closed the port for two days.")
    ("a2" "Storm warning for the coast"
     "A gale warning was issued for the coast tonight, and the ferries will stay in port.")
    ("a3" "Ferry delayed by the tide"
     "The ferry to the island was delayed by the storm and a low tide on Tuesday.")
    ("a4" "New crane for the container terminal"
     "The port has bought a new container crane, the largest on the coast.")
    ("a5" "Council approves the harbour budget"
     "The council voted for the harbour budget after a long debate about the cranes.")
    ("a6" "Skiing season opens early"
     "Heavy snow let the skiing season open two weeks early in the valley."))
  "Short articles to index: (ID TITLE BODY).")

(defun article (id title body)
  "Returns the document ID with TITLE and BODY."
  (make-document id :title title :body body))

(defun articles ()
  "Returns the documents of *ARTICLES*."
  (mapcar (lambda (entry) (apply #'article entry)) *articles*))

(defun small-index (&key (flush-size 1000) (merge-factor 8))
  "Returns an index of the documents of *ARTICLES*, committed."
  (let ((index (make-index :flush-size flush-size :merge-factor merge-factor)))
    (add-documents index (articles))
    (commit index)
    index))

(defun ids (index query &key (limit 100))
  "Returns the ids of the hits for QUERY in INDEX, best first."
  (mapcar #'hit-id (search-index index query :limit limit)))
