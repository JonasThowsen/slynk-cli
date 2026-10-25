(in-package #:stockfile)

;;; The files the warehouse exports.

(define-record-format stock-count (:delimiter #\;)
  "One line of a stock count from the handheld scanners."
  (sku "SKU" :check (plusp (length sku)))
  (location "Location" :default "MAIN")
  (quantity "Counted" :type :integer :check (not (minusp quantity)))
  (counted-on "Date" :type :date :default nil))

(define-record-format price-list ()
  "One article of the price list from the accounting system."
  (sku "Article")
  (description "Description" :default "")
  (unit-price "Price" :type :decimal :check (not (minusp unit-price)))
  (active "Active" :type :boolean :default t))

(define-record-format order-line ()
  "One line of an order exported from the webshop."
  (order-id "Order" :type :integer)
  (line "Line" :type :integer)
  (sku "SKU")
  (quantity "Qty" :type :integer :check (plusp quantity)))

(defun stock-totals (counts)
  "The counted quantity of each SKU among the STOCK-COUNT records COUNTS,
summed over locations, as an alist sorted by SKU."
  (let ((totals (make-hash-table :test 'equal)))
    (dolist (count counts)
      (incf (gethash (stock-count-sku count) totals 0)
            (stock-count-quantity count)))
    (sort (alexandria:hash-table-alist totals) #'string< :key #'car)))

(defun stock-value (counts prices)
  "The value of the stock counted in the STOCK-COUNT records COUNTS at
the unit prices of the PRICE-LIST records PRICES. Returns the value of
the SKUs with an active price, and as a second value the list of SKUs
counted that have none."
  (let ((price-of (make-hash-table :test 'equal))
        (value 0)
        (unpriced '()))
    (dolist (price prices)
      (when (price-list-active price)
        (setf (gethash (price-list-sku price) price-of)
              (price-list-unit-price price))))
    (loop for (sku . quantity) in (stock-totals counts)
          for unit-price = (gethash sku price-of)
          do (if unit-price
                 (incf value (* quantity unit-price))
                 (push sku unpriced)))
    (values value (nreverse unpriced))))
