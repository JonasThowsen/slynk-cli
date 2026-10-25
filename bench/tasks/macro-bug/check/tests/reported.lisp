;;;; Tests of the reported case: a format whose field has the name of a
;;;; variable that DEFINE-RECORD-FORMAT's expansion uses. Such a capture
;;;; only happens for formats defined in the STOCKFILE package, where the
;;;; expansion's own symbols live, so these formats are defined there.

(in-package #:stockfile)

;;; The same definition as ORDER-LINE in src/formats.lisp, under a name
;;; of its own so that it does not depend on what the project has.
(define-record-format webshop-order-line ()
  (order-id "Order" :type :integer)
  (line "Line" :type :integer)
  (sku "SKU")
  (quantity "Qty" :type :integer :check (plusp quantity)))

;;; A field named CELLS.
(define-record-format battery-pack ()
  (model "Model")
  (cells "Cells" :type :integer :check (plusp cells))
  (capacity "Capacity" :type :integer))

;;; A field named TEXT, which a later field's default uses.
(define-record-format bin-note ()
  (text "Text")
  (summary "Summary" :default text))

(in-package #:stockfile/tests)
(in-suite :stockfile)

(defparameter *orders*
  (lines "Order,Line,SKU,Qty"
         "1001,1,A-100,2"
         "1001,2,B-200,1"
         "1002,1,A-100,0"))

(test reported-order-line-error-points-at-the-line
  (let ((condition (first-error *orders* 'order-line)))
    (is (typep condition 'record-error))
    (is (eql 4 (record-error-line condition)))
    (is (string= "Qty" (record-error-column condition)))))

(test field-named-line-signals-the-file-line
  (let ((condition (first-error *orders* 'stockfile::webshop-order-line)))
    (is (typep condition 'record-error))
    (is (eql 4 (record-error-line condition)))
    (is (string= "Qty" (record-error-column condition))))
  (let ((condition (first-error (lines "Order,Line,SKU,Qty"
                                       ""
                                       "1003,7,A-100,x")
                                'stockfile::webshop-order-line)))
    (is (eql 3 (record-error-line condition)))
    (is (string= "x" (record-error-text condition)))))

(test field-named-line-collects-the-file-line
  (multiple-value-bind (records errors)
      (parse-text *orders* 'stockfile::webshop-order-line :on-error :collect)
    (is (equal '(1 2) (mapcar #'stockfile::webshop-order-line-line records)))
    (is (equal '(4) (mapcar #'record-error-line errors)))))

(test field-named-cells
  (let ((packs (parse-text (lines "Model,Cells,Capacity" "PX-1,4,2200" "PX-2,8,4400")
                           'stockfile::battery-pack)))
    (is (equal '(4 8) (mapcar #'stockfile::battery-pack-cells packs)))
    (is (equal '(2200 4400) (mapcar #'stockfile::battery-pack-capacity packs))))
  (let ((condition (first-error (lines "Model,Cells,Capacity" "PX-1,0,2200")
                                'stockfile::battery-pack)))
    (is (typep condition 'record-error))
    (is (eql 2 (record-error-line condition)))
    (is (string= "Cells" (record-error-column condition)))))

(test field-named-text
  (let ((notes (parse-text (lines "Text,Summary" "fragile," "heavy,two people")
                           'stockfile::bin-note)))
    (is (equal '("fragile" "two people")
               (mapcar #'stockfile::bin-note-summary notes)))))
