The current directory is a checkout of chipz, the deflate, gzip, zlib and
bzip2 decompression library. We got this bug report:

> **`make-decompressing-stream` fails on some gzip files with "Invalid stored block length"**
>
> We keep sensor recordings gzip'ed with `gzip -1` and read them back
> through `chipz:make-decompressing-stream`. Some recordings fail part-way
> with `CHIPZ:INVALID-STORED-BLOCK-LENGTH-ERROR` ("Invalid stored block
> length"), though `gzip -t` says the files are fine and `gunzip` unpacks
> them. This makes one that fails for us, from scratch:
>
> ```lisp
> ;; A stand-in recording: two lines of text, then 1.5 MB of noise.
> (with-open-file (out "recording.bin" :direction :output
>                      :element-type '(unsigned-byte 8) :if-exists :supersede)
>   (loop for char across (format nil "line 0~%line 1~%")
>         do (write-byte (char-code char) out))
>   (let ((x 1))
>     (dotimes (i 1500000)
>       (setf x (mod (* x 48271) 2147483647))
>       (write-byte (ldb (byte 8 16) x) out))))
> ```
>
> ```sh
> gzip -1 -n -k recording.bin        # writes recording.bin.gz
> ```
>
> ```lisp
> (with-open-file (in "recording.bin.gz" :element-type '(unsigned-byte 8))
>   (let ((gz (chipz:make-decompressing-stream 'chipz:gzip in))
>         (buffer (make-array 1500014 :element-type '(unsigned-byte 8))))
>     (read-sequence buffer gz)))
> ;; => error: Invalid stored block length
> ```
>
> Decompressing the same file with `(chipz:decompress nil 'chipz:gzip
> #p"recording.bin.gz")` gives all 1500014 bytes, and they are right.

Find the cause and fix it in the library. Done means: the recording above
reads back byte for byte through `make-decompressing-stream`, files like
it decompress right whichever way they reach chipz (a vector, a file, a
stream, or a dstate fed the input in pieces), and chipz's own tests
(`tests.lisp`; its header says how to run them) pass. Don't change the
tests.

One thing we know already: on some test files, the raw deflate tests in
`tests.lisp` fail with "Unexpected EOF" (issue #3, data from salza2);
that is a separate problem and not part of this report.
