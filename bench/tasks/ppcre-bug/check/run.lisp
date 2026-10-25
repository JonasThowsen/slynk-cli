;;;; Loads the cl-ppcre in CHECK_DIR, then runs the reproduction and
;;;; cl-ppcre's own tests from their copies in CHECK_WORK. Exits 0 when
;;;; both pass.

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

(quietly-load-system :cl-ppcre)
(unless (uiop:subpathp (asdf:system-source-directory :cl-ppcre)
                        (uiop:parse-native-namestring *dir*))
  (fail "cl-ppcre was loaded from ~A, not from the project"
        (asdf:system-source-directory :cl-ppcre)))
(quietly-load-system :flexi-streams)

;;; The reproduction from the report, and close relatives of it.
(load (concatenate 'string *work* "repro.lisp"))
(let ((failures (funcall (find-symbol "REPRODUCTION-FAILURES" :cl-user))))
  (when failures
    (fail "the reported case still goes wrong:~{~%  ~A~}" failures)))

;;; cl-ppcre's own test suite, from the pristine copy.
(let* ((log (make-string-output-stream))
       (passed
         (handler-case
             (let ((*standard-output* log)
                   (*error-output* log))
               (dolist (file '("packages" "tests" "perl-tests"))
                 (load (concatenate 'string *work* "test/" file ".lisp")))
               (funcall (find-symbol "RUN-ALL-TESTS" :cl-ppcre-test)))
           (error (e) (fail "cl-ppcre's tests signalled an error: ~A" e)))))
  (unless passed
    (let ((lines (remove-if-not (lambda (line) (search "expected" line))
                                (uiop:split-string (get-output-stream-string log)
                                                   :separator '(#\Newline)))))
      (fail "cl-ppcre's test suite fails:~{~%  ~A~}"
            (subseq lines 0 (min 10 (length lines)))))))

(format t "~&PASS: the reported case works and cl-ppcre's test suite passes~%")
(uiop:quit 0)
