;;;; The packages of depot: DEPOT.SEMVER, versions and constraints on
;;;; them; DEPOT.REGISTRY, the packages and releases there are; and
;;;; DEPOT, which resolves a project's requirements against a registry
;;;; and writes the lock. DEPOT exports the names of the other two that a
;;;; user of depot needs, so that DEPOT: is the only prefix to know.

(defpackage #:depot.semver
  (:use #:common-lisp)
  (:export
   ;; Conditions
   #:depot-error
   #:syntax-error
   #:version-syntax-error
   #:constraint-syntax-error
   #:syntax-error-text
   #:syntax-error-reason
   ;; Versions
   #:version
   #:make-version
   #:parse-version
   #:ensure-version
   #:version-major
   #:version-minor
   #:version-patch
   #:version-prerelease
   #:version-build
   #:version-prerelease-p
   #:version-string
   #:compare-versions
   #:version=
   #:version<
   #:version<=
   #:version>
   ;; Version sets
   #:version-set
   #:interval
   #:make-interval
   #:interval-lower
   #:interval-lower-inclusive-p
   #:interval-upper
   #:interval-upper-inclusive-p
   #:make-version-set
   #:any-version
   #:no-version
   #:exactly
   #:version-set-intervals
   #:version-set-empty-p
   #:version-set-contains-p
   #:version-set-intersection
   #:version-set-union
   #:version-set-equal
   #:version-set-string
   #:copy-version-set
   #:narrow-version-set
   ;; Constraints
   #:constraint
   #:parse-constraint
   #:ensure-constraint
   #:constraint-text
   #:constraint-version-set
   #:constraint-allows-prereleases-p
   #:satisfies-p))

(defpackage #:depot.registry
  (:use #:common-lisp #:depot.semver)
  (:export
   #:registry-error
   #:registry-error-file
   #:skip-package
   #:registry
   #:make-registry
   #:load-registry
   #:add-release
   #:registry-package-names
   #:package-known-p
   #:package-releases
   #:find-release
   #:release
   #:release-package
   #:release-version
   #:release-yanked-p
   #:release-published
   #:release-dependencies
   #:release-name
   #:dependency
   #:dependency-package
   #:dependency-constraint
   #:dependency-kind))

(defpackage #:depot
  (:use #:common-lisp #:depot.semver #:depot.registry)
  (:export
   ;; From DEPOT.SEMVER
   #:depot-error
   #:version-syntax-error
   #:constraint-syntax-error
   #:version
   #:parse-version
   #:version-string
   #:compare-versions
   #:version<
   #:version-set
   #:version-set-intervals
   #:version-set-string
   #:version-set-equal
   #:version-set-contains-p
   #:constraint
   #:parse-constraint
   #:constraint-text
   #:constraint-version-set
   #:satisfies-p
   ;; From DEPOT.REGISTRY
   #:registry-error
   #:skip-package
   #:registry
   #:make-registry
   #:load-registry
   #:add-release
   #:registry-package-names
   #:package-releases
   #:find-release
   #:release
   #:release-package
   #:release-version
   #:release-yanked-p
   #:release-dependencies
   #:release-name
   #:dependency
   #:dependency-package
   #:dependency-constraint
   #:dependency-kind
   ;; Projects
   #:project
   #:make-project
   #:read-project
   #:project-name
   #:project-version
   #:project-dependencies
   #:project-dev-dependencies
   ;; Resolving
   #:unknown-package
   #:unknown-package-name
   #:skip-requirement
   #:resolution-failed
   #:resolution-failed-project
   #:resolution-failed-conflicts
   #:requirement
   #:make-requirement
   #:requirement-package
   #:requirement-constraint
   #:requirement-source
   #:conflict
   #:conflict-package
   #:conflict-requirements
   #:conflict-selected
   #:describe-conflict
   #:*step-limit*
   #:resolve
   ;; Locks
   #:inconsistent-lock
   #:lock
   #:make-lock
   #:lock-project-name
   #:lock-entries
   #:lock-entry
   #:entry-package
   #:entry-version
   #:entry-required-by
   #:lock-version
   #:write-lock
   #:read-lock
   #:verify-lock
   ;; Explanations
   #:why
   #:print-dependency-tree
   ;; The whole job
   #:lock-project))
