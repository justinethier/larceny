; Copyright 1994 William Clinger
;
; $Id$
;
; 16 December 1998
;
; Compiler switches needed by Twobit.

(define make-twobit-flag)
(define display-twobit-flag)

(define make-twobit-flag
  (lambda (name)

    (define (twobit-warning)
      (display "Error: incorrect arguments to ")
      (write name)
      (newline)
      (reset))

    (define (display-flag state)
      (display #\tab)
      (display name)
      (display " is ")
      (display (if state "on" "off"))
      (newline))

    (let ((state #t))
      (lambda args
        (cond ((null? args) state)
              ((and (null? (cdr args))
                    (boolean? (car args)))
               (set! state (car args))
               state)
              ((and (null? (cdr args))
                    (eq? (car args) 'display))
               (display-flag state))
              (else (twobit-warning)))))))

(define (display-twobit-flag flag)
  (flag 'display))
  
; Debugging and convenience.

(define issue-warnings
  (make-twobit-flag 'issue-warnings))

(define include-source-code
  (make-twobit-flag 'include-source-code))

(define include-variable-names
  (make-twobit-flag 'include-variable-names))

(define include-procedure-names
  (make-twobit-flag 'include-procedure-names))

; Space efficiency.
; This switch isn't fully implemented yet.  If it is false, then
; Twobit will generate flat closures and will go to some trouble
; to zero stale registers and stack slots.
; Don't turn this switch off unless space is more important than speed.

(define ignore-space-leaks
  (make-twobit-flag 'ignore-space-leaks))

; Major optimizations.

(define integrate-usual-procedures
  (make-twobit-flag 'integrate-usual-procedures))

(define benchmark-mode
  (make-twobit-flag 'benchmark-mode))

(define benchmark-block-mode
  (make-twobit-flag 'benchmark-block-mode))

(define local-optimizations
  (make-twobit-flag 'local-optimizations))

(define global-optimizations
  (make-twobit-flag 'global-optimizations))

(define representation-optimizations
  (make-twobit-flag 'representation-optimizations))

(define lambda-optimizations
  (make-twobit-flag 'lambda-optimizations))

(define parallel-assignment-optimization
  (make-twobit-flag 'parallel-assignment-optimization))

(define (set-compiler-flags! how)
  (case how
    ((no-optimization)
     (set-compiler-flags! 'default)
     (local-optimizations #f)
     (global-optimizations #f)
     (representation-optimizations #f)
     (lambda-optimizations #f)
     (parallel-assignment-optimization #f))
    ((default) 
     (issue-warnings #t)
     (include-source-code #f)
     (include-procedure-names #t)
     (include-variable-names #t)
     (ignore-space-leaks #t)
     (integrate-usual-procedures #f)
     (benchmark-mode #f)
     (benchmark-block-mode #f)
     (local-optimizations #t)
     (global-optimizations #t)
     (representation-optimizations #t)
     (lambda-optimizations #t)
     (parallel-assignment-optimization #t))
    ((fast-safe) 
     (set-compiler-flags! 'default)
     (integrate-usual-procedures #t)
     (benchmark-mode #t))
    ((fast-unsafe) 
     (set-compiler-flags! 'fast-safe))
    (else 
     (error "set-compiler-flags!: unknown mode " how))))

(define (display-twobit-flags)
  (display "Twobit flags" ) (newline)
  (display-twobit-flag issue-warnings)
  (display-twobit-flag include-procedure-names)
  (display-twobit-flag include-source-code)
  (display-twobit-flag include-variable-names)
  (display-twobit-flag ignore-space-leaks)
  (display-twobit-flag integrate-usual-procedures)
  (display-twobit-flag benchmark-mode)
  (display-twobit-flag benchmark-block-mode)
  (display-twobit-flag local-optimizations)
  (display-twobit-flag global-optimizations)
  (display-twobit-flag representation-optimizations)
  (display-twobit-flag lambda-optimizations)
  (display-twobit-flag parallel-assignment-optimization))

; eof
