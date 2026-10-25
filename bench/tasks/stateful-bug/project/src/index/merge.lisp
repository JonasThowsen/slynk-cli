(in-package #:trove.index)

;;; Merging makes one segment of several: their live documents, in the
;;; order of the segments and then of their numbers, so that the
;;; postings stay ascending, and without the deleted ones, which are
;;; gone for good once merged. A search across fewer, larger segments is
;;; faster, and merging is how deleted documents leave the index.

(defun document-maps (segments)
  "Returns for each of SEGMENTS a fixnum vector from its document numbers
to their numbers in the merged segment, -1 for a deleted document."
  (let ((next 0))
    (mapcar (lambda (segment)
              (let ((map (make-array (segment-size segment) :element-type 'fixnum
                                                            :initial-element -1)))
                (dotimes (number (segment-size segment) map)
                  (when (live-p segment number)
                    (setf (aref map number) next)
                    (incf next)))))
            segments)))

(defun merged-documents (segments maps size)
  "Returns the vector of the SIZE live documents of SEGMENTS, at their
places in MAPS."
  (let ((documents (make-array size)))
    (loop for segment in segments
          for map in maps
          do (dotimes (number (segment-size segment))
               (let ((new (aref map number)))
                 (when (>= new 0)
                   (setf (svref documents new) (segment-document segment number))))))
    documents))

(defun merged-lengths (segments maps size)
  "Returns a hash table from field to the field lengths of the SIZE live
documents of SEGMENTS, at their places in MAPS."
  (let ((lengths (make-hash-table)))
    (dolist (field *fields* lengths)
      (let ((merged (make-array size :element-type 'fixnum :initial-element 0)))
        (loop for segment in segments
              for map in maps
              for old = (gethash field (segment-lengths segment))
              do (dotimes (number (segment-size segment))
                   (let ((new (aref map number)))
                     (when (>= new 0)
                       (setf (aref merged new) (aref old number))))))
        (setf (gethash field lengths) merged)))))

(defun merged-terms (segments maps)
  "Returns a hash table from field to the dictionary of the postings of
SEGMENTS' live documents, renumbered by MAPS."
  (let ((terms (make-hash-table)))
    (dolist (field *fields* terms)
      (let ((builders (make-hash-table :test 'equal)))
        (loop for segment in segments
              for map in maps
              do (alexandria:when-let ((dictionary (gethash field (segment-terms segment))))
                   (maphash (lambda (term postings)
                              (let ((builder nil))
                                (dotimes (i (postings-count postings))
                                  (let ((new (aref map (aref (postings-documents postings) i))))
                                    (when (>= new 0)
                                      (unless builder
                                        (setf builder (alexandria:ensure-gethash
                                                       term builders (make-postings-builder))))
                                      (add-document-postings builder new postings i))))))
                            dictionary)))
        (let ((dictionary (make-hash-table :test 'equal :size (hash-table-count builders))))
          (maphash (lambda (term builder)
                     (setf (gethash term dictionary) (finish-postings builder)))
                   builders)
          (setf (gethash field terms) dictionary))))))

(defun merge-segments (segments number)
  "Returns segment NUMBER, made of the live documents of SEGMENTS, at
the level after the highest of theirs. Its second value is the list of
the document maps of SEGMENTS: for each, a vector from its document
numbers to those in the new segment, -1 for a deleted document."
  (let* ((maps (document-maps segments))
         (size (reduce #'+ segments :key #'segment-live-count)))
    (values (make-instance 'segment
                           :number number
                           :level (1+ (reduce #'max segments :key #'segment-level))
                           :documents (merged-documents segments maps size)
                           :terms (merged-terms segments maps)
                           :lengths (merged-lengths segments maps size)
                           :deleted (make-array size :element-type 'bit :initial-element 0))
            maps)))
