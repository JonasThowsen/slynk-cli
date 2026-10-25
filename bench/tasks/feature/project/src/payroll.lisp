(in-package #:timesheet)

;;; A payroll run: for each employee, the hours of the period split
;;; into regular and overtime hours, and the gross pay in cents.

(defstruct pay-line
  "What one employee is paid for a period."
  (employee-id "" :type string)
  (name "" :type string)
  (regular-hours 0 :type rational)
  (overtime-hours 0 :type rational)
  (gross 0 :type integer))

(defun hours-by-day (entries)
  "Returns the hours ENTRIES record per day, as a list of (DAY-NUMBER
. HOURS), earliest day first."
  (let ((days (make-hash-table)))
    (dolist (entry entries)
      (incf (gethash (date-day-number (entry-date entry)) days 0)
            (entry-hours entry)))
    (sort (loop for day being the hash-keys of days using (hash-value hours)
                collect (cons day hours))
          #'< :key #'car)))

(defun group-by-week (days)
  "Groups DAYS, a list of (DAY-NUMBER . HOURS) in date order, into a
list of weeks, each a list of the days in it, in date order."
  ;; WEEKS holds (MONDAY . DAYS), both latest first, while it is built.
  (let ((weeks '()))
    (dolist (day days)
      (let ((monday (date-day-number (week-start (%make-date (car day))))))
        (if (and weeks (= (car (first weeks)) monday))
            (push day (cdr (first weeks)))
            (push (list monday day) weeks))))
    (nreverse (mapcar (lambda (week) (reverse (cdr week))) weeks))))

(defun split-hours (entries rules)
  "Returns two values, the regular and the overtime hours of ENTRIES,
which are all of one employee, under RULES.

Hours above the daily threshold on a day are overtime. Of the rest,
those that take the week, Monday to Sunday, above the weekly threshold
are overtime too; the daily overtime does not count towards it."
  (let ((daily-threshold (daily-threshold rules))
        (weekly-threshold (weekly-threshold rules))
        (regular 0)
        (overtime 0))
    (dolist (week (group-by-week (hours-by-day entries)))
      (let ((week-regular 0))
        (dolist (day week)
          (let* ((hours (cdr day))
                 (daily-overtime (if daily-threshold
                                     (max 0 (- hours daily-threshold))
                                     0))
                 (candidate (- hours daily-overtime))
                 (room (max 0 (- weekly-threshold week-regular)))
                 (day-regular (min candidate room)))
            (incf week-regular day-regular)
            (incf overtime (+ daily-overtime (- candidate day-regular)))))
        (incf regular week-regular)))
    (values regular overtime)))

(defun total-hours (entries)
  (reduce #'+ entries :key #'entry-hours))

(defgeneric compute-pay (employee entries rules)
  (:documentation "Returns the PAY-LINE of EMPLOYEE for the period that
ENTRIES, the employee's entries of the period, cover, under RULES."))

(defmethod compute-pay ((employee hourly-employee) entries rules)
  (multiple-value-bind (regular overtime) (split-hours entries rules)
    (let ((rate (hourly-rate employee)))
      (make-pay-line :employee-id (employee-id employee)
                     :name (employee-name employee)
                     :regular-hours regular
                     :overtime-hours overtime
                     :gross (round (+ (* regular rate)
                                      (* overtime rate (overtime-multiplier rules))))))))

(defmethod compute-pay ((employee contractor) entries rules)
  (declare (ignore rules))
  (let ((hours (total-hours entries)))
    (make-pay-line :employee-id (employee-id employee)
                   :name (employee-name employee)
                   :regular-hours hours
                   :gross (round (* hours (hourly-rate employee))))))

(defmethod compute-pay ((employee salaried-employee) entries rules)
  (make-pay-line :employee-id (employee-id employee)
                 :name (employee-name employee)
                 :regular-hours (total-hours entries)
                 :gross (round (annual-salary employee) (periods-per-year rules))))

(defun run-payroll (roster timesheet start end &key (rules (make-pay-rules)))
  "Returns the pay lines of every employee in ROSTER for the period
from START to END, both inclusive, ordered by employee id."
  (unless (date<= start end)
    (error "The period ~A to ~A ends before it starts."
           (format-date start) (format-date end)))
  (mapcar (lambda (employee)
            (compute-pay employee
                         (employee-entries timesheet (employee-id employee)
                                           :start start :end end)
                         rules))
          (roster-employees roster)))

(defun payroll-totals (pay-lines)
  "Returns the sums over PAY-LINES as a property list with the keys
:REGULAR-HOURS, :OVERTIME-HOURS and :GROSS."
  (list :regular-hours (reduce #'+ pay-lines :key #'pay-line-regular-hours)
        :overtime-hours (reduce #'+ pay-lines :key #'pay-line-overtime-hours)
        :gross (reduce #'+ pay-lines :key #'pay-line-gross)))
