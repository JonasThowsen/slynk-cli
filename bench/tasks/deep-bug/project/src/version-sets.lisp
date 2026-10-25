(in-package #:depot.semver)

;;; A version set is the set of versions a constraint allows, kept as a
;;; sorted list of disjoint intervals. ^1.2.0 is one interval, from 1.2.0
;;; up to but not including 2.0.0-0; ^1.2.0 || ^3.0.0 is two. Intervals
;;; never change once made; a version set's list of them can be
;;; replaced, as NARROW-VERSION-SET does.

(defstruct (interval (:constructor %make-interval
                         (lower lower-inclusive-p upper upper-inclusive-p))
                     (:copier nil))
  "The versions from LOWER to UPPER. A bound of NIL is no bound; each
bound that is a version includes that version when its -INCLUSIVE-P is
true."
  (lower nil :type (or null version) :read-only t)
  (lower-inclusive-p nil :type boolean :read-only t)
  (upper nil :type (or null version) :read-only t)
  (upper-inclusive-p nil :type boolean :read-only t))

(defun bounds-empty-p (lower lower-inclusive-p upper upper-inclusive-p)
  "True when no version lies between the bounds LOWER and UPPER."
  (and lower upper
       (let ((order (compare-versions lower upper)))
         (or (plusp order)
             (and (zerop order)
                  (not (and lower-inclusive-p upper-inclusive-p)))))))

(defun make-interval (lower lower-inclusive-p upper upper-inclusive-p)
  "Returns the interval between the bounds, or NIL when it is empty. An
inclusive flag counts only for a bound that is a version."
  (let ((lower-inclusive-p (and lower lower-inclusive-p t))
        (upper-inclusive-p (and upper upper-inclusive-p t)))
    (unless (bounds-empty-p lower lower-inclusive-p upper upper-inclusive-p)
      (%make-interval lower lower-inclusive-p upper upper-inclusive-p))))

(defun interval-contains-p (interval version)
  "True when VERSION lies in INTERVAL."
  (let ((lower (interval-lower interval))
        (upper (interval-upper interval)))
    (and (or (null lower)
             (let ((order (compare-versions version lower)))
               (or (plusp order)
                   (and (zerop order) (interval-lower-inclusive-p interval)))))
         (or (null upper)
             (let ((order (compare-versions version upper)))
               (or (minusp order)
                   (and (zerop order) (interval-upper-inclusive-p interval))))))))

(defun compare-lower-bounds (a b)
  "Compares the lower bounds of intervals A and B: -1 when A's admits
versions B's does not, 1 the other way round, 0 when they are the same."
  (let ((va (interval-lower a))
        (vb (interval-lower b)))
    (cond ((and (null va) (null vb)) 0)
          ((null va) -1)
          ((null vb) 1)
          (t (let ((order (compare-versions va vb)))
               (cond ((/= order 0) order)
                     ((eq (interval-lower-inclusive-p a) (interval-lower-inclusive-p b)) 0)
                     ((interval-lower-inclusive-p a) -1)
                     (t 1)))))))

(defun compare-upper-bounds (a b)
  "Compares the upper bounds of intervals A and B: -1 when A's ends
first, 1 when B's does, 0 when they are the same."
  (let ((va (interval-upper a))
        (vb (interval-upper b)))
    (cond ((and (null va) (null vb)) 0)
          ((null va) 1)
          ((null vb) -1)
          (t (let ((order (compare-versions va vb)))
               (cond ((/= order 0) order)
                     ((eq (interval-upper-inclusive-p a) (interval-upper-inclusive-p b)) 0)
                     ((interval-upper-inclusive-p a) 1)
                     (t -1)))))))

(defun intersect-intervals (a b)
  "Returns the interval of the versions in both A and B, or NIL."
  (let ((lower (if (minusp (compare-lower-bounds a b)) b a))
        (upper (if (minusp (compare-upper-bounds a b)) a b)))
    (make-interval (interval-lower lower) (interval-lower-inclusive-p lower)
                   (interval-upper upper) (interval-upper-inclusive-p upper))))

(defun intervals-meet-p (a b)
  "True when interval B, which does not start before A, overlaps A or
starts where A ends, so that the two make one interval."
  (let ((end (interval-upper a))
        (start (interval-lower b)))
    (or (null end)
        (null start)
        (let ((order (compare-versions start end)))
          (or (minusp order)
              (and (zerop order)
                   (or (interval-lower-inclusive-p b) (interval-upper-inclusive-p a))))))))

(defun join-intervals (a b)
  "Returns the interval from the start of A to the later end of A and B."
  (let ((upper (if (minusp (compare-upper-bounds a b)) b a)))
    (%make-interval (interval-lower a) (interval-lower-inclusive-p a)
                    (interval-upper upper) (interval-upper-inclusive-p upper))))

(defun normalize-intervals (intervals)
  "Returns the intervals INTERVALS cover, sorted and disjoint, as a new
list; INTERVALS itself is not changed."
  ;; REMOVE may return INTERVALS itself, and SORT reuses its conses.
  (let ((sorted (sort (copy-list (remove nil intervals))
                      (lambda (a b) (minusp (compare-lower-bounds a b)))))
        (result '()))
    (dolist (interval sorted (nreverse result))
      (if (and result (intervals-meet-p (first result) interval))
          (setf (first result) (join-intervals (first result) interval))
          (push interval result)))))

(defun intersect-interval-lists (as bs)
  "Returns the intervals of the versions in both sorted, disjoint lists
AS and BS, as a new sorted, disjoint list."
  (let ((result '()))
    (loop while (and as bs)
          do (let ((both (intersect-intervals (first as) (first bs))))
               (when both
                 (push both result))
               (if (minusp (compare-upper-bounds (first as) (first bs)))
                   (pop as)
                   (pop bs))))
    (nreverse result)))

;;; Version sets

(defclass version-set ()
  ((intervals :initarg :intervals
              :initform '()
              :accessor version-set-intervals
              :documentation "The sorted, disjoint intervals of the set."))
  (:documentation "A set of versions, as the intervals they lie in."))

(defun make-version-set (&rest intervals)
  "Returns the set of the versions in any of INTERVALS; a NIL among them
is an empty interval."
  (make-instance 'version-set :intervals (normalize-intervals intervals)))

(defun any-version ()
  "Returns the set of all versions."
  (make-version-set (make-interval nil nil nil nil)))

(defun no-version ()
  "Returns the empty set."
  (make-version-set))

(defun exactly (version)
  "Returns the set of only VERSION."
  (let ((version (ensure-version version)))
    (make-version-set (make-interval version t version t))))

(defun copy-version-set (set)
  "Returns a new set with the versions of SET."
  (make-instance 'version-set :intervals (version-set-intervals set)))

(defun version-set-empty-p (set)
  "True when SET has no versions."
  (null (version-set-intervals set)))

(defun version-set-contains-p (set version)
  "True when VERSION is in SET."
  (let ((version (ensure-version version)))
    (some (lambda (interval) (interval-contains-p interval version))
          (version-set-intervals set))))

(defun version-set-intersection (a b)
  "Returns a new set of the versions in both A and B."
  (make-instance 'version-set
                 :intervals (intersect-interval-lists (version-set-intervals a)
                                                      (version-set-intervals b))))

(defun version-set-union (a b)
  "Returns a new set of the versions in A or B."
  (make-instance 'version-set
                 :intervals (normalize-intervals (append (version-set-intervals a)
                                                         (version-set-intervals b)))))

(defun narrow-version-set (set other)
  "Narrows SET, in place, to the versions that are also in OTHER, and
returns SET."
  (setf (version-set-intervals set)
        (intersect-interval-lists (version-set-intervals set)
                                  (version-set-intervals other)))
  set)

(defun version-set-equal (a b)
  "True when sets A and B have the same versions."
  (let ((as (version-set-intervals a))
        (bs (version-set-intervals b)))
    (and (= (length as) (length bs))
         (every (lambda (a b)
                  (and (zerop (compare-lower-bounds a b))
                       (zerop (compare-upper-bounds a b))))
                as bs))))

(defun interval-string (interval)
  "Returns INTERVAL as the comparators that make it, as \">=1.2.0 <2.0.0-0\"."
  (let ((lower (interval-lower interval))
        (upper (interval-upper interval)))
    (cond ((and (null lower) (null upper)) "*")
          ((and lower upper (version= lower upper)) (format nil "=~A" lower))
          (t (format nil "~@[~A~]~:[~; ~]~@[~A~]"
                     (and lower (format nil "~:[>~;>=~]~A"
                                        (interval-lower-inclusive-p interval) lower))
                     (and lower upper)
                     (and upper (format nil "~:[<~;<=~]~A"
                                        (interval-upper-inclusive-p interval) upper)))))))

(defun version-set-string (set)
  "Returns SET as a constraint text, its intervals separated by \" || \"."
  (if (version-set-empty-p set)
      "<none>"
      (format nil "~{~A~^ || ~}" (mapcar #'interval-string (version-set-intervals set)))))

(defmethod print-object ((set version-set) stream)
  (print-unreadable-object (set stream :type t)
    (write-string (version-set-string set) stream)))
