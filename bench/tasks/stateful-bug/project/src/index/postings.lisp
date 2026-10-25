(in-package #:trove.index)

;;; The postings of a term in a segment: the documents that have it, by
;;; their numbers in the segment, ascending, with how often each has it
;;; and at which positions. The positions of all the documents are in one
;;; vector, each document's from its start there, ascending: an archive
;;; has tens of millions of postings, and a vector for each would take
;;; more room than the positions in it. While a segment is being built
;;; the postings grow in adjustable vectors.

(deftype index-vector () '(simple-array (unsigned-byte 32) (*)))

(defun make-index-vector (length)
  "Returns a vector for LENGTH document numbers or positions."
  (make-array length :element-type '(unsigned-byte 32)))

(defun index-vector (sequence)
  "Returns a vector of the document numbers or positions in SEQUENCE."
  (coerce sequence 'index-vector))

(defstruct (postings (:constructor %make-postings (documents frequencies starts positions)))
  "The DOCUMENTS of a term, ascending, the FREQUENCIES of the term in
each, and the POSITIONS of the term in all of them, each document's from
its index in STARTS."
  (documents (make-index-vector 0) :type index-vector :read-only t)
  (frequencies (make-index-vector 0) :type index-vector :read-only t)
  (starts (make-index-vector 0) :type index-vector :read-only t)
  (positions (make-index-vector 0) :type index-vector :read-only t))

(defun postings-count (postings)
  "Returns the number of documents in POSTINGS."
  (length (postings-documents postings)))

(defmethod print-object ((postings postings) stream)
  (print-unreadable-object (postings stream :type t :identity t)
    (format stream "~D document~:P" (postings-count postings))))

(defmacro do-postings ((document frequency start) postings &body body)
  "Evaluates BODY for each document of POSTINGS, ascending, with
DOCUMENT, FREQUENCY and START bound to its number, the term's frequency
in it, and where its positions start in POSTINGS-POSITIONS."
  (alexandria:with-gensyms (p i)
    `(let ((,p ,postings))
       (dotimes (,i (postings-count ,p))
         (let ((,document (aref (postings-documents ,p) ,i))
               (,frequency (aref (postings-frequencies ,p) ,i))
               (,start (aref (postings-starts ,p) ,i)))
           (declare (ignorable ,document ,frequency ,start))
           ,@body)))))

(defun document-positions (postings index)
  "Returns the positions of the INDEXth document of POSTINGS, as a list."
  (let ((start (aref (postings-starts postings) index)))
    (loop for i from start below (+ start (aref (postings-frequencies postings) index))
          collect (aref (postings-positions postings) i))))

;;; Building postings

(defstruct (postings-builder (:constructor make-postings-builder ()))
  "Postings while their segment is built."
  (documents (make-array 4 :element-type '(unsigned-byte 32) :adjustable t :fill-pointer 0))
  (frequencies (make-array 4 :element-type '(unsigned-byte 32) :adjustable t :fill-pointer 0))
  (starts (make-array 4 :element-type '(unsigned-byte 32) :adjustable t :fill-pointer 0))
  (positions (make-array 4 :element-type '(unsigned-byte 32) :adjustable t :fill-pointer 0)))

(defun add-posting (builder document position)
  "Records that DOCUMENT has the term at POSITION. Documents come in
ascending order, and the positions of each ascending."
  (declare (type (unsigned-byte 32) document position))
  (let* ((documents (postings-builder-documents builder))
         (last (1- (length documents))))
    (cond ((and (>= last 0) (= document (aref documents last)))
           (incf (aref (postings-builder-frequencies builder) last)))
          ((and (>= last 0) (< document (aref documents last)))
           (error "Postings out of order: document ~D after ~D." document (aref documents last)))
          (t
           (vector-push-extend document documents)
           (vector-push-extend 1 (postings-builder-frequencies builder))
           (vector-push-extend (length (postings-builder-positions builder))
                               (postings-builder-starts builder))))
    (vector-push-extend position (postings-builder-positions builder))))

(defun add-document-postings (builder document postings index)
  "Records that DOCUMENT has the term at the positions of the INDEXth
document of POSTINGS."
  (let ((start (aref (postings-starts postings) index))
        (positions (postings-positions postings)))
    (loop for i from start below (+ start (aref (postings-frequencies postings) index))
          do (add-posting builder document (aref positions i)))))

(defun finish-postings (builder)
  "Returns the postings BUILDER has built."
  (%make-postings (index-vector (postings-builder-documents builder))
                  (index-vector (postings-builder-frequencies builder))
                  (index-vector (postings-builder-starts builder))
                  (index-vector (postings-builder-positions builder))))
