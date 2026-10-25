;;;; Loads the chipz in CHECK_DIR, then runs the reproduction and chipz's
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

(quietly-load-system :chipz)
(unless (uiop:subpathp (asdf:system-source-directory :chipz)
                        (uiop:parse-native-namestring *dir*))
  (fail "chipz was loaded from ~A, not from the project"
        (asdf:system-source-directory :chipz)))
(quietly-load-system :salza2)

;;; The reproduction from the report, and close relatives of it.
(load (concatenate 'string *work* "repro.lisp"))
(let ((failures (funcall (find-symbol "REPRODUCTION-FAILURES" :cl-user))))
  (when failures
    (fail "the reported case still goes wrong:~{~%  ~A~}" failures)))

;;; chipz's own tests, from the pristine tests.lisp: compress the test
;;; files with salza2 and bzip2, then decompress them every way it knows.
;;; A test that signals an error counts as failed.
(let* ((log (make-string-output-stream))
       (files (pathname (concatenate 'string *work* "test-files/")))
       (passed
         (handler-case
             (let ((*standard-output* log)
                   (*error-output* log))
               (load (concatenate 'string *work* "tests.lisp"))
               (funcall (find-symbol "COMPRESS-TEST-FILES" :chipz-tests) files)
               (handler-bind ((error (lambda (e)
                                       (format t "~&; ERROR ~A~%" e)
                                       (let ((skip (find-restart (find-symbol "SKIP-TEST" :chipz-tests))))
                                         (when skip (invoke-restart skip))))))
                 (funcall (find-symbol "RUN-ALL-TESTS" :chipz-tests) files)))
           (error (e) (fail "chipz's tests signalled an error: ~A" e)))))
  (unless passed
    (let* ((lines (uiop:split-string (get-output-stream-string log)
                                     :separator '(#\Newline)))
           (failed (loop for (test result) on lines
                         when (and result (or (search "FAILED" result)
                                              (search "ERROR" result)))
                           collect (format nil "~A: ~A" test result))))
      (fail "chipz's test suite fails:~{~%  ~A~}"
            (subseq failed 0 (min 10 (length failed)))))))

(format t "~&PASS: the reported case works and chipz's test suite passes~%")
(uiop:quit 0)
