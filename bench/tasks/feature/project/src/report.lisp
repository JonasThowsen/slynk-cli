(in-package #:timesheet)

;;; Plain-text reports for the payroll office.

(defun format-money (cents)
  "Returns CENTS as an amount with two decimals, such as \"1234.50\"."
  (multiple-value-bind (whole fraction) (truncate (abs cents) 100)
    (format nil "~:[~;-~]~D.~2,'0D" (minusp cents) whole fraction)))

(defun format-hours (hours)
  "Returns HOURS with two decimals, rounded to the nearest hundredth."
  (format-money (round (* hours 100))))

(defun write-payroll-report (pay-lines &optional (stream *standard-output*))
  "Writes PAY-LINES to STREAM as a table, one employee to a line, with
a line of totals at the end."
  (let ((row "~&~8A ~20A ~9@A ~9@A ~11@A~%"))
    (format stream row "Id" "Name" "Regular" "Overtime" "Gross")
    (dolist (line pay-lines)
      (format stream row
              (pay-line-employee-id line)
              (pay-line-name line)
              (format-hours (pay-line-regular-hours line))
              (format-hours (pay-line-overtime-hours line))
              (format-money (pay-line-gross line))))
    (destructuring-bind (&key regular-hours overtime-hours gross)
        (payroll-totals pay-lines)
      (format stream row
              "" "Total"
              (format-hours regular-hours)
              (format-hours overtime-hours)
              (format-money gross)))))

(defun project-hours (timesheet start end)
  "Returns the hours recorded on each project from START to END, both
inclusive, as a list of (PROJECT . HOURS), most hours first and
projects with equal hours by name."
  (let ((projects (make-hash-table :test 'equal)))
    (loop for entries being the hash-values of (timesheet-table timesheet)
          do (dolist (entry entries)
               (when (and (date<= start (entry-date entry))
                          (date<= (entry-date entry) end))
                 (incf (gethash (entry-project entry) projects 0)
                       (entry-hours entry)))))
    (sort (loop for project being the hash-keys of projects using (hash-value hours)
                collect (cons project hours))
          (lambda (a b)
            (or (> (cdr a) (cdr b))
                (and (= (cdr a) (cdr b)) (string< (car a) (car b))))))))
