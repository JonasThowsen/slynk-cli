(in-package #:trove.search)

;;; Documents are ranked by BM25 (Robertson and Zaragoza, "The
;;; Probabilistic Relevance Framework", 2009), summed over the fields
;;; with a weight each: a word in the title counts twice. The statistics
;;; are those of the whole index: the number of documents a search can
;;; find, the average length of each field, and for each term the
;;; number of documents with it. As in Lucene, the document frequency
;;; counts deleted documents until a merge removes them; it changes the
;;; scores a little, and keeps a search from looking at every deleted bit.

(defparameter *field-weights* '((:title . 2.0d0) (:body . 1.0d0))
  "The weight of each field in a document's score.")

(defparameter *k1* 1.2d0
  "How quickly more occurrences of a term stop adding to the score.")

(defparameter *b* 0.75d0
  "How much a longer field lowers the score of each occurrence.")

(defclass statistics ()
  ((document-count :initarg :document-count :reader statistics-document-count)
   (average-lengths :initarg :average-lengths :reader statistics-average-lengths
                    :documentation "An alist from field to its average length.")
   (segments :initarg :segments :reader statistics-segments)
   (document-frequencies :initform (make-hash-table :test 'equal)
                         :documentation "The document frequency of each (FIELD
. TERM) asked for so far.")
   (clause-matches :initform (make-hash-table :test 'equal)
                   :documentation "The documents each (CLAUSE . SEGMENT) of
an OR matches, for scoring only the clauses that match."))
  (:documentation "The statistics of an index that scores depend on, as of
one search."))

(defun index-statistics-for-scoring (index)
  "Returns the statistics of INDEX for scoring a search."
  (let* ((segments (index-segments index))
         (count (document-count index)))
    (make-instance 'statistics
                   :document-count count
                   :segments segments
                   :average-lengths
                   (mapcar (lambda (field)
                             (cons field
                                   (if (zerop count)
                                       0d0
                                       (/ (float (reduce #'+ segments
                                                         :key (lambda (segment)
                                                                (live-field-length segment field)))
                                                 1d0)
                                          count))))
                           *fields*))))

(defun document-frequency (statistics field term)
  "Returns the number of documents with TERM in FIELD."
  (alexandria:ensure-gethash
   (cons field term) (slot-value statistics 'document-frequencies)
   (loop for segment in (statistics-segments statistics)
         for postings = (segment-postings segment field term)
         when postings sum (postings-count postings))))

(defun clause-matches-p (statistics clause segment number)
  "True when CLAUSE matches the document NUMBER of SEGMENT."
  (binary-search number
                 (alexandria:ensure-gethash (cons clause segment)
                                            (slot-value statistics 'clause-matches)
                                            (matching-numbers clause segment))))

(defun inverse-document-frequency (statistics field term)
  "Returns the BM25 weight of TERM in FIELD: higher the rarer it is."
  (let ((n (statistics-document-count statistics))
        (df (document-frequency statistics field term)))
    (log (+ 1d0 (/ (+ (- n df) 0.5d0) (+ df 0.5d0))))))

(defun term-score (statistics segment number field term)
  "Returns the BM25 score of TERM in FIELD of the document NUMBER of
SEGMENT, 0 when it does not have the term."
  (let* ((postings (segment-postings segment field term))
         (at (and postings (binary-search number (postings-documents postings)))))
    (if (null at)
        0d0
        (let* ((frequency (float (aref (postings-frequencies postings) at) 1d0))
               (length (float (field-length segment field number) 1d0))
               (average (cdr (assoc field (statistics-average-lengths statistics))))
               (norm (if (zerop average) 1d0 (/ length average))))
          (* (cdr (assoc field *field-weights*))
             (inverse-document-frequency statistics field term)
             (/ (* frequency (+ *k1* 1d0))
                (+ frequency (* *k1* (+ (- 1d0 *b*) (* *b* norm))))))))))

(defgeneric score (query statistics segment number)
  (:documentation "Returns the score of the document NUMBER of SEGMENT
for QUERY, which matches it."))

(defmethod score ((query term-query) statistics segment number)
  (loop for field in (query-fields query)
        sum (term-score statistics segment number field (query-term query))))

(defmethod score ((query phrase-query) statistics segment number)
  (loop for field in (query-fields query)
        sum (loop for (term) in (query-terms query)
                  sum (term-score statistics segment number field term))))

(defmethod score ((query all-query) statistics segment number)
  (declare (ignore statistics segment number))
  1d0)

(defmethod score ((query boolean-query) statistics segment number)
  ;; The clauses that match add up; the excluded ones match nothing.
  (+ (loop for clause in (query-must query)
           sum (score clause statistics segment number))
     (loop for clause in (query-should query)
           when (clause-matches-p statistics clause segment number)
             sum (score clause statistics segment number))))
