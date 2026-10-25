;;;; Loads the logsum in CHECK_DIR and runs the project's tests from their
;;;; copy in CHECK_WORK; then makes two sample logs, the report's March
;;;; and a February of another seed, and checks that the report of each
;;;; is the expected one and that March's, read from its log, takes at
;;;; most CHECK_BOUND seconds in the best of three runs. Exits 0 when all
;;;; of that holds.

;; Before ASDF, so that it comes from the SBCL's contribs as it is.
(require :sb-md5)
(require :asdf)

(defvar *dir* (uiop:getenv "CHECK_DIR"))
(defvar *work* (uiop:getenv "CHECK_WORK"))
(defvar *here* (uiop:getenv "CHECK_HERE"))
(defvar *bound* (parse-integer (uiop:getenv "CHECK_BOUND")))

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

(quietly-load-system :logsum)
(unless (uiop:subpathp (asdf:system-source-directory :logsum)
                       (uiop:parse-native-namestring *dir*))
  (fail "logsum was loaded from ~A, not from the project"
        (asdf:system-source-directory :logsum)))
(quietly-load-system :fiveam)

;;; The project's tests, from the hidden copy.
(let ((results (handler-case
                   (let ((*standard-output* (make-broadcast-stream))
                         (*error-output* (make-broadcast-stream)))
                     (load (concatenate 'string *work* "tests/tests.lisp"))
                     (fiveam:run :logsum))
                 (error (e) (fail "the project's tests signalled an error: ~A" e)))))
  (unless (fiveam:results-status results)
    (fail "the project's tests fail: ~{~A~^, ~}"
          (remove-duplicates
           (mapcar (lambda (result) (fiveam::name (fiveam::test-case result)))
                   (remove-if-not (lambda (result) (typep result 'fiveam::test-failure))
                                  results))
           :from-end t))))

;;; The sample logs, which must be the ones the expected reports are of.

(defun write-sample (name md5 &rest options)
  "Writes the sample log of OPTIONS to NAME.log in the work directory, and
returns its pathname."
  (let ((file (concatenate 'string *work* name ".log")))
    (handler-case
        (with-open-file (out file :direction :output :external-format :utf-8)
          (apply #'logsum:write-sample-log out options))
      (error (e) (fail "writing the sample log ~A signalled an error: ~A" name e)))
    (let ((sum (format nil "~(~{~2,'0X~}~)" (coerce (sb-md5:md5sum-file file) 'list))))
      (unless (string= sum md5)
        (fail "the sample log ~A is not the one the check knows (MD5 ~A): the sample changed"
              name sum)))
    file))

(defun expected (name)
  (uiop:read-file-string (concatenate 'string *here* "expected/" name ".txt")
                         :external-format :utf-8))

(defun report-of (file)
  "Returns the report of the log FILE, and the seconds reading the log and
making the report took."
  (sb-ext:gc :full t)
  (let ((start (get-internal-real-time)))
    (let ((report (handler-case
                      (logsum:monthly-report
                       (with-open-file (in file :external-format :utf-8)
                         (logsum:read-log in)))
                    (error (e) (fail "the report of ~A signalled an error: ~A" file e)))))
      (values report (/ (- (get-internal-real-time) start) internal-time-units-per-second)))))

(defun expect-report (name report)
  (let ((expected (expected name)))
    (unless (string= report expected)
      (let* ((got (uiop:split-string report :separator '(#\Newline)))
             (want (uiop:split-string expected :separator '(#\Newline)))
             (line (or (mismatch got want :test #'string=) 0)))
        (fail "the report of ~A differs from the expected one at line ~D:~%  got:      ~S~%  expected: ~S"
              name (1+ line) (nth line got) (nth line want))))))

(let ((february (write-sample "february" "e1c48e097750d3337f9cf82cab4d75e6"
                              :seed 2 :start "2026-02-01" :days 28 :visitors 3200))
      (march (write-sample "march" "723724b4f941a774712f2afac7b7e5ec")))
  (expect-report "february" (report-of february))
  ;; The best of three runs; no more once one is fast enough, nor after
  ;; one so slow that the others could not be.
  (let ((times '()))
    (loop repeat 3
          do (multiple-value-bind (report seconds) (report-of march)
               (expect-report "march" report)
               (push seconds times)
               (when (or (<= seconds *bound*) (> seconds (* 3 *bound*)))
                 (return))))
    (let ((best (reduce #'min times)))
      (when (> best *bound*)
        (fail "the March report takes ~,1F s at best (~{~,1F~^, ~} s), more than ~D s"
              best (reverse times) *bound*))
      (format t "~&PASS: the reports are the expected ones, and March's takes ~,1F s~%" best))))
(uiop:quit 0)
