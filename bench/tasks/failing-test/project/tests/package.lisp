;;;; tests/package.lisp

(defpackage #:billing-tests
  (:use #:common-lisp #:billing #:fiveam)
  (:export #:billing))

(in-package #:billing-tests)

(def-suite billing
  :description "All tests of the billing system.")
