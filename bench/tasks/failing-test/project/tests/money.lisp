;;;; tests/money.lisp

(in-package #:billing-tests)

(def-suite money :in billing)
(in-suite money)

(test parse-amount-forms
  (is (= 123450 (parse-amount "1234.50")))
  (is (= 123450 (parse-amount "1234.5")))
  (is (= 30000 (parse-amount "300")))
  (is (= 5 (parse-amount "0.05")))
  (is (= -1250 (parse-amount "-12.50")))
  (is (= 999 (parse-amount " 9.99 "))))

(test parse-amount-rejects-garbage
  (signals error (parse-amount ""))
  (signals error (parse-amount "12,50"))
  (signals error (parse-amount "1.234"))
  (signals error (parse-amount "kr 10")))

(test format-amount-pads-ore
  (is (string= "1234.50" (format-amount 123450)))
  (is (string= "0.05" (format-amount 5)))
  (is (string= "300.00" (format-amount 30000))))

(test format-amount-negative
  (is (string= "-12.50" (format-amount -1250)))
  (is (string= "-0.01" (format-amount -1))))

(test round-half-away
  (is (= 3 (round-half-away 5/2)))
  (is (= -3 (round-half-away -5/2)))
  (is (= 2 (round-half-away 9/4)))
  (is (= -2 (round-half-away -9/4)))
  (is (= 0 (round-half-away 0))))

(test percent-of-rounds-half-away
  (is (= 25 (percent-of 100 25)))
  (is (= 1 (percent-of 2 25)))           ; 0.5 øre rounds up
  (is (= 2903 (percent-of 38700 15/2)))  ; 2902.5
  (is (= -2903 (percent-of -38700 15/2))))

(test allocate-adds-up
  (is (equal '(334 333 333) (allocate 1000 '(1 1 1))))
  (is (= 1999 (reduce #'+ (allocate 1999 '(7 3 11 5))))))

(test allocate-gives-left-over-to-largest
  (is (equal '(286 572 142) (allocate 1000 '(1 2 1/2))))
  (is (equal '(1 0) (allocate 1 '(1 1)))))

(test allocate-proportions
  (is (equal '(2500 7500) (allocate 10000 '(1 3))))
  (is (equal '(0 100) (allocate 100 '(0 5)))))
