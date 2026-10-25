(in-package #:tally)

;;; A small generator of our own for the sample data, so that a seed
;;; gives the same data on every Lisp and every run. It is the "minimal
;;; standard" Lehmer generator (Park and Miller, with multiplier 48271).

(defconstant +modulus+ 2147483647)
(defconstant +multiplier+ 48271)

(defstruct (generator (:constructor %make-generator (state)))
  (state 1 :type (integer 1 2147483646)))

(defun make-generator (seed)
  "Returns a generator whose sequence is determined by the integer SEED."
  (%make-generator (1+ (mod seed (1- +modulus+)))))

(defun next-integer (generator limit)
  "Returns the next integer of GENERATOR's sequence, from 0 below LIMIT."
  (declare (type generator generator) (type (integer 1 #.+modulus+) limit))
  (let ((state (mod (* (generator-state generator) +multiplier+) +modulus+)))
    (setf (generator-state generator) state)
    (mod state limit)))

(defun next-between (generator low high)
  "Returns the next integer of GENERATOR's sequence from LOW to HIGH, both
included."
  (+ low (next-integer generator (1+ (- high low)))))
