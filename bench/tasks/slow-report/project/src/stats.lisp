(in-package #:logsum)

;;; Counting and percentiles. All of it is exact: counts are integers, and
;;; shares are rounded once, when they are written.

(defun count-by (key items)
  "Returns an alist from each of the keys of ITEMS, as KEY gives them,
to how many of ITEMS have it, in the order the keys first appear. Keys are
compared with EQUAL."
  (let ((counts '()))
    (dolist (item items)
      (let* ((key (funcall key item))
             (entry (assoc key counts :test #'equal)))
        (if entry
            (incf (cdr entry))
            (push (cons key 1) counts))))
    (nreverse counts)))

(defun most-common (counts &optional count)
  "Returns the entries of the alist COUNTS, from keys to counts, the
highest counts first, and those with the same count in the order of
their keys (strings); only the first COUNT of them when COUNT is given."
  (let ((sorted (sort (copy-list counts)
                      (lambda (a b)
                        (or (> (cdr a) (cdr b))
                            (and (= (cdr a) (cdr b)) (string< (car a) (car b))))))))
    (if (and count (< count (length sorted)))
        (subseq sorted 0 count)
        sorted)))

(defun percentile (numbers p)
  "Returns the P-th percentile of NUMBERS, a non-empty sequence of reals,
by the nearest-rank method: the smallest number that at least P percent of
NUMBERS are no greater than."
  (let* ((sorted (sort (make-array (length numbers) :initial-contents numbers) #'<))
         (rank (max 1 (ceiling (* p (length sorted)) 100))))
    (aref sorted (1- rank))))

(defun per-mille (part whole)
  "Returns PART of WHOLE in tenths of a per mille, rounded, or 0 when
WHOLE is 0."
  (if (zerop whole) 0 (round (* 10000 part) whole)))

(defun percent-tenths (part whole)
  "Returns PART of WHOLE in tenths of a percent, rounded, or 0 when WHOLE
is 0."
  (if (zerop whole) 0 (round (* 1000 part) whole)))

(defun format-tenths (tenths)
  "Returns the number of tenths TENTHS as a decimal, such as 41.2."
  (multiple-value-bind (whole tenth) (floor tenths 10)
    (format nil "~D.~D" whole tenth)))

(defun format-count (n)
  "Returns the integer N with a comma between each group of three digits."
  (format nil "~:D" n))
