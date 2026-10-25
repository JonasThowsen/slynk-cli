(in-package #:stockfile)

;;; A cell's text becomes a value through CONVERT-CELL, by the type its
;;; field declares. A program adds a type by adding a method.

(define-condition invalid-cell (error)
  ((text :initarg :text :reader invalid-cell-text)
   (expected :initarg :expected :reader invalid-cell-expected))
  (:report (lambda (condition stream)
             (format stream "~S is not ~A"
                     (invalid-cell-text condition)
                     (invalid-cell-expected condition))))
  (:documentation "Signalled by CONVERT-CELL when a cell's text is not a
value of the type asked for."))

(defun trim-cell (text)
  "TEXT without the spaces and tabs around it."
  (string-trim '(#\Space #\Tab) text))

(defun blank-cell-p (text)
  "True when the cell TEXT is empty or only spaces and tabs."
  (zerop (length (trim-cell text))))

(defgeneric convert-cell (type text)
  (:documentation "Returns the value of type TYPE, a keyword, that the
cell TEXT, which is not blank, holds. Signals INVALID-CELL when TEXT is not
a valid value of TYPE."))

(defmethod convert-cell (type text)
  (error "There is no cell type ~S for the cell ~S." type text))

(defmethod convert-cell ((type (eql :string)) text)
  (trim-cell text))

(defmethod convert-cell ((type (eql :integer)) text)
  (handler-case (parse-integer (trim-cell text))
    (parse-error ()
      (error 'invalid-cell :text text :expected "an integer"))))

(defun parse-decimal (text)
  "The rational number that TEXT writes in decimal, as -12.5 or 12,50,
with a dot or a comma before the fraction; NIL if TEXT is not one."
  (let* ((negative (and (plusp (length text)) (char= (char text 0) #\-)))
         (digits (if negative (subseq text 1) text))
         (point (position-if (lambda (char) (member char '(#\. #\,))) digits))
         (whole (subseq digits 0 point))
         (fraction (if point (subseq digits (1+ point)) "")))
    (flet ((digits-p (string)
             (and (plusp (length string)) (every #'digit-char-p string))))
      (when (and (digits-p whole)
                 (or (null point) (digits-p fraction)))
        (let ((magnitude (+ (parse-integer whole)
                            (if point
                                (/ (parse-integer fraction)
                                   (expt 10 (length fraction)))
                                0))))
          (if negative (- magnitude) magnitude))))))

(defmethod convert-cell ((type (eql :decimal)) text)
  (or (parse-decimal (trim-cell text))
      (error 'invalid-cell :text text :expected "a decimal number")))

(defun days-in-month (month year)
  "The number of days in MONTH, 1 to 12, of YEAR."
  (if (= month 2)
      (if (and (zerop (mod year 4))
               (or (plusp (mod year 100)) (zerop (mod year 400))))
          29
          28)
      (nth (1- month) '(31 28 31 30 31 30 31 31 30 31 30 31))))

(defun parse-iso-date (text)
  "The universal time of midnight UTC on the date TEXT writes as
YYYY-MM-DD, or NIL when TEXT is not such a date."
  (when (and (= (length text) 10)
             (char= (char text 4) #\-)
             (char= (char text 7) #\-)
             (every #'digit-char-p (remove #\- text)))
    (let ((year (parse-integer text :end 4))
          (month (parse-integer text :start 5 :end 7))
          (day (parse-integer text :start 8)))
      (when (and (<= 1900 year)
                 (<= 1 month 12)
                 (<= 1 day (days-in-month month year)))
        (encode-universal-time 0 0 0 day month year 0)))))

(defmethod convert-cell ((type (eql :date)) text)
  (or (parse-iso-date (trim-cell text))
      (error 'invalid-cell :text text :expected "a date written YYYY-MM-DD")))

(defmethod convert-cell ((type (eql :boolean)) text)
  (let ((word (trim-cell text)))
    (cond ((member word '("yes" "true" "1") :test #'string-equal) t)
          ((member word '("no" "false" "0") :test #'string-equal) nil)
          (t (error 'invalid-cell :text text :expected "yes or no")))))
