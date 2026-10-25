(in-package #:depot)

;;; A lock records the release chosen for each package a project needs,
;;; and for each the requirements on it: who requires it, with what
;;; constraint. Its file is
;;;
;;;   (:lock "webshop"
;;;    :packages (("html-escape" "2.4.1"
;;;                :required-by (("^2.1.0" "template 1.3.0")
;;;                              ("^2.3.0" "markup 1.1.0")))
;;;               ("template" "1.3.0" :required-by (("^1.2.0" :project)))
;;;               ...))
;;;
;;; The requirements are kept as text, so that a lock read back can be
;;; checked against them without the registry: VERIFY-LOCK.

(define-condition inconsistent-lock (depot-error)
  ((package :initarg :package :reader inconsistent-lock-package)
   (message :initarg :message :reader inconsistent-lock-message))
  (:report (lambda (condition stream)
             (format stream "The lock is inconsistent at ~A: ~A"
                     (inconsistent-lock-package condition)
                     (inconsistent-lock-message condition))))
  (:documentation "A lock whose versions do not satisfy the requirements
it records, or that misses a package one of its releases needs."))

(defstruct (lock-entry (:constructor make-lock-entry (package version required-by))
                       (:conc-name entry-))
  "The release VERSION chosen for PACKAGE. REQUIRED-BY is a list of
(CONSTRAINT-TEXT . SOURCE), SOURCE a release name as \"template 1.3.0\"
or :PROJECT."
  (package "" :type string :read-only t)
  (version nil :type version :read-only t)
  (required-by '() :type list :read-only t))

(defmethod print-object ((entry lock-entry) stream)
  (print-unreadable-object (entry stream :type t)
    (format stream "~A ~A" (entry-package entry) (entry-version entry))))

(defclass lock ()
  ((project-name :initarg :project-name :reader lock-project-name)
   (entries :initarg :entries :reader lock-entries
            :documentation "The entries, sorted by package name."))
  (:documentation "The releases chosen for a project."))

(defmethod print-object ((lock lock) stream)
  (print-unreadable-object (lock stream :type t)
    (format stream "~A, ~D package~:P" (lock-project-name lock) (length (lock-entries lock)))))

(defun find-entry (lock package)
  "Returns the entry of PACKAGE in LOCK, or NIL."
  (find package (lock-entries lock) :key #'entry-package :test #'string=))

(defun lock-version (lock package)
  "Returns the version locked for PACKAGE, as a text, or NIL when LOCK
does not have it."
  (alexandria:when-let ((entry (find-entry lock package)))
    (version-string (entry-version entry))))

(defun project-requirements (project)
  "Returns the requirements of PROJECT, its dependencies and then its
development dependencies."
  (mapcar (lambda (dependency)
            (make-requirement (car dependency) (cdr dependency)))
          (append (project-dependencies project) (project-dev-dependencies project))))

(defun make-lock (project releases)
  "Returns the lock of PROJECT with RELEASES chosen, recording for each
package the requirements of the project and of RELEASES on it."
  (let ((required-by (make-hash-table :test 'equal)))
    (dolist (requirement (project-requirements project))
      (push (cons (constraint-text (requirement-constraint requirement)) :project)
            (gethash (requirement-package requirement) required-by)))
    (dolist (release releases)
      (dolist (dependency (release-dependencies release))
        (when (eq (dependency-kind dependency) :runtime)
          (push (cons (constraint-text (dependency-constraint dependency))
                      (release-name release))
                (gethash (dependency-package dependency) required-by)))))
    (make-instance 'lock
                   :project-name (project-name project)
                   :entries (mapcar (lambda (release)
                                      (make-lock-entry (release-package release)
                                                       (release-version release)
                                                       (reverse (gethash (release-package release)
                                                                         required-by))))
                                    (sort (copy-list releases) #'string<
                                          :key #'release-package)))))

(defun verify-lock (lock)
  "Checks that each version in LOCK satisfies every requirement the lock
records on it, and that each package required is in the lock. Returns
LOCK, or signals INCONSISTENT-LOCK."
  (dolist (entry (lock-entries lock) lock)
    (loop for (text . source) in (entry-required-by entry)
          unless (satisfies-p (entry-version entry) (parse-constraint text))
            do (error 'inconsistent-lock
                      :package (entry-package entry)
                      :message (format nil "~A ~A does not satisfy ~A, which ~A requires."
                                       (entry-package entry)
                                       (version-string (entry-version entry))
                                       text
                                       (if (eq source :project) "the project" source)))))
  (let ((names (mapcar (lambda (entry)
                         (format nil "~A ~A" (entry-package entry)
                                 (version-string (entry-version entry))))
                       (lock-entries lock))))
    (dolist (entry (lock-entries lock) lock)
      (loop for (nil . source) in (entry-required-by entry)
            unless (or (eq source :project) (member source names :test #'string=))
              do (error 'inconsistent-lock
                        :package (entry-package entry)
                        :message (format nil "~A requires it, but is not in the lock."
                                         source))))))

;;; Lock files

(defun write-lock (lock stream)
  "Writes LOCK to STREAM in the form READ-LOCK reads."
  (with-standard-io-syntax
    (let ((*print-readably* nil)
          (*print-right-margin* 100))
      (format stream "(:lock ~S~% :packages~% (" (lock-project-name lock))
      (loop for (entry . more) on (lock-entries lock)
            do (format stream "(~S ~S~%   :required-by ~S)"
                       (entry-package entry)
                       (version-string (entry-version entry))
                       (mapcar (lambda (requirement)
                                 (list (car requirement) (cdr requirement)))
                               (entry-required-by entry)))
               (when more
                 (format stream "~%  ")))
      (format stream "))~%")))
  lock)

(defun read-lock (stream)
  "Returns the lock READ-LOCK wrote to STREAM."
  (let ((form (with-standard-io-syntax
                (let ((*read-eval* nil)
                      (*package* (find-package '#:depot)))
                  (read stream)))))
    (unless (and (consp form) (eq (first form) :lock) (stringp (second form)))
      (error 'depot-error-with-message :message "This is not a lock file."))
    (destructuring-bind (name &key packages) (rest form)
      (make-instance 'lock
                     :project-name name
                     :entries (mapcar (lambda (entry)
                                        (destructuring-bind (package version &key required-by) entry
                                          (make-lock-entry package (parse-version version)
                                                           (mapcar (lambda (requirement)
                                                                     (cons (first requirement)
                                                                           (second requirement)))
                                                                   required-by))))
                                      packages)))))
