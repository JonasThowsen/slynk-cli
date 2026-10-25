(in-package #:logsum)

;;; A generator of our own for the sample logs, so that a seed gives the
;;; same log on every Lisp and every run: the "minimal standard" Lehmer
;;; generator of Park and Miller, with the multiplier 48271.

(defconstant +modulus+ 2147483647)
(defconstant +multiplier+ 48271)

(defstruct (generator (:constructor %make-generator (state)))
  (state 1 :type (integer 1 2147483646)))

(defun make-generator (seed)
  "Returns a generator whose numbers are set by the integer SEED."
  (%make-generator (1+ (mod seed (1- +modulus+)))))

(defun next-below (generator limit)
  "Returns the next number of GENERATOR, an integer from 0 below LIMIT."
  (declare (type generator generator) (type (integer 1 #.+modulus+) limit))
  (let ((state (mod (* (generator-state generator) +multiplier+) +modulus+)))
    (setf (generator-state generator) state)
    (mod state limit)))

(defun next-between (generator low high)
  "Returns the next number of GENERATOR from LOW to HIGH, both included."
  (+ low (next-below generator (1+ (- high low)))))

(defun chance (generator percent)
  "Returns true PERCENT times in a hundred."
  (< (next-below generator 100) percent))

(defun pick (generator choices)
  "Returns one of the vector CHOICES, each as likely."
  (aref choices (next-below generator (length choices))))

(defun pick-weighted (generator choices)
  "Returns the value of one of CHOICES, a list of (weight . value), each
as likely as its weight says."
  (let ((roll (next-below generator (reduce #'+ choices :key #'car))))
    (loop for (weight . value) in choices
          when (< roll weight) return value
          do (decf roll weight))))
