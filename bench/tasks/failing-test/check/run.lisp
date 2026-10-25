;;;; Loads the billing system in CHECK_DIR, then the test suite from its
;;;; copy in CHECK_WORK, and runs it. Exits 0 when every test passes.

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

(quietly-load-system :billing)
(unless (uiop:subpathp (asdf:system-source-directory :billing)
                       (uiop:parse-native-namestring *dir*))
  (fail "billing was loaded from ~A, not from the project"
        (asdf:system-source-directory :billing)))
(quietly-load-system :fiveam)

;;; The test suite, from the pristine copy.
(handler-case
    (let ((*standard-output* (make-broadcast-stream))
          (*error-output* (make-broadcast-stream)))
      (dolist (file '("package" "money" "dates" "invoice"))
        (load (concatenate 'string *work* "tests/" file ".lisp"))))
  (error (e) (fail "the tests do not load: ~A" e)))

(let ((results (let ((fiveam:*test-dribble* (make-broadcast-stream))
                     (*standard-output* (make-broadcast-stream)))
                 (fiveam:run (find-symbol "BILLING" :billing-tests)))))
  (multiple-value-bind (passed failures) (fiveam:results-status results)
    (unless passed
      (fail "~D failed check~:P in ~{~A~^, ~}"
            (length failures)
            (remove-duplicates
             (mapcar (lambda (failure)
                       (fiveam::name (fiveam::test-case failure)))
                     failures)
             :from-end t)))
    (format t "~&PASS: all ~D checks of the test suite pass~%" (length results))))
(uiop:quit 0)
