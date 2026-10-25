(in-package #:trove.index)

;;; The index is a list of segments, the oldest first, a buffer for the
;;; documents added since the last flush, and a table from document id to
;;; where the current version of the document is.
;;;
;;; - ADD-DOCUMENT puts a document in the buffer. The buffer becomes a
;;;   segment when it holds FLUSH-SIZE documents, and at COMMIT; from then
;;;   on searches find the document.
;;;
;;; - DELETE-DOCUMENT takes effect at COMMIT, and so does the deletion of
;;;   the old version that UPDATE-DOCUMENT makes: until then searches find
;;;   the old version of an updated document, so that there is no moment
;;;   at which they find neither version. A deletion is resolved to the
;;;   document it deletes when it is made, because by the commit the id
;;;   may name the new version.
;;;
;;; - After a flush, segments are merged: when MERGE-FACTOR segments have
;;;   the same level, the oldest of them become one segment of the next
;;;   level, which may make MERGE-FACTOR segments of that level, and so
;;;   on. With the defaults, an index of a million documents has a few
;;;   dozen segments.

(define-condition index-error (error)
  ()
  (:documentation "An error in using an index."))

(define-condition document-exists (index-error)
  ((id :initarg :id :reader document-exists-id))
  (:report (lambda (condition stream)
             (format stream "The index has a document ~A already."
                     (document-exists-id condition))))
  (:documentation "ADD-DOCUMENT with the id of a document the index has."))

(defun replace-document (&optional condition)
  "Invokes the REPLACE-DOCUMENT restart of DOCUMENT-EXISTS: the new
document replaces the one with its id, as UPDATE-DOCUMENT would."
  (invoke-restart (find-restart 'replace-document condition)))

(defclass index ()
  ((analyzer :initarg :analyzer :reader index-analyzer)
   (flush-size :initarg :flush-size :reader index-flush-size)
   (merge-factor :initarg :merge-factor :reader index-merge-factor)
   (segments :initform '() :reader index-segments
             :documentation "The segments, the oldest first.")
   (ids :initform (make-hash-table :test 'equal)
        :documentation "For each document id, where the current version of
the document is, as (SEGMENT . NUMBER). Flushes and merges keep it up to
date, and commits remove the ids of deleted documents.")
   (buffer :documentation "The segment builder of the documents not
flushed yet.")
   (buffered-ids :initform (make-hash-table :test 'equal)
                 :documentation "For each document in the buffer, by id,
its number there.")
   (pending-deletes :initform '()
                    :documentation "The deletions to make at the next
commit, the most recent first, each (ID SEGMENT-NUMBER . NUMBER).")
   (next-segment-number :initform 0)
   (generation :initform 0 :reader index-generation
               :documentation "The number of commits so far."))
  (:documentation "A full-text index of documents."))

(defun make-index (&key (analyzer (make-analyzer)) (flush-size 1000) (merge-factor 8))
  "Returns an empty index that analyzes texts with ANALYZER, flushes its
buffer every FLUSH-SIZE documents, and merges MERGE-FACTOR segments of a
level into one."
  (check-type flush-size (integer 1))
  (check-type merge-factor (integer 2))
  (let ((index (make-instance 'index :analyzer analyzer
                                     :flush-size flush-size
                                     :merge-factor merge-factor)))
    (setf (slot-value index 'buffer) (make-segment-builder analyzer))
    index))

(defmethod print-object ((index index) stream)
  (print-unreadable-object (index stream :type t :identity t)
    (format stream "~D document~:P in ~D segment~:P, generation ~D"
            (document-count index) (length (index-segments index))
            (index-generation index))))

(defun next-segment-number (index)
  "Returns a number for a new segment of INDEX."
  (with-slots (next-segment-number) index
    (prog1 next-segment-number
      (incf next-segment-number))))

(defun document-count (index)
  "Returns the number of documents a search of INDEX can find."
  (reduce #'+ (index-segments index) :key #'segment-live-count))

(defun find-location (index id)
  "Returns where the current version of the document ID is, as
(SEGMENT . NUMBER), or NIL."
  (values (gethash id (slot-value index 'ids))))

(defun get-document (index id)
  "Returns the current version of the document ID, or NIL when INDEX has
none. Documents still in the buffer are not found; neither are those
deleted by a commit."
  (alexandria:when-let ((location (find-location index id)))
    (destructuring-bind (segment . number) location
      (and (live-p segment number)
           (segment-document segment number)))))

;;; Adding and deleting

(defun pending-delete-p (index id)
  "True when the document ID has a deletion waiting for the commit."
  (find id (slot-value index 'pending-deletes) :key #'first :test #'string=))

(defun buffer-document (index document)
  "Adds DOCUMENT to the buffer of INDEX, and flushes the buffer when it is
full."
  (with-slots (buffer buffered-ids flush-size) index
    (setf (gethash (document-id document) buffered-ids) (builder-add buffer document))
    (when (>= (builder-count buffer) flush-size)
      (flush index))))

(defun add-document (index document)
  "Adds DOCUMENT to INDEX and returns it. A document with its id in the
index signals DOCUMENT-EXISTS, with a REPLACE-DOCUMENT restart."
  (let ((id (document-id document)))
    (if (or (nth-value 1 (gethash id (slot-value index 'buffered-ids)))
            (and (find-location index id) (not (pending-delete-p index id))))
        (restart-case (error 'document-exists :id id)
          (replace-document ()
            :report "Replace the document with this id."
            (update-document index document)))
        (buffer-document index document)))
  document)

(defun add-documents (index documents)
  "Adds each of DOCUMENTS to INDEX, and returns the number added."
  (dolist (document documents (length documents))
    (add-document index document)))

(defun delete-document (index id)
  "Deletes the document ID from INDEX at the next commit. Returns true
when INDEX has such a document."
  (with-slots (buffer buffered-ids pending-deletes) index
    (let ((buffered (gethash id buffered-ids))
          (location (find-location index id)))
      ;; A document added since the last flush was never searchable: it
      ;; can go from the buffer now.
      (when buffered
        (builder-delete buffer buffered)
        (remhash id buffered-ids))
      (when location
        (push (list* id (segment-number (car location)) (cdr location)) pending-deletes))
      (and (or buffered location) t))))

(defun update-document (index document)
  "Replaces the document with the id of DOCUMENT by DOCUMENT, or adds it
when INDEX has none. Searches find the old version until the next
commit, and the new one once its buffer is flushed."
  (delete-document index (document-id document))
  (buffer-document index document)
  document)

;;; Flushing and merging

(defun segments-to-merge (index)
  "Returns the oldest MERGE-FACTOR segments of the lowest level that has
that many, or NIL."
  (with-slots (segments merge-factor) index
    (loop for level from 0 to (reduce #'max segments :key #'segment-level :initial-value 0)
          for of-level = (remove level segments :key #'segment-level :test-not #'=)
          when (>= (length of-level) merge-factor)
            return (subseq of-level 0 merge-factor))))

(defun merge-group (index group)
  "Replaces the segments GROUP of INDEX by their merge, which takes the
place of the oldest of them, and moves their documents' ids."
  (with-slots (segments ids) index
    (multiple-value-bind (merged maps) (merge-segments group (next-segment-number index))
      (setf segments
            (loop for segment in segments
                  when (eq segment (first group))
                    collect merged
                  unless (member segment group)
                    collect segment))
      (loop for segment in group
            for map in maps
            do (dotimes (number (segment-size segment))
                 (let ((new (aref map number)))
                   (when (>= new 0)
                     (let* ((id (document-id (segment-document segment number)))
                            (location (gethash id ids)))
                       ;; Only where the id names this version.
                       (when (and location
                                  (eq (car location) segment)
                                  (= (cdr location) number))
                         (setf (gethash id ids) (cons merged new)))))))))))

(defun merge-as-needed (index)
  "Merges segments of INDEX as long as some level has MERGE-FACTOR."
  (loop for group = (segments-to-merge index)
        while group
        do (merge-group index group)))

(defun flush (index)
  "Makes the buffer of INDEX a segment, when it has documents, and merges
segments as needed."
  (with-slots (analyzer buffer buffered-ids ids segments) index
    (when (plusp (builder-count buffer))
      (let ((segment (finish-segment buffer (next-segment-number index))))
        (setf segments (append segments (list segment)))
        (maphash (lambda (id number)
                   (setf (gethash id ids) (cons segment number)))
                 buffered-ids)
        (setf buffer (make-segment-builder analyzer))
        (clrhash buffered-ids)
        (merge-as-needed index)))))

(defun apply-pending-deletes (index)
  "Makes the deletions waiting in INDEX, in the order they were made."
  (with-slots (pending-deletes segments ids) index
    (dolist (pending (reverse pending-deletes))
      (destructuring-bind (id segment-number . number) pending
        (let ((segment (find segment-number segments :key #'segment-number)))
          (unless segment
            ;; The segment was merged away since the deletion, after a
            ;; flush of a full buffer: its live documents moved, and the
            ;; id table says where this one went.
            (alexandria:when-let ((location (gethash id ids)))
              (setf segment (car location)
                    number (cdr location))))
          (when segment
            (delete-from-segment segment number)
            ;; The id goes with the document it names; after an update it
            ;; names the new version, which stays.
            (when (equal (gethash id ids) (cons segment number))
              (remhash id ids))))))
    (setf pending-deletes '())))

(defun commit (index)
  "Makes the deletions waiting since the last commit and flushes the
buffer of INDEX. Returns the new generation of INDEX."
  ;; The deletions first: they were resolved against the segments there
  ;; are now, and the flush may merge some of them away.
  (apply-pending-deletes index)
  (flush index)
  (incf (slot-value index 'generation)))

(defun index-statistics (index)
  "Returns a property list about INDEX: :DOCUMENTS, the searchable ones;
:DELETED, those deleted but still in segments; :BUFFERED; and :LEVELS,
the number of segments of each level from 0 up."
  (with-slots (segments buffer) index
    (list :documents (document-count index)
          :deleted (reduce #'+ segments :key #'segment-deleted-count)
          :buffered (builder-count buffer)
          :levels (loop for level from 0 to (reduce #'max segments :key #'segment-level
                                                                   :initial-value 0)
                        collect (count level segments :key #'segment-level)))))

(defun map-documents (function index)
  "Calls FUNCTION with each searchable document of INDEX, the oldest
segment first."
  (dolist (segment (index-segments index))
    (dotimes (number (segment-size segment))
      (when (live-p segment number)
        (funcall function (segment-document segment number))))))
