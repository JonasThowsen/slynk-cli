(in-package #:depot)

;;; The whole job: read the project, resolve it against the registry,
;;; check the result, and write the lock.

(defun ensure-project (thing)
  "Returns THING if it is a project, or the project in the file THING."
  (etypecase thing
    (project thing)
    ((or string pathname) (read-project thing))))

(defun ensure-registry (thing)
  "Returns THING if it is a registry, or the registry in the directory
THING."
  (etypecase thing
    (registry thing)
    ((or string pathname) (load-registry thing))))

(defun ensure-lock (thing)
  "Returns THING if it is a lock, or the lock in the file THING."
  (etypecase thing
    (lock thing)
    ((or string pathname)
     (with-open-file (stream thing :external-format :utf-8)
       (read-lock stream)))))

(defun lock-project (project registry &key previous output as-of)
  "Resolves the requirements of PROJECT, a project or its file, against
REGISTRY, a registry or its directory, and returns the lock.

PREVIOUS, a lock or its file, gives the versions to keep where the
requirements still allow them, including yanked ones. AS-OF, a day as
\"2025-06-30\", leaves out releases published after it. With OUTPUT, a
file name, the lock is written there too.

The lock is verified before it is returned: a lock that does not
satisfy its own requirements signals INCONSISTENT-LOCK and is not
written."
  (let* ((project (ensure-project project))
         (registry (ensure-registry registry))
         (previous (and previous (ensure-lock previous)))
         (releases (resolve registry (project-requirements project)
                            :project-name (project-name project)
                            :as-of as-of
                            :preferred (and previous
                                            (mapcar (lambda (entry)
                                                      (cons (entry-package entry)
                                                            (entry-version entry)))
                                                    (lock-entries previous)))))
         (lock (verify-lock (make-lock project releases))))
    (when output
      (with-open-file (stream output :direction :output :if-exists :supersede
                                     :external-format :utf-8)
        (write-lock lock stream)))
    lock))
