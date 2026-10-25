(in-package #:depot.registry)

;;; The registry is what depot resolves against: the packages there are,
;;; each with its releases, and each release with its dependencies. A
;;; registry on disk is a directory with a file per package (see
;;; LOAD-REGISTRY); tests make one in memory with ADD-RELEASE.
;;;
;;; The registry is large and a resolution looks at a small part of it,
;;; so a release keeps its dependencies as the texts the file gives until
;;; RELEASE-DEPENDENCIES first asks for them.

(define-condition registry-error (depot-error)
  ((file :initarg :file :initform nil :reader registry-error-file)
   (message :initarg :message :reader registry-error-message))
  (:report (lambda (condition stream)
             (format stream "~@[~A: ~]~A"
                     (registry-error-file condition)
                     (registry-error-message condition))))
  (:documentation "A package file of the registry, or an entry in one,
that depot cannot read."))

(defun skip-package (&optional condition)
  "Invokes the SKIP-PACKAGE restart: the registry is loaded without the
package file that could not be read."
  (invoke-restart (find-restart 'skip-package condition)))

(defclass registry ()
  ((packages :initform (make-hash-table :test 'equal)
             :reader registry-packages
             :documentation "The releases of each package, by package
name: a list, the newest first.")
   (constraints :initform (make-hash-table :test 'equal)
                :reader registry-constraints
                :documentation "The constraints of the registry's
dependencies, by their text. A registry repeats a few hundred constraint
texts in tens of thousands of dependencies, so each text is parsed once.")
   (source :initarg :source :initform nil :reader registry-source
           :documentation "The directory the registry was loaded from, or NIL."))
  (:documentation "The packages a project can depend on."))

(defmethod print-object ((registry registry) stream)
  (print-unreadable-object (registry stream :type t :identity t)
    (format stream "~D package~:P~@[ from ~A~]"
            (hash-table-count (registry-packages registry))
            (registry-source registry))))

(defun make-registry ()
  "Returns an empty registry."
  (make-instance 'registry))

(defstruct (dependency (:constructor make-dependency (package constraint kind)))
  "A release's dependency on a PACKAGE, with a CONSTRAINT on its version.
KIND is :RUNTIME, or :DEVELOPMENT for what only working on the package
needs, which a project that uses the package does not install."
  (package "" :type string :read-only t)
  (constraint nil :type constraint :read-only t)
  (kind :runtime :type (member :runtime :development) :read-only t))

(defmethod print-object ((dependency dependency) stream)
  (print-unreadable-object (dependency stream :type t)
    (format stream "~A ~A~:[ (development)~;~]"
            (dependency-package dependency)
            (constraint-text (dependency-constraint dependency))
            (eq (dependency-kind dependency) :runtime))))

(defclass release ()
  ((registry :initarg :registry :reader release-registry)
   (package :initarg :package :reader release-package
            :documentation "The name of the package.")
   (version :initarg :version :reader release-version)
   (yanked :initarg :yanked :initform nil :reader release-yanked-p
           :documentation "True when the release was withdrawn: new
resolutions leave it out, while locks that have it keep it.")
   (published :initarg :published :initform nil :reader release-published
              :documentation "The day of the release, as \"2025-03-14\", or NIL.")
   (dependency-specs :initarg :dependency-specs :initform '()
                     :documentation "The dependencies as the registry
gives them, (PACKAGE CONSTRAINT-TEXT &key KIND), until they are parsed.")
   (dependencies :documentation "The parsed dependencies, once
RELEASE-DEPENDENCIES has made them."))
  (:documentation "One version of a package in a registry."))

(defun release-name (release)
  "Returns RELEASE as \"package version\", for messages."
  (format nil "~A ~A" (release-package release) (release-version release)))

(defmethod print-object ((release release) stream)
  (print-unreadable-object (release stream :type t)
    (write-string (release-name release) stream)
    (when (release-yanked-p release)
      (write-string " (yanked)" stream))))

(defun registry-constraint (registry text)
  "Returns the constraint TEXT, parsed once per REGISTRY."
  (alexandria:ensure-gethash text (registry-constraints registry)
                             (parse-constraint text)))

(defun spec-dependency (release spec)
  "Returns the dependency of RELEASE that SPEC, (PACKAGE TEXT &key KIND),
describes."
  (destructuring-bind (package text &key (kind :runtime)) spec
    (make-dependency package
                     (handler-case (registry-constraint (release-registry release) text)
                       (constraint-syntax-error (condition)
                         (error 'registry-error
                                :message (format nil "~A: the dependency on ~A: ~A"
                                                 (release-name release) package condition))))
                     kind)))

(defun release-dependencies (release)
  "Returns the dependencies of RELEASE, parsing them the first time."
  (unless (slot-boundp release 'dependencies)
    (setf (slot-value release 'dependencies)
          (mapcar (lambda (spec) (spec-dependency release spec))
                  (slot-value release 'dependency-specs))))
  (slot-value release 'dependencies))

;;; Looking things up

(defun registry-package-names (registry)
  "Returns the names of the packages in REGISTRY, sorted."
  (sort (alexandria:hash-table-keys (registry-packages registry)) #'string<))

(defun package-known-p (registry name)
  "True when REGISTRY has a package NAME."
  (nth-value 1 (gethash name (registry-packages registry))))

(defun package-releases (registry name)
  "Returns the releases of package NAME in REGISTRY, the newest first, or
NIL when there is no such package."
  (values (gethash name (registry-packages registry))))

(defun find-release (registry name version)
  "Returns the release VERSION of package NAME in REGISTRY, or NIL."
  (let ((version (ensure-version version)))
    (find-if (lambda (release) (version= (release-version release) version))
             (package-releases registry name))))

(defun validate-spec (spec)
  "Signals an error unless SPEC is a dependency spec, (PACKAGE TEXT
&key KIND)."
  (unless (and (consp spec) (stringp (first spec))
               (consp (rest spec)) (stringp (second spec))
               (member (getf (cddr spec) :kind :runtime) '(:runtime :development)))
    (error 'registry-error :message (format nil "~S is not a dependency" spec))))

(defun add-release (registry package version &key dependencies yanked published)
  "Adds the release VERSION of PACKAGE to REGISTRY and returns it.
DEPENDENCIES are lists (PACKAGE CONSTRAINT-TEXT &key KIND). A release
that is there already is an error."
  (let ((version (ensure-version version)))
    (mapc #'validate-spec dependencies)
    (when (find-release registry package version)
      (error 'registry-error
             :message (format nil "~A ~A is in the registry twice" package version)))
    (let ((release (make-instance 'release
                                  :registry registry
                                  :package package
                                  :version version
                                  :yanked yanked
                                  :published published
                                  :dependency-specs (copy-tree dependencies))))
      (setf (gethash package (registry-packages registry))
            (merge 'list (list release) (package-releases registry package)
                   #'version> :key #'release-version))
      release)))

;;; Loading a registry from disk
;;;
;;; Each file NAME.sexp in the directory is one package:
;;;
;;;   (:package "html-escape"
;;;    :description "..."
;;;    :releases ((:version "2.4.1" :published "2025-11-02"
;;;                :dependencies (("text-utils" "^1.0.0")))
;;;               (:version "2.4.0" :yanked t ...)))

(defun read-package-file (pathname)
  "Returns the form in the package file PATHNAME."
  (with-open-file (stream pathname :external-format :utf-8)
    (with-standard-io-syntax
      (let ((*read-eval* nil)
            (*package* (find-package '#:depot.registry)))
        (handler-case (prog1 (read stream)
                        (unless (eq (read stream nil stream) stream)
                          (error 'registry-error :file pathname
                                                 :message "the file has more than one form")))
          (reader-error (condition)
            (error 'registry-error :file pathname
                                   :message (format nil "it does not read: ~A" condition)))
          (end-of-file ()
            (error 'registry-error :file pathname :message "the file is empty or incomplete")))))))

(defun load-package-file (registry pathname)
  "Adds the package in the file PATHNAME and its releases to REGISTRY."
  (let ((form (read-package-file pathname)))
    (unless (and (consp form) (eq (first form) :package) (stringp (second form)))
      (error 'registry-error :file pathname :message "the file is not a (:package NAME ...) form"))
    (destructuring-bind (name &key description releases) (rest form)
      (declare (ignore description))
      (unless (string= name (pathname-name pathname))
        (error 'registry-error :file pathname
                               :message (format nil "the file of package ~A has another name" name)))
      (dolist (entry releases)
        (destructuring-bind (&key version dependencies yanked published) entry
          (unless (stringp version)
            (error 'registry-error :file pathname
                                   :message (format nil "a release of ~A has no version" name)))
          (handler-case
              (add-release registry name version
                           :dependencies dependencies :yanked yanked :published published)
            (version-syntax-error (condition)
              (error 'registry-error :file pathname :message (princ-to-string condition)))
            (registry-error (condition)
              (error 'registry-error :file pathname
                                     :message (registry-error-message condition)))))))))

(defun load-registry (directory)
  "Returns the registry in DIRECTORY, a package file NAME.sexp for each
package. A file that does not read signals a REGISTRY-ERROR, with a
SKIP-PACKAGE restart that leaves the package out."
  (let* ((directory (uiop:ensure-directory-pathname directory))
         (registry (make-instance 'registry :source directory)))
    (unless (uiop:directory-exists-p directory)
      (error 'registry-error :file directory :message "there is no such directory"))
    (dolist (pathname (sort (uiop:directory-files directory "*.sexp")
                            #'string< :key #'namestring))
      (restart-case (load-package-file registry pathname)
        (skip-package ()
          :report (lambda (stream)
                    (format stream "Leave the package ~A out of the registry."
                            (pathname-name pathname)))
          (remhash (pathname-name pathname) (registry-packages registry)))))
    registry))
