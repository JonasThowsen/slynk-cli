(defpackage #:depot/tests
  (:use #:common-lisp #:depot.semver #:depot.registry #:depot #:fiveam))

(in-package #:depot/tests)

(def-suite :depot :description "Tests for depot.")

(defun project-file (name)
  "Returns the pathname of NAME in the depot project's directory. The
check reads the registry and the examples from the task's own copy,
CHECK_DATA, so that the data the agent left does not count."
  (let ((data (uiop:getenv "CHECK_DATA")))
    (if data
        (merge-pathnames name (uiop:ensure-directory-pathname data))
        (asdf:system-relative-pathname "depot" name))))

(defun test-registry (&rest releases)
  "Returns a registry with RELEASES, each (PACKAGE VERSION DEPENDENCY...)
where a dependency is (PACKAGE CONSTRAINT-TEXT &key KIND); a release
whose version is followed by :YANKED is yanked."
  (let ((registry (make-registry)))
    (dolist (release releases registry)
      (destructuring-bind (package version &rest dependencies) release
        (let ((yanked (eq (first dependencies) :yanked)))
          (add-release registry package version
                       :yanked yanked
                       :dependencies (if yanked (rest dependencies) dependencies)))))))

(defun requirements (&rest pairs)
  "Returns requirements of a project from PAIRS, (PACKAGE CONSTRAINT-TEXT)."
  (mapcar (lambda (pair)
            (make-requirement (first pair) (parse-constraint (second pair))))
          pairs))

(defun resolved (registry &rest pairs)
  "Resolves the requirements PAIRS against REGISTRY and returns the
releases chosen as a list of \"package version\"."
  (mapcar #'release-name (resolve registry (apply #'requirements pairs))))
