(in-package #:depot)

;;; Answers to "why is this package in the lock?" and the tree of what
;;; requires what, from a lock alone.

(defun entry-name (entry)
  "Returns ENTRY as the release name \"package version\"."
  (format nil "~A ~A" (entry-package entry) (version-string (entry-version entry))))

(defun entry-by-name (lock name)
  "Returns the entry of LOCK whose release name is NAME, or NIL."
  (find name (lock-entries lock) :key #'entry-name :test #'string=))

(defun why (lock package)
  "Returns the chains of requirements that bring PACKAGE into LOCK: each
a list from the project's own requirement to PACKAGE, of the release
names and constraints on the way, as

  (\"webshop\" \"template ^1.2.0\" \"template 1.3.0\" \"html-escape ^2.1.0\"
   \"html-escape 2.4.1\")

The chains are the shortest first. A package LOCK does not have has
none."
  (let ((chains '()))
    (labels ((walk (entry path)
               (dolist (requirement (entry-required-by entry))
                 (destructuring-bind (text . source) requirement
                   (let ((step (list (format nil "~A ~A" (entry-package entry) text)
                                     (entry-name entry))))
                     (if (eq source :project)
                         (push (append (list (lock-project-name lock)) step path) chains)
                         (let ((requirer (entry-by-name lock source)))
                           ;; A cycle in the lock would never end.
                           (when (and requirer
                                      (not (member (entry-name requirer) path :test #'string=)))
                             (walk requirer (append step path))))))))))
      (alexandria:when-let ((entry (find-entry lock package)))
        (walk entry '())))
    (stable-sort (nreverse chains) #'< :key #'length)))

(defun print-dependency-tree (lock &optional (stream *standard-output*))
  "Prints the releases of LOCK as the tree of what requires what, from
the project's own requirements down. A release whose dependencies were
printed already is marked (*), and they are not printed again."
  (let ((printed (make-hash-table :test 'equal))
        (dependents (make-hash-table :test 'equal)))
    ;; Each entry under the entries that require it.
    (dolist (entry (lock-entries lock))
      (loop for (nil . source) in (entry-required-by entry)
            do (pushnew entry (gethash source dependents) :test #'eq)))
    (labels ((print-entry (entry depth)
               (let* ((name (entry-name entry))
                      (seen (gethash name printed)))
                 (format stream "~&~vT~A~:[~; (*)~]~%" (* 2 depth) name seen)
                 (unless seen
                   (setf (gethash name printed) t)
                   (dolist (child (sort (copy-list (gethash name dependents)) #'string<
                                        :key #'entry-package))
                     (print-entry child (1+ depth)))))))
      (format stream "~&~A~%" (lock-project-name lock))
      (dolist (entry (sort (copy-list (gethash :project dependents)) #'string<
                           :key #'entry-package))
        (print-entry entry 1))))
  (values))
