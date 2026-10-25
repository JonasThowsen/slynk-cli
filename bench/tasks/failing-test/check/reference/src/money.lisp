;;;; money.lisp
;;;;
;;;; Amounts are integers in øre, the 1/100 of a krone. Keeping them as
;;;; integers means sums are exact; the only rounding happens where a
;;;; percentage is taken, and that rounding is done here.

(in-package #:billing)

(defun round-half-away (number)
  "Rounds the rational NUMBER to the nearest integer, with halves going
away from zero, as invoices expect. (CL:ROUND rounds halves to even,
which would turn 0.5 øre into 0.)"
  (if (minusp number)
      (- (floor (+ (- number) 1/2)))
      (floor (+ number 1/2))))

(defun percent-of (amount percent)
  "Returns PERCENT percent of AMOUNT, rounded to whole øre. PERCENT may
be a rational, such as 15/2 for 7.5 %."
  (round-half-away (* amount percent 1/100)))

(defun parse-amount (string)
  "Parses STRING, such as \"1234.50\", \"-12.5\" or \"300\", into an
amount in øre. Signals an error for anything else."
  (let* ((string (string-trim " " string))
         (negative (and (plusp (length string)) (char= (char string 0) #\-)))
         (digits (if negative (subseq string 1) string))
         (dot (position #\. digits))
         (kroner (subseq digits 0 dot))
         (fraction (if dot (subseq digits (1+ dot)) "")))
    (unless (and (plusp (length kroner))
                 (every #'digit-char-p kroner)
                 (<= (length fraction) 2)
                 (every #'digit-char-p fraction))
      (error "~S is not an amount." string))
    (let ((ore (+ (* 100 (parse-integer kroner))
                  (if (string= fraction "")
                      0
                      (* (parse-integer fraction)
                         (if (= (length fraction) 1) 10 1))))))
      (if negative (- ore) ore))))

(defun format-amount (amount &optional stream)
  "Writes AMOUNT in øre as kroner with two decimals, such as \"1234.50\",
to STREAM, or returns it as a string when STREAM is NIL."
  (multiple-value-bind (kroner ore) (truncate (abs amount) 100)
    (format stream "~:[~;-~]~D.~2,'0D" (minusp amount) kroner ore)))

(defun indices-by-weight (weights)
  "Returns the indices of WEIGHTS, the index of the largest weight first.
Equal weights keep their order."
  (let ((indices (loop for index from 0 below (length weights)
                       collect index)))
    (stable-sort indices #'> :key (lambda (index) (nth index weights)))))

(defun allocate (amount weights)
  "Splits AMOUNT into integer parts proportional to WEIGHTS that add up to
AMOUNT exactly. Each part is first rounded down; the øre left over then
go one at a time to the parts with the largest weights. WEIGHTS must not
add up to zero."
  (let* ((total-weight (reduce #'+ weights))
         (parts (mapcar (lambda (weight)
                          (floor (* amount weight) total-weight))
                        weights))
         (left-over (- amount (reduce #'+ parts))))
    (loop for index in (indices-by-weight weights)
          repeat left-over
          do (incf (nth index parts)))
    parts))
