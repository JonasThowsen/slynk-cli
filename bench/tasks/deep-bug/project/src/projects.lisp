(in-package #:depot)

;;; A project is what depot locks: a name, a version, and the packages it
;;; depends on. Its file, depot.sexp or any other, is
;;;
;;;   (:project "webshop"
;;;    :version "0.9.0"
;;;    :dependencies (("http-server" "^3.0.0") ...)
;;;    :dev-dependencies (("test-harness" "^1.0.0") ...))
;;;
;;; The development dependencies are locked with the others: the lock is
;;; for working on the project as well as for running it.

(define-condition depot-error-with-message (depot-error)
  ((message :initarg :message :reader depot-error-message))
  (:report (lambda (condition stream)
             (write-string (depot-error-message condition) stream)))
  (:documentation "A depot error that is only its message."))

(defclass project ()
  ((name :initarg :name :reader project-name)
   (version :initarg :version :initform nil :reader project-version)
   (dependencies :initarg :dependencies :initform '() :reader project-dependencies
                 :documentation "A list of (PACKAGE . CONSTRAINT).")
   (dev-dependencies :initarg :dev-dependencies :initform '()
                     :reader project-dev-dependencies
                     :documentation "A list of (PACKAGE . CONSTRAINT)."))
  (:documentation "A project to resolve and lock."))

(defmethod print-object ((project project) stream)
  (print-unreadable-object (project stream :type t)
    (format stream "~A~@[ ~A~]" (project-name project) (project-version project))))

(defun parse-dependency-list (list what)
  "Returns the dependency list LIST of a project, ((PACKAGE TEXT) ...),
as a list of (PACKAGE . CONSTRAINT). WHAT names the list for errors."
  (mapcar (lambda (entry)
            (unless (and (consp entry) (stringp (first entry))
                         (consp (rest entry)) (stringp (second entry))
                         (null (cddr entry)))
              (error 'depot-error-with-message
                     :message (format nil "~S in the ~A is not (PACKAGE CONSTRAINT)" entry what)))
            (cons (first entry) (parse-constraint (second entry))))
          list))

(defun make-project (name &key version dependencies dev-dependencies)
  "Returns the project NAME. DEPENDENCIES and DEV-DEPENDENCIES are lists
of (PACKAGE CONSTRAINT-TEXT)."
  (let ((packages (mapcar #'first (append dependencies dev-dependencies))))
    (alexandria:when-let ((twice (find-if (lambda (package)
                                            (> (count package packages :test #'string=) 1))
                                          packages)))
      (error 'depot-error-with-message
             :message (format nil "The project ~A depends on ~A twice." name twice))))
  (make-instance 'project
                 :name name
                 :version (and version (ensure-version version))
                 :dependencies (parse-dependency-list dependencies "dependencies")
                 :dev-dependencies (parse-dependency-list dev-dependencies
                                                          "development dependencies")))

(defun read-project (pathname)
  "Returns the project in the file PATHNAME."
  (let ((form (with-open-file (stream pathname :external-format :utf-8)
                (with-standard-io-syntax
                  (let ((*read-eval* nil)
                        (*package* (find-package '#:depot)))
                    (read stream))))))
    (unless (and (consp form) (eq (first form) :project) (stringp (second form)))
      (error 'depot-error-with-message
             :message (format nil "~A is not a (:project NAME ...) form." pathname)))
    (destructuring-bind (name &key version dependencies dev-dependencies) (rest form)
      (make-project name :version version
                         :dependencies dependencies
                         :dev-dependencies dev-dependencies))))
