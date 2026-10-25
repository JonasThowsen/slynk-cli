;;;; billing.asd

(defsystem "billing"
  :description "Invoices with Norwegian VAT, customer groups and discounts."
  :version "0.4.0"
  :license "MIT"
  :depends-on ("alexandria")
  :pathname "src/"
  :serial t
  :components ((:file "package")
               (:file "money")
               (:file "dates")
               (:file "tax")
               (:file "catalog")
               (:file "customers")
               (:file "invoice")
               (:file "render"))
  :in-order-to ((test-op (test-op "billing/tests"))))

(defsystem "billing/tests"
  :description "Tests for billing."
  :depends-on ("billing" "fiveam")
  :pathname "tests/"
  :serial t
  :components ((:file "package")
               (:file "money")
               (:file "dates")
               (:file "invoice"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :billing :billing-tests))))
