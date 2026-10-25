(in-package #:trove.search)

;;; A search runs a query over every segment of the index, scores the
;;; live documents that match, and returns the best. Hits with the same
;;; score come in the order of their ids, so that a search gives the same
;;; answer however the index is cut into segments.

(defstruct (hit (:constructor make-hit (id score document)))
  "A document a search found, with its SCORE."
  (id "" :type string :read-only t)
  (score 0d0 :type double-float :read-only t)
  (document nil :read-only t))

(defun hit-title (hit)
  "Returns the title of the document of HIT."
  (document-title (hit-document hit)))

(defmethod print-object ((hit hit) stream)
  (print-unreadable-object (hit stream :type t)
    (format stream "~A ~,3F ~S" (hit-id hit) (hit-score hit) (hit-title hit))))

(defun ensure-query (query index)
  "Returns QUERY if it is a query, or the query the text QUERY is, for
INDEX."
  (etypecase query
    (query query)
    (string (parse-query query (index-analyzer index)))))

(defun hit< (a b)
  "True when hit A ranks before hit B: a higher score, or the same and a
smaller id."
  (or (> (hit-score a) (hit-score b))
      (and (= (hit-score a) (hit-score b))
           (string< (hit-id a) (hit-id b)))))

(defun map-matches (function index query)
  "Calls FUNCTION with each segment of INDEX and the number of each live
document there that QUERY matches."
  (dolist (segment (index-segments index))
    (loop for number across (matching-numbers query segment)
          when (live-p segment number)
            do (funcall function segment number))))

(defun search-index (index query &key (limit 10))
  "Returns the hits for QUERY, a query or its text, in INDEX: at most
LIMIT, the best first."
  (let* ((query (ensure-query query index))
         (statistics (index-statistics-for-scoring index))
         (hits '()))
    (map-matches (lambda (segment number)
                   (let ((document (segment-document segment number)))
                     (push (make-hit (document-id document)
                                     (score query statistics segment number)
                                     document)
                           hits)))
                 index query)
    (let ((sorted (sort hits #'hit<)))
      (subseq sorted 0 (min limit (length sorted))))))

(defun count-matches (index query)
  "Returns the number of documents of INDEX that QUERY, a query or its
text, matches."
  (let ((query (ensure-query query index))
        (count 0))
    (map-matches (lambda (segment number)
                   (declare (ignore segment number))
                   (incf count))
                 index query)
    count))
