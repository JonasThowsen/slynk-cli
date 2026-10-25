(in-package #:spool)

;;; The jobs waiting in a queue, in a binary heap with the job to run next
;;; at the top: the one of the highest priority, and of those the one
;;; queued first. The heap is a vector with a fill pointer; the children
;;; of the job at I are at 2I+1 and 2I+2.
;;;
;;; Each job in the heap knows its index there, JOB-HEAP-INDEX, so that a
;;; cancelled job is taken out without searching the queue for it. Every
;;; change to the vector keeps the indexes right.

(defun make-job-heap ()
  "Returns an empty heap of jobs."
  (make-array 16 :adjustable t :fill-pointer 0))

(defun heap-count (heap)
  "Returns the number of jobs in HEAP."
  (length heap))

(defun heap-jobs (heap)
  "Returns the jobs in HEAP, in the order they will run."
  (sort (coerce heap 'list) #'runs-before-p))

(defun runs-before-p (a b)
  "True when job A runs before job B."
  (or (> (job-priority a) (job-priority b))
      (and (= (job-priority a) (job-priority b))
           (< (job-sequence a) (job-sequence b)))))

(defun heap-swap (heap i j)
  "Swaps the jobs at I and J in HEAP."
  (rotatef (aref heap i) (aref heap j))
  (setf (job-heap-index (aref heap i)) i
        (job-heap-index (aref heap j)) j))

(defun sift-up (heap index)
  "Moves the job at INDEX up HEAP until its parent runs before it."
  (loop while (plusp index)
        do (let ((parent (floor (1- index) 2)))
             (unless (runs-before-p (aref heap index) (aref heap parent))
               (return))
             (heap-swap heap index parent)
             (setf index parent))))

(defun sift-down (heap index)
  "Moves the job at INDEX down HEAP until it runs before its children."
  (let ((count (length heap)))
    (loop
      (let* ((left (1+ (* 2 index)))
             (right (1+ left))
             (first index))
        (when (and (< left count) (runs-before-p (aref heap left) (aref heap first)))
          (setf first left))
        (when (and (< right count) (runs-before-p (aref heap right) (aref heap first)))
          (setf first right))
        (when (= first index)
          (return))
        (heap-swap heap index first)
        (setf index first)))))

(defun heap-insert (heap job)
  "Adds JOB to HEAP and returns it."
  (let ((index (vector-push-extend job heap)))
    (setf (job-heap-index job) index)
    (sift-up heap index)
    job))

(defun heap-pop (heap)
  "Takes the job to run next out of HEAP and returns it, or returns NIL
when HEAP is empty."
  (when (plusp (length heap))
    (let ((top (aref heap 0))
          (last (vector-pop heap)))
      (when (plusp (length heap))
        (setf (aref heap 0) last)
        (sift-down heap 0))
      (setf (job-heap-index top) nil)
      top)))

(defun heap-delete (heap job)
  "Takes JOB, which is in HEAP, out of it, and returns it."
  (let ((index (job-heap-index job))
        (last (vector-pop heap)))
    (unless (eq last job)
      ;; The last job fills the hole, and moves up or down from there.
      (setf (aref heap index) last
            (job-heap-index last) index)
      (sift-up heap index)
      (sift-down heap (job-heap-index last)))
    (setf (job-heap-index job) nil)
    job))
