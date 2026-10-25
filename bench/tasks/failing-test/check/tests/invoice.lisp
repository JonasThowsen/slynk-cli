;;;; tests/invoice.lisp

(in-package #:billing-tests)

(def-suite invoices :in billing)
(in-suite invoices)

(defun shop-catalog ()
  "The catalog of the coffee shop the tests invoice from."
  (let ((catalog (make-catalog)))
    (add-product catalog "COF-500" "Kaffe, hele bønner, 500 g" "129.00" :food)
    (add-product catalog "TEA-100" "Te, løs, 100 g" "49.90" :food)
    (add-product catalog "MUG-01" "Krus" "89.00" :standard)
    (add-product catalog "GRN-01" "Kaffekvern" "699.00" :standard)
    (add-product catalog "BOK-01" "Kaffeboka" "349.00" :exempt)
    catalog))

(defun invoice-for (customer date &rest lines)
  "Returns an invoice to CUSTOMER on DATE with LINES, each (SKU QUANTITY)."
  (let ((invoice (make-invoice "2026-0001" customer date (shop-catalog))))
    (loop for (sku quantity) in lines
          do (add-line invoice sku quantity))
    invoice))

(defvar *retail* (make-customer "K100" "Kari Nordmann"))
(defvar *cafe* (make-customer "K200" "Kafé Bønna AS" :group :wholesale :payment-terms 30))
(defvar *friend* (make-customer "K300" "Ola Venn" :discount 20))

(test vat-rate-history
  (is (= 25 (vat-rate :standard (parse-date "2026-01-01"))))
  (is (= 14 (vat-rate :food (parse-date "2011-12-31"))))
  (is (= 15 (vat-rate :food (parse-date "2012-01-01"))))
  (is (= 10 (vat-rate :low (parse-date "2017-06-01"))))
  (is (= 12 (vat-rate :low (parse-date "2026-03-02"))))
  (is (= 0 (vat-rate :exempt (parse-date "2026-03-02")))))

(test vat-rate-before-first-period-signals
  (signals no-vat-rate (vat-rate :low (parse-date "2015-12-31"))))

(test unknown-product-signals
  (signals unknown-product (find-product (shop-catalog) "NOPE")))

(test add-line-uses-list-price
  (let* ((invoice (invoice-for *retail* "2026-03-02"))
         (line (add-line invoice "MUG-01" 2)))
    (is (= 8900 (line-unit-price line)))
    (is (= 17800 (line-net line)))
    (is (eq line (first (invoice-lines invoice))))))

(test add-line-with-price-override
  (let ((invoice (invoice-for *retail* "2026-03-02")))
    (is (= 7500 (line-unit-price (add-line invoice "MUG-01" 1 :unit-price "75.00"))))
    (is (= 7000 (line-unit-price (add-line invoice "MUG-01" 1 :unit-price 7000))))))

(test category-nets-in-order
  (let ((invoice (invoice-for *retail* "2026-03-02"
                              '("MUG-01" 1) '("COF-500" 2) '("GRN-01" 1) '("BOK-01" 1))))
    (is (equal '((:standard . 78800) (:food . 25800) (:exempt . 34900))
               (category-nets invoice)))
    (is (= 139500 (invoice-subtotal invoice)))))

(test retail-invoice-total
  (let ((invoice (invoice-for *retail* "2026-03-02"
                              '("COF-500" 2) '("MUG-01" 1) '("BOK-01" 1))))
    ;; 258.00 food at 15 % and 89.00 standard at 25 %, 349.00 exempt
    (is (= 0 (discount-amount invoice)))
    (is (= 69600 (invoice-net invoice)))
    (is (= (+ 3870 2225) (invoice-vat invoice)))
    (is (= 75695 (invoice-total invoice)))))

(test customer-own-discount-overrides-group
  (is (= 0 (discount-percent *retail*)))
  (is (= 15/2 (discount-percent *cafe*)))
  (is (= 20 (discount-percent *friend*))))

(test wholesale-single-category-discount
  (let ((invoice (invoice-for *cafe* "2026-03-02" '("COF-500" 3))))
    ;; 387.00 less 7.5 % is 357.97; VAT 15 % of that is 53.6955
    (is (= -2903 (discount-amount invoice)))
    (is (= 35797 (invoice-net invoice)))
    (is (= 5370 (invoice-vat invoice)))
    (is (= 41167 (invoice-total invoice)))))

(test discounted-invoice-total
  (let ((invoice (invoice-for *cafe* "2026-03-02"
                              '("COF-500" 3) '("TEA-100" 2) '("GRN-01" 1)
                              '("MUG-01" 4) '("BOK-01" 1))))
    (is (= 189080 (invoice-subtotal invoice)))
    (is (= -14181 (discount-amount invoice)))
    (is (= 206050 (invoice-total invoice)))))

(test due-date-moves-off-weekend
  ;; 14 days after Friday 2026-10-09 is Friday 2026-10-23
  (is (string= "2026-10-23" (format-date (due-date (invoice-for *retail* "2026-10-09")))))
  ;; 30 days after Monday 2026-09-28 is Wednesday 2026-10-28
  (is (string= "2026-10-28" (format-date (due-date (invoice-for *cafe* "2026-09-28")))))
  ;; 14 days after Saturday 2026-10-10 is Saturday 2026-10-24: Monday
  (is (string= "2026-10-26" (format-date (due-date (invoice-for *retail* "2026-10-10")))))
  ;; 14 days after Sunday 2026-10-11 is Sunday 2026-10-25: Monday
  (is (string= "2026-10-26" (format-date (due-date (invoice-for *retail* "2026-10-11"))))))

(test credit-note-cancels-invoice
  (let* ((invoice (invoice-for *retail* "2026-03-02"
                               '("COF-500" 2) '("GRN-01" 1) '("BOK-01" 1)))
         (note (credit-note invoice "2026-K001" :date "2026-03-09")))
    (is (eq invoice (invoice-credits note)))
    (is (= (length (invoice-lines invoice)) (length (invoice-lines note))))
    (is (= -2 (line-quantity (first (invoice-lines note)))))
    (is (= 0 (+ (invoice-total invoice) (invoice-total note))))
    (is (= 0 (+ (invoice-vat invoice) (invoice-vat note))))))

(test render-invoice-shows-amounts
  (let ((text (render-invoice (invoice-for *cafe* "2026-03-02" '("COF-500" 3)) nil)))
    (is (search "Faktura 2026-0001" text))
    (is (search "Kafé Bønna AS (K200)" text))
    (is (search "Forfall: 2026-04-01" text))
    (is (search "3 x Kaffe, hele bønner, 500 g (129.00)" text))
    (is (search "Rabatt 7.5 %" text))
    (is (search "-29.03" text))
    (is (search "MVA 15 % av 357.97" text))
    (is (search "411.67" text))))
