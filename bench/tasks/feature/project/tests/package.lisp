(defpackage #:timesheet/tests
  (:use #:cl #:fiveam #:timesheet))

(in-package #:timesheet/tests)

(def-suite timesheet :description "All the tests of timesheet.")

(defun d (string)
  "The date STRING, YYYY-MM-DD."
  (parse-date string))

(defun hourly (id name rate)
  (make-instance 'hourly-employee :id id :name name :hourly-rate rate))

(defun sheet (&rest lines)
  "A timesheet with LINES, each DATE,ID,HOURS,PROJECT."
  (let ((timesheet (make-timesheet)))
    (load-entries timesheet lines)
    timesheet))
