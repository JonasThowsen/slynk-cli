(defsystem "stockfile"
  :description "Reads the stock counts and price lists the warehouse exports as delimited text files."
  :version "0.3.0"
  :license "MIT"
  :depends-on ("alexandria")
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "csv")
                             (:file "cells")
                             (:file "format")
                             (:file "import")
                             (:file "formats"))))
  :in-order-to ((test-op (test-op "stockfile/tests"))))

(defsystem "stockfile/tests"
  :description "Tests of stockfile."
  :depends-on ("stockfile" "fiveam")
  :components ((:module "tests"
                :components ((:file "tests"))))
  :perform (test-op (operation component)
             (uiop:symbol-call '#:fiveam '#:run! :stockfile)))
