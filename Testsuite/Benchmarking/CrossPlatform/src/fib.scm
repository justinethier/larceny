;;; FIB -- A classic benchmark, computes fib(30) inefficiently.

(define (fib n)
  (if (< n 2)
    n
    (+ (fib (- n 1))
       (fib (- n 2)))))

(define (main . args)
  (run-benchmark
    "fib"
    fib-iters
    (lambda () (fib 30))
    (lambda (result) (equal? result 832040))))
