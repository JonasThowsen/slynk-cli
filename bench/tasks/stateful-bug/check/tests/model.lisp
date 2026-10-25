;;;; Random sequences of additions, updates, withdrawals and commits on
;;;; small indexes that flush and merge often, against a model: a table
;;;; from id to the document last given. After each commit, the index must
;;;; give each id its last version and find it by the words of that
;;;; version only, and must have nothing else.

(in-package #:trove/tests)

(in-suite :trove)

(defvar *model-state* 4242)

(defun model-random (limit)
  "Returns the next number below LIMIT of a fixed sequence."
  (setf *model-state* (mod (* *model-state* 48271) 2147483647))
  (mod *model-state* limit))

(defun versioned (id version)
  "Returns a document ID whose title and body name VERSION, a word no
other version has."
  (let ((word (format nil "version~36R" version)))
    (make-document id :title (format nil "~A ~A" id word)
                      :body (format nil "Text of ~A as of ~A." id word))))

(defun model-problems (index model versions)
  "Returns how INDEX differs from MODEL, a table from id to document;
VERSIONS are all the version words ever used."
  (let ((problems '()))
    (flet ((problem (control &rest arguments)
             (push (apply #'format nil control arguments) problems)))
      (maphash (lambda (id document)
                 (let ((found (get-document index id)))
                   (unless (and found (string= (document-title found) (document-title document)))
                     (problem "get-document ~A gives ~A, not ~A" id found document))))
               model)
      (unless (= (document-count index) (hash-table-count model))
        (problem "~D documents, not ~D" (document-count index) (hash-table-count model)))
      (dolist (word versions)
        (let ((hits (ids index word))
              (current (loop for document being the hash-values of model
                             when (alexandria:ends-with-subseq
                                   (concatenate 'string " " word) (document-title document))
                               collect (document-id document))))
          (unless (equal hits current)
            (problem "~A finds ~S, not ~S" word hits current)))))
    problems))

(test model-sequences
  (setf *model-state* 4242)
  (let ((failures '()))
    (dotimes (run 300)
      (let* ((index (make-index :analyzer (make-analyzer :stemming nil)
                                :flush-size (1+ (model-random 4))
                                :merge-factor (+ 2 (model-random 2))))
             (model (make-hash-table :test 'equal))
             (pending (make-hash-table :test 'equal))
             (versions '())
             (version 0)
             (steps '()))
        ;; PENDING is the model as of the next commit; MODEL as of the last.
        (dotimes (step 40)
          (let* ((id (format nil "d~D" (model-random 12)))
                 (roll (model-random 10)))
            (cond ((< roll 5)
                   (let ((document (versioned id (incf version))))
                     (push (format nil "version~36R" version) versions)
                     (if (gethash id pending)
                         (progn (update-document index document) (push (list :update id) steps))
                         (progn (add-document index document) (push (list :add id) steps)))
                     (setf (gethash id pending) document)))
                  ((< roll 7)
                   (when (gethash id pending)
                     (delete-document index id)
                     (remhash id pending)
                     (push (list :delete id) steps)))
                  (t
                   (commit index)
                   (push :commit steps)
                   (setf model (alexandria:copy-hash-table pending))
                   (let ((problems (model-problems index model versions)))
                     (when problems
                       (push (list run (reverse steps) (first problems)) failures)
                       (return)))))))))
    (is (null failures) "~D of 300 random sequences go wrong; the first:~%  ~S"
        (length failures) (first (last failures)))))
