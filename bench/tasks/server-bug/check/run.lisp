;;;; Loads the spool in CHECK_DIR, then runs the project's tests and the
;;;; reproduction from their copies in CHECK_WORK. Exits 0 when both pass.

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

(quietly-load-system :spool)
(unless (uiop:subpathp (asdf:system-source-directory :spool)
                       (uiop:parse-native-namestring *dir*))
  (fail "spool was loaded from ~A, not from the project"
        (asdf:system-source-directory :spool)))
(quietly-load-system :fiveam)

;;; The project's tests, from the hidden copy.
(handler-case
    (let ((*standard-output* (make-broadcast-stream))
          (*error-output* (make-broadcast-stream)))
      (dolist (file '("package" "tokens" "heap" "server" "protocol"))
        (load (concatenate 'string *work* "tests/" file ".lisp"))))
  (error (e) (fail "the project's tests do not load: ~A" e)))

(let ((results (handler-case
                   (let ((fiveam:*test-dribble* (make-broadcast-stream))
                         (*standard-output* (make-broadcast-stream)))
                     (fiveam:run :spool))
                 (error (e) (fail "the project's tests signalled an error: ~A" e)))))
  (multiple-value-bind (passed failures) (fiveam:results-status results)
    (unless passed
      (fail "the project's tests fail: ~{~A~^, ~}"
            (remove-duplicates
             (mapcar (lambda (failure)
                       (fiveam::name (fiveam::test-case failure)))
                     failures)
             :from-end t)))))

;;; The reported sequence, and many others against a model of the queue.
(load (concatenate 'string *work* "repro.lisp"))
(let ((failures (handler-case (funcall (find-symbol "REPRODUCTION-FAILURES" :cl-user))
                  (error (e) (fail "the reproduction signalled an error: ~A" e)))))
  (when failures
    (fail "jobs still go wrong:~{~%  ~A~}" failures)))

(format t "~&PASS: the reported sequence and the model's give the right jobs in the right order, and the tests pass~%")
(uiop:quit 0)
