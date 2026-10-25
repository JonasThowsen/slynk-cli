;;;; Loads the tally in CHECK_DIR, then runs the reproduction and the
;;;; project's tests from their copies in CHECK_WORK. Exits 0 when both
;;;; pass.

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

(quietly-load-system :tally)
(unless (uiop:subpathp (asdf:system-source-directory :tally)
                       (uiop:parse-native-namestring *dir*))
  (fail "tally was loaded from ~A, not from the project"
        (asdf:system-source-directory :tally)))
(quietly-load-system :fiveam)

;;; The project's tests, from the hidden copy.
(let* ((log (make-string-output-stream))
       (results (handler-case
                    (let ((*standard-output* log)
                          (*error-output* log))
                      (load (concatenate 'string *work* "tests.lisp"))
                      (fiveam:run :tally))
                  (error (e) (fail "the project's tests signalled an error: ~A" e)))))
  (unless (fiveam:results-status results)
    (fail "the project's tests fail:~{~%  ~A~}"
          (mapcar (lambda (result)
                    (fiveam::name (fiveam::test-case result)))
                  (remove-if-not (lambda (result)
                                   (typep result 'fiveam::test-failure))
                                 results)))))

;;; The reproduction from the report, and related query sequences.
(load (concatenate 'string *work* "repro.lisp"))
(let ((failures (handler-case (funcall (find-symbol "REPRODUCTION-FAILURES" :cl-user))
                  (error (e) (fail "the reproduction signalled an error: ~A" e)))))
  (when failures
    (fail "queries still go wrong:~{~%  ~A~}" failures)))

(format t "~&PASS: the reported sequence and related ones give the right answers, and the tests pass~%")
(uiop:quit 0)
