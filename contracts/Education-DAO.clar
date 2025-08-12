(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-INVALID-AMOUNT (err u400))
(define-constant ERR-INSUFFICIENT-FUNDS (err u402))
(define-constant ERR-VOTING-CLOSED (err u403))
(define-constant ERR-ALREADY-VOTED (err u405))
(define-constant ERR-INVALID-PROPOSAL (err u406))
(define-constant ERR-PROPOSAL-ACTIVE (err u407))
(define-constant ERR-SELF-DELEGATION (err u408))
(define-constant ERR-DELEGATION-EXISTS (err u409))
(define-constant ERR-DELEGATION-NOT-FOUND (err u410))

(define-data-var total-funds uint u0)
(define-data-var next-proposal-id uint u1)
(define-data-var voting-duration uint u1008)
(define-data-var min-voting-power uint u1000000)

(define-map alumni
    { alumnus: principal }
    {
        contribution: uint,
        voting-power: uint,
        joined-at: uint,
        active: bool,
    }
)

(define-map proposals
    { proposal-id: uint }
    {
        title: (string-ascii 100),
        description: (string-ascii 500),
        recipient: principal,
        amount: uint,
        proposer: principal,
        created-at: uint,
        voting-ends: uint,
        votes-for: uint,
        votes-against: uint,
        executed: bool,
        active: bool,
    }
)

(define-map votes
    {
        proposal-id: uint,
        voter: principal,
    }
    {
        vote: bool,
        voting-power: uint,
        voted-at: uint,
    }
)

(define-map alumni-proposals
    { alumnus: principal }
    { proposal-count: uint }
)

(define-map delegations
    { delegator: principal }
    {
        delegate: principal,
        delegated-at: uint,
        active: bool,
    }
)

(define-map delegation-totals
    { delegate: principal }
    { total-delegated-power: uint }
)

(define-public (register-alumni)
    (let ((alumnus tx-sender))
        (asserts! (is-none (map-get? alumni { alumnus: alumnus }))
            ERR-ALREADY-EXISTS
        )
        (map-set alumni { alumnus: alumnus } {
            contribution: u0,
            voting-power: u0,
            joined-at: stacks-block-height,
            active: true,
        })
        (ok true)
    )
)

(define-public (contribute-funds (amount uint))
    (let (
            (alumnus tx-sender)
            (current-data (unwrap! (map-get? alumni { alumnus: alumnus }) ERR-NOT-FOUND))
        )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (get active current-data) ERR-UNAUTHORIZED)

        (try! (stx-transfer? amount alumnus (as-contract tx-sender)))

        (let ((new-contribution (+ (get contribution current-data) amount)))
            (map-set alumni { alumnus: alumnus }
                (merge current-data {
                    contribution: new-contribution,
                    voting-power: (calculate-voting-power new-contribution),
                })
            )
            (var-set total-funds (+ (var-get total-funds) amount))
            (ok true)
        )
    )
)

(define-public (create-proposal
        (title (string-ascii 100))
        (description (string-ascii 500))
        (recipient principal)
        (amount uint)
    )
    (let (
            (proposer tx-sender)
            (proposer-data (unwrap! (map-get? alumni { alumnus: proposer }) ERR-UNAUTHORIZED))
            (proposal-id (var-get next-proposal-id))
            (current-height stacks-block-height)
        )
        (asserts! (get active proposer-data) ERR-UNAUTHORIZED)
        (asserts!
            (>= (get voting-power proposer-data) (var-get min-voting-power))
            ERR-UNAUTHORIZED
        )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= amount (var-get total-funds)) ERR-INSUFFICIENT-FUNDS)

        (map-set proposals { proposal-id: proposal-id } {
            title: title,
            description: description,
            recipient: recipient,
            amount: amount,
            proposer: proposer,
            created-at: current-height,
            voting-ends: (+ current-height (var-get voting-duration)),
            votes-for: u0,
            votes-against: u0,
            executed: false,
            active: true,
        })

        (let ((current-count (default-to u0
                (get proposal-count
                    (map-get? alumni-proposals { alumnus: proposer })
                ))))
            (map-set alumni-proposals { alumnus: proposer } { proposal-count: (+ current-count u1) })
        )

        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal
        (proposal-id uint)
        (vote-for bool)
    )
    (let (
            (voter tx-sender)
            (voter-data (unwrap! (map-get? alumni { alumnus: voter }) ERR-UNAUTHORIZED))
            (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id })
                ERR-NOT-FOUND
            ))
            (current-height stacks-block-height)
        )
        (asserts! (get active voter-data) ERR-UNAUTHORIZED)
        (asserts! (get active proposal-data) ERR-INVALID-PROPOSAL)
        (asserts! (< current-height (get voting-ends proposal-data))
            ERR-VOTING-CLOSED
        )
        (asserts!
            (is-none (map-get? votes {
                proposal-id: proposal-id,
                voter: voter,
            }))
            ERR-ALREADY-VOTED
        )

        (let ((effective-voting-power (get-effective-voting-power voter)))
            (map-set votes {
                proposal-id: proposal-id,
                voter: voter,
            } {
                vote: vote-for,
                voting-power: effective-voting-power,
                voted-at: current-height,
            })

            (if vote-for
                (map-set proposals { proposal-id: proposal-id }
                    (merge proposal-data { votes-for: (+ (get votes-for proposal-data) effective-voting-power) })
                )
                (map-set proposals { proposal-id: proposal-id }
                    (merge proposal-data { votes-against: (+ (get votes-against proposal-data) effective-voting-power) })
                )
            )
            (ok true)
        )
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let (
            (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id })
                ERR-NOT-FOUND
            ))
            (current-height stacks-block-height)
        )
        (asserts! (get active proposal-data) ERR-INVALID-PROPOSAL)
        (asserts! (>= current-height (get voting-ends proposal-data))
            ERR-VOTING-CLOSED
        )
        (asserts! (not (get executed proposal-data)) ERR-ALREADY-EXISTS)
        (asserts!
            (> (get votes-for proposal-data) (get votes-against proposal-data))
            ERR-UNAUTHORIZED
        )

        (let ((amount (get amount proposal-data)))
            (asserts! (<= amount (var-get total-funds)) ERR-INSUFFICIENT-FUNDS)

            (try! (as-contract (stx-transfer? amount tx-sender (get recipient proposal-data))))

            (map-set proposals { proposal-id: proposal-id }
                (merge proposal-data {
                    executed: true,
                    active: false,
                })
            )

            (var-set total-funds (- (var-get total-funds) amount))
            (ok true)
        )
    )
)

(define-public (close-proposal (proposal-id uint))
    (let (
            (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id })
                ERR-NOT-FOUND
            ))
            (current-height stacks-block-height)
        )
        (asserts!
            (or (is-eq tx-sender (get proposer proposal-data)) (is-eq tx-sender CONTRACT-OWNER))
            ERR-UNAUTHORIZED
        )
        (asserts! (get active proposal-data) ERR-INVALID-PROPOSAL)
        (asserts! (not (get executed proposal-data)) ERR-ALREADY-EXISTS)

        (map-set proposals { proposal-id: proposal-id }
            (merge proposal-data { active: false })
        )
        (ok true)
    )
)

(define-public (set-voting-duration (new-duration uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (> new-duration u0) ERR-INVALID-AMOUNT)
        (var-set voting-duration new-duration)
        (ok true)
    )
)

(define-public (set-min-voting-power (new-power uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (> new-power u0) ERR-INVALID-AMOUNT)
        (var-set min-voting-power new-power)
        (ok true)
    )
)

(define-public (deactivate-alumni (alumnus principal))
    (let ((alumni-data (unwrap! (map-get? alumni { alumnus: alumnus }) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set alumni { alumnus: alumnus }
            (merge alumni-data { active: false })
        )
        (ok true)
    )
)

(define-public (delegate-voting-power (delegate principal))
    (let (
            (delegator tx-sender)
            (delegator-data (unwrap! (map-get? alumni { alumnus: delegator }) ERR-UNAUTHORIZED))
            (delegate-data (unwrap! (map-get? alumni { alumnus: delegate }) ERR-NOT-FOUND))
            (current-height stacks-block-height)
        )
        (asserts! (get active delegator-data) ERR-UNAUTHORIZED)
        (asserts! (get active delegate-data) ERR-UNAUTHORIZED)
        (asserts! (not (is-eq delegator delegate)) ERR-SELF-DELEGATION)
        (asserts! (is-none (map-get? delegations { delegator: delegator }))
            ERR-DELEGATION-EXISTS
        )

        (let ((delegator-power (get voting-power delegator-data)))
            (map-set delegations { delegator: delegator } {
                delegate: delegate,
                delegated-at: current-height,
                active: true,
            })

            (let ((current-delegated (default-to u0
                    (get total-delegated-power
                        (map-get? delegation-totals { delegate: delegate })
                    ))))
                (map-set delegation-totals { delegate: delegate } { total-delegated-power: (+ current-delegated delegator-power) })
            )
            (ok true)
        )
    )
)

(define-public (revoke-delegation)
    (let (
            (delegator tx-sender)
            (delegation-data (unwrap! (map-get? delegations { delegator: delegator })
                ERR-DELEGATION-NOT-FOUND
            ))
            (delegator-data (unwrap! (map-get? alumni { alumnus: delegator }) ERR-UNAUTHORIZED))
        )
        (asserts! (get active delegation-data) ERR-DELEGATION-NOT-FOUND)

        (let (
                (delegate (get delegate delegation-data))
                (delegator-power (get voting-power delegator-data))
            )
            (map-set delegations { delegator: delegator }
                (merge delegation-data { active: false })
            )

            (let ((current-delegated (default-to u0
                    (get total-delegated-power
                        (map-get? delegation-totals { delegate: delegate })
                    ))))
                (map-set delegation-totals { delegate: delegate } { total-delegated-power: (if (>= current-delegated delegator-power)
                    (- current-delegated delegator-power)
                    u0
                ) }
                )
            )
            (ok true)
        )
    )
)

(define-private (calculate-voting-power (contribution uint))
    (if (< contribution u1000000)
        u0
        (/ contribution u1000)
    )
)

(define-private (get-effective-voting-power (alumnus principal))
    (let ((alumni-data (unwrap-panic (map-get? alumni { alumnus: alumnus }))))
        (let ((own-power (get voting-power alumni-data)))
            (let ((delegated-power (default-to u0
                    (get total-delegated-power
                        (map-get? delegation-totals { delegate: alumnus })
                    ))))
                (+ own-power delegated-power)
            )
        )
    )
)

(define-read-only (get-alumni-data (alumnus principal))
    (map-get? alumni { alumnus: alumnus })
)

(define-read-only (get-proposal-data (proposal-id uint))
    (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-vote-data
        (proposal-id uint)
        (voter principal)
    )
    (map-get? votes {
        proposal-id: proposal-id,
        voter: voter,
    })
)

(define-read-only (get-total-funds)
    (var-get total-funds)
)

(define-read-only (get-next-proposal-id)
    (var-get next-proposal-id)
)

(define-read-only (get-voting-duration)
    (var-get voting-duration)
)

(define-read-only (get-min-voting-power)
    (var-get min-voting-power)
)

(define-read-only (get-alumni-proposal-count (alumnus principal))
    (default-to u0
        (get proposal-count (map-get? alumni-proposals { alumnus: alumnus }))
    )
)

(define-read-only (is-proposal-active (proposal-id uint))
    (match (map-get? proposals { proposal-id: proposal-id })
        proposal-data (and (get active proposal-data) (< stacks-block-height (get voting-ends proposal-data)))
        false
    )
)

(define-read-only (can-execute-proposal (proposal-id uint))
    (match (map-get? proposals { proposal-id: proposal-id })
        proposal-data (and
            (get active proposal-data)
            (>= stacks-block-height (get voting-ends proposal-data))
            (not (get executed proposal-data))
            (> (get votes-for proposal-data) (get votes-against proposal-data))
        )
        false
    )
)

(define-read-only (get-contract-owner)
    CONTRACT-OWNER
)

(define-read-only (get-delegation-data (delegator principal))
    (map-get? delegations { delegator: delegator })
)

(define-read-only (get-delegation-totals (delegate principal))
    (map-get? delegation-totals { delegate: delegate })
)

(define-read-only (get-effective-voting-power-read (alumnus principal))
    (match (map-get? alumni { alumnus: alumnus })
        alumni-data (let ((own-power (get voting-power alumni-data)))
            (let ((delegated-power (default-to u0
                    (get total-delegated-power
                        (map-get? delegation-totals { delegate: alumnus })
                    ))))
                (+ own-power delegated-power)
            )
        )
        u0
    )
)
