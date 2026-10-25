;;;; Loads the FSet in CHECK_DIR, then runs the reproduction and FSet's
;;;; own tests from their copies in CHECK_WORK. Exits 0 when both pass.

(require :asdf)

(defvar *dir* (uiop:getenv "CHECK_DIR"))
(defvar *work* (uiop:getenv "CHECK_WORK"))

(setf *print-right-margin* 200)

(defun fail (control &rest arguments)
  (format t "~&FAIL: ~?~%" control arguments)
  (finish-output)
  (uiop:quit 1))

(asdf:initialize-source-registry
 `(:source-registry (:tree ,*dir*) :inherit-configuration))
(asdf:initialize-output-translations
 `(:output-translations (,*dir* ,(concatenate 'string *work* "fasl/"))
                        :inherit-configuration))

(defun quietly-load-system (name)
  (handler-case
      (let ((*standard-output* (make-broadcast-stream))
            (*error-output* (make-broadcast-stream)))
        (asdf:load-system name))
    (error (e) (fail "~A does not load: ~A" name e))))

(quietly-load-system :fset)
(unless (uiop:subpathp (asdf:system-source-directory :fset)
                        (uiop:parse-native-namestring *dir*))
  (fail "FSet was loaded from ~A, not from the project"
        (asdf:system-source-directory :fset)))

;;; The reproduction from the report, and close relatives of it.
(load (concatenate 'string *work* "repro.lisp"))
(let ((failures (funcall (find-symbol "REPRODUCTION-FAILURES" :cl-user))))
  (when failures
    (fail "the reported case still goes wrong:~{~%  ~A~}" failures)))

;;; FSet's own tests, from the pristine copy. They are in Code/testing.lisp,
;;; which the FSet system loads too; loading the pristine file replaces
;;; whatever the project's copy defined. A test that fails signals an
;;; error. They run as FSet's own test-op runs them, with 200 iterations
;;; of the random tests. One test interns symbols at run time and expects
;;; them in the FSet package (upstream.patch, in the project, makes it say
;;; so), so the tests run in it.
(let* ((log (make-string-output-stream))
       (failure
         (handler-case
             (let ((*standard-output* log)
                   (*error-output* log)
                   (*package* (find-package :fset)))
               (load (concatenate 'string *work* "testing.lisp"))
               (funcall (find-symbol "RUN-TEST-SUITE" :fset) 200)
               nil)
           (error (e) e))))
  (when failure
    (fail "FSet's test suite fails: ~A" failure)))

(format t "~&PASS: the reported case works and FSet's test suite passes~%")
(uiop:quit 0)
