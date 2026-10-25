(in-package #:trove.index)

;;; A segment is a part of the index that never changes once it is made,
;;; except that its documents can be marked deleted. Its documents have
;;; the numbers 0, 1, 2... in the order they were added; for each field
;;; it has a dictionary from term to postings, and the length of the
;;; field, in terms, of each document.
;;;
;;; New documents are added to a segment builder, the index's buffer,
;;; which becomes a segment when it is flushed.

(defclass segment ()
  ((number :initarg :number :reader segment-number
           :documentation "The segment's number: numbers grow with each
segment the index makes.")
   (level :initarg :level :reader segment-level
          :documentation "0 for a segment flushed from the buffer, and one
more than theirs for a merge of segments.")
   (documents :initarg :documents :reader segment-documents :type simple-vector)
   (terms :initarg :terms :reader segment-terms
          :documentation "A hash table from field to a hash table from term
to postings.")
   (lengths :initarg :lengths :reader segment-lengths
            :documentation "A hash table from field to a fixnum vector of
the length of that field in each document.")
   (deleted :initarg :deleted :reader segment-deleted :type simple-bit-vector
            :documentation "A bit for each document, 1 when it is deleted.")
   (deleted-count :initarg :deleted-count :initform 0 :accessor segment-deleted-count))
  (:documentation "A part of the index: documents and their postings."))

(defun segment-size (segment)
  "Returns the number of documents in SEGMENT, deleted ones included."
  (length (segment-documents segment)))

(defun segment-live-count (segment)
  "Returns the number of documents in SEGMENT that are not deleted."
  (- (segment-size segment) (segment-deleted-count segment)))

(defmethod print-object ((segment segment) stream)
  (print-unreadable-object (segment stream :type t)
    (format stream "~D, level ~D, ~D document~:P, ~D deleted"
            (segment-number segment) (segment-level segment)
            (segment-size segment) (segment-deleted-count segment))))

(defun segment-document (segment number)
  "Returns the document NUMBER of SEGMENT."
  (svref (segment-documents segment) number))

(declaim (inline live-p))
(defun live-p (segment number)
  "True when the document NUMBER of SEGMENT is not deleted."
  (zerop (sbit (segment-deleted segment) number)))

(defun delete-from-segment (segment number)
  "Marks the document NUMBER of SEGMENT deleted. Returns true when it was
not deleted before."
  (when (live-p segment number)
    (setf (sbit (segment-deleted segment) number) 1)
    (incf (segment-deleted-count segment))
    t))

(defun segment-postings (segment field term)
  "Returns the postings of TERM in FIELD of SEGMENT, or NIL."
  (alexandria:when-let ((dictionary (gethash field (segment-terms segment))))
    (values (gethash term dictionary))))

(defun field-length (segment field number)
  "Returns the length of FIELD, in terms, of the document NUMBER of
SEGMENT."
  (aref (the (simple-array fixnum (*)) (gethash field (segment-lengths segment))) number))

(defun live-field-length (segment field)
  "Returns the sum of the lengths of FIELD of SEGMENT's live documents."
  (let ((lengths (gethash field (segment-lengths segment))))
    (loop for number below (segment-size segment)
          when (live-p segment number)
            sum (aref lengths number))))

;;; Building a segment

(defclass segment-builder ()
  ((analyzer :initarg :analyzer :reader builder-analyzer)
   (documents :initform (make-array 64 :adjustable t :fill-pointer 0)
              :reader builder-documents)
   (terms :initform (make-hash-table)
          :documentation "A hash table from field to a hash table from term
to postings builder.")
   (lengths :initform (make-hash-table)
            :documentation "A hash table from field to an adjustable vector
of field lengths.")
   (deleted :initform '()
            :documentation "The numbers of the documents deleted before the
builder became a segment."))
  (:documentation "A segment being built, as documents are added."))

(defun make-segment-builder (analyzer)
  "Returns an empty segment builder that analyzes with ANALYZER."
  (make-instance 'segment-builder :analyzer analyzer))

(defun builder-count (builder)
  "Returns the number of documents added to BUILDER."
  (length (builder-documents builder)))

(defun builder-add (builder document)
  "Adds DOCUMENT to BUILDER, and returns its number in the segment."
  (with-slots (analyzer documents terms lengths) builder
    (let ((number (vector-push-extend document documents)))
      (dolist (field *fields* number)
        (let ((dictionary (alexandria:ensure-gethash field terms (make-hash-table :test 'equal)))
              (count 0))
          (map-terms (lambda (term token)
                       (add-posting (alexandria:ensure-gethash term dictionary
                                                               (make-postings-builder))
                                    number (token-position token))
                       (incf count))
                     analyzer (field-text document field))
          (vector-push-extend count (alexandria:ensure-gethash
                                     field lengths
                                     (make-array 64 :element-type 'fixnum
                                                    :adjustable t :fill-pointer 0))))))))

(defun builder-delete (builder number)
  "Marks the document NUMBER of BUILDER deleted in the segment it will be."
  (pushnew number (slot-value builder 'deleted)))

(defun finish-segment (builder number)
  "Returns the segment BUILDER has built, as segment NUMBER of level 0."
  (with-slots (documents terms lengths deleted) builder
    (let ((finished-terms (make-hash-table))
          (finished-lengths (make-hash-table))
          (deleted-bits (make-array (length documents) :element-type 'bit :initial-element 0)))
      (maphash (lambda (field dictionary)
                 (let ((finished (make-hash-table :test 'equal :size (hash-table-count dictionary))))
                   (maphash (lambda (term builder)
                              (setf (gethash term finished) (finish-postings builder)))
                            dictionary)
                   (setf (gethash field finished-terms) finished)))
               terms)
      (dolist (field *fields*)
        (setf (gethash field finished-lengths)
              (coerce (or (gethash field lengths) #()) '(simple-array fixnum (*)))))
      (dolist (deleted-number deleted)
        (setf (sbit deleted-bits deleted-number) 1))
      (make-instance 'segment
                     :number number
                     :level 0
                     :documents (coerce documents 'simple-vector)
                     :terms finished-terms
                     :lengths finished-lengths
                     :deleted deleted-bits
                     :deleted-count (length deleted)))))
