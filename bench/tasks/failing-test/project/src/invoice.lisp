;;;; invoice.lisp
;;;;
;;;; Invoices and credit notes. The amounts follow the order a Norwegian
;;;; invoice shows them in: the lines' net amounts, summed per VAT
;;;; category; the customer's discount, spread over the categories in
;;;; proportion to their amounts; VAT on each category's discounted
;;;; amount; and the total.

(in-package #:billing)

(defclass invoice-line ()
  ((product :initarg :product :reader line-product)
   (quantity :initarg :quantity :reader line-quantity
             :documentation "The number of units, an integer; negative on a
credit note.")
   (unit-price :initarg :unit-price :reader line-unit-price
               :documentation "The price of one unit in øre, without VAT."))
  (:documentation "One product on an invoice."))

(defclass invoice ()
  ((number :initarg :number :reader invoice-number)
   (customer :initarg :customer :reader invoice-customer)
   (date :initarg :date :reader invoice-date)
   (catalog :initarg :catalog :reader invoice-catalog
            :documentation "The catalog that ADD-LINE finds products in.")
   (lines :initform '() :accessor invoice-lines
          :documentation "The INVOICE-LINEs, in the order they were added.")
   (credits :initarg :credits :initform nil :reader invoice-credits
            :documentation "For a credit note, the invoice it credits."))
  (:documentation "An invoice, or with CREDITS a credit note."))

(defmethod print-object ((invoice invoice) stream)
  (print-unreadable-object (invoice stream :type t)
    (format stream "~A ~A" (invoice-number invoice)
            (format-date (invoice-date invoice)))))

(defun make-invoice (number customer date catalog)
  "Returns a new invoice without lines. DATE is a date or a date string."
  (make-instance 'invoice
                 :number number
                 :customer customer
                 :date (if (stringp date) (parse-date date) date)
                 :catalog catalog))

(defun add-line (invoice sku quantity &key unit-price)
  "Adds QUANTITY units of the product SKU to INVOICE, at the product's
list price unless UNIT-PRICE (an amount or an amount string) is given.
Returns the new line."
  (let* ((product (find-product (invoice-catalog invoice) sku))
         (line (make-instance 'invoice-line
                              :product product
                              :quantity quantity
                              :unit-price (etypecase unit-price
                                            (null (product-unit-price product))
                                            (string (parse-amount unit-price))
                                            (integer unit-price)))))
    (setf (invoice-lines invoice)
          (append (invoice-lines invoice) (list line)))
    line))

(defgeneric line-net (line)
  (:documentation "Returns the net amount of LINE in øre, without VAT."))

(defmethod line-net ((line invoice-line))
  (* (line-quantity line) (line-unit-price line)))

(defun category-nets (invoice)
  "Returns the net amounts of INVOICE's lines summed per VAT category, as
an alist of (CATEGORY-CODE . NET), the categories in the order their
first line appears."
  (let ((nets (make-hash-table :test 'eq))
        (order '()))
    (dolist (line (invoice-lines invoice))
      (let ((code (product-vat-category (line-product line))))
        (multiple-value-bind (net present) (gethash code nets)
          (unless present
            (push code order))
          (setf (gethash code nets) (+ (or net 0) (line-net line))))))
    (loop for code in (reverse order)
          collect (cons code (gethash code nets)))))

(defun invoice-subtotal (invoice)
  "Returns the sum of INVOICE's line amounts, before discount and VAT."
  (reduce #'+ (invoice-lines invoice) :key #'line-net))

(defun discount-amount (invoice)
  "Returns the customer's discount on INVOICE as a negative amount, or 0."
  (- (percent-of (invoice-subtotal invoice)
                 (discount-percent (invoice-customer invoice)))))

(defstruct (vat-line (:constructor make-vat-line (category rate base vat)))
  "The VAT of one category on an invoice: the RATE in percent, the BASE it
is taken of (the category's net amount less its share of the discount),
and the VAT itself."
  category rate base vat)

(defun vat-breakdown (invoice)
  "Returns a VAT-LINE for each VAT category on INVOICE, in the order of
CATEGORY-NETS. The discount is spread over the categories in proportion
to their net amounts, so that their bases add up to the subtotal plus
the discount."
  (let* ((nets (category-nets invoice))
         (discount (discount-amount invoice))
         (shares (if (zerop discount)
                     (make-list (length nets) :initial-element 0)
                     (allocate discount (mapcar #'cdr nets)))))
    (loop for (code . net) in nets
          for share in shares
          for base = (+ net share)
          for rate = (vat-rate code (invoice-date invoice))
          collect (make-vat-line code rate base (percent-of base rate)))))

(defun invoice-net (invoice)
  "Returns INVOICE's amount after discount, without VAT."
  (reduce #'+ (vat-breakdown invoice) :key #'vat-line-base))

(defun invoice-vat (invoice)
  "Returns the VAT on INVOICE."
  (reduce #'+ (vat-breakdown invoice) :key #'vat-line-vat))

(defun invoice-total (invoice)
  "Returns the amount the customer pays for INVOICE: net plus VAT."
  (+ (invoice-net invoice) (invoice-vat invoice)))

(defun due-date (invoice)
  "Returns the date INVOICE is due: its date plus the customer's payment
terms, moved on to the Monday when that is a Saturday or Sunday."
  (let ((due (add-days (invoice-date invoice)
                       (customer-payment-terms (invoice-customer invoice)))))
    (case (weekday due)
      (5 (add-days due 2))
      (6 (add-days due 1))
      (t due))))

(defun credit-note (invoice number &key (date (invoice-date invoice)))
  "Returns a credit note numbered NUMBER that cancels INVOICE: the same
lines at the same prices, with their quantities negated."
  (let ((note (make-instance 'invoice
                             :number number
                             :customer (invoice-customer invoice)
                             :date (if (stringp date) (parse-date date) date)
                             :catalog (invoice-catalog invoice)
                             :credits invoice)))
    (setf (invoice-lines note)
          (loop for line in (invoice-lines invoice)
                collect (make-instance 'invoice-line
                                       :product (line-product line)
                                       :quantity (- (line-quantity line))
                                       :unit-price (line-unit-price line))))
    note))
