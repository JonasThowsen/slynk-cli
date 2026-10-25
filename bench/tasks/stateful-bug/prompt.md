The current directory is trove, the search index of our newsroom
archive (the `trove` system; its tests are the `trove/tests` system).
Ingrid from the archive desk sent this:

> A correction to an article from last week got lost in the nightly
> import. With the sample archive (building it takes about a minute):
>
> ```lisp
> (defparameter *index* (trove:make-sample-index))
> (defparameter *old* (trove:get-document *index* "doc-204917"))
> (trove:document-title *old*)
> ;; => "New festival increase surgeries authors"
>
> ;; The correction:
> (trove:update-document *index*
>                        (trove:make-document "doc-204917"
>                                             :title "Harbour cranes back at work after the storm"
>                                             :body (trove:document-body *old*)
>                                             :published (trove:document-published *old*)))
> ;; The day's import:
> (trove:add-documents *index* (trove:sample-documents :seed 2 :count 1500
>                                                      :first-number 210401 :day 263))
> (trove:commit *index*)
>
> (trove:get-document *index* "doc-204917")
> ;; => NIL                 but it should be the corrected article
> (mapcar #'trove:hit-id (trove:search-index *index* "title:\"cranes back at work\""))
> ;; => NIL                 but it should be ("doc-204917")
> (mapcar #'trove:hit-id (trove:search-index *index* "title:\"festival increase surgeries\""))
> ;; => ("doc-204917")      the old title, which should be gone
> ```
>
> When I tried the same steps on a small index of my own, the correction
> came through.

Find the cause and fix the code. Done means: after the sequence above,
`get-document` gives the corrected article, searches find it by its new
title and not by its old one, every other article is as it should be,
and the project's tests pass. Don't change the tests.
