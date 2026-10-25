(in-package #:timesheet)

;;; Time entries: who worked how many hours on which day, for which
;;; project. Hours are exact rationals, so 7.5 hours is 15/2 and sums
;;; never drift.

(define-condition timesheet-error (simple-error)
  ()
  (:documentation "Any error in reading or recording hours."))

(define-condition malformed-entry (timesheet-error)
  ((line :initarg :line :reader malformed-entry-line)
   (reason :initarg :reason :reader malformed-entry-reason))
  (:report (lambda (condition stream)
             (format stream "Malformed timesheet line ~S: ~A"
                     (malformed-entry-line condition)
                     (malformed-entry-reason condition))))
  (:documentation "A timesheet line that cannot be read."))

(defclass time-entry ()
  ((employee-id :initarg :employee-id :reader entry-employee-id :type string)
   (date :initarg :date :reader entry-date :type date)
   (hours :initarg :hours :reader entry-hours :type rational)
   (project :initarg :project :reader entry-project :type string))
  (:documentation "Hours one employee worked on one day for one project."))

(defmethod print-object ((entry time-entry) stream)
  (print-unreadable-object (entry stream :type t)
    (format stream "~A ~A ~A ~A"
            (entry-employee-id entry)
            (format-date (entry-date entry))
            (format-hours (entry-hours entry))
            (entry-project entry))))

(defclass timesheet ()
  ((entries :initform (make-hash-table :test 'equal)
            :reader timesheet-table
            :documentation "Lists of entries by employee id, latest first."))
  (:documentation "All the hours recorded, by employee."))

(defun make-timesheet ()
  (make-instance 'timesheet))

(defun record-hours (timesheet employee-id date hours project)
  "Records HOURS worked by EMPLOYEE-ID on DATE for PROJECT and returns
the new entry. A day has at most 24 hours."
  (unless (and (rationalp hours) (< 0 hours 24))
    (error 'timesheet-error
           :format-control "~S is not a number of hours in a day."
           :format-arguments (list hours)))
  (let ((entry (make-instance 'time-entry
                              :employee-id employee-id
                              :date date
                              :hours hours
                              :project project)))
    (push entry (gethash employee-id (timesheet-table timesheet)))
    entry))

(defun employee-entries (timesheet employee-id &key start end)
  "Returns the entries of EMPLOYEE-ID in date order, only those from
START and up to END, both inclusive, when they are given."
  (sort (remove-if-not (lambda (entry)
                         (let ((date (entry-date entry)))
                           (and (or (null start) (date<= start date))
                                (or (null end) (date<= date end)))))
                       (gethash employee-id (timesheet-table timesheet)))
        #'date< :key #'entry-date))

(defun parse-hours (string)
  "Parses a decimal number of hours, such as \"8\" or \"7.25\", into
an exact rational."
  (let* ((string (string-trim " " string))
         (dot (position #\. string))
         (whole (subseq string 0 dot))
         (fraction (if dot (subseq string (1+ dot)) "")))
    (unless (and (plusp (length string))
                 (every #'digit-char-p whole)
                 (every #'digit-char-p fraction)
                 (or (plusp (length whole)) (plusp (length fraction))))
      (error "Not a number of hours: ~S" string))
    (+ (if (plusp (length whole)) (parse-integer whole) 0)
       (if (plusp (length fraction))
           (/ (parse-integer fraction) (expt 10 (length fraction)))
           0))))

(defun split-fields (line)
  "Splits LINE at commas, trimming each field."
  (loop for start = 0 then (1+ comma)
        for comma = (position #\, line :start start)
        collect (string-trim " " (subseq line start comma))
        while comma))

(defun parse-entry-line (line)
  "Parses a timesheet line, DATE,EMPLOYEE-ID,HOURS,PROJECT, and returns
the four values. Signals MALFORMED-ENTRY if the line is not one."
  (let ((fields (split-fields line)))
    (unless (= (length fields) 4)
      (error 'malformed-entry :line line :reason "expected four fields"))
    (destructuring-bind (date id hours project) fields
      (when (string= id "")
        (error 'malformed-entry :line line :reason "no employee id"))
      (values (handler-case (parse-date date)
                (error () (error 'malformed-entry :line line :reason "bad date")))
              id
              (handler-case (parse-hours hours)
                (error () (error 'malformed-entry :line line :reason "bad hours")))
              project))))

(defun load-entries (timesheet lines)
  "Records the hours of each of LINES in TIMESHEET and returns how many
were recorded. Blank lines and lines starting with # are skipped."
  (let ((count 0))
    (dolist (line lines count)
      (let ((line (string-trim " " line)))
        (unless (or (string= line "") (char= (char line 0) #\#))
          (multiple-value-bind (date id hours project) (parse-entry-line line)
            (record-hours timesheet id date hours project)
            (incf count)))))))
