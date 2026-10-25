(in-package #:trove.index)

;;; A document is an article of the archive: an id that the newsroom's
;;; system gives it, a title and a body, the two fields that are indexed,
;;; and the day it was published. Updating an article replaces the
;;; document with its id by a new one; documents themselves never change.

(defparameter *fields* '(:title :body)
  "The indexed fields of a document, in the order they are analyzed.")

(defclass document ()
  ((id :initarg :id :reader document-id :type string)
   (title :initarg :title :initform "" :reader document-title :type string)
   (body :initarg :body :initform "" :reader document-body :type string)
   (published :initarg :published :initform nil :reader document-published
              :documentation "The day it was published, as \"2024-03-01\", or NIL."))
  (:documentation "An article to index."))

(defun make-document (id &key (title "") (body "") published)
  "Returns the document ID with TITLE, BODY and the day PUBLISHED."
  (check-type id string)
  (check-type title string)
  (check-type body string)
  (make-instance 'document :id id :title title :body body :published published))

(defmethod print-object ((document document) stream)
  (print-unreadable-object (document stream :type t)
    (format stream "~A ~S" (document-id document)
            (let ((title (document-title document)))
              (if (> (length title) 40)
                  (concatenate 'string (subseq title 0 37) "...")
                  title)))))

(defgeneric field-text (document field)
  (:documentation "Returns the text of FIELD of DOCUMENT.")
  (:method ((document document) (field (eql :title))) (document-title document))
  (:method ((document document) (field (eql :body))) (document-body document)))
