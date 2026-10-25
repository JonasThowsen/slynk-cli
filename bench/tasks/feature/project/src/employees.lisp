(in-package #:timesheet)

;;; Employees, and the roster that holds them. Money is in cents
;;; throughout: an hourly rate of 2500 is 25.00 an hour.

(defclass employee ()
  ((id :initarg :id
       :reader employee-id
       :type string
       :documentation "Short unique identifier, as used in timesheet lines.")
   (name :initarg :name
         :reader employee-name
         :type string))
  (:documentation "Someone whose hours we record."))

(defclass hourly-employee (employee)
  ((hourly-rate :initarg :hourly-rate
                :reader hourly-rate
                :type integer
                :documentation "Pay per hour, in cents."))
  (:documentation "An employee paid by the hour, with overtime."))

(defclass salaried-employee (employee)
  ((annual-salary :initarg :annual-salary
                  :reader annual-salary
                  :type integer
                  :documentation "Pay per year, in cents."))
  (:documentation "An employee paid a fixed salary per period, whatever the hours."))

(defclass contractor (employee)
  ((hourly-rate :initarg :hourly-rate
                :reader hourly-rate
                :type integer
                :documentation "Pay per hour, in cents."))
  (:documentation "Paid by the hour at a flat rate: no overtime."))

(defmethod print-object ((employee employee) stream)
  (print-unreadable-object (employee stream :type t)
    (format stream "~A ~S" (employee-id employee) (employee-name employee))))

(defclass roster ()
  ((employees :initform (make-hash-table :test 'equal)
              :reader roster-table
              :documentation "Employees by id."))
  (:documentation "The employees of the company."))

(defun make-roster (&rest employees)
  "Returns a roster with EMPLOYEES."
  (let ((roster (make-instance 'roster)))
    (dolist (employee employees roster)
      (add-employee roster employee))))

(defun add-employee (roster employee)
  "Adds EMPLOYEE to ROSTER and returns it. Ids are unique."
  (let ((id (employee-id employee)))
    (when (gethash id (roster-table roster))
      (error "There is already an employee with id ~S." id))
    (setf (gethash id (roster-table roster)) employee)))

(defun find-employee (roster id &key (errorp t))
  "Returns the employee with ID. If there is none, signals an error,
or returns NIL when ERRORP is false."
  (or (gethash id (roster-table roster))
      (and errorp (error "No employee with id ~S." id))))

(defun roster-employees (roster)
  "Returns the employees of ROSTER, ordered by id."
  (sort (loop for employee being the hash-values of (roster-table roster)
              collect employee)
        #'string< :key #'employee-id))
