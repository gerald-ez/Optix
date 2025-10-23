;; Options Trading Contract
;; A decentralized options trading platform for STX

;; Error constants
(define-constant ERR-OPTION-NOT-FOUND (err u1800))
(define-constant ERR-OPTION-EXPIRED (err u1801))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u1802))
(define-constant ERR-NOT-AUTHORIZED (err u1803))
(define-constant ERR-INVALID-STRIKE (err u1804))
(define-constant ERR-ALREADY-EXERCISED (err u1805))
(define-constant ERR-OUT-OF-MONEY (err u1806))
(define-constant ERR-INVALID-PREMIUM (err u1807))

;; Constants
(define-constant OPTION-CALL u0)
(define-constant OPTION-PUT u1)
(define-constant OPTION-ACTIVE u0)
(define-constant OPTION-EXERCISED u1)
(define-constant OPTION-EXPIRED u2)

;; Data variables
(define-data-var option-counter uint u0)
(define-data-var oracle principal tx-sender) ;; Price oracle

;; Data maps
(define-map options
  { option-id: uint }
  {
    writer: principal,
    holder: (optional principal),
    option-type: uint, ;; 0 = call, 1 = put
    strike-price: uint,
    premium: uint,
    expiry-block: uint,
    collateral-amount: uint,
    status: uint,
    created-at: uint,
    underlying-asset: (string-ascii 10)
  }
)

(define-map option-collateral
  { option-id: uint }
  { locked-amount: uint, released: bool }
)

(define-map user-positions
  { user: principal, option-id: uint }
  { position-type: (string-ascii 10), entry-price: uint } ;; "long" or "short"
)

(define-map market-prices
  { asset: (string-ascii 10) }
  { price: uint, last-updated: uint }
)

(define-map exercise-history
  { option-id: uint }
  {
    exercised-at: uint,
    exercise-price: uint,
    profit: uint
  }
)

;; Write/Create an option
(define-public (write-option
  (option-type uint)
  (strike-price uint)
  (premium uint)
  (expiry-duration uint)
  (underlying-asset (string-ascii 10))
)
  (let
    (
      (option-id (+ (var-get option-counter) u1))
      (expiry-block (+ block-height expiry-duration))
      (collateral-needed (if (is-eq option-type OPTION-CALL) 
        strike-price  ;; For calls, collateral is the underlying
        strike-price  ;; For puts, collateral is STX
      ))
    )
    (asserts! (or (is-eq option-type OPTION-CALL) (is-eq option-type OPTION-PUT)) ERR-INVALID-STRIKE)
    (asserts! (> strike-price u0) ERR-INVALID-STRIKE)
    (asserts! (> premium u0) ERR-INVALID-PREMIUM)
    (asserts! (> expiry-duration u144) ERR-OPTION-EXPIRED) ;; Min 1 day
    (asserts! (>= (stx-get-balance tx-sender) collateral-needed) ERR-INSUFFICIENT-COLLATERAL)
    
    ;; Lock collateral
    (try! (stx-transfer? collateral-needed tx-sender (as-contract tx-sender)))
    
    ;; Create option
    (map-set options
      { option-id: option-id }
      {
        writer: tx-sender,
        holder: none,
        option-type: option-type,
        strike-price: strike-price,
        premium: premium,
        expiry-block: expiry-block,
        collateral-amount: collateral-needed,
        status: OPTION-ACTIVE,
        created-at: block-height,
        underlying-asset: underlying-asset
      }
    )
    
    ;; Lock collateral record
    (map-set option-collateral
      { option-id: option-id }
      { locked-amount: collateral-needed, released: false }
    )
    
    ;; Record writer position
    (map-set user-positions
      { user: tx-sender, option-id: option-id }
      { position-type: "short", entry-price: premium }
    )
    
    (var-set option-counter option-id)
    (ok option-id)
  )
)

;; Buy an option
(define-public (buy-option (option-id uint))
  (let
    (
      (option-data (unwrap! (map-get? options { option-id: option-id }) ERR-OPTION-NOT-FOUND))
      (premium (get premium option-data))
    )
    (asserts! (is-eq (get status option-data) OPTION-ACTIVE) ERR-ALREADY-EXERCISED)
    (asserts! (<= block-height (get expiry-block option-data)) ERR-OPTION-EXPIRED)
    (asserts! (is-none (get holder option-data)) ERR-ALREADY-EXERCISED)
    (asserts! (not (is-eq tx-sender (get writer option-data))) ERR-NOT-AUTHORIZED)
    (asserts! (>= (stx-get-balance tx-sender) premium) ERR-INSUFFICIENT-COLLATERAL)
    
    ;; Transfer premium to writer
    (try! (stx-transfer? premium tx-sender (get writer option-data)))
    
    ;; Update option holder
    (map-set options
      { option-id: option-id }
      (merge option-data { holder: (some tx-sender) })
    )
    
    ;; Record buyer position
    (map-set user-positions
      { user: tx-sender, option-id: option-id }
      { position-type: "long", entry-price: premium }
    )
    
    (ok true)
  )
)

;; Exercise an option
(define-public (exercise-option (option-id uint) (current-price uint))
  (let
    (
      (option-data (unwrap! (map-get? options { option-id: option-id }) ERR-OPTION-NOT-FOUND))
      (collateral-data (unwrap! (map-get? option-collateral { option-id: option-id }) ERR-OPTION-NOT-FOUND))
      (holder (unwrap! (get holder option-data) ERR-NOT-AUTHORIZED))
      (strike (get strike-price option-data))
      (option-type (get option-type option-data))
      (is-profitable (if (is-eq option-type OPTION-CALL)
        (> current-price strike)  ;; Call is profitable if current > strike
        (< current-price strike)  ;; Put is profitable if current < strike
      ))
      (profit (if is-profitable
        (if (is-eq option-type OPTION-CALL)
          (- current-price strike)
          (- strike current-price)
        )
        u0
      ))
    )
    (asserts! (is-eq tx-sender holder) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status option-data) OPTION-ACTIVE) ERR-ALREADY-EXERCISED)
    (asserts! (<= block-height (get expiry-block option-data)) ERR-OPTION-EXPIRED)
    (asserts! (is-eq tx-sender (var-get oracle)) ERR-NOT-AUTHORIZED) ;; Price verification
    (asserts! is-profitable ERR-OUT-OF-MONEY)
    
    ;; Transfer profit to option holder
    (if (> profit u0)
      (try! (as-contract (stx-transfer? profit tx-sender holder)))
      true
    )
    
    ;; Return remaining collateral to writer
    (let ((remaining-collateral (- (get locked-amount collateral-data) profit)))
      (if (> remaining-collateral u0)
        (try! (as-contract (stx-transfer? remaining-collateral tx-sender (get writer option-data))))
        true
      )
    )
    
    ;; Update option status
    (map-set options
      { option-id: option-id }
      (merge option-data { status: OPTION-EXERCISED })
    )
    
    ;; Mark collateral as released
    (map-set option-collateral
      { option-id: option-id }
      (merge collateral-data { released: true })
    )
    
    ;; Record exercise
    (map-set exercise-history
      { option-id: option-id }
      {
        exercised-at: block-height,
        exercise-price: current-price,
        profit: profit
      }
    )
    
    (ok profit)
  )
)

;; Expire worthless option and release collateral
(define-public (expire-option (option-id uint))
  (let
    (
      (option-data (unwrap! (map-get? options { option-id: option-id }) ERR-OPTION-NOT-FOUND))
      (collateral-data (unwrap! (map-get? option-collateral { option-id: option-id }) ERR-OPTION-NOT-FOUND))
    )
    (asserts! (is-eq (get status option-data) OPTION-ACTIVE) ERR-ALREADY-EXERCISED)
    (asserts! (> block-height (get expiry-block option-data)) ERR-OPTION-EXPIRED)
    
    ;; Return full collateral to writer
    (try! (as-contract (stx-transfer? (get locked-amount collateral-data) tx-sender (get writer option-data))))
    
    ;; Update option status
    (map-set options
      { option-id: option-id }
      (merge option-data { status: OPTION-EXPIRED })
    )
    
    ;; Mark collateral as released
    (map-set option-collateral
      { option-id: option-id }
      (merge collateral-data { released: true })
    )
    
    (ok true)
  )
)

;; Close position early (for option holders)
(define-public (close-position (option-id uint) (sale-price uint) (buyer principal))
  (let
    (
      (option-data (unwrap! (map-get? options { option-id: option-id }) ERR-OPTION-NOT-FOUND))
      (holder (unwrap! (get holder option-data) ERR-NOT-AUTHORIZED))
    )
    (asserts! (is-eq tx-sender holder) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status option-data) OPTION-ACTIVE) ERR-ALREADY-EXERCISED)
    (asserts! (<= block-height (get expiry-block option-data)) ERR-OPTION-EXPIRED)
    (asserts! (> sale-price u0) ERR-INVALID-PREMIUM)
    (asserts! (>= (stx-get-balance buyer) sale-price) ERR-INSUFFICIENT-COLLATERAL)
    
    ;; Transfer payment to current holder
    (try! (stx-transfer? sale-price buyer tx-sender))
    
    ;; Transfer option to buyer
    (map-set options
      { option-id: option-id }
      (merge option-data { holder: (some buyer) })
    )
    
    ;; Update buyer position
    (map-set user-positions
      { user: buyer, option-id: option-id }
      { position-type: "long", entry-price: sale-price }
    )
    
    (ok true)
  )
)

;; Update market price (oracle function)
(define-public (update-price (asset (string-ascii 10)) (price uint))
  (begin
    (asserts! (is-eq tx-sender (var-get oracle)) ERR-NOT-AUTHORIZED)
    (asserts! (> price u0) ERR-INVALID-STRIKE)
    
    (map-set market-prices
      { asset: asset }
      { price: price, last-updated: block-height }
    )
    
    (ok true)
  )
)

;; Calculate option value using Black-Scholes approximation
(define-private (calculate-option-value 
  (option-type uint) 
  (current-price uint) 
  (strike-price uint) 
  (time-to-expiry uint)
)
  (let
    (
      (intrinsic-value (if (is-eq option-type OPTION-CALL)
        (if (> current-price strike-price) (- current-price strike-price) u0)
        (if (> strike-price current-price) (- strike-price current-price) u0)
      ))
      (time-value (/ (* time-to-expiry current-price) u10000)) ;; Simplified time value
    )
    (+ intrinsic-value time-value)
  )
)

;; Set oracle (admin function)
(define-public (set-oracle (new-oracle principal))
  (begin
    ;; In production, this would have proper admin controls
    (var-set oracle new-oracle)
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-option (option-id uint))
  (map-get? options { option-id: option-id })
)

(define-read-only (get-option-collateral (option-id uint))
  (map-get? option-collateral { option-id: option-id })
)

(define-read-only (get-user-position (user principal) (option-id uint))
  (map-get? user-positions { user: user, option-id: option-id })
)

(define-read-only (get-market-price (asset (string-ascii 10)))
  (map-get? market-prices { asset: asset })
)

(define-read-only (get-exercise-history (option-id uint))
  (map-get? exercise-history { option-id: option-id })
)

(define-read-only (get-option-count)
  (var-get option-counter)
)

(define-read-only (get-oracle)
  (var-get oracle)
)

(define-read-only (is-option-in-money (option-id uint) (current-price uint))
  (match (map-get? options { option-id: option-id })
    option-data
      (let
        (
          (strike (get strike-price option-data))
          (option-type (get option-type option-data))
        )
        (if (is-eq option-type OPTION-CALL)
          (> current-price strike)
          (< current-price strike)
        )
      )
    false
  )
)

(define-read-only (calculate-payoff (option-id uint) (current-price uint))
  (match (map-get? options { option-id: option-id })
    option-data
      (let
        (
          (strike (get strike-price option-data))
          (option-type (get option-type option-data))
          (premium (get premium option-data))
        )
        (if (is-eq option-type OPTION-CALL)
          (if (> current-price strike)
            (- (- current-price strike) premium)  ;; Subtract premium paid
            (- u0 premium)  ;; Loss limited to premium
          )
          (if (< current-price strike)
            (- (- strike current-price) premium)  ;; Subtract premium paid
            (- u0 premium)  ;; Loss limited to premium
          )
        )
      )
    u0
  )
)

(define-read-only (get-time-to-expiry (option-id uint))
  (match (map-get? options { option-id: option-id })
    option-data
      (if (> (get expiry-block option-data) block-height)
        (- (get expiry-block option-data) block-height)
        u0
      )
    u0
  )
)