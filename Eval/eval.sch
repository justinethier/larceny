; Eval/eval.sch
; Larceny -- fast interpreter.
;
; $Id: eval.sch,v 1.5 1997/07/18 13:51:43 lth Exp $
;
; Description
;   `Eval' takes an expression and optionally an R5RS environment and
;   evaluates the expression in the environment, or in the interaction
;   environment if none is given. It returns the result of the evaluation,
;   and may change the environment argument (or the interaction-environment).
;
;   `Eval' accepts full R4RS Scheme, but requires a procedure `macro-expand'
;   that converts full Scheme to its core form with all constants quoted.
;
; Technique
;   The interpreter works by preprocessing the source code into a procedure
;   that takes a run-time environment as its only argument.  The procedure
;   in turn calls procedures representing subexpressions, and so on, so all
;   steps in the interpretation are translated into direct function calls,
;   with roughly one call per subexpression.  This technique strongly
;   resembles the use of threaded code.
;
;   By judiciously translating common cases specially and using some caching
;   (using local transformations only), much interpretive overhead is avoided.
;   A number of further optimizations are possible; see the comments.
;
;   Run-time lexical environments are lists of vectors, in inside-out lexical
;   order.
;
; Features Needed or Deeply Desired
;   Optimizations:
;   * More primitives (we need macros before this is practical).  Notably,
;     we need more predicates and both vector and string operations.  See
;     the file Eval/evalprim.sch.
;
;   * If+predicate, for example, (if (< a b) ...) can be optimized to
;     use no calls.  (if (not (< a b)) ...) is more of a mess because
;     `not' is a procedure that may have been redefined, also, but it's
;     clearly doable.
;
;   * Immediate optimization in primitives: if a primitive uses a constant,
;     then avoid the call by just closing over a variable that uses the
;     constant and let the primitive reference that variable.
;
;   * Rib0 optimization in primitives: if a local is fetched in a primitive,
;     and that local is at rib0, then do the vector-ref in the primitive.
;
;   * `Let' optimization akin to letrec optimization.  This avoids calls,
;     but payoff is smaller because an intermediate structure must be built
;     to avoid problems with call/cc.
;
;   * `Eval:benchmark-mode' switch that makes the interpreter skip the
;     global cache check for primitive names.  It's a bit of a joke, but
;     it might improve performance some.
;
;   * We could unroll several cases for eval/setlex just as for eval/lexical.
;
;   * We could have a special case for calling a global variable: the
;     reference to the variable could be lifted out, saving a call to get it.
;
;   Niceties:
;   * In general, it would be nice to be able to give better error messages
;     when calling a procedure that was fetched from a variable, rather than
;     just "#f is not a procedure".
;
;   * Debuggability -- can the procedures be constructed so that they
;     contain the source code for the expression being evaluated?
;
; Bugs
;   It's possible that there should be some restrictions here for
;   certain environment arguments; for example, some environments
;   are immutable (cf the Report).  We can detect immutable arguments
;   at preprocessing time and generate code for setglbl that signals
;   an error if executed (and perhaps a warning during preprocessing).

($$trace "eval")

(define *eval-macro-expander* #f)

(define (eval-macro-expander . rest)
  (cond ((null? rest)
	 (if (not *eval-macro-expander*)
	     macro-expand		; In macro-expand.sch
	     *eval-macro-expander*))
	((null? (cdr rest))
	 (set! *eval-macro-expander* (car rest))
	 *eval-macro-expander*)
	(else
	 (error "Too many arguments to eval-macro-expander."))))

(define eval
  (let ()

    (define (definition? x) (and (pair? x) (eq? (car x) 'define)))
    (define (begin? x) (and (pair? x) (eq? (car x) 'begin)))

    (define (all-definitions? elist)
      (if (null? elist)
	  #t
	  (let ((expr (car elist)))
	    (or (and (definition? expr)
		     (all-definitions? (cdr elist)))
		(and (begin? expr)
		     (all-definitions? (cdr expr))
		     (all-definitions? (cdr elist)))))))

    (define (rewrite-begin-nest elist)
      (if (null? elist)
	  (list (unspecified))
	  (let ((expr (car elist)))
	    (cond ((definition? expr)
		   (cons `(set! ,(cadr expr) ,(caddr expr))
			 (rewrite-begin-nest (cdr elist))))
		  ((begin? expr)
		   (append (rewrite-begin-nest (cdr expr))
			   (rewrite-begin-nest (cdr elist))))
		  (else
		   ???)))))

    (define (toplevel-preprocess expr env)
      (cond ((definition? expr)
	     (really-preprocess `(begin (set! ,(cadr expr) ,(caddr expr))
					,(unspecified))
				env))
	    ((begin? expr)
	     (if (all-definitions? (cdr expr))
		 (really-preprocess (cons 'begin
					  (rewrite-begin-nest (cdr expr)))
				    env)
		 (really-preprocess expr env)))
	    (else
	     (really-preprocess expr env))))

    (define (really-preprocess expr env)
      (eval/preprocess expr 
		       '() 
		       (lambda (sym)
			 (environment-lookup-binding env sym))))

    (define (eval expr . rest)
      (let ((env (cond ((null? rest)
			(interaction-environment))
		       ((and (null? (cdr rest))
			     (environment? (car rest)))
			(car rest))
		       (else
			(error "Eval: bad arguments: " rest)
			#t)))
	    (expr ((eval-macro-expander) expr)))
	((toplevel-preprocess expr env) '())))

    eval))

(define (eval/preprocess expr env find-global)
  (cond ((symbol? expr)
	 (let ((address (eval/var-address expr env)))
	   (if address
	       (eval/lexical (car address) (cdr address) expr)
	       (eval/global expr find-global expr))))
	((pair? expr)
	 (case (car expr)
	   ((quote)  (eval/const (cadr expr)))
	   ((set!)   (let ((address (eval/var-address (cadr expr) env))
			   (rhs
			    (eval/preprocess (caddr expr) env find-global)))
		       (if address
			   (eval/setlex (car address) (cdr address) rhs expr)
			   (eval/setglbl (cadr expr) rhs find-global expr))))
	   ((lambda) (eval/make-proc expr env find-global expr))
	   ((begin)  (if (null? (cdr expr))
			 (begin (error "EVAL: empty BEGIN")
				#t)
			 (eval/sequence
			  (map (lambda (x)
				 (eval/preprocess x env find-global))
			       (cdr expr)))))
	   ((if)     (let ((test
			    (eval/preprocess (cadr expr) env find-global))
			   (*then
			    (eval/preprocess (caddr expr) env find-global))
			   (*else
			    (if (null? (cdddr expr))
				(eval/const (unspecified))
				(eval/preprocess (cadddr expr) env
						 find-global))))
		       (eval/if test *then *else expr)))
	   (else     (eval/make-call expr env find-global))))
	((eval/self-evaluating? expr)
	 (eval/const expr))
	(else
	 (error "EVAL: preprocess: unknown expression: " expr)
	 #t)))

(define (eval/self-evaluating? expr)
  (or (procedure? expr) 
      (bytevector-like? expr)
      (vector-like? expr)
      (boolean? expr)
      (number? expr)
      (char? expr)
      (eq? expr (unspecified))
      (eq? expr (undefined))
      (eof-object? expr)))

; Closure creation.  Special cases handled: 
;  - procedures of 0..4 arguments.
;  - varargs procedures.

(define (eval/make-proc expr env find-global src)

  (define (listify x)
    (cond ((null? x) x)
	  ((pair? x) (cons (car x) (listify (cdr x))))
	  (else (list x))))

  (define (fixed-args x n)
    (if (pair? x)
	(fixed-args (cdr x) (+ n 1))
	n))

  (let* ((args  (cadr expr))
	 (body  (cddr expr))
	 (nenv  (eval/extend-env env (listify args)))
	 (exprs (eval/preprocess (cons 'begin body) nenv find-global)))
    (if (list? args)
	(case (length args)
	  ((0) (eval/lambda0 exprs src))
	  ((1) (eval/lambda1 exprs src))
	  ((2) (eval/lambda2 exprs src))
	  ((3) (eval/lambda3 exprs src))
	  ((4) (eval/lambda4 exprs src))
	  (else (eval/lambda-n (length args) exprs src)))
	(eval/lambda-dot (fixed-args args 0) exprs src))))

; Procedure call.  Special cases handled:
;  - letrec:  ((lambda (a b ...) ...) #!unspecified ...)
;  - primitive: (op a b ...)
;  - short: 0..4 arguments

(define (eval/make-call expr env find-global)

  (define (lambda? op)
    (and (pair? op)
	 (eq? (car op) 'lambda)))

  (define (let? op n)
    (and (lambda? op)
	 (list? (cadr op))
	 (= (length (cadr op)) n)))

  (define unspecd `',(unspecified))

  (define (letrec? op n args)
    (and (let? op n)
	 (not (null? (cadr op)))
	 (every? (lambda (v) (equal? v unspecd))
		 args)))

  (let* ((pexps (map (lambda (x) (eval/preprocess x env find-global)) expr))
	 (proc  (car pexps))
	 (args  (cdr pexps))
	 (n     (length args)))
    (cond ;((letrec? (car expr) n (cdr expr))
	  ; (eval/invoke-letrec 
	  ; (eval/preprocess (cons 'begin (cddar expr)) env find-global)
	  ; (length args)))
	  ((<= n 4)
	   (eval/invoke-short proc args (car expr) n env find-global))
	  (else
	   (eval/invoke-n proc args)))))

(define (eval/extend-env env names)
  (cons names env))

(define (eval/var-address name env)
  (let r-loop ((env env) (i 0))
    (if (null? env)
	#f
	(let a-loop ((rib (car env)) (j 0))
	  (cond ((null? rib)
		 (r-loop (cdr env) (+ i 1)))
		((eq? (car rib) name)
		 (cons i j))
		(else
		 (a-loop (cdr rib) (+ j 1))))))))

(define (eval/global name find-global src)
  (let ((cell (find-global name)))
    (evaluator-procedure
     (lambda (env)
       (let ((v (car cell)))
	 (if (eq? v (undefined))
	     (begin
	       (error "Reference to undefined global variable `" name "'.")
	       #t)
	     v)))
     src)))

(define (eval/setglbl name expr find-global src)
  (let ((cell (find-global name)))
    (evaluator-procedure 
     (lambda (env)
       (set-car! cell (expr env)))
     src)))

; Unroll loop for the closest ribs.

(define (eval/lexical rib offset src)
  (case rib
    ((0) (eval/lexical0 offset src))
    ((1) (eval/lexical1 offset src))
    ((2) (eval/lexical2 offset src))
    ((3) (eval/lexical3 offset src))
    (else (eval/lexical-n rib offset src))))

(define (eval/lexical0 offset src)
  (evaluator-procedure
   (lambda (env)
     (vector-ref (car env) offset))
   src))

(define (eval/lexical1 offset src)
  (evaluator-procedure
   (lambda (env)
     (vector-ref (cadr env) offset))
   src))

(define (eval/lexical2 offset src)
  (evaluator-procedure
   (lambda (env)
     (vector-ref (caddr env) offset))
   src))

(define (eval/lexical3 offset src)
  (evaluator-procedure
   (lambda (env)
     (vector-ref (cadddr env) offset))
   src))

(define (eval/lexical-n rib offset src)
  (evaluator-procedure
   (lambda (env0)
     (let loop ((rib rib) (env env0))
       (if (= rib 0)
	   (vector-ref (car env) offset)
	   (loop (- rib 1) (cdr env)))))
   src))

(define (eval/setlex rib offset expr src)
  (evaluator-procedure
   (lambda (env0)
     (let loop ((rib rib) (env env0))
       (if (= rib 0)
	   (vector-set! (car env) offset (expr env0))
	   (loop (- rib 1) (cdr env)))))
   src))

(define (eval/const c)
  (evaluator-procedure
   (lambda (env)
     c)
   c))

(define (eval/if test consequent alternate src)
  (evaluator-procedure
   (lambda (env)
     (if (test env) (consequent env) (alternate env)))
   src))

; Special cases: 1..4 expressions.

(define (eval/sequence exprs)
  (case (length exprs)
    ((1) (car exprs))
    ((2) (eval/sequence2 (car exprs) (cadr exprs)))
    ((3) (eval/sequence3 (car exprs) (cadr exprs) (caddr exprs)))
    ((4) (eval/sequence4 (car exprs) (cadr exprs) (caddr exprs)
			 (cadddr exprs)))
    (else (eval/sequence-n exprs))))

(define (eval/sequence2 a b)
  (lambda (env)
    (a env) (b env)))

(define (eval/sequence3 a b c)
  (lambda (env)
    (a env) (b env) (c env)))

(define (eval/sequence4 a b c d)
  (lambda (env)
    (a env) (b env) (c env) (d env)))

(define (eval/sequence-n exprs)
  (lambda (env)
    (let loop ((exprs exprs))
      (cond ((null? (cdr exprs))
	     ((car exprs) env))
	    (else
	     ((car exprs) env)
	     (loop (cdr exprs)))))))

(define (eval/invoke-prim1 name a find-global)
  ((eval/primitive name 1) a (eval/prim-orig name) (find-global name)))

(define (eval/invoke-prim2 name a b find-global)
  ((eval/primitive name 2) a b (eval/prim-orig name) (find-global name)))

; Call to a literal lambda expression where all the arguments are
; (quote #!unspecified).  Could be generalized to where all are the same
; constant, or indeed to the case where all arguments are constants.

(define (eval/invoke-letrec lambda-body n)
  (lambda (env)
    (let ((env (cons (make-vector n (unspecified)) env)))
      ((lambda-body env)))))

; Calls that take 0..4 arguments.

(define (eval/invoke-short proc args op n env find-global)

  (define (prim?)
    (and (symbol? op)
	 (not (eval/var-address op env))
	 (eval/primitive? op n)))

  (case n
    ((0) (eval/invoke0 proc))
    ((1) (if (prim?)
	     (eval/invoke-prim1 op (car args) find-global)
	     (eval/invoke1 proc (car args))))
    ((2) (if (prim?)
	     (eval/invoke-prim2 op (car args) (cadr args) find-global)
	     (eval/invoke2 proc (car args) (cadr args))))
    ((3) (eval/invoke3 proc (car args) (cadr args) (caddr args)))
    ((4) (eval/invoke4 proc (car args) (cadr args) (caddr args) (cadddr args)))
    (else ???)))

(define (eval/invoke0 proc)
  (lambda (env)
    ((proc env))))

(define (eval/invoke1 proc a)
  (lambda (env)
    ((proc env) (a env))))

(define (eval/invoke2 proc a b)
  (lambda (env)
    ((proc env) (a env) (b env))))

(define (eval/invoke3 proc a b c)
  (lambda (env)
    ((proc env) (a env) (b env) (c env))))

(define (eval/invoke4 proc a b c d)
  (lambda (env)
    ((proc env) (a env) (b env) (c env) (d env))))

(define (eval/invoke-n proc args)
  (lambda (env)
    (let ((proc (proc env))
	  (args (map (lambda (p) (p env)) args)))
      (apply proc args))))

; Closure creation.
;
; If 'vector' were faster, it would be a better choice for constructing 
; ribs than make-vector + vector-set!.

(define (eval/lambda0 body src)
  (lambda (env)
    (evaluator-procedure
     (lambda ()
       (body (cons '#() env)))
     src)))

(define (eval/lambda1 body src)
  (lambda (env)
    (evaluator-procedure
     (lambda (a)
       (let ((v (make-vector 1 a)))
	 (body (cons v env))))
     src)))

(define (eval/lambda2 body src)
  (lambda (env)
    (evaluator-procedure
     (lambda (a b)
       (let ((v (make-vector 2 a)))
	 (vector-set! v 1 b)
	 (body (cons v env))))
     src)))

(define (eval/lambda3 body src)
  (lambda (env)
    (evaluator-procedure
     (lambda (a b c)
       (let ((v (make-vector 3 a)))
	 (vector-set! v 1 b)
	 (vector-set! v 2 c)
	 (body (cons v env))))
     src)))

(define (eval/lambda4 body src)
  (evaluator-procedure
   (lambda (env)
     (lambda (a b c d)
       (let ((v (make-vector 4 a)))
	 (vector-set! v 1 b)
	 (vector-set! v 2 c)
	 (vector-set! v 3 d)
	 (body (cons v env)))))
   src))

(define (eval/lambda-n n body src)
  (evaluator-procedure
   (lambda (env)
     (lambda args
       (body (cons (list->vector args) env))))
   src))

; `n' is the number of fixed arguments.

(define (eval/lambda-dot n body src)
  (evaluator-procedure
   (lambda (env)
     (lambda args
       (let ((l (length args))
	     (v (make-vector (+ n 1) (unspecified))))
	 (if (< l n)
	     (error "Too few arguments to procedure."))
	 (do ((args args (cdr args))
	      (i 0 (+ i 1)))
	     ((= i n)
	      (vector-set! v i args)
	      (body (cons v env)))
	   (vector-set! v i (car args))))))
   src))

;;; Debugger support

(define (evaluator-procedure proc doc)
  (let* ((l (procedure-length proc))
	 (p (make-procedure (+ l 1))))
    (do ((i 0 (+ i 1)))
	((= i l))
      (procedure-set! p i (procedure-ref proc i)))
    (procedure-set! p l doc)
    (typetag-set! p 0)
    p))

; eof
