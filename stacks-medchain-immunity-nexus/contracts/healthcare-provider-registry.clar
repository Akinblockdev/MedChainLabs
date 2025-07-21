;; MedChain Healthcare Provider Registry Contract
;; healthcare-provider-registry.clar
;; Advanced medical professional credentialing and verification system

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-PROVIDER-NOT-FOUND (err u301))
(define-constant ERR-INVALID-LICENSE (err u302))
(define-constant ERR-PROVIDER-SUSPENDED (err u303))
(define-constant ERR-CREDENTIAL-EXPIRED (err u304))
(define-constant ERR-INSUFFICIENT-AUTHORITY (err u305))
(define-constant ERR-ALREADY-VERIFIED (err u306))
(define-constant ERR-VERIFICATION-PENDING (err u307))
(define-constant ERR-INVALID-JURISDICTION (err u308))
(define-constant ERR-INVALID-SPECIALIZATION (err u309))
(define-constant ERR-RENEWAL-TOO-EARLY (err u310))
(define-constant ERR-INVALID-ENDORSEMENT (err u311))
(define-constant ERR-VERIFICATION-QUORUM-NOT-MET (err u312))
(define-constant ERR-INVALID-CREDENTIAL-TYPE (err u313))
(define-constant ERR-INVALID-INPUT (err u314))
(define-constant ERR-INVALID-PRINCIPAL (err u315))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-VERIFICATION-QUORUM u3)        ;; Minimum verifiers required
(define-constant MAX-AUTHORITY-LEVEL u4)            ;; Highest provider authority
(define-constant CREDENTIAL-VALIDITY-PERIOD u5256000) ;; ~10 years in blocks
(define-constant RENEWAL-PERIOD u525600)            ;; ~1 year renewal window
(define-constant ENDORSEMENT-VALIDITY u2628000)     ;; ~5 years for endorsements
(define-constant MAX-SPECIALIZATIONS u10)           ;; Max specializations per provider

;; Authority levels
(define-constant AUTHORITY-BASIC u1)         ;; Basic practitioner
(define-constant AUTHORITY-SPECIALIST u2)    ;; Medical specialist
(define-constant AUTHORITY-SUPERVISOR u3)    ;; Department head/supervisor
(define-constant AUTHORITY-EXECUTIVE u4)     ;; Chief medical officer

;; Credential types
(define-constant CRED-MEDICAL-LICENSE u1)
(define-constant CRED-BOARD-CERTIFICATION u2)
(define-constant CRED-HOSPITAL-PRIVILEGES u3)
(define-constant CRED-RESEARCH-AUTHORIZATION u4)
(define-constant CRED-EMERGENCY-AUTHORITY u5)

;; Data structures
(define-map healthcare-providers
  { provider: principal }
  {
    license-number: (string-ascii 64),
    primary-license-hash: (buff 32),
    jurisdiction: (string-ascii 64),
    authority-level: uint,
    specializations: (list 10 (string-ascii 32)),
    institution: (string-ascii 128),
    verification-status: uint,           ;; 0=Pending, 1=Verified, 2=Suspended, 3=Revoked
    verified-by: (list 5 principal),     ;; Multi-signature verification
    verification-date: uint,
    credential-expiry: uint,
    last-renewal: uint,
    certificates-issued: uint,
    reputation-score: uint,              ;; 0-1000 reputation points
    is-emergency-responder: bool,
    created-at: uint
  }
)

(define-map provider-credentials
  { provider: principal, credential-type: uint }
  {
    credential-hash: (buff 32),
    issuing-authority: (string-ascii 128),
    issued-date: uint,
    expiry-date: uint,
    verification-status: uint,
    verified-by: principal,
    verification-date: uint,
    renewal-count: uint,
    is-active: bool
  }
)

(define-map verification-requests
  { provider: principal, request-id: uint }
  {
    credential-type: uint,
    requested-authority-level: uint,
    supporting-documents: (list 5 (buff 32)),
    endorsements: (list 5 principal),
    requesting-institution: (string-ascii 128),
    submitted-at: uint,
    status: uint,                        ;; 0=Pending, 1=Approved, 2=Rejected
    reviewed-by: (list 5 principal),
    review-comments: (string-ascii 256),
    decision-date: (optional uint)
  }
)

(define-map provider-endorsements
  { endorser: principal, endorsee: principal }
  {
    endorsement-type: uint,              ;; 1=Competency, 2=Character, 3=Experience
    endorsement-hash: (buff 32),
    endorsement-date: uint,
    validity-period: uint,
    is-active: bool,
    verification-score: uint
  }
)

(define-map jurisdiction-authorities
  { jurisdiction: (string-ascii 64) }
  {
    regulatory-body: (string-ascii 128),
    contact-info: (string-ascii 256),
    verification-requirements: (list 10 uint),
    recognized-credentials: (list 10 uint),
    mutual-recognition: (list 10 (string-ascii 64)),
    last-updated: uint,
    is-active: bool
  }
)

(define-map provider-audit-trail
  { provider: principal, audit-id: uint }
  {
    action-type: (string-ascii 32),      ;; "verification", "suspension", "renewal"
    performed-by: principal,
    timestamp: uint,
    details: (string-ascii 256),
    evidence-hash: (optional (buff 32)),
    impact-level: uint                   ;; 1=Low, 2=Medium, 3=High, 4=Critical
  }
)

(define-map specialization-registry
  { specialization: (string-ascii 32) }
  {
    full-name: (string-ascii 128),
    required-credentials: (list 5 uint),
    minimum-authority: uint,
    certification-body: (string-ascii 128),
    renewal-frequency: uint,
    is-active: bool
  }
)

;; Data variables
(define-data-var next-request-id uint u1)
(define-data-var next-audit-id uint u1)
(define-data-var total-providers uint u0)
(define-data-var total-verified-providers uint u0)
(define-data-var emergency-mode bool false)
(define-data-var verification-quorum-threshold uint MIN-VERIFICATION-QUORUM)

;; Input validation helpers
(define-private (is-valid-principal (user principal))
  (not (is-eq user (as-contract tx-sender)))
)

(define-private (is-valid-license-number (license (string-ascii 64)))
  (and (> (len license) u0) (<= (len license) u64))
)

(define-private (is-valid-jurisdiction (jurisdiction (string-ascii 64)))
  (and (> (len jurisdiction) u0) (<= (len jurisdiction) u64))
)

(define-private (is-valid-authority-level (level uint))
  (and (>= level u1) (<= level MAX-AUTHORITY-LEVEL))
)

(define-private (is-valid-institution (institution (string-ascii 128)))
  (and (> (len institution) u0) (<= (len institution) u128))
)

(define-private (is-valid-credential-type (cred-type uint))
  (and (>= cred-type u1) (<= cred-type u5))
)

(define-private (is-valid-verification-status (status uint))
  (and (>= status u0) (<= status u3))
)

(define-private (is-valid-specialization (spec (string-ascii 32)))
  (and (> (len spec) u0) (<= (len spec) u32))
)

(define-private (is-valid-reputation-score (score uint))
  (<= score u1000)
)

(define-private (is-valid-endorsement-type (etype uint))
  (and (>= etype u1) (<= etype u3))
)

(define-private (is-valid-impact-level (level uint))
  (and (>= level u1) (<= level u4))
)

;; Provider status checking
(define-private (is-provider-active (provider-data {license-number: (string-ascii 64), primary-license-hash: (buff 32), jurisdiction: (string-ascii 64), authority-level: uint, specializations: (list 10 (string-ascii 32)), institution: (string-ascii 128), verification-status: uint, verified-by: (list 5 principal), verification-date: uint, credential-expiry: uint, last-renewal: uint, certificates-issued: uint, reputation-score: uint, is-emergency-responder: bool, created-at: uint}))
  (and 
    (is-eq (get verification-status provider-data) u1) ;; Verified
    (> (get credential-expiry provider-data) block-height) ;; Not expired
  )
)

(define-private (has-sufficient-authority (provider principal) (required-level uint))
  (match (map-get? healthcare-providers { provider: provider })
    provider-data
    (and 
      (is-provider-active provider-data)
      (>= (get authority-level provider-data) required-level)
    )
    false
  )
)

;; Audit trail recording
(define-private (record-audit-event 
  (provider principal) 
  (action-type (string-ascii 32)) 
  (details (string-ascii 256))
  (impact-level uint)
)
  (let ((audit-id (var-get next-audit-id)))
    (begin
      (map-set provider-audit-trail
        { provider: provider, audit-id: audit-id }
        {
          action-type: action-type,
          performed-by: tx-sender,
          timestamp: block-height,
          details: details,
          evidence-hash: none,
          impact-level: impact-level
        }
      )
      (var-set next-audit-id (+ audit-id u1))
      audit-id
    )
  )
)

;; Public functions

;; Register as healthcare provider (initial application)
(define-public (register-healthcare-provider
  (license-number (string-ascii 64))
  (primary-license-hash (buff 32))
  (jurisdiction (string-ascii 64))
  (requested-authority-level uint)
  (specializations (list 10 (string-ascii 32)))
  (institution (string-ascii 128))
)
  (let ((existing-provider (map-get? healthcare-providers { provider: tx-sender })))
    (if (and
      (is-none existing-provider)
      (is-valid-license-number license-number)
      (> (len primary-license-hash) u0)
      (is-valid-jurisdiction jurisdiction)
      (is-valid-authority-level requested-authority-level)
      (<= (len specializations) MAX-SPECIALIZATIONS)
      (is-valid-institution institution)
    )
      (begin
        ;; Create provider profile with pending status
        (map-set healthcare-providers
          { provider: tx-sender }
          {
            license-number: license-number,
            primary-license-hash: primary-license-hash,
            jurisdiction: jurisdiction,
            authority-level: u1, ;; Start with basic authority
            specializations: specializations,
            institution: institution,
            verification-status: u0, ;; Pending verification
            verified-by: (list),
            verification-date: u0,
            credential-expiry: (+ block-height CREDENTIAL-VALIDITY-PERIOD),
            last-renewal: block-height,
            certificates-issued: u0,
            reputation-score: u500, ;; Start with neutral reputation
            is-emergency-responder: false,
            created-at: block-height
          }
        )
        ;; Create verification request
        (map-set verification-requests
          { provider: tx-sender, request-id: (var-get next-request-id) }
          {
            credential-type: CRED-MEDICAL-LICENSE,
            requested-authority-level: requested-authority-level,
            supporting-documents: (list primary-license-hash),
            endorsements: (list),
            requesting-institution: institution,
            submitted-at: block-height,
            status: u0, ;; Pending
            reviewed-by: (list),
            review-comments: "",
            decision-date: none
          }
        )
        ;; Record audit event
        (record-audit-event tx-sender "registration" "Healthcare provider registration submitted" u2)
        ;; Update counters
        (var-set next-request-id (+ (var-get next-request-id) u1))
        (var-set total-providers (+ (var-get total-providers) u1))
        (ok (var-get next-request-id))
      )
      (if (is-some existing-provider)
        ERR-ALREADY-VERIFIED
        ERR-INVALID-INPUT
      )
    )
  )
)

;; Verify healthcare provider (multi-signature verification)
(define-public (verify-healthcare-provider 
  (provider principal) 
  (request-id uint)
  (approval bool)
  (comments (string-ascii 256))
)
  (let (
    (request-data (unwrap! (map-get? verification-requests { provider: provider, request-id: request-id }) ERR-VERIFICATION-PENDING))
    (provider-data (unwrap! (map-get? healthcare-providers { provider: provider }) ERR-PROVIDER-NOT-FOUND))
    (verifier-authority (unwrap! (map-get? healthcare-providers { provider: tx-sender }) ERR-NOT-AUTHORIZED))
  )
    (if (and
      ;; Verifier has sufficient authority
      (>= (get authority-level verifier-authority) u3) ;; Supervisor level required
      (is-provider-active verifier-authority)
      ;; Request is still pending
      (is-eq (get status request-data) u0)
      ;; Verifier hasn't already reviewed this request
      (is-none (index-of (get reviewed-by request-data) tx-sender))
    )
      (let (
        (updated-reviewers (unwrap-panic (as-max-len? (append (get reviewed-by request-data) tx-sender) u5)))
        (quorum-met (>= (len updated-reviewers) (var-get verification-quorum-threshold)))
      )
        (begin
          ;; Update verification request
          (map-set verification-requests
            { provider: provider, request-id: request-id }
            (merge request-data {
              reviewed-by: updated-reviewers,
              review-comments: comments,
              decision-date: (if quorum-met (some block-height) none),
              status: (if quorum-met (if approval u1 u2) u0)
            })
          )
          ;; If quorum met and approved, update provider status
          (if (and quorum-met approval)
            (begin
              (map-set healthcare-providers
                { provider: provider }
                (merge provider-data {
                  verification-status: u1, ;; Verified
                  verified-by: updated-reviewers,
                  verification-date: block-height,
                  authority-level: (get requested-authority-level request-data)
                })
              )
              (var-set total-verified-providers (+ (var-get total-verified-providers) u1))
              (record-audit-event provider "verification" "Provider verified by quorum" u3)
              true
            )
            (if (and quorum-met (not approval))
              (begin
                (record-audit-event provider "rejection" "Provider verification rejected" u3)
                true
              )
              true ;; Still pending more reviews
            )
          )
          (ok quorum-met)
        )
      )
      ERR-INSUFFICIENT-AUTHORITY
    )
  )
)

;; Add credential to provider profile
(define-public (add-provider-credential
  (provider principal)
  (credential-type uint)
  (credential-hash (buff 32))
  (issuing-authority (string-ascii 128))
  (expiry-date uint)
)
  (if (and
    (is-valid-principal provider)
    (is-valid-credential-type credential-type)
    (> (len credential-hash) u0)
    (> (len issuing-authority) u0)
    (> expiry-date block-height)
    ;; Only the provider themselves or authorized verifiers can add credentials
    (or (is-eq tx-sender provider)
        (has-sufficient-authority tx-sender u3))
  )
    (begin
      (map-set provider-credentials
        { provider: provider, credential-type: credential-type }
        {
          credential-hash: credential-hash,
          issuing-authority: issuing-authority,
          issued-date: block-height,
          expiry-date: expiry-date,
          verification-status: u0, ;; Pending verification
          verified-by: tx-sender,
          verification-date: block-height,
          renewal-count: u0,
          is-active: true
        }
      )
      (record-audit-event provider "credential-added" issuing-authority u2)
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)

;; Endorse another healthcare provider
(define-public (endorse-provider
  (endorsee principal)
  (endorsement-type uint)
  (endorsement-hash (buff 32))
)
  (let (
    (endorser-data (unwrap! (map-get? healthcare-providers { provider: tx-sender }) ERR-NOT-AUTHORIZED))
    (endorsee-data (unwrap! (map-get? healthcare-providers { provider: endorsee }) ERR-PROVIDER-NOT-FOUND))
  )
    (if (and
      (is-provider-active endorser-data)
      (is-valid-principal endorsee)
      (is-valid-endorsement-type endorsement-type)
      (> (len endorsement-hash) u0)
      ;; Can't endorse yourself
      (not (is-eq tx-sender endorsee))
      ;; Endorser must have sufficient authority
      (>= (get authority-level endorser-data) u2)
    )
      (begin
        (map-set provider-endorsements
          { endorser: tx-sender, endorsee: endorsee }
          {
            endorsement-type: endorsement-type,
            endorsement-hash: endorsement-hash,
            endorsement-date: block-height,
            validity-period: ENDORSEMENT-VALIDITY,
            is-active: true,
            verification-score: (get reputation-score endorser-data)
          }
        )
        ;; Boost endorsee's reputation based on endorser's reputation
        (let (
          (reputation-boost (/ (get reputation-score endorser-data) u10))
          (proposed-reputation (+ (get reputation-score endorsee-data) reputation-boost))
          (new-reputation (if (> proposed-reputation u1000) u1000 proposed-reputation))
        )
          (map-set healthcare-providers
            { provider: endorsee }
            (merge endorsee-data { reputation-score: new-reputation })
          )
        )
        (record-audit-event endorsee "endorsement-received" "Provider endorsement received" u1)
        (ok true)
      )
      ERR-INSUFFICIENT-AUTHORITY
    )
  )
)

;; Suspend healthcare provider
(define-public (suspend-provider 
  (provider principal) 
  (reason (string-ascii 256))
  (suspension-duration uint)
)
  (let (
    (provider-data (unwrap! (map-get? healthcare-providers { provider: provider }) ERR-PROVIDER-NOT-FOUND))
    (suspender-authority (unwrap! (map-get? healthcare-providers { provider: tx-sender }) ERR-NOT-AUTHORIZED))
  )
    (if (and
      (is-valid-principal provider)
      (> (len reason) u0)
      (> suspension-duration u0)
      ;; Suspender must have executive authority or be contract owner
      (or (is-eq tx-sender CONTRACT-OWNER)
          (>= (get authority-level suspender-authority) u4))
      ;; Can't suspend someone with equal or higher authority
      (> (get authority-level suspender-authority) (get authority-level provider-data))
    )
      (begin
        (map-set healthcare-providers
          { provider: provider }
          (merge provider-data {
            verification-status: u2, ;; Suspended
            credential-expiry: (+ block-height suspension-duration)
          })
        )
        (record-audit-event provider "suspension" reason u4)
        ;; Update verified provider count
        (if (is-eq (get verification-status provider-data) u1)
          (var-set total-verified-providers (- (var-get total-verified-providers) u1))
          true
        )
        (ok true)
      )
      ERR-INSUFFICIENT-AUTHORITY
    )
  )
)

;; Renew provider credentials
(define-public (renew-credentials 
  (updated-license-hash (buff 32))
  (renewal-evidence (list 5 (buff 32)))
)
  (let (
    (provider-data (unwrap! (map-get? healthcare-providers { provider: tx-sender }) ERR-PROVIDER-NOT-FOUND))
  )
    (if (and
      (> (len updated-license-hash) u0)
      (> (len renewal-evidence) u0)
      ;; Must be within renewal period (not too early, not expired)
      (>= block-height (- (get credential-expiry provider-data) RENEWAL-PERIOD))
      (is-eq (get verification-status provider-data) u1) ;; Must be verified
    )
      (begin
        (map-set healthcare-providers
          { provider: tx-sender }
          (merge provider-data {
            primary-license-hash: updated-license-hash,
            credential-expiry: (+ block-height CREDENTIAL-VALIDITY-PERIOD),
            last-renewal: block-height
          })
        )
        (record-audit-event tx-sender "credential-renewal" "Provider credentials renewed" u2)
        (ok true)
      )
      (if (< block-height (- (get credential-expiry provider-data) RENEWAL-PERIOD))
        ERR-RENEWAL-TOO-EARLY
        ERR-CREDENTIAL-EXPIRED
      )
    )
  )
)

;; Register jurisdiction authority
(define-public (register-jurisdiction-authority
  (jurisdiction (string-ascii 64))
  (regulatory-body (string-ascii 128))
  (contact-info (string-ascii 256))
  (verification-requirements (list 10 uint))
  (recognized-credentials (list 10 uint))
)
  (if (and
    (is-eq tx-sender CONTRACT-OWNER) ;; Only contract owner can register jurisdictions
    (is-valid-jurisdiction jurisdiction)
    (> (len regulatory-body) u0)
    (> (len contact-info) u0)
    (> (len verification-requirements) u0)
    (> (len recognized-credentials) u0)
  )
    (begin
      (map-set jurisdiction-authorities
        { jurisdiction: jurisdiction }
        {
          regulatory-body: regulatory-body,
          contact-info: contact-info,
          verification-requirements: verification-requirements,
          recognized-credentials: recognized-credentials,
          mutual-recognition: (list),
          last-updated: block-height,
          is-active: true
        }
      )
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)

;; Read-only functions
(define-read-only (get-provider-profile (provider principal))
  (map-get? healthcare-providers { provider: provider })
)

(define-read-only (get-provider-credential (provider principal) (credential-type uint))
  (map-get? provider-credentials { provider: provider, credential-type: credential-type })
)

(define-read-only (get-verification-request (provider principal) (request-id uint))
  (map-get? verification-requests { provider: provider, request-id: request-id })
)

(define-read-only (get-provider-endorsement (endorser principal) (endorsee principal))
  (map-get? provider-endorsements { endorser: endorser, endorsee: endorsee })
)

(define-read-only (get-jurisdiction-info (jurisdiction (string-ascii 64)))
  (map-get? jurisdiction-authorities { jurisdiction: jurisdiction })
)

(define-read-only (get-provider-audit-trail (provider principal) (audit-id uint))
  (map-get? provider-audit-trail { provider: provider, audit-id: audit-id })
)

(define-read-only (get-system-stats)
  {
    total-providers: (var-get total-providers),
    total-verified-providers: (var-get total-verified-providers),
    emergency-mode: (var-get emergency-mode),
    verification-quorum-threshold: (var-get verification-quorum-threshold),
    next-request-id: (var-get next-request-id)
  }
)

(define-read-only (is-provider-verified (provider principal))
  (match (map-get? healthcare-providers { provider: provider })
    provider-data
    (and 
      (is-eq (get verification-status provider-data) u1)
      (> (get credential-expiry provider-data) block-height)
    )
    false
  )
)

(define-read-only (get-provider-authority-level (provider principal))
  (match (map-get? healthcare-providers { provider: provider })
    provider-data
    (if (is-provider-active provider-data)
      (some (get authority-level provider-data))
      none
    )
    none
  )
)

;; Admin functions (contract owner only)
(define-public (set-verification-quorum (new-threshold uint))
  (if (and 
    (is-eq tx-sender CONTRACT-OWNER)
    (>= new-threshold u1)
    (<= new-threshold u10)
  )
    (begin
      (var-set verification-quorum-threshold new-threshold)
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)

(define-public (set-emergency-mode (enabled bool))
  (if (is-eq tx-sender CONTRACT-OWNER)
    (begin
      (var-set emergency-mode enabled)
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)

(define-public (revoke-provider-credentials (provider principal) (reason (string-ascii 256)))
  (if (and
    (is-eq tx-sender CONTRACT-OWNER)
    (is-valid-principal provider)
    (> (len reason) u0)
  )
    (match (map-get? healthcare-providers { provider: provider })
      provider-data
      (begin
        (map-set healthcare-providers
          { provider: provider }
          (merge provider-data { verification-status: u3 }) ;; Revoked
        )
        (record-audit-event provider "credential-revocation" reason u4)
        (if (is-eq (get verification-status provider-data) u1)
          (var-set total-verified-providers (- (var-get total-verified-providers) u1))
          true
        )
        (ok true)
      )
      ERR-PROVIDER-NOT-FOUND
    )
    ERR-NOT-AUTHORIZED
  )
)