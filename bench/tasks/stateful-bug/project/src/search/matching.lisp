(in-package #:trove.search)

;;; Matching finds the documents of a segment that a query matches, as a
;;; sorted vector of their numbers, deleted documents included: the search
;;; leaves those out as it scores. Sets of documents are combined by
;;; walking the sorted vectors together.

(deftype numbers () 'index-vector)

(defun no-numbers ()
  "Returns an empty vector of document numbers."
  (make-index-vector 0))

(defun intersect-numbers (a b)
  "Returns the numbers in both sorted vectors A and B."
  (declare (type numbers a b))
  (let ((result (make-index-vector (min (length a) (length b))))
        (i 0) (j 0) (k 0))
    (declare (type fixnum i j k))
    (loop while (and (< i (length a)) (< j (length b)))
          do (let ((x (aref a i)) (y (aref b j)))
               (cond ((< x y) (incf i))
                     ((> x y) (incf j))
                     (t (setf (aref result k) x)
                        (incf i) (incf j) (incf k)))))
    (subseq result 0 k)))

(defun union-numbers (a b)
  "Returns the numbers in either sorted vector A or B."
  (declare (type numbers a b))
  (let ((result (make-index-vector (+ (length a) (length b))))
        (i 0) (j 0) (k 0))
    (declare (type fixnum i j k))
    (loop while (or (< i (length a)) (< j (length b)))
          do (let ((x (if (< i (length a)) (aref a i) most-positive-fixnum))
                   (y (if (< j (length b)) (aref b j) most-positive-fixnum)))
               (setf (aref result k) (min x y))
               (incf k)
               (when (<= x y) (incf i))
               (when (<= y x) (incf j))))
    (subseq result 0 k)))

(defun subtract-numbers (a b)
  "Returns the numbers of sorted vector A that are not in B."
  (declare (type numbers a b))
  (let ((result (make-index-vector (length a)))
        (j 0) (k 0))
    (declare (type fixnum j k))
    (loop for x across a
          do (loop while (and (< j (length b)) (< (aref b j) x)) do (incf j))
             (unless (and (< j (length b)) (= (aref b j) x))
               (setf (aref result k) x)
               (incf k)))
    (subseq result 0 k)))

(defun query-fields (query)
  "Returns the fields QUERY looks in."
  (let ((field (query-field query)))
    (if field (list field) *fields*)))

(defgeneric matching-numbers (query segment)
  (:documentation "Returns the sorted vector of the numbers of the
documents of SEGMENT that QUERY matches, deleted ones included."))

(defmethod matching-numbers ((query term-query) segment)
  (reduce #'union-numbers
          (mapcar (lambda (field)
                    (let ((postings (segment-postings segment field (query-term query))))
                      (if postings (postings-documents postings) (no-numbers))))
                  (query-fields query))))

(defun binary-search (number numbers)
  "Returns the index of NUMBER in the sorted vector NUMBERS, or NIL."
  (declare (type fixnum number) (type numbers numbers))
  (let ((low 0) (high (1- (length numbers))))
    (declare (type fixnum low high))
    (loop while (<= low high)
          do (let* ((middle (floor (+ low high) 2))
                    (value (aref numbers middle)))
               (cond ((< value number) (setf low (1+ middle)))
                     ((> value number) (setf high (1- middle)))
                     (t (return middle)))))))

(defun has-position-p (postings index position)
  "True when the INDEXth document of POSTINGS has the term at POSITION."
  (let ((start (aref (postings-starts postings) index))
        (positions (postings-positions postings)))
    (loop for i from start below (+ start (aref (postings-frequencies postings) index))
            thereis (= position (aref positions i)))))

(defun phrase-at-p (all-postings indexes offsets)
  "True when for some position P of the first term, in the document at
INDEXES of ALL-POSTINGS, each other term is at P plus its offset in
OFFSETS."
  (let* ((first (first all-postings))
         (start (aref (postings-starts first) (first indexes))))
    (loop for i from start below (+ start (aref (postings-frequencies first) (first indexes)))
          for position = (aref (postings-positions first) i)
            thereis (every (lambda (postings index offset)
                             (has-position-p postings index (+ position offset)))
                           (rest all-postings) (rest indexes) (rest offsets)))))

(defun phrase-numbers-in-field (query segment field)
  "Returns the numbers of the documents of SEGMENT with QUERY's phrase in
FIELD."
  (let ((all-postings (mapcar (lambda (term) (segment-postings segment field (car term)))
                              (query-terms query))))
    (if (some #'null all-postings)
        (no-numbers)
        (let ((candidates (reduce #'intersect-numbers (mapcar #'postings-documents all-postings)))
              (offsets (mapcar #'cdr (query-terms query))))
          (remove-if-not (lambda (number)
                           (phrase-at-p all-postings
                                        (mapcar (lambda (postings)
                                                  (binary-search number (postings-documents postings)))
                                                all-postings)
                                        offsets))
                         candidates)))))

(defmethod matching-numbers ((query phrase-query) segment)
  (reduce #'union-numbers
          (mapcar (lambda (field) (phrase-numbers-in-field query segment field))
                  (query-fields query))))

(defun all-numbers (segment)
  "Returns the numbers of all documents of SEGMENT."
  (let ((numbers (make-index-vector (segment-size segment))))
    (dotimes (i (length numbers) numbers)
      (setf (aref numbers i) i))))

(defmethod matching-numbers ((query all-query) segment)
  (all-numbers segment))

(defmethod matching-numbers ((query boolean-query) segment)
  (let ((positive (cond ((query-must query)
                         (reduce #'intersect-numbers
                                 (mapcar (lambda (clause) (matching-numbers clause segment))
                                         (query-must query))))
                        ((query-should query)
                         (reduce #'union-numbers
                                 (mapcar (lambda (clause) (matching-numbers clause segment))
                                         (query-should query))))
                        (t (no-numbers)))))
    (reduce #'subtract-numbers
            (mapcar (lambda (clause) (matching-numbers clause segment))
                    (query-must-not query))
            :initial-value positive)))
