;;;; customers.lisp
;;;;
;;;; Customers and the groups they belong to. A group carries the
;;;; discount its customers get; a customer may have a discount of their
;;;; own, which then replaces the group's.

(in-package #:billing)

(defclass customer-group ()
  ((name :initarg :name :reader group-name
         :documentation "A keyword, such as :WHOLESALE.")
   (discount :initarg :discount :initform 0 :reader group-discount
             :documentation "The discount in percent, a rational."))
  (:documentation "A kind of customer, with the discount it gets."))

(defvar *customer-groups* (make-hash-table :test 'eq)
  "The customer groups by name.")

(defun define-customer-group (name &key (discount 0))
  "Defines, or redefines, the customer group NAME with DISCOUNT percent."
  (setf (gethash name *customer-groups*)
        (make-instance 'customer-group :name name :discount discount)))

(defun find-customer-group (name)
  "Returns the customer group NAME, or signals an error."
  (or (gethash name *customer-groups*)
      (error "There is no customer group ~S." name)))

(define-customer-group :retail)
(define-customer-group :wholesale :discount 15/2)
(define-customer-group :partner :discount 12)

(defclass customer ()
  ((id :initarg :id :reader customer-id)
   (name :initarg :name :reader customer-name)
   (group :initarg :group :reader customer-group-of
          :documentation "The CUSTOMER-GROUP the customer belongs to.")
   (discount :initarg :discount :initform nil :reader customer-own-discount
             :documentation "The customer's own discount in percent, or NIL
to use the group's.")
   (payment-terms :initarg :payment-terms :initform 14
                  :reader customer-payment-terms
                  :documentation "Days from the invoice date to the due date."))
  (:documentation "Someone the business invoices."))

(defmethod print-object ((customer customer) stream)
  (print-unreadable-object (customer stream :type t)
    (format stream "~A ~S" (customer-id customer) (customer-name customer))))

(defun make-customer (id name &key (group :retail) discount (payment-terms 14))
  "Returns a new customer in the group named GROUP."
  (make-instance 'customer
                 :id id
                 :name name
                 :group (find-customer-group group)
                 :discount discount
                 :payment-terms payment-terms))

(defgeneric discount-percent (party)
  (:documentation "Returns the discount, in percent, that PARTY gets on an
invoice's net amount."))

(defmethod discount-percent ((group customer-group))
  (group-discount group))

(defmethod discount-percent ((customer customer))
  (or (customer-own-discount customer)
      (discount-percent (customer-group-of customer))))
