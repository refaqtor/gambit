;;==============================================================================

;;; File: "_t-cpu-backend-x86.scm"

;;; Copyright (c) 2018 by Laurent Huberdeau, All Rights Reserved.

(include "generic.scm")

(include-adt "_x86#.scm")
(include-adt "_asm#.scm")
(include-adt "_codegen#.scm")

;;------------------------------------------------------------------------------

;; Constants

; (define x86-narg-register  (x86-cl))  ;; number of arguments register

(define nb-gvm-regs 5)
(define nb-arg-regs 3)

;;------------------------------------------------------------------------------
;;----------------------------  x86 32-bit backend  ----------------------------
;;------------------------------------------------------------------------------

(define (x86-32-target)
  (make-cpu-target
    (x86-32-abstract-machine-info)
    'x86 '((".c" . X86)) nb-gvm-regs nb-arg-regs))

(define (x86-32-abstract-machine-info)
  (make-backend make-cgc-x86-32 (x86-32-info) (x86-instructions) (x86-routines)))

(define (make-cgc-x86-32)
  (let ((cgc (make-codegen-context)))
    (codegen-context-listing-format-set! cgc 'gnu)
    (asm-init-code-block cgc 0 'le)
    (x86-arch-set! cgc 'x86-32)
    cgc))

;;------------------------------------------------------------------------------
;;----------------------------  x86 64-bit backend  ----------------------------
;;------------------------------------------------------------------------------

(define (x86-64-target)
  (make-cpu-target
    (x86-64-abstract-machine-info)
    'x86-64 '((".c" . X86-64)) nb-gvm-regs nb-arg-regs))

(define (x86-64-abstract-machine-info)
  (make-backend make-cgc-x86-64 (x86-64-info) (x86-instructions) (x86-routines)))

(define (make-cgc-x86-64)
  (let ((cgc (make-codegen-context)))
    (codegen-context-listing-format-set! cgc 'gnu)
    (asm-init-code-block cgc 0 'le)
    (x86-arch-set! cgc 'x86-64)
    cgc))

;;------------------------------------------------------------------------------

;; x86 backend info

(define (x86-32-info)
  (make-cpu-info
    4                         ;; Word width
    'le                       ;; Endianness
    FORCE_LOAD_STORE_ARCH     ;; Load store architecture?
    0                         ;; Frame offset
    primitive-object-table    ;; Primitive table
    nb-gvm-regs               ;; GVM register count
    nb-arg-regs               ;; GVM register count for passing arguments
    x86-32-registers          ;; Main registers
    (x86-ecx)                 ;; Processor state pointer
    (x86-esp)                 ;; Stack pointer
    (x86-ebp)                 ;; Heap pointer
  ))

(define x86-32-registers
  (vector
    (x86-edi)   ;; R0
    (x86-eax)   ;; R1
    (x86-ebx)   ;; R2
    (x86-edx)   ;; R3
    (x86-esi))) ;; R4

;;------------------------------------------------------------------------------

;; x86 64-bit backend info

(define (x86-64-info)
  (make-cpu-info
    8                         ;; Word width
    'le                       ;; Endianness
    FORCE_LOAD_STORE_ARCH     ;; Load store architecture?
    0                         ;; Frame offset
    primitive-object-table    ;; Primitive table
    nb-gvm-regs               ;; GVM register count
    nb-arg-regs               ;; GVM register count for passing arguments
    x86-64-registers          ;; Main registers
    (x86-rcx)                 ;; Processor state pointer
    (x86-rsp)                 ;; Stack pointer
    (x86-rbp)                 ;; Heap pointer
  ))

;; Registers
(define x86-64-registers
  (vector
    (x86-rdi) ;; R0
    (x86-rax) ;; R1
    (x86-rbx) ;; R2
    (x86-rdx) ;; R3
    (x86-rsi) ;; R4
    (x86-r8)
    (x86-r9)
    (x86-r10)
    (x86-r11)
    (x86-r12)
    (x86-r13)
    (x86-r14)
    (x86-r15)))

;;------------------------------------------------------------------------------

;; x86 Abstract machine instructions

(define (x86-instructions)
  (make-instruction-dictionnary
    x86-label-align         ;; am-lbl
    data-instr              ;; am-data
    mov-instr               ;; am-mov
    (arith-instr x86-add)   ;; am-add
    (arith-instr x86-sub)   ;; am-sub
    (arith-instr x86-shr)   ;; am-bit-shift-right
    (arith-instr x86-shl)   ;; am-bit-shift-left
    (arith-instr x86-not)   ;; am-not
    (arith-instr x86-and)   ;; am-and
    (arith-instr x86-or)    ;; am-or
    (arith-instr x86-xor)   ;; am-xor
    x86-jmp-instr           ;; am-jmp
    cmp-jump-instr          ;; am-compare-jump
    cmp-move-instr))        ;; am-compare-move

(define (make-x86-opnd opnd)
  (cond
    ((reg-opnd? opnd) opnd)
    ((int-opnd? opnd) (x86-imm-int (int-opnd-value opnd)))
    ((mem-opnd? opnd) (x86-mem (mem-opnd-offset opnd) (mem-opnd-base opnd)))
    ((lbl-opnd? opnd) (x86-imm-lbl (lbl-opnd-label opnd) (lbl-opnd-offset opnd)))
    ((obj-opnd? opnd) (x86-imm-obj (obj-opnd-value opnd)))
    ((glo-opnd? opnd) (x86-imm-glo (glo-opnd-name opnd)))
    (else (compiler-internal-error "make-x86-opnd - Unknown opnd: " opnd))))

; (define (apply-and-mov fun)
;   (lambda (cgc result-reg opnd1 opnd2)
;     (if (equal? result-reg opnd1)
;         (fun cgc result-reg opnd2)
;         (begin
;           (x86-mov cgc result-reg opnd1)
;           (fun cgc result-reg opnd2)))))

(define (arith-instr instr)
  (lambda (cgc result-loc opnd1 opnd2)
    (let ((x86-result-loc (make-x86-opnd result-loc))
          (x86-opnd1 (make-x86-opnd opnd1))
          (x86-opnd2 (make-x86-opnd opnd2)))
      (if (equal? result-loc opnd1)
          (instr cgc x86-result-loc x86-opnd2)
          (begin
            (x86-mov cgc x86-result-loc x86-opnd1)
            (instr cgc x86-result-loc x86-opnd2))))))

(define (x86-label-align cgc label-opnd #!optional (align #f))
  (if align (asm-align cgc (car align) (cdr align) #x90))
  (x86-label cgc (lbl-opnd-label label-opnd)))

(define data-instr
  (make-am-data x86-db x86-dw x86-dd x86-dq))

;; Args : CGC, reg/mem/label, reg/mem/imm/label
;; Todo: Check if some cases can be eliminated
(define (mov-instr cgc dst src #!optional (width #f))
  (define dst-type (opnd-type dst))
  (define src-type (opnd-type src))

  (define x86-src (make-x86-opnd src))
  (define x86-dst (make-x86-opnd dst))

  ;; new-src can be directly used as an operand to mov
  (define (mov-in-dst new-src)
    (define x86-new-src (make-x86-opnd new-src))
    (if (not (equal? dst new-src))
      (if (equal? dst-type 'ind)
        (get-free-register cgc (list dst new-src)
          (lambda (reg-dst)
            (x86-mov cgc reg-dst x86-dst)
            (x86-mov cgc (x86-mem 0 reg-dst) x86-new-src width)))
        (x86-mov cgc x86-dst x86-new-src width))))

  (if (not (equal? dst src))
    (cond
      ((and
        (or (equal? dst-type 'mem) (equal? dst-type 'ind))
        (or (equal? src-type 'mem) (equal? src-type 'lbl)))
          (get-free-register cgc (list src)
            (lambda (reg-src)
              (x86-mov cgc reg-src x86-src)
              (mov-in-dst reg-src))))

      ((equal? src-type 'ind)
        (let ((action
                (lambda (reg-src)
                  (x86-mov cgc reg-src x86-src)
                  (x86-mov cgc reg-src (x86-mem 0 reg-src))
                  (mov-in-dst reg-src))))
          (if (equal? dst-type 'reg)
            (action dst)
            (get-free-register cgc (list src) action))))

      (else
        (mov-in-dst src)))))

(define (x86-jmp-instr cgc opnd)
  (if (lbl-opnd? opnd)
    (x86-jmp cgc (lbl-opnd-label opnd))
    (mov-if-necessary cgc '(reg int mem lbl) opnd
      (lambda (opnd)
        (x86-jmp cgc (make-x86-opnd opnd))))))

(define (get-jumps condition)
  (define (flip pair) (cons (cdr pair) (car pair)))

  (case (get-condition condition)
    ((equal)
      (cons x86-je  x86-jne))
    ((greater)
      (cond
        ((and (cond-is-equal condition) (cond-is-signed condition))
          (cons x86-jge x86-jl))
        ((and (not (cond-is-equal condition)) (cond-is-signed condition))
          (cons x86-jg x86-jle))
        ((and (cond-is-equal condition) (not (cond-is-signed condition)))
          (cons x86-jae x86-jb))
        ((and (not (cond-is-equal condition)) (not (cond-is-signed condition)))
          (cons x86-ja x86-jbe))))
    ((not-equal) (flip (get-jumps (inverse-condition condition))))
    ((lesser) (flip (get-jumps (inverse-condition condition))))
    (else
      (compiler-internal-error "get-jumps - Unknown condition: " condition))))

(define (cmp-jump-instr cgc condition opnd1 opnd2 loc-true loc-false #!optional (opnds-width #f))
  (define x86-opnd1 (make-x86-opnd opnd1))
  (define x86-opnd2 (make-x86-opnd opnd2))

  (let* ((jumps (get-jumps condition)))
    ;; In case both jump locations are false, the cmp is unnecessary.
    (if (or loc-true loc-false)
      (mov-if-necessary cgc '(reg mem) opnd1
        (lambda (opnd1) (x86-cmp cgc x86-opnd1 x86-opnd2 opnds-width))))

    (cond
      ((and loc-false loc-true)
        ((car jumps) cgc (lbl-opnd-label loc-true))
        (x86-jmp cgc (lbl-opnd-label loc-false)))
      ((and (not loc-true) loc-false)
        ((cdr jumps) cgc (lbl-opnd-label loc-false)))
      ((and loc-true (not loc-false))
        ((car jumps) cgc (lbl-opnd-label loc-true)))
      (else
        (debug "am-compare-jump: No jump encoded")))))

(define (cmp-move-instr cgc condition dest opnd1 opnd2 true-opnd false-opnd #!optional (opnds-width #f))
  (let* ((jumps (get-jumps condition))
         (label-true (make-unique-label cgc "mov-true" #f))
         (label-false (make-unique-label cgc "mov-false" #f)))
    ;; In case both jump locations are false, the cmp is unnecessary.
    (mov-if-necessary cgc '(reg mem) opnd1
      (lambda (opnd1) (x86-cmp cgc opnd1 opnd2 opnds-width)))

    (cond
      ((and true-opnd false-opnd)
        ((car jumps) cgc label-true)
        (am-mov cgc dest false-opnd)
        (am-jmp cgc label-false)
        (am-lbl cgc label-true)
        (am-mov cgc dest true-opnd)
        (am-lbl cgc label-false))
      ((and (not true-opnd) false-opnd)
        ((car jumps) cgc label-true) ;; Jump if true
        (am-mov cgc dest false-opnd)
        (am-lbl cgc label-true))
      ((and true-opnd (not false-opnd))
        ((cdr jumps) cgc label-false) ;; Jump if false
        (am-mov cgc dest true-opnd)
        (am-lbl cgc label-false))
      (else
        (debug "am-compare-move: No move encoded")))))

;;------------------------------------------------------------------------------

;; Backend routines

(define (x86-routines)
  (make-routine-dictionnary
    x86-poll
    x86-set-nargs
    x86-check-nargs
    x86-check-nargs-simple
    x86-allocate-memory
    x86-place-extra-data))

(define (x86-poll cgc frame)
  (debug "x86-poll")
  (let* ((stack-trip (car (get-processor-state-field cgc 'stack-trip)))
         (temp1 (get-processor-state-field cgc 'temp1))
         (return-loc (make-unique-label cgc "return-from-overflow")))

    (am-compare-jump cgc
      (condition-lesser #f #f)
      (get-frame-pointer cgc) stack-trip
      #f return-loc)

    ;; Jump to handler
    (am-mov cgc (car temp1) return-loc (cdr temp1))
    (call-handler cgc 'handler_stack_limit frame return-loc)))

;; Nargs passing

(define (x86-set-nargs cgc arg-count)
  (debug "x86-set-narg: " arg-count)
  (let ((narg-field (get-processor-state-field cgc 'nargs)))
    (am-mov cgc (car narg-field) (int-opnd arg-count) (cdr narg-field))))

; (define (x86-check-nargs-simple cgc arg-count jmp-loc error-label if-equal?)
;   (debug "x86-check-narg-simple: " arg-count)
;   (let ((narg-field (get-processor-state-field cgc 'nargs)))

;     (x86-cmp cgc (car narg-field) (int-opnd arg-count) (cdr narg-field))
;     (if if-equal?
;       (x86-je cgc jmp-loc)
;       (x86-jne cgc jmp-loc))
;     (x86-jmp cgc error-label)))

(define (x86-check-nargs cgc fun-label fs arg-count optional-args-values rest? place-label-fun)
  (define error-label (make-unique-label cgc "narg-error" #f))
  (debug "x86-check-narg: " arg-count)
  ;; Error handler
  (let ((temp1-field (get-processor-state-field cgc 'temp1))
        (narg-field (get-processor-state-field cgc 'nargs))
        (error-handler (get-processor-state-field cgc 'handler_wrong_nargs)))
    (am-lbl cgc error-label)
    (am-mov cgc (car temp1-field) fun-label (cdr temp1-field))
    (am-jmp cgc (car error-handler))

    (place-label-fun fun-label)

    (am-compare-jump cgc
      condition-not-equal
      (car narg-field) (int-opnd arg-count)
      error-label #f
      (cdr narg-field))))

; (define use-f-flag #t)
; ;; Must be ordered and can't be longer than 5
; (define nargs-passed-in-flags '(0 1 2 3 4))

; (define (narg-index nargs) (index-of nargs nargs-passed-in-flags))
; (define (passed-in-ps nargs) (= -1 (narg-index nargs)))
; (define (passed-in-flags nargs) (not (passed-in-ps nargs)))

; (define (x86-set-nargs cgc nargs)
;   ;; set flags = jb  jne jle jno jp  jbe jl  js   wrong_na = jae
;   (define (flags-a) (x86-cmp cgc x86-narg-register (x86-imm-int -3)))
;   ;; set flags = jae je  jle jno jp  jbe jge jns  wrong_na = jne
;   (define (flags-b) (x86-cmp cgc x86-narg-register x86-narg-register))
;   ;; set flags = jae jne jg  jno jp  ja  jge jns  wrong_na = jle
;   (define (flags-c) (x86-cmp cgc x86-narg-register (x86-imm-int -123)))
;   ;; set flags = jae jne jle jo  jp  ja  jl  jns  wrong_na = jno
;   (define (flags-d) (x86-cmp cgc x86-narg-register (x86-imm-int 10)))
;   ;; set flags = jae jne jle jno jnp ja  jl  js   wrong_na = jp
;   (define (flags-e) (x86-cmp cgc x86-narg-register (x86-imm-int 2)))
;   ;; set flags = jae jne jle jno jp  ja  jl  js
;   (define (flags-f) (x86-cmp cgc x86-narg-register (x86-imm-int 0)))

;   (define (set-ps-na arg-count)
;     (let ((na-opnd (get-processor-state-field cgc 'nargs)))
;       (x86-mov cgc (car na-opnd) (x86-imm-int arg-count) (cdr na-opnd))))

;   (define all-tests
;     (list flags-a flags-b flags-c flags-d flags-e))
;   (define tests
;     (if use-f-flag all-tests (cdr all-tests)))

;   (debug "x86-set-narg: " nargs)

;   (if (passed-in-ps nargs)
;     ;; Use processor state to pass narg
;     (begin
;       (set-ps-na nargs)
;       (if use-f-flag
;         (flags-f)
;         (flags-a)))
;     ;; Use flag register
;     ((list-ref tests (narg-index nargs)))))

; ;; The function returns if it checked the flags
; (define (x86-check-nargs-simple cgc arg-count jmp-loc error-label if-equal?
;           #!optional (check-flags #t))
;   ;; a flags = jb  jne jle jno jp  jbe jl  js   wrong_na = jae
;   ;; b flags = jae je  jle jno jp  jbe jge jns  wrong_na = jne
;   ;; c flags = jae jne jg  jno jp  ja  jge jns  wrong_na = jle
;   ;; d flags = jae jne jle jo  jp  ja  jl  jns  wrong_na = jno
;   ;; e flags = jae jne jle jno jnp ja  jl  js   wrong_na = jp
;   ;; f flags = jae jne jle jno jp  ja  jl  js   no jump
;   (define (check-a label)               (x86-jb  cgc label))
;   (define (check-not-a label)           (x86-jae cgc label))
;   (define (check-b label)               (x86-je  cgc label))
;   (define (check-not-b label)           (x86-jne cgc label))
;   (define (check-c label)               (x86-jg  cgc label))
;   (define (check-not-c label)           (x86-jle cgc label))
;   (define (check-d label)               (x86-jo  cgc label))
;   (define (check-not-d label)           (x86-jno cgc label))
;   (define (check-e label)               (x86-jnp cgc label))
;   (define (check-not-e label)           (x86-jp  cgc label))
;   (define (check-ab label)              (x86-jbe cgc label))
;   (define (check-not-a-or-b label)      (x86-ja  cgc label))
;   (define (check-bc label)              (x86-jge cgc label))
;   (define (check-not-b-or-c label)      (x86-jl  cgc label))
;   (define (check-bcd label)             (x86-jns cgc label))
;   (define (check-not-b-or-c-or-d label) (x86-js  cgc label))

;   (define (check-ps-na arg-count label)
;     (let ((na-opnd (get-processor-state-field cgc 'nargs)))
;       (x86-cmp cgc (car na-opnd) (x86-imm-int arg-count) (cdr na-opnd))
;       (if if-equal?
;         (x86-je cgc label)
;         (x86-jne cgc label))))

;   (define all-negative-tests
;     (list check-not-a check-not-b check-not-c check-not-d check-not-e))
;   (define negative-tests
;     (if use-f-flag all-negative-tests (cdr all-negative-tests)))

;   (define all-positive-tests
;     (list check-a check-b check-c check-d check-e))
;   (define positive-tests
;     (if use-f-flag all-positive-tests (cdr all-positive-tests)))

;   (if (passed-in-ps arg-count)
;     ;; Use processor state to pass narg
;     (begin
;       (if check-flags
;         (if use-f-flag
;           (begin
;             (check-a   error-label)
;             (check-bcd error-label)
;             (check-e   error-label))
;           (check-not-a jmp-loc)))
;       (check-ps-na arg-count jmp-loc)
;       #f)
;     ;; Use flag register
;     (begin
;       ((list-ref
;         (if if-equal? positive-tests negative-tests)
;         (narg-index arg-count))
;         jmp-loc)
;       #t)))

; (define (x86-check-nargs cgc fun-label fs nargs optional-args-values rest? place-label-fun)
;   ;; Constants
;   (define target (codegen-context-target cgc))
;   (define nargs-in-regs (target-nb-arg-regs target))

;   (define nargs-in-flags? (elem? nargs nargs-passed-in-flags))

;   (define opts-count (length optional-args-values))
;   (define nargs-no-rest (- nargs (if rest? 1 0)))
;   (define nargs-no-opts (- nargs-no-rest opts-count))

;   (define continue-label (make-unique-label cgc "continue" #f))
;   (define pop-label      (make-unique-label cgc "restore-flags" #f))
;   (define error-label    (make-unique-label cgc "narg-error" #f))
;   (define rest-label     (make-unique-label cgc "get-rest" #f))

;   (define (make-label-curried prefix)
;     (lambda (i) (make-unique-label cgc
;       (string-append prefix (number->string i)) #f)))

;   (define check-flags #t)
;   ;; Places switch for optional parameters
;   ;; Moves the parameters to the right position if necessary
;   ;; Moves the default values if necessary
;   (define (place-optional-arguments-switch)
;     ;; Places the arguments in their correct place
;     (define (mov-arguments-in-correct-position arg-count)
;       (let ((min-frame-to-move (max 1 (+ 1 (- arg-count nargs-in-regs)))))
;         (for-each
;           (lambda (n)
;             (let ((dst (get-nth-arg cgc fs nargs n))
;                   (src (get-nth-arg cgc fs arg-count n)))
;               (am-mov cgc dst src (get-word-width-bits cgc))))
;           (iota min-frame-to-move arg-count))))

;     (define (place-case arg-count case-label next-case-label)
;       (debug "place-case: " arg-count)
;       (am-lbl cgc case-label)
;       (if (not (x86-check-nargs-simple cgc arg-count next-case-label error-label #f check-flags))
;         (set! check-flags #f))

;       ;; Merge with x86-frame-pointer adjustement
;       (if (and rest? (not nargs-in-flags?)) (x86-popf cgc))

;       ;; When called with not all arguments, the frame size needs to be adjusted.
;       (let* ((nargs-in-frames (max 0 (- arg-count nargs-in-regs)))
;              (offset (- fs nargs-in-frames)))
;         (if (not (= 0 offset))
;           (am-sub cgc
;             (get-frame-pointer cgc)
;             (get-frame-pointer cgc)
;             (int-opnd (* (get-word-width cgc) offset)))))

;       (mov-arguments-in-correct-position arg-count)

;       ;; Places the default values
;       (let* ((optional-opnds
;               (map (lambda (val) (make-opnd cgc val)) optional-args-values))
;             (default-values-to-move
;               (drop-n optional-opnds (- arg-count nargs-no-opts))))

;         (for-each
;           (lambda (default-value i)
;             (am-mov cgc
;               (get-nth-arg cgc fs nargs (+ arg-count i 1))
;               default-value
;               (get-word-width-bits cgc)))

;           default-values-to-move
;           (iota 0 (length default-values-to-move)))

;         ;; Place empty list
;         (if rest?
;           (am-mov cgc
;             (get-nth-arg cgc fs nargs nargs)
;             (obj-opnd '())
;             (get-word-width-bits cgc))))

;       (am-jmp cgc continue-label))

;     (debug "place-optional-arguments-switch")
;     (let* ((nargs-to-test (iota nargs-no-opts nargs-no-rest))
;            (last-label (if rest? rest-label error-label)))

;       ;; Because testing ps->nargs changes the flags register,
;       ;; we need to test the flags first. We then test ps->na.
;       (let* ((nargs-to-test-flags (filter
;                 (lambda (n) (elem? n nargs-passed-in-flags))
;                 nargs-to-test))
;              (nargs-to-test-ps (filter
;                 (lambda (n) (not (elem? n nargs-passed-in-flags)))
;                 nargs-to-test))
;              (cases (append nargs-to-test-flags nargs-to-test-ps))
;              (case-labels (map (make-label-curried "opt-case_") cases)))
;         (if (not (null? case-labels))
;           (for-each place-case
;             cases
;             case-labels
;             (append (cdr case-labels) (list last-label)))))))

;   (define (place-get-rest-code)
;     (let* ((invalid-flags-to-test
;              (filter
;                 (lambda (n) (< n nargs-no-rest))
;                 nargs-passed-in-flags))
;            (call-rest-handler (make-unique-label cgc "call-rest-handler" #f))
;            (return-from-get-rest (make-unique-label cgc "return-from-get-rest" #f))
;            (narg-field (get-processor-state-field cgc 'nargs))
;            (temp1-field (get-processor-state-field cgc 'temp1))
;            (rest-handler (get-processor-state-field cgc 'handler_get_rest)))

;       ;; Optimize case with 0 elem
;       ;; Todo: Fix case where nargs-passed-in-flags doesn't contain 0.
;       ;; Maybe replace check-flags by #f. Check if doesn't break everything...
;       (x86-check-nargs-simple cgc nargs-no-rest call-rest-handler error-label #f check-flags)
;       (if (not nargs-in-flags?) (x86-popf cgc))   ;; Replace with pop? Maybe faster
;       (am-mov cgc
;         (get-nth-arg cgc fs nargs nargs)
;         (obj-opnd '())
;         (get-word-width-bits cgc))
;       (am-sub cgc                           ;; Adjusts the frame pointer
;         (get-frame-pointer cgc)
;         (get-frame-pointer cgc)
;         (int-opnd (* (get-word-width cgc) 1)))
;       (am-jmp cgc continue-label)

;       (am-lbl cgc call-rest-handler)
;       (if nargs-in-flags? (x86-pushf cgc)) ;; Save flags if not saved before
;       (x86-cmp cgc (car narg-field) (int-opnd 0) (cdr narg-field))
;       (x86-js cgc return-from-get-rest)
;       (x86-popf cgc)

;       ;; Jump to rest handler here
;       (am-mov cgc (car temp1-field) fun-label (cdr temp1-field))
;       (am-jmp cgc (car rest-handler))

;       ;; Jump to continue after restoring flags
;       (am-lbl cgc return-from-get-rest)
;       (x86-popf cgc)
;       (am-mov cgc
;         (car narg-field)
;         (int-opnd 0)
;         (cdr narg-field))
;       (am-jmp cgc continue-label)))

;   (debug "x86-check-narg: " nargs)

;   ;; Error handler
;   (let ((temp1-field (get-processor-state-field cgc 'temp1))
;         (narg-field (get-processor-state-field cgc 'nargs))
;         (error-handler (get-processor-state-field cgc 'handler_wrong_nargs)))
;     (am-lbl cgc error-label)
;     (if (not nargs-in-flags?) (x86-popf cgc))
;     (am-mov cgc (car temp1-field) fun-label (cdr temp1-field))
;     (am-jmp cgc (car error-handler)))

;   (place-label-fun fun-label)

;   (if (and (null? optional-args-values) (not rest?))
;     ;; Basic case
;     (if nargs-in-flags?
;         (x86-check-nargs-simple cgc nargs error-label error-label #f)
;         (begin
;           (x86-pushf cgc)
;           (x86-check-nargs-simple cgc nargs error-label error-label #f)))
;           ;; Then continues to pop-label

;     ;; Optional and rest arguments case
;     (if rest?
;       ;; If rest
;       (begin
;         ;; Save flags register if necessary
;         (if (not nargs-in-flags?) (x86-pushf cgc))
;         (if (not (= 0 opts-count))
;           (place-optional-arguments-switch))
;         (am-lbl cgc rest-label)
;         (place-get-rest-code))

;       ;; If not rest
;       (place-optional-arguments-switch)))

;   (if (not nargs-in-flags?)
;     (begin
;       (am-lbl cgc pop-label)
;       (x86-popf cgc)))
;   (am-lbl cgc continue-label))

(define (x86-allocate-memory cgc dest-reg bytes offset frame)
  (let* ((stack-trip (car (get-processor-state-field cgc 'stack-trip)))
          (temp1 (get-processor-state-field cgc 'temp1))
          (return-loc (make-unique-label cgc "return-from-gc")))

      (x86-lea cgc dest-reg (make-x86-opnd (mem-opnd (get-heap-pointer cgc) offset)))
      (x86-add cgc (get-heap-pointer cgc) (make-x86-opnd (int-opnd bytes)))

      (am-compare-jump cgc
        (condition-lesser #f #f)
        (get-frame-pointer cgc) stack-trip
        #f return-loc)

      ;; Jump to handler
      (am-mov cgc (car temp1) return-loc (cdr temp1))
      (call-handler cgc 'handler_heap_limit frame return-loc)))

(define (x86-place-extra-data cgc)
  (debug "place-extra-data"))

;; Utils

(define (call-handler cgc sym frame return-loc)
  (let* ((handler-loc (car (get-processor-state-field cgc sym))))
    (debug "handler-loc: " handler-loc)
    (jump-with-return-point cgc handler-loc return-loc frame #t)))

;;------------------------------------------------------------------------------

;; Primitives

(define (make-function-opnds func)
  (lambda (cgc . args) (apply func (cons cgc (map make-x86-opnd args)))))

(define x86-prim-fx+
  (foldl-prim
    (make-function-opnds x86-add)
    allowed-opnds: '(reg mem int)
    allowed-opnds-accum: '(reg mem)
    start-value: 0
    start-value-null?: #t
    reduce-1: am-mov
    commutative: #t))

(define x86-prim-fx-
  (foldl-prim
    (make-function-opnds x86-sub)
    allowed-opnds: '(reg mem int)
    allowed-opnds-accum: '(reg mem)
    ; start-value: 0 ;; Start the fold on the first operand
    reduce-1: (lambda (cgc dst opnd) (am-sub cgc dst (int-opnd 0) opnd))
    commutative: #f))

(define x86-prim-fx<
  (foldl-compare-prim
    (lambda (cgc opnd1 opnd2 true-label false-label)
      (am-compare-jump cgc
        (condition-lesser #t #t)
        opnd1 opnd2
        false-label true-label
        (get-word-width-bits cgc)))
    allowed-opnds1: '(reg mem)
    allowed-opnds2: '(reg int)))

(define x86-prim-fx<=
  (foldl-compare-prim
    (lambda (cgc opnd1 opnd2 true-label false-label)
      (am-compare-jump cgc
        (condition-lesser #f #t)
        opnd1 opnd2
        false-label true-label
        (get-word-width-bits cgc)))
    allowed-opnds1: '(reg mem)
    allowed-opnds2: '(reg int)))

(define x86-prim-fx>
  (foldl-compare-prim
    (lambda (cgc opnd1 opnd2 true-label false-label)
      (am-compare-jump cgc
        (condition-greater #t #t)
        opnd1 opnd2
        false-label true-label
        (get-word-width-bits cgc)))
    allowed-opnds1: '(reg mem)
    allowed-opnds2: '(reg int)))

(define x86-prim-fx>=
  (foldl-compare-prim
    (lambda (cgc opnd1 opnd2 true-label false-label)
      (am-compare-jump cgc
        (condition-greater #f #t)
        opnd1 opnd2
        false-label true-label
        (get-word-width-bits cgc)))
    allowed-opnds1: '(reg mem)
    allowed-opnds2: '(reg int)))

(define x86-prim-fx=
  (foldl-compare-prim
    (lambda (cgc opnd1 opnd2 true-label false-label)
      (am-compare-jump cgc
        condition-not-equal
        opnd1 opnd2
        false-label true-label
        (get-word-width-bits cgc)))
    allowed-opnds1: '(reg mem)
    allowed-opnds2: '(reg int)))

(define x86-prim-##cons
  (lambda (cgc result-action args)
    (with-result-opnd cgc result-action args
      allowed-opnds: '(reg)
      fun:
        (lambda (result-reg result-opnd-in-args)
          (let* ((word (get-word-width cgc))
                 (size (* word 3))
                 (tag 3)
                 (offset (+ tag (* 2 word))))

            (am-allocate-memory cgc result-reg size offset
              (codegen-context-frame cgc))

            (am-mov cgc
              (mem-opnd result-reg (- offset))
              (int-opnd (* 8 3))
              (get-word-width-bits cgc))

            (am-mov cgc
              (mem-opnd result-reg (- word offset))
              (cadr args)
              (get-word-width-bits cgc))

            (am-mov cgc
              (mem-opnd result-reg (- (* 2 word) offset))
              (car args)
              (get-word-width-bits cgc)))))))

(define x86-prim-##null?
  (lambda (cgc result-action args)
    (check-nargs-if-necessary cgc result-action 1)
    (call-with-nargs args
      (lambda (arg1)
        (am-if-eq cgc arg1 (make-obj-opnd cgc '())
          (lambda (cgc) (am-return-const cgc result-action #t))
          (lambda (cgc) (am-return-const cgc result-action #f))
          #f
          (get-word-width-bits cgc))))))

(define primitive-object-table
  (let ((table (make-table test: equal?)))
    (table-set! table '##identity (make-prim-obj ##identity-primitive 1 #t #t))
    (table-set! table '##not      (make-prim-obj ##not 1 #t #t))

    (table-set! table '##fx+      (make-prim-obj x86-prim-fx+  2 #t #f))
    (table-set! table '##fx-      (make-prim-obj x86-prim-fx-  2 #t #f))
    (table-set! table '##fx<      (make-prim-obj x86-prim-fx<  2 #t #t))
    (table-set! table '##fx<=     (make-prim-obj x86-prim-fx<= 2 #t #t))
    (table-set! table '##fx>      (make-prim-obj x86-prim-fx>  2 #t #t))
    (table-set! table '##fx>=     (make-prim-obj x86-prim-fx>= 2 #t #t))
    (table-set! table '##fx=      (make-prim-obj x86-prim-fx=  2 #t #t))

    (table-set! table '##car      (make-prim-obj (object-read-prim pair-obj-desc 1) 1 #t #f))
    (table-set! table '##cdr      (make-prim-obj (object-read-prim pair-obj-desc 0) 1 #t #f))
    (table-set! table '##set-car! (make-prim-obj (object-set-prim pair-obj-desc 1) 2 #t #f))
    (table-set! table '##set-cdr! (make-prim-obj (object-set-prim pair-obj-desc 0) 2 #t #f))
    (table-set! table '##cons     (make-prim-obj x86-prim-##cons 2 #t #f))
    (table-set! table '##null?    (make-prim-obj x86-prim-##null? 2 #t #f))

    table))