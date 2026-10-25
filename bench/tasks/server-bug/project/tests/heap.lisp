(in-package #:spool/tests)
(in-suite :spool)

(defvar *sequence* 0)

(defun test-job (id priority)
  (spool::%make-job :id id :queue "test" :kind "echo" :priority priority
                    :sequence (incf *sequence*)))

(defun pop-all (heap)
  (loop for job = (spool::heap-pop heap)
        while job
        collect (spool::job-id job)))

(defun indexes-right-p (heap)
  (loop for index from 0 below (spool::heap-count heap)
        always (eql index (spool::job-heap-index (aref heap index)))))

(test heap-order
  (let ((heap (spool::make-job-heap)))
    (loop for (id priority) in '((1 5) (2 5) (3 9) (4 0) (5 7) (6 5) (7 9))
          do (spool::heap-insert heap (test-job id priority)))
    (is (= 7 (spool::heap-count heap)))
    (is (indexes-right-p heap))
    (is (equal '(3 7 5 1 2 6 4) (mapcar #'spool::job-id (spool::heap-jobs heap))))
    (is (equal '(3 7 5 1 2 6 4) (pop-all heap)))
    (is (null (spool::heap-pop heap)))))

(test heap-delete
  (let ((heap (spool::make-job-heap))
        (jobs (loop for id from 1 to 10 collect (test-job id (mod (* id 7) 10)))))
    (dolist (job jobs)
      (spool::heap-insert heap job))
    (dolist (id '(4 1 10 7))
      (spool::heap-delete heap (nth (1- id) jobs))
      (is (indexes-right-p heap)))
    (is (= 6 (spool::heap-count heap)))
    (is (every #'null (mapcar #'spool::job-heap-index
                              (list (nth 0 jobs) (nth 3 jobs) (nth 6 jobs) (nth 9 jobs)))))
    (is (equal '(8 5 2 9 6 3) (pop-all heap)))))

(test heap-inserts-and-deletes
  ;; Many inserts and deletes in a random order, then the jobs come out
  ;; in the order of their priorities.
  (let ((random (sb-ext:seed-random-state 7))
        (heap (spool::make-job-heap))
        (inside '()))
    (loop for id from 1 to 400
          do (if (and inside (< (random 3 random) 1))
                 (let ((job (nth (random (length inside) random) inside)))
                   (spool::heap-delete heap job)
                   (setf inside (remove job inside)))
                 (let ((job (test-job id (random 10 random))))
                   (spool::heap-insert heap job)
                   (push job inside))))
    (is (indexes-right-p heap))
    (is (equal (mapcar #'spool::job-id (sort (copy-list inside) #'spool::runs-before-p))
               (pop-all heap)))))
