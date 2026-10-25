;;;; catalog.lisp
;;;;
;;;; The products the business sells, by SKU.

(in-package #:billing)

(defclass product ()
  ((sku :initarg :sku :reader product-sku
        :documentation "The stock keeping unit, a string such as \"TEA-100\".")
   (name :initarg :name :reader product-name)
   (unit-price :initarg :unit-price :reader product-unit-price
               :documentation "The list price of one unit, in øre, without VAT.")
   (vat-category :initarg :vat-category :reader product-vat-category
                 :documentation "The code of the product's VAT category."))
  (:documentation "Something the business sells."))

(defmethod print-object ((product product) stream)
  (print-unreadable-object (product stream :type t)
    (format stream "~A ~S" (product-sku product) (product-name product))))

(defclass catalog ()
  ((products :initform (make-hash-table :test 'equal) :reader catalog-products
             :documentation "The products by SKU."))
  (:documentation "The products on sale."))

(defun make-catalog ()
  (make-instance 'catalog))

(define-condition unknown-product (error)
  ((sku :initarg :sku :reader unknown-product-sku))
  (:report (lambda (condition stream)
             (format stream "There is no product with SKU ~S."
                     (unknown-product-sku condition)))))

(defun add-product (catalog sku name price vat-category)
  "Adds a product to CATALOG, or replaces the one with the same SKU.
PRICE is a string for PARSE-AMOUNT or an amount in øre. Returns the
product."
  (find-vat-category vat-category)      ; reject unknown categories now
  (setf (gethash sku (catalog-products catalog))
        (make-instance 'product
                       :sku sku
                       :name name
                       :unit-price (if (stringp price) (parse-amount price) price)
                       :vat-category vat-category)))

(defun find-product (catalog sku)
  "Returns the product with SKU in CATALOG, or signals UNKNOWN-PRODUCT."
  (or (gethash sku (catalog-products catalog))
      (error 'unknown-product :sku sku)))
