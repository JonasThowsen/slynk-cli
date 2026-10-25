;;;; The reported case: a gzip file whose stored block header straddles
;;;; the end of chipz's input buffer reads back wrong. Also builds
;;;; deflate, zlib and gzip data of stored blocks with a header at every
;;;; offset around the 4096- and 8192-byte buffer ends, and feeds stored
;;;; and compressed data to a dstate in pieces of many sizes; every way
;;;; must give back the original bytes.

(in-package :cl-user)

(defun octets (length)
  (make-array length :element-type '(unsigned-byte 8)))

(defun pattern (length)
  "LENGTH bytes that are not all alike."
  (let ((data (octets length)))
    (dotimes (i length data)
      (setf (aref data i) (ldb (byte 8 0) (+ (* i 7) (floor i 251)))))))

(defun concat (&rest vectors)
  (let ((result (octets (reduce #'+ vectors :key #'length)))
        (start 0))
    (dolist (vector vectors result)
      (replace result vector :start1 start)
      (incf start (length vector)))))

(defun crc32 (data)
  (let ((crc #xffffffff))
    (loop for byte across data
          do (setf crc (logxor crc byte))
             (dotimes (i 8)
               (setf crc (if (logbitp 0 crc)
                             (logxor (ash crc -1) #xedb88320)
                             (ash crc -1)))))
    (logxor crc #xffffffff)))

(defun adler32 (data)
  (let ((a 1) (b 0))
    (loop for byte across data
          do (setf a (mod (+ a byte) 65521)
                   b (mod (+ b a) 65521)))
    (logior (ash b 16) a)))

(defun little-endian (value bytes)
  (let ((result (octets bytes)))
    (dotimes (i bytes result)
      (setf (aref result i) (ldb (byte 8 (* 8 i)) value)))))

(defun big-endian (value bytes)
  (reverse (little-endian value bytes)))

(defun octets-of (&rest bytes)
  (coerce bytes '(simple-array (unsigned-byte 8) (*))))

(defun stored-deflate (data sizes)
  "Raw deflate data of DATA as stored blocks of SIZES, which sum to its length."
  (apply #'concat
         (loop for (size . more) on sizes
               for start = 0 then (+ start previous)
               for previous = size
               collect (concat (octets-of (if more 0 1))
                               (little-endian size 2)
                               (little-endian (logxor size #xffff) 2)
                               (subseq data start (+ start size))))))

(defun wrap (format deflate data)
  (ecase format
    (chipz:deflate deflate)
    (chipz:zlib (concat (octets-of #x78 #x01) deflate (big-endian (adler32 data) 4)))
    (chipz:gzip (concat (octets-of #x1f #x8b 8 0 0 0 0 0 0 #xff) deflate
                        (little-endian (crc32 data) 4)
                        (little-endian (length data) 4)))))

(defun header-length (format)
  (ecase format (chipz:deflate 0) (chipz:zlib 2) (chipz:gzip 10)))

(defun write-file (data path)
  (with-open-file (out path :direction :output :element-type '(unsigned-byte 8)
                            :if-exists :supersede)
    (write-sequence data out))
  path)

(defun read-file (path)
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((data (octets (file-length in))))
      (read-sequence data in)
      data)))

;;; The ways data reaches chipz. Each returns the decompressed bytes.

(defun from-vector (format compressed)
  (chipz:decompress nil format compressed))

(defun from-pathname (format path)
  (chipz:decompress nil format (pathname path)))

(defun from-stream (format path)
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (chipz:decompress nil format in)))

(defun through-gray-stream (format path length)
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((stream (chipz:make-decompressing-stream format in))
          (buffer (octets length)))
      (subseq buffer 0 (read-sequence buffer stream)))))

(defun in-pieces (format compressed piece)
  "Feed COMPRESSED to one dstate PIECE bytes at a time."
  (let ((state (chipz:make-dstate format))
        (output (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0))
        (buffer (octets 4000)))
    (loop for start from 0 below (length compressed) by piece
          for end = (min (length compressed) (+ start piece))
          do (loop with index = start
                   do (multiple-value-bind (read written)
                          (chipz:decompress buffer state compressed
                                            :input-start index :input-end end)
                        (loop for i below written
                              do (vector-push-extend (aref buffer i) output))
                        (incf index read)
                        (when (or (and (>= index end) (< written (length buffer)))
                                  (and (zerop read) (zerop written)))
                          (return)))))
    (coerce output '(simple-array (unsigned-byte 8) (*)))))

(defun reproduction-failures ()
  (let ((failures '())
        (work (uiop:getenv "CHECK_WORK")))
    (labels ((path (name) (concatenate 'string work name))
             (expect (description original thunk)
               (let ((got (handler-case (funcall thunk)
                            (error (e) (format nil "~A: ~A" (type-of e) e)))))
                 (cond ((stringp got)
                        (push (format nil "~A: ~A" description got) failures))
                       ((not (equalp got original))
                        (push (format nil "~A: ~D bytes, ~:[different from~;the same length as~] the original's ~D"
                                      description (length got)
                                      (= (length got) (length original)) (length original))
                              failures))))))
      ;; The report: two lines of text and 1.5 MB of noise, gzip -1.
      (let ((recording (path "recording.bin")))
        (with-open-file (out recording :direction :output
                                       :element-type '(unsigned-byte 8) :if-exists :supersede)
          (loop for char across (format nil "line 0~%line 1~%")
                do (write-byte (char-code char) out))
          (let ((x 1))
            (dotimes (i 1500000)
              (setf x (mod (* x 48271) 2147483647))
              (write-byte (ldb (byte 8 16) x) out))))
        (handler-case (uiop:run-program (list "gzip" "-1" "-n" "-k" "-f" recording))
          (error (e) (push (format nil "gzip did not run: ~A" e) failures)))
        (let ((original (read-file recording))
              (gz (concatenate 'string recording ".gz")))
          (expect "the recording through make-decompressing-stream" original
                  (lambda () (through-gray-stream 'chipz:gzip gz (length original))))
          (expect "the recording from its pathname" original
                  (lambda () (from-pathname 'chipz:gzip gz)))))
      ;; Stored blocks whose header sits at each offset around the end
      ;; of a 4096- or 8192-byte input buffer.
      (dolist (format '(chipz:deflate chipz:zlib chipz:gzip))
        (dolist (boundary '(4096 8192))
          (loop for offset from -3 to 6
                for first = (- boundary 5 (header-length format) offset)
                for sizes = (list first 3000 (- 20000 first) 70)
                for data = (pattern (reduce #'+ sizes))
                for compressed = (wrap format (stored-deflate data sizes) data)
                for file = (write-file compressed (path "stored.bin"))
                for what = (format nil "~(~A~), stored blocks of ~{~D~^, ~} bytes" format sizes)
                do (expect (format nil "~A, from a vector" what) data
                           (lambda () (from-vector format compressed)))
                   (expect (format nil "~A, from a pathname" what) data
                           (lambda () (from-pathname format file)))
                   (expect (format nil "~A, from a stream" what) data
                           (lambda () (from-stream format file)))
                   (expect (format nil "~A, through make-decompressing-stream" what) data
                           (lambda () (through-gray-stream format file (length data)))))))
      ;; Stored and compressed data fed to a dstate in pieces.
      (let* ((sizes '(100 2000 65535 7))
             (data (pattern (reduce #'+ sizes)))
             (text (let ((*print-pretty* nil))
                     (map '(vector (unsigned-byte 8)) #'char-code
                          (format nil "~{~A~%~}" (loop for i below 3000 collect (list i (* i i)))))))
             (cases (list (list "stored gzip" 'chipz:gzip data
                                (wrap 'chipz:gzip (stored-deflate data sizes) data))
                          (list "stored deflate" 'chipz:deflate data (stored-deflate data sizes))
                          (list "salza2 gzip" 'chipz:gzip text
                                (salza2:compress-data text 'salza2:gzip-compressor))
                          (list "salza2 zlib" 'chipz:zlib text
                                (salza2:compress-data text 'salza2:zlib-compressor)))))
        (loop for (name format original compressed) in cases
              do (dolist (piece '(1 2 3 4 5 6 7 8 9 10 11 13 17 64 100 1000 4096))
                   (expect (format nil "~A in pieces of ~D bytes" name piece) original
                           (lambda () (in-pieces format compressed piece)))))))
    (let ((failures (nreverse failures)))
      (if (> (length failures) 12)
          (append (subseq failures 0 12)
                  (list (format nil "... and ~D more" (- (length failures) 12))))
          failures))))
