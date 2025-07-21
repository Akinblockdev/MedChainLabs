;; MedChain Immunity Passport Protocol - Core Contract
;; immunity-passport-registry.clar
;; A privacy-preserving vaccine verification system with zero-knowledge proofs

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-CERTIFICATE-NOT-FOUND (err u201))
(define-constant ERR-INVALID-PROVIDER (err u202))
(define-constant ERR-CERTIFICATE-EXPIRED (err u203))
(define-constant ERR-INVALID-DISCLOSURE-LEVEL (err u204))
(define-constant ERR-PATIENT-NOT-FOUND (err u205))
(define-constant ERR-INVALID-VACCINE-HASH (err u206))
(define-constant ERR-CERTIFICATE-REVOKED (err u207))
(define-constant ERR-INSUFFICIENT-PRIVACY-LEVEL (err u208))
(define-constant ERR-INVALID-VALIDITY-PERIOD (err u209))
(define-constant ERR-DUPLICATE-CERTIFICATE (err u210))
(define-constant ERR-EMERGENCY-RECALL-ACTIVE (err u211))
(define-constant ERR-INVALID-INPUT (err u212))
(define-constant ERR-INVALID-PRINCIPAL (err u213))
(define-constant ERR-INVALID-PERMISSIONS (err u214))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-VALIDITY-PERIOD u31536000) ;; 1 year in seconds (approximate blocks)
(define-constant MIN-VALIDITY-PERIOD u86400)    ;; 1 day minimum validity
(define-constant MAX-DISCLOSURE-LEVEL u4)       ;; Highest privacy disclosure level
(define-constant EMERGENCY-AUTHORITY-THRESHOLD u3) ;; Min authorities for emergency actions

;; Privacy disclosure levels
(define-constant DISCLOSURE-BASIC u1)      ;; Basic verification only
(define-constant DISCLOSURE-STANDARD u2)   ;; Travel/employment level
(define-constant DISCLOSURE-HEALTHCARE u3) ;; Medical context
(define-constant DISCLOSURE-EMERGENCY u4)  ;; Public health emergency

;; Data structures
(define-map immunity-certificates
  { patient: principal, certificate-id: uint }
  {
    vaccine-hash: (buff 32),           ;; Cryptographic hash of vaccine data
    provider: principal,               ;; Healthcare provider who issued
    issued-at: uint,                   ;; Block height when issued
    valid-until: uint,                 ;; Expiration block height
    privacy-commitment: (buff 32),     ;; Zero-knowledge commitment
    disclosure-permissions: uint,       ;; Bitmask for allowed disclosure levels
    is-active: bool,                   ;; Certificate status
    emergency-revoked: bool,           ;; Emergency recall status
    verification-count: uint           ;; Usage tracking
  }
)

(define-map patient-profiles
  { patient: principal }
  {
    total-certificates: uint,
    privacy-preferences: uint,         ;; Default privacy settings
    emergency-contact: (optional principal),
    created-at: uint,
    last-updated: uint,
    is-verified: bool                  ;; Identity verification status
  }
)

(define-map healthcare-providers
  { provider: principal }
  {
    license-hash: (buff 32),           ;; Medical license verification
    jurisdiction: (string-ascii 64),    ;; Licensed jurisdiction
    authority-level: uint,             ;; Provider authority (1-4)
    certificates-issued: uint,
    is-verified: bool,
    verified-by: principal,
    verification-date: uint,
    is-suspended: bool
  }
)

(define-map verification-requests
  { requester: principal, request-id: uint }
  {
    patient: principal,
    required-vaccines: (list 10 (buff 32)),
    disclosure-level: uint,
    purpose: (string-ascii 128),
    requested-at: uint,
    expires-at: uint,
    is-fulfilled: bool,
    verification-result: (optional bool)
  }
)

(define-map emergency-recalls
  { recall-id: uint }
  {
    affected-vaccine-hash: (buff 32),
    recall-reason: (string-ascii 256),
    initiated-by: principal,
    initiated-at: uint,
    affected-certificates: uint,
    is-active: bool,
    authority-confirmations: uint
  }
)

(define-map certificate-verifications
  { patient: principal, verifier: principal, verification-id: uint }
  {
    certificates-verified: (list 10 uint),
    disclosure-level-used: uint,
    verification-timestamp: uint,
    purpose: (string-ascii 128),
    result-hash: (buff 32)             ;; Hash of verification result
  }
)

;; Data variables
(define-data-var next-certificate-id uint u1)
(define-data-var next-request-id uint u1)
(define-data-var next-recall-id uint u1)
(define-data-var next-verification-id uint u1)
(define-data-var total-certificates-issued uint u0)
(define-data-var total-verifications-performed uint u0)
(define-data-var emergency-mode bool false)

;; Input validation helpers
(define-private (is-valid-disclosure-level (level uint))
  (and (>= level u1) (<= level MAX-DISCLOSURE-LEVEL))
)

(define-private (is-valid-validity-period (period uint))
  (and (>= period MIN-VALIDITY-PERIOD) (<= period MAX-VALIDITY-PERIOD))
)

(define-private (is-valid-vaccine-hash (hash (buff 32)))
  (> (len hash) u0)
)

(define-private (is-valid-principal (user principal))
  (not (is-eq user (as-contract tx-sender)))
)

(define-private (is-valid-privacy-preferences (prefs uint))
  (and (>= prefs u0) (<= prefs u15)) ;; 4-bit bitmask for privacy settings
)

(define-private (is-valid-authority-level (level uint))
  (and (>= level u1) (<= level u4))
)

(define-private (is-valid-jurisdiction (jurisdiction (string-ascii 64)))
  (and (> (len jurisdiction) u0) (<= (len jurisdiction) u64))
)

(define-private (is-valid-certificate-id (cert-id uint))
  (and (> cert-id u0) (< cert-id (var-get next-certificate-id)))
)

(define-private (is-valid-disclosure-permissions (permissions uint))
  (and (>= permissions u0) (<= permissions u15)) ;; 4-bit bitmask
)

(define-private (is-valid-purpose (purpose (string-ascii 128)))
  (and (> (len purpose) u0) (<= (len purpose) u128))
)

(define-private (is-valid-recall-reason (reason (string-ascii 256)))
  (and (> (len reason) u0) (<= (len reason) u256))
)

(define-private (is-certificate-valid (cert-data {vaccine-hash: (buff 32), provider: principal, issued-at: uint, valid-until: uint, privacy-commitment: (buff 32), disclosure-permissions: uint, is-active: bool, emergency-revoked: bool, verification-count: uint}))
  (and 
    (get is-active cert-data)
    (not (get emergency-revoked cert-data))
    (> (get valid-until cert-data) block-height)
  )
)

(define-private (has-disclosure-permission (cert-permissions uint) (requested-level uint))
  (> (bit-and cert-permissions (pow u2 requested-level)) u0)
)

;; Zero-knowledge proof utilities (simplified for demonstration)
(define-private (generate-privacy-commitment (patient principal) (vaccine-hash (buff 32)) (salt (buff 32)))
  (sha256 (concat (concat (unwrap-panic (to-consensus-buff? patient)) vaccine-hash) salt))
)

(define-private (verify-privacy-proof (commitment (buff 32)) (patient principal) (vaccine-hash (buff 32)) (salt (buff 32)))
  (is-eq commitment (generate-privacy-commitment patient vaccine-hash salt))
)

;; Public functions

;; Register a patient in the system
(define-public (register-patient (privacy-preferences uint) (emergency-contact (optional principal)))
  (let ((existing-profile (map-get? patient-profiles { patient: tx-sender })))
    (if (and
      (is-valid-privacy-preferences privacy-preferences)
      (match emergency-contact 
        contact (is-valid-principal contact)
        true) ;; None is valid
      (is-none existing-profile)
    )
      (begin
        (map-set patient-profiles
          { patient: tx-sender }
          {
            total-certificates: u0,
            privacy-preferences: privacy-preferences,
            emergency-contact: emergency-contact,
            created-at: block-height,
            last-updated: block-height,
            is-verified: false
          }
        )
        (ok true)
      )
      (if (is-some existing-profile)
        (ok true) ;; Already registered
        ERR-INVALID-INPUT
      )
    )
  )
)

;; Register healthcare provider (requires verification)
(define-public (register-healthcare-provider 
  (provider principal) 
  (license-hash (buff 32)) 
  (jurisdiction (string-ascii 64))
  (authority-level uint)
)
  (if (and 
    (is-eq tx-sender CONTRACT-OWNER) ;; Only contract owner can verify providers initially
    (is-valid-principal provider)
    (is-valid-vaccine-hash license-hash)
    (is-valid-jurisdiction jurisdiction)
    (is-valid-authority-level authority-level)
  )
    (let ((existing-provider (map-get? healthcare-providers { provider: provider })))
      (if (is-none existing-provider)
        (begin
          (map-set healthcare-providers
            { provider: provider }
            {
              license-hash: license-hash,
              jurisdiction: jurisdiction,
              authority-level: authority-level,
              certificates-issued: u0,
              is-verified: true,
              verified-by: tx-sender,
              verification-date: block-height,
              is-suspended: false
            }
          )
          (ok true)
        )
        ERR-DUPLICATE-CERTIFICATE
      )
    )
    ERR-NOT-AUTHORIZED
  )
)

;; Issue immunity certificate by verified healthcare provider
(define-public (issue-immunity-certificate 
  (patient principal) 
  (vaccine-hash (buff 32)) 
  (validity-period uint)
  (privacy-commitment (buff 32))
  (disclosure-permissions uint)
)
  (let (
    (certificate-id (var-get next-certificate-id))
    (provider-data (unwrap! (map-get? healthcare-providers { provider: tx-sender }) ERR-INVALID-PROVIDER))
    (patient-profile (unwrap! (map-get? patient-profiles { patient: patient }) ERR-PATIENT-NOT-FOUND))
  )
    (if (and
      ;; Validate inputs
      (is-valid-principal patient)
      (is-valid-vaccine-hash vaccine-hash)
      (is-valid-validity-period validity-period)
      (> (len privacy-commitment) u0)
      (is-valid-disclosure-permissions disclosure-permissions)
      ;; Validate provider
      (get is-verified provider-data)
      (not (get is-suspended provider-data))
      ;; Check for emergency mode
      (not (var-get emergency-mode))
    )
      (let ((valid-until (+ block-height validity-period)))
        (begin
          ;; Create the certificate
          (map-set immunity-certificates
            { patient: patient, certificate-id: certificate-id }
            {
              vaccine-hash: vaccine-hash,
              provider: tx-sender,
              issued-at: block-height,
              valid-until: valid-until,
              privacy-commitment: privacy-commitment,
              disclosure-permissions: disclosure-permissions,
              is-active: true,
              emergency-revoked: false,
              verification-count: u0
            }
          )
          ;; Update patient profile
          (map-set patient-profiles
            { patient: patient }
            (merge patient-profile {
              total-certificates: (+ (get total-certificates patient-profile) u1),
              last-updated: block-height
            })
          )
          ;; Update provider stats
          (map-set healthcare-providers
            { provider: tx-sender }
            (merge provider-data {
              certificates-issued: (+ (get certificates-issued provider-data) u1)
            })
          )
          ;; Update global counters
          (var-set next-certificate-id (+ certificate-id u1))
          (var-set total-certificates-issued (+ (var-get total-certificates-issued) u1))
          (ok certificate-id)
        )
      )
      (if (not (is-valid-principal patient))
        ERR-INVALID-PRINCIPAL
        (if (not (is-valid-vaccine-hash vaccine-hash))
          ERR-INVALID-VACCINE-HASH
          (if (not (is-valid-validity-period validity-period))
            ERR-INVALID-VALIDITY-PERIOD
            (if (not (is-valid-disclosure-permissions disclosure-permissions))
              ERR-INVALID-PERMISSIONS
              (if (not (get is-verified provider-data))
                ERR-INVALID-PROVIDER
                (if (get is-suspended provider-data)
                  ERR-NOT-AUTHORIZED
                  ERR-EMERGENCY-RECALL-ACTIVE
                )
              )
            )
          )
        )
      )
    )
  )
)

;; Verify immunity status with privacy controls
(define-public (verify-immunity-status 
  (patient principal) 
  (required-vaccines (list 10 (buff 32))) 
  (disclosure-level uint)
  (purpose (string-ascii 128))
)
  (let (
    (verification-id (var-get next-verification-id))
    (patient-profile (unwrap! (map-get? patient-profiles { patient: patient }) ERR-PATIENT-NOT-FOUND))
  )
    (if (and
      (is-valid-principal patient)
      (is-valid-disclosure-level disclosure-level)
      (> (len required-vaccines) u0)
      (is-valid-purpose purpose)
    )
      (let (
        (verification-result (fold check-vaccine-requirement required-vaccines { verified: true, certificates: (list), level: disclosure-level, patient-addr: patient }))
      )
        (begin
          ;; Record verification attempt
          (map-set certificate-verifications
            { patient: patient, verifier: tx-sender, verification-id: verification-id }
            {
              certificates-verified: (get certificates verification-result),
              disclosure-level-used: disclosure-level,
              verification-timestamp: block-height,
              purpose: purpose,
              result-hash: (sha256 (unwrap-panic (to-consensus-buff? (get verified verification-result))))
            }
          )
          ;; Update global stats
          (var-set next-verification-id (+ verification-id u1))
          (var-set total-verifications-performed (+ (var-get total-verifications-performed) u1))
          (ok {
            verification-id: verification-id,
            verified: (get verified verification-result),
            disclosure-level: disclosure-level,
            timestamp: block-height
          })
        )
      )
      (if (not (is-valid-principal patient))
        ERR-INVALID-PRINCIPAL
        (if (not (is-valid-disclosure-level disclosure-level))
          ERR-INVALID-DISCLOSURE-LEVEL
          ERR-INVALID-INPUT
        )
      )
    )
  )
)

;; Helper function for vaccine requirement checking
(define-private (check-vaccine-requirement 
  (vaccine-hash (buff 32)) 
  (acc { verified: bool, certificates: (list 10 uint), level: uint, patient-addr: principal })
)
  (let (
    (patient-addr (get patient-addr acc))
    (disclosure-level (get level acc))
    (current-verified (get verified acc))
  )
    (if current-verified
      (let ((matching-cert (find-matching-certificate patient-addr vaccine-hash disclosure-level)))
        (if (is-some matching-cert)
          (merge acc { 
            certificates: (unwrap-panic (as-max-len? (append (get certificates acc) (unwrap-panic matching-cert)) u10))
          })
          (merge acc { verified: false })
        )
      )
      acc ;; Already failed, don't check further
    )
  )
)

;; Find matching certificate for patient and vaccine
(define-private (find-matching-certificate (patient principal) (vaccine-hash (buff 32)) (disclosure-level uint))
  (let (
    (cert-1 (map-get? immunity-certificates { patient: patient, certificate-id: u1 }))
    (cert-2 (map-get? immunity-certificates { patient: patient, certificate-id: u2 }))
    (cert-3 (map-get? immunity-certificates { patient: patient, certificate-id: u3 }))
  )
    ;; Simplified search - in production, would iterate through all certificates
    (if (and (is-some cert-1) 
             (is-eq (get vaccine-hash (unwrap-panic cert-1)) vaccine-hash)
             (is-certificate-valid (unwrap-panic cert-1))
             (has-disclosure-permission (get disclosure-permissions (unwrap-panic cert-1)) disclosure-level))
      (some u1)
      (if (and (is-some cert-2)
               (is-eq (get vaccine-hash (unwrap-panic cert-2)) vaccine-hash)
               (is-certificate-valid (unwrap-panic cert-2))
               (has-disclosure-permission (get disclosure-permissions (unwrap-panic cert-2)) disclosure-level))
        (some u2)
        (if (and (is-some cert-3)
                 (is-eq (get vaccine-hash (unwrap-panic cert-3)) vaccine-hash)
                 (is-certificate-valid (unwrap-panic cert-3))
                 (has-disclosure-permission (get disclosure-permissions (unwrap-panic cert-3)) disclosure-level))
          (some u3)
          none
        )
      )
    )
  )
)

;; Emergency recall system
(define-public (initiate-emergency-recall 
  (vaccine-hash (buff 32)) 
  (recall-reason (string-ascii 256))
)
  (let (
    (recall-id (var-get next-recall-id))
    (provider-data (unwrap! (map-get? healthcare-providers { provider: tx-sender }) ERR-INVALID-PROVIDER))
  )
    (if (and
      (get is-verified provider-data)
      (>= (get authority-level provider-data) u3) ;; High authority required
      (is-valid-vaccine-hash vaccine-hash)
      (is-valid-recall-reason recall-reason)
    )
      (begin
        (map-set emergency-recalls
          { recall-id: recall-id }
          {
            affected-vaccine-hash: vaccine-hash,
            recall-reason: recall-reason,
            initiated-by: tx-sender,
            initiated-at: block-height,
            affected-certificates: u0, ;; Will be updated by separate function
            is-active: true,
            authority-confirmations: u1
          }
        )
        (var-set next-recall-id (+ recall-id u1))
        (var-set emergency-mode true)
        (ok recall-id)
      )
      (if (not (get is-verified provider-data))
        ERR-INVALID-PROVIDER
        (if (< (get authority-level provider-data) u3)
          ERR-NOT-AUTHORIZED
          (if (not (is-valid-vaccine-hash vaccine-hash))
            ERR-INVALID-VACCINE-HASH
            ERR-INVALID-INPUT
          )
        )
      )
    )
  )
)

;; Revoke certificate (emergency or provider action)
(define-public (revoke-certificate (patient principal) (certificate-id uint) (reason (string-ascii 128)))
  (let (
    (cert-data (unwrap! (map-get? immunity-certificates { patient: patient, certificate-id: certificate-id }) ERR-CERTIFICATE-NOT-FOUND))
    (provider-data (map-get? healthcare-providers { provider: tx-sender }))
  )
    (if (and
      (is-valid-principal patient)
      (is-valid-certificate-id certificate-id)
      (> (len reason) u0)
      (<= (len reason) u128)
    )
      (if (or
        ;; Certificate issuer can revoke
        (is-eq tx-sender (get provider cert-data))
        ;; High authority provider can revoke
        (and (is-some provider-data) 
             (>= (get authority-level (unwrap-panic provider-data)) u3))
        ;; Contract owner can revoke
        (is-eq tx-sender CONTRACT-OWNER)
      )
        (begin
          (map-set immunity-certificates
            { patient: patient, certificate-id: certificate-id }
            (merge cert-data {
              is-active: false,
              emergency-revoked: true
            })
          )
          (ok true)
        )
        ERR-NOT-AUTHORIZED
      )
      ERR-INVALID-INPUT
    )
  )
)

;; Read-only functions
(define-read-only (get-certificate (patient principal) (certificate-id uint))
  (map-get? immunity-certificates { patient: patient, certificate-id: certificate-id })
)

(define-read-only (get-patient-profile (patient principal))
  (map-get? patient-profiles { patient: patient })
)

(define-read-only (get-healthcare-provider (provider principal))
  (map-get? healthcare-providers { provider: provider })
)

(define-read-only (get-emergency-recall (recall-id uint))
  (map-get? emergency-recalls { recall-id: recall-id })
)

(define-read-only (get-verification-record (patient principal) (verifier principal) (verification-id uint))
  (map-get? certificate-verifications { patient: patient, verifier: verifier, verification-id: verification-id })
)

(define-read-only (get-system-stats)
  {
    total-certificates-issued: (var-get total-certificates-issued),
    total-verifications-performed: (var-get total-verifications-performed),
    emergency-mode: (var-get emergency-mode),
    next-certificate-id: (var-get next-certificate-id)
  }
)

;; Admin functions (contract owner only)
(define-public (set-emergency-mode (enabled bool))
  (if (is-eq tx-sender CONTRACT-OWNER)
    (begin
      (var-set emergency-mode enabled)
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)

(define-public (suspend-healthcare-provider (provider principal))
  (if (and 
    (is-eq tx-sender CONTRACT-OWNER)
    (is-valid-principal provider)
  )
    (match (map-get? healthcare-providers { provider: provider })
      provider-data
      (begin
        (map-set healthcare-providers
          { provider: provider }
          (merge provider-data { is-suspended: true })
        )
        (ok true)
      )
      ERR-INVALID-PROVIDER
    )
    ERR-NOT-AUTHORIZED
  )
)