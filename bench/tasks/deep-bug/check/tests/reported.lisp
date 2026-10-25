;;;; The reported case and related ones. The webshop must lock, with the
;;;; releases the resolver's order of decisions gives when every
;;;; requirement means what its text says; other projects on the same
;;;; registry, which the defect made fail or silently get older versions,
;;;; must lock as they should; and resolving must not change the
;;;; registry, so that the answers do not depend on what was resolved
;;;; before.

(in-package #:depot/tests)

(in-suite :depot)

(defparameter *webshop-lock*
  '("ascii-table@1.2.5" "atomics@1.6.0" "base64@1.2.2" "bit-vectors@1.1.3"
    "bytes@1.4.0" "cache@1.4.1" "color@1.3.1" "cookies@1.2.4" "crc32@0.1.1"
    "csv@2.0.1" "date-time@1.7.0" "endian@1.3.3" "env@1.2.1" "events@1.4.2"
    "fnv-hash@1.1.0" "forms@3.0.1" "glob@2.1.3" "gzip@1.6.0" "hex@0.5.0"
    "html-escape@2.4.1" "http-server@3.4.0" "i18n@1.3.2" "ini@0.1.1"
    "jobs@1.3.0" "json@1.8.0" "levenshtein@1.1.1" "log-format@0.2.2"
    "logging@2.2.0" "mailer@2.2.0" "markup@1.1.0" "metrics@1.2.2"
    "mime-types@2.1.6" "mock-server@1.2.0" "money@1.2.0" "murmur@1.2.1"
    "openapi@1.3.2" "pg@1.3.0" "promise@1.2.0" "queue@2.2.0"
    "rational-math@1.3.0" "router@0.4.0" "session@1.4.1" "smtp@0.3.0"
    "streams@1.4.1" "strings@2.1.0" "template@1.3.0" "terminal@1.3.1"
    "test-harness@2.2.1" "text-utils@1.3.0" "time-zones@1.2.0"
    "unicode@1.2.2" "url@2.1.2" "uuid@2.0.1" "varint@1.6.0"
    "websocket@1.2.0" "yaml@1.4.0")
  "The lock of examples/webshop.sexp, as \"package@version\".")

(defparameter *other-projects*
  '(
  ((("test-harness" "^2.0.0") ("validate" "^2.0.0") ("rest" "^1.0.0"))
   ("atomics@1.6.0" "base64@1.2.2" "color@1.3.1" "config@0.3.2"
    "cookies@1.2.5" "crc32@0.1.1" "endian@1.3.3" "env@1.2.1"
    "levenshtein@1.1.1" "lru@1.4.1" "murmur@1.2.1" "pg@1.3.0"
    "promise@1.1.1" "queue@2.2.0" "rest@1.5.0" "strings@1.3.1"
    "terminal@2.0.0" "test-harness@2.2.1" "text-utils@1.3.0" "threads@1.1.1"
    "unicode@1.2.2" "url@2.1.2" "uuid@2.0.1" "validate@2.0.0" "varint@1.6.0"
    "yaml@1.4.0"))
  ((("pg" "^1.0.0") ("sse" "^0.5.0") ("dns" "^1.0.0"))
   ("atomics@1.6.0" "bytes@1.4.0" "color@1.3.1" "dns@1.3.1" "endian@1.3.3"
    "env@1.2.1" "fnv-hash@1.1.0" "glob@2.1.3" "levenshtein@1.1.1"
    "logging@2.2.0" "murmur@1.2.1" "pg@1.3.0" "queue@2.2.0" "sse@0.5.0"
    "streams@1.4.1" "unicode@1.2.2" "url@2.1.2" "varint@1.6.0" "yaml@1.4.0"))
  ((("markdown" "^1.0.0") ("test-harness" "^2.0.0") ("graphql" "^1.0.0"))
   ("atomics@1.6.0" "base64@1.2.2" "bit-vectors@1.1.3" "color@1.3.1"
    "cookies@1.2.5" "crc32@0.2.0" "endian@1.3.3" "env@1.2.1" "glob@2.1.3"
    "graphql@1.2.0" "logging@2.1.0" "markdown@1.5.1" "pg@1.3.0"
    "promise@1.1.1" "queue@2.2.0" "sqlite@1.4.1" "strings@1.3.1"
    "terminal@2.0.0" "test-harness@2.2.1" "text-utils@1.3.0" "unicode@1.2.2"
    "uuid@2.0.1" "varint@1.6.0" "yaml@1.4.0"))
  ((("pg" "^1.0.0") ("router" "^0.4.0") ("admin-ui" "^1.0.0"))
   ("admin-ui@1.5.0" "atomics@1.6.0" "base64@1.2.2" "bit-vectors@1.1.3"
    "bytes@1.4.0" "color@1.3.1" "crc32@1.1.1" "glob@2.1.3" "hex@0.5.0"
    "ini@1.3.0" "levenshtein@2.2.1" "logging@2.1.0" "markdown@1.5.1"
    "pg@1.3.0" "queue@2.2.0" "router@0.4.0" "unicode@1.2.2" "yaml@1.4.0")))
  "Projects on the registry, (DEPENDENCIES LOCK), that the defect made
fail or lock older versions.")

(defun lock-names (lock)
  "Returns the entries of LOCK as \"package@version\"."
  (mapcar (lambda (entry)
            (format nil "~A@~A" (entry-package entry) (version-string (entry-version entry))))
          (lock-entries lock)))

(defun registry-unchanged-p (registry)
  "True when every dependency in REGISTRY still has the versions its text
says. Returns the first one that does not as the second value."
  (dolist (name (registry-package-names registry) t)
    (dolist (release (package-releases registry name))
      (dolist (dependency (release-dependencies release))
        (let ((constraint (dependency-constraint dependency)))
          (unless (version-set-equal (constraint-version-set constraint)
                                     (constraint-version-set
                                      (parse-constraint (constraint-text constraint))))
            (return-from registry-unchanged-p
              (values nil (format nil "~A: ~A ~A has the versions ~A"
                                  (release-name release) (dependency-package dependency)
                                  (constraint-text constraint)
                                  (version-set-string (constraint-version-set constraint)))))))))))

(test reported-webshop
  (let* ((registry (load-registry (project-file "registry/")))
         (lock (handler-case (lock-project (project-file "examples/webshop.sexp") registry)
                 (depot-error (condition) condition))))
    (is (typep lock 'lock) "the webshop does not lock: ~A" lock)
    (when (typep lock 'lock)
      (is (string= "2.4.1" (lock-version lock "html-escape")))
      (is (string= "2.2.0" (lock-version lock "mailer")))
      (is (string= "2.1.6" (lock-version lock "mime-types")))
      (is (equal *webshop-lock* (lock-names lock))))
    (multiple-value-bind (unchanged-p what) (registry-unchanged-p registry)
      (is (not (null unchanged-p)) "locking the webshop changed the registry: ~A" what))))

(test other-projects
  (loop for (dependencies expected) in *other-projects*
        do (let* ((registry (load-registry (project-file "registry/")))
                  (lock (handler-case (lock-project (make-project "p" :dependencies dependencies)
                                                    registry)
                          (depot-error (condition) condition))))
             (is-true (and (typep lock 'lock) (equal expected (lock-names lock)))
                      "~S locks as ~A" dependencies
                      (if (typep lock 'lock) (lock-names lock) lock))
             (is (registry-unchanged-p registry)
                 "locking ~S changed the registry" dependencies))))

(test one-registry-many-resolutions
  ;; The answers with one registry for all are those with a fresh one each.
  (let ((registry (load-registry (project-file "registry/")))
        (projects (append (list (project-file "examples/blog.sexp")
                                (project-file "examples/webshop.sexp"))
                          (mapcar (lambda (project) (make-project "p" :dependencies (first project)))
                                  *other-projects*)
                          (list (project-file "examples/blog.sexp")))))
    (dolist (project projects)
      (flet ((names (registry)
               (handler-case (lock-names (lock-project project registry))
                 (depot-error (condition) (princ-to-string condition)))))
        (is (equal (names (load-registry (project-file "registry/"))) (names registry))
            "~A locks differently after other projects" project)))))

(test shared-constraint-texts
  ;; Two packages required with the same text, and one of them narrowed by
  ;; another requirement: the other keeps the versions of its text.
  (flet ((world ()
           (test-registry '("server" "1.0.0" ("types" "^2.1.0"))
                          '("mail" "1.0.0" ("types" "~2.1.4"))
                          '("page" "1.0.0" ("escape" "^2.1.0"))
                          '("types" "2.1.0") '("types" "2.1.5") '("types" "2.3.0")
                          '("escape" "2.1.0") '("escape" "2.2.0") '("escape" "2.4.0"))))
    (is (equal '("escape 2.4.0" "mail 1.0.0" "page 1.0.0" "server 1.0.0" "types 2.1.5")
               (resolved (world) '("server" "*") '("mail" "*") '("page" "*"))))
    (is (equal '("escape 2.4.0" "mail 1.0.0" "page 1.0.0" "server 1.0.0" "types 2.1.5")
               (resolved (world) '("page" "*") '("server" "*") '("mail" "*"))))
    (let ((registry (world)))
      (resolved registry '("page" "*") '("server" "*") '("mail" "*"))
      (is (equal '("escape 2.4.0" "page 1.0.0") (resolved registry '("page" "*")))
          "a second resolution with the same registry")
      (is (equal '("server 1.0.0" "types 2.3.0") (resolved registry '("server" "*")))))))
