;;;; Loads the jzon in CHECK_DIR, then runs the reproduction and jzon's
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

(quietly-load-system :com.inuoe.jzon)
(unless (uiop:subpathp (asdf:system-source-directory :com.inuoe.jzon)
                        (uiop:parse-native-namestring *dir*))
  (fail "jzon was loaded from ~A, not from the project"
        (asdf:system-source-directory :com.inuoe.jzon)))
(quietly-load-system :fiveam)
(quietly-load-system :alexandria)
(quietly-load-system :flexi-streams)

;;; The reproduction from the report, and close relatives of it.
(load (concatenate 'string *work* "repro.lisp"))
(let ((failures (funcall (find-symbol "REPRODUCTION-FAILURES" :cl-user))))
  (when failures
    (fail "the reported case still goes wrong:~{~%  ~A~}"
          (subseq failures 0 (min 10 (length failures))))))

;;; jzon's own tests, from the pristine copy.
(let* ((log (make-string-output-stream))
       (passed
         (handler-case
             (let ((*standard-output* log)
                   (*error-output* log))
               (load (concatenate 'string *work* "test/jzon-tests.lisp")
                     :external-format :utf-8)
               (funcall (find-symbol "RUN" :com.inuoe.jzon-tests)))
           (error (e) (fail "jzon's tests signalled an error: ~A" e)))))
  (unless passed
    (let* ((lines (uiop:split-string (get-output-stream-string log)
                                     :separator '(#\Newline)))
           (start (position-if (lambda (line) (search "Failure Details" line)) lines)))
      (fail "jzon's test suite fails:~{~%  ~A~}"
            (if start
                (subseq lines start (min (length lines) (+ start 20)))
                (last lines 20))))))

(format t "~&PASS: the reported case works and jzon's test suite passes~%")
(uiop:quit 0)
