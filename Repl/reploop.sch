; Repl/reploop.sch
; Larceny -- read-eval-print loop and error handler.
;
; $Id: reploop.sch,v 1.1 1997/05/15 00:53:10 lth Exp lth $

(define *reset-continuation* #f)    ; to jump to for error or reset
(define *saved-continuation* #f)    ; saved on error

(define *argv*)

(define (command-line-arguments)
  *argv*)

(define (main argv)
;  (display "; Evaluator version ")
;  (display eval-version)
;  (newline)
  (reset-handler new-reset-handler)
  (error-handler (new-error-handler))
  (init-toplevel-environment)
  (rep-loop0 argv))

(define (rep-loop0 argv)
  (set! *argv* argv)
  ; FIXME: Should reinitialize I/O system!!!!
  ; Try to load init file; on error signal error and abandon load.
  (if (not (call-with-current-continuation
	    (lambda (k)
	      (set! *reset-continuation* k)
	      (load-init-file)
	      #t)))
      (begin (display "Init file load failed.")
	     (newline)))
  (if (and (> (vector-length (command-line-arguments)) 0)
	   (file-exists? (vector-ref (command-line-arguments) 0)))
      (if (not (call-with-current-continuation
		(lambda (k)
		  (set! *reset-continuation* k)
		  (load (vector-ref (command-line-arguments) 0))
		  #t)))
	  (begin (display "Failed to load ")
		 (display (vector-ref (command-line-arguments) 0))
		 (newline))))
  (rep-loop))

(define (load-init-file)
  (let ((home (getenv "HOME")))
    (cond ((file-exists? ".larceny")
	   (display "; Loading .larceny")
	   (newline)
	   (load ".larceny"))
	  (home
	   (let ((fn (string-append home "/.larceny")))
	     (if (file-exists? fn)
		 (begin (display "; Loading ~/.larceny")
			(newline)
			(load fn))))))))

(define (rep-loop)

  ; This loop should check that the current output port is still writable,
  ; and should exit without any fuss if it is not.  If it does not
  ; discover that the output is not writable, then it may try to write the
  ; final newline to it, resulting in an error, resulting in an error ...
  ; and so on, until kingdom come.  This may be the source of some looping
  ; seen on EOF (race condition), and the 300MB runaway process on everest.
  ; In general, we need to catch SIGHUP too.

  (define (loop)
    (display "> ")
    (flush-output-port)
    (let ((expr   (read)))
      (if (not (eof-object? expr))
	  (let ((result (eval expr)))
	    (if (not (eq? result (unspecified)))
		(begin (display result)
		       (newline)))
	    (loop))
	  (begin (newline)
		 (exit)))))

  ; Setup the error continuation

  (call-with-current-continuation
   (lambda (k)
     (set! *reset-continuation* k)))
  (newline)
  (loop))

(define (new-error-handler)
  (let ((old (error-handler)))
    (lambda args
      (call-with-current-continuation 
       (lambda (k) 
	 (set! *saved-continuation* k)
	 (apply old args))))))

(define (error-continuation)
  *saved-continuation*)

(define (backtrace)
  (print-continuation (error-continuation)))

(define (new-reset-handler)
  (if *reset-continuation*
      (*reset-continuation* #f)
      (begin (display "No reset continuation! Exiting.")
	     (newline)
	     (exit))))

(define (dump-interactive-heap filename)
  (dump-heap filename rep-loop0))


; eof
