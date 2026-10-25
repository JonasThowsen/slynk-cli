(in-package #:depot/tests)

(in-suite :depot)

(defun small-world ()
  "Returns a registry and a project that depends on part of it."
  (values (test-registry '("web" "1.0.0" ("url" "^1.0.0") ("log" "^1.0.0"))
                         '("web" "1.1.0" ("url" "^1.2.0") ("log" "^1.0.0"))
                         '("url" "1.0.0") '("url" "1.2.0") '("url" "1.3.0")
                         '("log" "1.0.0") '("log" "1.1.0" ("url" "^1.0.0")))
          (make-project "site" :version "0.1.0"
                               :dependencies '(("web" "^1.0.0"))
                               :dev-dependencies '(("log" "~1.1.0")))))

(test make-lock
  (multiple-value-bind (registry project) (small-world)
    (let ((lock (lock-project project registry)))
      (is (equal '("log" "url" "web") (mapcar #'entry-package (lock-entries lock))))
      (is (string= "1.1.0" (lock-version lock "web")))
      (is (string= "1.3.0" (lock-version lock "url")))
      (is (string= "1.1.0" (lock-version lock "log")))
      (is (equal '(("^1.0.0" . "log 1.1.0") ("^1.2.0" . "web 1.1.0"))
                 (entry-required-by (find "url" (lock-entries lock)
                                          :key #'entry-package :test #'string=)))))))

(test lock-round-trip
  (multiple-value-bind (registry project) (small-world)
    (let* ((lock (lock-project project registry))
           (text (with-output-to-string (stream) (write-lock lock stream)))
           (read (with-input-from-string (stream text) (read-lock stream))))
      (is (string= "site" (lock-project-name read)))
      (is (equal (mapcar #'princ-to-string (lock-entries lock))
                 (mapcar #'princ-to-string (lock-entries read))))
      (is (equal (mapcar #'entry-required-by (lock-entries lock))
                 (mapcar #'entry-required-by (lock-entries read))))
      (is (eq read (verify-lock read))))))

(test verify-lock
  (flet ((lock (&rest entries)
           (with-input-from-string (stream (format nil "(:lock \"x\" :packages ~S)" entries))
             (read-lock stream))))
    (is (verify-lock (lock '("a" "1.0.0" :required-by (("^1.0.0" :project)))
                           '("b" "1.4.0" :required-by (("^1.2.0" "a 1.0.0"))))))
    (signals inconsistent-lock
      (verify-lock (lock '("a" "1.0.0" :required-by (("^1.0.0" :project)))
                         '("b" "2.0.0" :required-by (("^1.2.0" "a 1.0.0"))))))
    (signals inconsistent-lock
      (verify-lock (lock '("b" "1.4.0" :required-by (("^1.2.0" "a 1.0.0"))))))))

(test previous-lock
  (multiple-value-bind (registry project) (small-world)
    (let* ((old (lock-project project registry))
           (newer (progn (add-release registry "url" "1.4.0")
                         (lock-project project registry :previous old)))
           (fresh (lock-project project registry)))
      (is (string= "1.3.0" (lock-version newer "url")) "the previous lock's version stays")
      (is (string= "1.4.0" (lock-version fresh "url"))))))

(test why-and-tree
  (multiple-value-bind (registry project) (small-world)
    (let ((lock (lock-project project registry)))
      (is (equal '(("site" "log ~1.1.0" "log 1.1.0" "url ^1.0.0" "url 1.3.0")
                   ("site" "web ^1.0.0" "web 1.1.0" "url ^1.2.0" "url 1.3.0")
                   ("site" "web ^1.0.0" "web 1.1.0" "log ^1.0.0" "log 1.1.0" "url ^1.0.0"
                    "url 1.3.0"))
                 (why lock "url")))
      (is (null (why lock "nothing")))
      (is (string= (format nil "site~%  log 1.1.0~%    url 1.3.0~%  web 1.1.0~%    log 1.1.0 (*)~%    url 1.3.0 (*)~%")
                   (with-output-to-string (stream) (print-dependency-tree lock stream)))))))
