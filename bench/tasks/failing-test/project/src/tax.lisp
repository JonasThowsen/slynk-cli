;;;; tax.lisp
;;;;
;;;; VAT categories. Each product belongs to one; the rate of a category
;;;; changes now and then, so a category keeps its history and an invoice
;;;; uses the rate in force on its date.

(in-package #:billing)

(defclass vat-category ()
  ((code :initarg :code :reader category-code
         :documentation "A keyword, such as :STANDARD.")
   (description :initarg :description :reader category-description)
   (periods :initarg :periods :accessor category-periods
            :documentation "The rate history: a list of (START-DATE . PERCENT),
the latest START-DATE first."))
  (:documentation "A VAT category and the rates it has had."))

(defmethod print-object ((category vat-category) stream)
  (print-unreadable-object (category stream :type t)
    (prin1 (category-code category) stream)))

(defvar *vat-categories* (make-hash-table :test 'eq)
  "The VAT categories by code.")

(define-condition no-vat-rate (error)
  ((category :initarg :category :reader no-vat-rate-category)
   (date :initarg :date :reader no-vat-rate-date))
  (:report (lambda (condition stream)
             (format stream "VAT category ~S has no rate on ~A."
                     (no-vat-rate-category condition)
                     (format-date (no-vat-rate-date condition))))))

(defun define-vat-category (code description &rest periods)
  "Defines, or redefines, the VAT category CODE. Each of PERIODS is a list
(START PERCENT): from the date string START on, the rate is PERCENT."
  (setf (gethash code *vat-categories*)
        (make-instance 'vat-category
                       :code code
                       :description description
                       :periods (sort (loop for (start percent) in periods
                                            collect (cons (parse-date start) percent))
                                      #'> :key #'car))))

(defun find-vat-category (code)
  "Returns the VAT category CODE, or signals an error."
  (or (gethash code *vat-categories*)
      (error "There is no VAT category ~S." code)))

(defun vat-rate (code date)
  "Returns the VAT percentage of category CODE on DATE."
  (let ((category (find-vat-category code)))
    (or (cdr (find-if (lambda (start) (<= start date))
                      (category-periods category)
                      :key #'car))
        (error 'no-vat-rate :category code :date date))))

;;; The Norwegian categories that the business uses.

(define-vat-category :standard "Alminnelig sats"
  '("2005-01-01" 25))

(define-vat-category :food "Næringsmidler"
  '("2007-01-01" 14) '("2012-01-01" 15))

(define-vat-category :low "Lav sats: persontransport, kino, overnatting"
  '("2016-01-01" 10) '("2018-01-01" 12))

(define-vat-category :exempt "Fritatt: bøker og aviser"
  '("2001-01-01" 0))
