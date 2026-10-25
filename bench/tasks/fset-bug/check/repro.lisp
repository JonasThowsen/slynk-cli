;;;; The reported case: dotted pairs that differ only in a cdr FSet has
;;;; no order for (instances of a class without a COMPARE method, or 3
;;;; and 3.0) must stay distinct in sets and maps, and ordinary pairs
;;;; must keep their order.

(in-package :cl-user)

(defclass repro-node ()
  ((name :initarg :name :reader repro-node-name)))

(defun reproduction-failures ()
  (let* ((failures '())
         (app (make-instance 'repro-node :name "app"))
         (db (make-instance 'repro-node :name "db"))
         (cache (make-instance 'repro-node :name "cache"))
         (edges (list (cons app db) (cons app cache) (cons db cache))))
    (flet ((expect (description got expected)
             (unless (equal got expected)
               (push (format nil "~A: got ~S, expected ~S" description got expected)
                     failures))))
      (let ((graph (reduce #'fset:with edges :initial-value (fset:empty-set))))
        (expect "size of a set of three edges" (fset:size graph) 3)
        (dolist (edge edges)
          (expect (format nil "the set contains the edge ~A -> ~A"
                          (repro-node-name (car edge)) (repro-node-name (cdr edge)))
                  (and (fset:contains? graph edge) t) t)))
      (let ((weights (fset:with (fset:empty-map) (cons app db) 1)))
        (expect "lookup of (app . cache) in a map that has only (app . db)"
                (subseq (multiple-value-list (fset:lookup weights (cons app cache))) 0 2)
                '(nil nil))
        (let ((both (fset:with weights (cons app cache) 2)))
          (expect "size of a map with two edges" (fset:size both) 2)
          (expect "lookup of (app . db)" (fset:lookup both (cons app db)) 1)
          (expect "lookup of (app . cache)" (fset:lookup both (cons app cache)) 2)))
      (expect "(compare (app . db) (app . cache))" (fset:compare (cons app db) (cons app cache)) :unequal)
      (expect "(compare (app . cache) (app . db))" (fset:compare (cons app cache) (cons app db)) :unequal)
      (expect "(compare (1 2 . app) (1 2 . db))" (fset:compare (list* 1 2 app) (list* 1 2 db)) :unequal)
      (expect "(compare '(a . 3) '(a . 3.0))" (fset:compare '(a . 3) '(a . 3.0)) :unequal)
      (expect "size of (set '(a . 3) '(a . 3.0))" (fset:size (fset:set '(a . 3) '(a . 3.0))) 2)
      (expect "(compare (app . db) (app . db))" (fset:compare (cons app db) (cons app db)) :equal)
      (expect "(compare '(1 . 2) '(1 . 3))" (fset:compare '(1 . 2) '(1 . 3)) :less)
      (expect "(compare '(1 . 3) '(1 . 2))" (fset:compare '(1 . 3) '(1 . 2)) :greater)
      (expect "(compare '(1 . 2) '(1 . 2))" (fset:compare '(1 . 2) (cons 1 2)) :equal)
      (expect "(compare (list :dep app) (list :dep db))" (fset:compare (list :dep app) (list :dep db)) :unequal))
    (nreverse failures)))
