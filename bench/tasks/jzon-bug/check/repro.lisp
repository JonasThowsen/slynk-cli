;;;; The reported case: floats with no fractional part stringify with
;;;; their digits shifted and garbage in front. Also checks such floats
;;;; of every length jzon writes without an exponent, single and double,
;;;; and that random floats of every magnitude read back as themselves.

(in-package :cl-user)

(defun reproduction-failures ()
  (let ((failures '()))
    (flet ((expect (value expected)
             (let ((got (com.inuoe.jzon:stringify value)))
               (unless (string= got expected)
                 (push (format nil "(stringify ~S) => ~S, expected ~S" value got expected)
                       failures)))))
      (expect 1.0d0 "1.0")
      (expect 12.0d0 "12.0")
      (expect 123456.0f0 "123456.0")
      (expect 1.0f0 "1.0")
      (expect -42.0d0 "-42.0")
      (expect 1.5d0 "1.5")
      (expect 1.0d7 "1.0e7")
      (expect (vector 1.0d0 2.5d0 300.0d0) "[1.0,2.5,300.0]")
      ;; Every whole number below 10^7 is written as itself with ".0",
      ;; whatever its number of digits; a sample of each length, and the
      ;; lengths' edges.
      (loop for n in (append (loop for digits from 1 to 7
                                   for low = (expt 10 (1- digits))
                                   append (list low (1+ low) (* 5 low) (1- (* 10 low))))
                             (loop for n from 1 below 10000000 by 7919 collect n))
            for expected = (format nil "~D.0" n)
            do (expect (coerce n 'double-float) expected)
               (expect (coerce n 'single-float) expected)
               (expect (- (coerce n 'double-float)) (concatenate 'string "-" expected))))
    ;; Random floats of every magnitude read back as the same float.
    (let ((*random-state* (sb-ext:seed-random-state 1066)))
      (loop repeat 20000
            for exponent = (- (random 60) 30)
            for double = (* (random 1d0) (expt 10d0 exponent))
            for single = (coerce double 'single-float)
            do (dolist (x (list double single (ffloor double) (ffloor single)))
                 (let* ((string (com.inuoe.jzon:stringify x))
                        (back (ignore-errors (com.inuoe.jzon:parse string))))
                   ;; jzon reads every float as a double; a single's
                   ;; shortest digits name the single, not the double.
                   (unless (and (realp back) (= (coerce back (type-of x)) x))
                     (push (format nil "(stringify ~S) => ~S, which reads back as ~S"
                                   x string back)
                           failures))))
            until (> (length failures) 20)))
    (nreverse failures)))
