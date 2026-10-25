(defpackage #:stockfile/tests
  (:use #:common-lisp #:stockfile #:fiveam))

(in-package #:stockfile/tests)

(def-suite :stockfile :description "Tests of stockfile.")
(in-suite :stockfile)

(defun lines (&rest lines)
  "LINES as the text of a file, each ended by a newline."
  (format nil "~{~A~%~}" lines))

(defun parse-text (text format-name &rest options)
  "PARSE-RECORDS of the string TEXT."
  (with-input-from-string (stream text)
    (apply #'parse-records stream format-name options)))

(defun first-error (text format-name)
  "The RECORD-ERROR that parsing TEXT signals first, or NIL."
  (handler-case (progn (parse-text text format-name) nil)
    (record-error (condition) condition)))

;;; Lines and cells

(test split-plain-line
  (is (equal '("a" "b" "" "d") (split-csv-line "a,b,,d")))
  (is (equal '("a" "b") (split-csv-line "a;b" :delimiter #\;)))
  (is (equal '("") (split-csv-line ""))))

(test split-quoted-cells
  (is (equal '("Bolt, M8" "12") (split-csv-line "\"Bolt, M8\",12")))
  (is (equal '("say \"hi\"" "x") (split-csv-line "\"say \"\"hi\"\"\",x"))))

(test convert-integers-and-strings
  (is (= 42 (convert-cell :integer " 42 ")))
  (is (= -3 (convert-cell :integer "-3")))
  (is (string= "Shelf 4" (convert-cell :string "  Shelf 4 ")))
  (signals invalid-cell (convert-cell :integer "4x")))

(test convert-decimals
  (is (= 25/2 (convert-cell :decimal "12.50")))
  (is (= 25/2 (convert-cell :decimal "12,5")))
  (is (= -7 (convert-cell :decimal "-7")))
  (signals invalid-cell (convert-cell :decimal "12."))
  (signals invalid-cell (convert-cell :decimal "-"))
  (signals invalid-cell (convert-cell :decimal "1.2.3")))

(test convert-dates
  (is (= (encode-universal-time 0 0 0 29 2 2024 0)
         (convert-cell :date "2024-02-29")))
  (signals invalid-cell (convert-cell :date "2023-02-29"))
  (signals invalid-cell (convert-cell :date "2024-13-01"))
  (signals invalid-cell (convert-cell :date "24-01-01")))

(test convert-booleans
  (is (eq t (convert-cell :boolean "Yes")))
  (is (eq nil (convert-cell :boolean "0")))
  (signals invalid-cell (convert-cell :boolean "maybe")))

(test blank-cells
  (is (blank-cell-p ""))
  (is (blank-cell-p "   "))
  (is (not (blank-cell-p " x "))))

;;; Formats

(test stock-count-format
  (let ((format (find-record-format 'stock-count)))
    (is (eq 'stock-count (record-format-name format)))
    (is (char= #\; (record-format-delimiter format)))
    (is (equal '("SKU" "Location" "Counted" "Date")
               (mapcar #'column-header (record-format-columns format))))
    (is (equal '(t nil t nil)
               (mapcar #'column-required (record-format-columns format))))))

(test parse-stock-count
  (let ((counts (parse-text (lines "SKU;Location;Counted;Date"
                                   "A-100;MAIN;12;2024-03-01"
                                   "B-200;;3;"
                                   "C-300;BACK;0;2024-03-02")
                            'stock-count)))
    (is (= 3 (length counts)))
    (is (equal '("A-100" "B-200" "C-300") (mapcar #'stock-count-sku counts)))
    (is (equal '("MAIN" "MAIN" "BACK") (mapcar #'stock-count-location counts)))
    (is (equal '(12 3 0) (mapcar #'stock-count-quantity counts)))
    (is (null (stock-count-counted-on (second counts))))
    (is (= (encode-universal-time 0 0 0 1 3 2024 0)
           (stock-count-counted-on (first counts))))))

(test columns-in-any-order
  (let ((counts (parse-text (lines "counted;sku" "5;A-100") 'stock-count)))
    (is (equal '("A-100") (mapcar #'stock-count-sku counts)))
    (is (equal '(5) (mapcar #'stock-count-quantity counts)))
    (is (equal '("MAIN") (mapcar #'stock-count-location counts)))))

(test quoted-cells-and-windows-line-endings
  (let ((prices (parse-text (format nil "Article,Description,Price~C~%~
                                         A-100,\"Bolt, M8\",\"1,25\"~C~%"
                                    #\Return #\Return)
                            'price-list)))
    (is (equal '("Bolt, M8") (mapcar #'price-list-description prices)))
    (is (equal '(5/4) (mapcar #'price-list-unit-price prices)))))

(test missing-required-column
  (let ((condition (first-error (lines "SKU;Location" "A-100;MAIN") 'stock-count)))
    (is (typep condition 'record-error))
    (is (= 1 (record-error-line condition)))
    (is (string= "Counted" (record-error-column condition)))))

(test error-points-at-the-line
  (let ((condition (first-error (lines "SKU;Counted"
                                       "A-100;4"
                                       ""
                                       "B-200;four")
                                'stock-count)))
    (is (typep condition 'record-error))
    (is (= 4 (record-error-line condition)))
    (is (string= "QUANTITY" (record-error-field condition)))
    (is (string= "four" (record-error-text condition)))))

(test empty-required-cell
  (let ((condition (first-error (lines "SKU;Counted" ";4") 'stock-count)))
    (is (= 2 (record-error-line condition)))
    (is (string= "SKU" (record-error-column condition)))))

(test failed-check
  (let ((condition (first-error (lines "SKU;Counted" "A-100;-1") 'stock-count)))
    (is (= 2 (record-error-line condition)))
    (is (string= "Counted" (record-error-column condition)))
    (is (search "MINUSP" (record-error-message condition)))))

(test collect-errors
  (multiple-value-bind (counts errors)
      (parse-text (lines "SKU;Counted" "A-100;1" "B-200;x" "C-300;2" ";3")
                  'stock-count :on-error :collect)
    (is (equal '("A-100" "C-300") (mapcar #'stock-count-sku counts)))
    (is (equal '(3 5) (mapcar #'record-error-line errors)))))

(test continue-skips-the-line
  (let ((counts (handler-bind ((record-error #'continue))
                  (parse-text (lines "SKU;Counted" "A-100;1" "B-200;x" "C-300;2")
                              'stock-count))))
    (is (equal '("A-100" "C-300") (mapcar #'stock-count-sku counts)))))

;;; Defining formats

(define-record-format shelf-label ()
  "A label to print for a shelf."
  (aisle "Aisle" :type :integer)
  (shelf "Shelf" :type :integer :check (> shelf 0))
  (code "Code" :default (format nil "~D-~D" aisle shelf)))

(test defaults-and-checks-see-earlier-fields
  (let ((labels (parse-text (lines "Aisle,Shelf,Code" "3,7," "4,1,X") 'shelf-label)))
    (is (equal '("3-7" "X") (mapcar #'shelf-label-code labels))))
  (let ((condition (first-error (lines "Aisle,Shelf" "3,0") 'shelf-label)))
    (is (string= "Shelf" (record-error-column condition)))))

(test format-defines-a-structure
  (let ((label (make-shelf-label :aisle 1 :shelf 2 :code "1-2")))
    (is (typep label 'shelf-label))
    (is (= 2 (shelf-label-shelf label)))
    (is (string= "A label to print for a shelf."
                 (documentation 'shelf-label 'structure)))))

;;; The warehouse's reports

(defparameter *counts*
  (lines "SKU;Location;Counted"
         "A-100;MAIN;10"
         "A-100;BACK;2"
         "B-200;MAIN;3"
         "C-300;MAIN;1"))

(defparameter *prices*
  (lines "Article,Price,Active"
         "A-100,1.50,yes"
         "B-200,10,no"
         "C-300,\"0,25\","))

(test stock-totals-per-sku
  (is (equal '(("A-100" . 12) ("B-200" . 3) ("C-300" . 1))
             (stock-totals (parse-text *counts* 'stock-count)))))

(test stock-value-of-priced-skus
  (multiple-value-bind (value unpriced)
      (stock-value (parse-text *counts* 'stock-count)
                   (parse-text *prices* 'price-list))
    (is (= 73/4 value))
    (is (equal '("B-200") unpriced))))
