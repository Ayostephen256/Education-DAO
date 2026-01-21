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
(define-constant ERR-INVALID-MILESTONE (err u411))
(define-constant ERR-MILESTONE-ALREADY-VERIFIED (err u412))
(define-constant ERR-MILESTONE-NOT-READY (err u413))
(define-constant ERR-MILESTONE-FUNDS-RELEASED (err u414))
(define-constant ERR-NO-MILESTONES (err u415))
(define-constant ERR-ACHIEVEMENT-NOT-FOUND (err u416))
(define-constant ERR-ACHIEVEMENT-ALREADY-EARNED (err u417))
(define-constant ERR-ACHIEVEMENT-NOT-ELIGIBLE (err u418))
(define-constant ERR-INVALID-DIFFICULTY (err u419))

(define-data-var total-funds uint u0)
(define-data-var next-proposal-id uint u1)
(define-data-var voting-duration uint u1008)
(define-data-var min-voting-power uint u1000000)
(define-data-var achievement-counter uint u0)

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

(define-map milestone-proposals
    { proposal-id: uint }
    {
        total-milestones: uint,
        current-milestone: uint,
        milestone-voting-duration: uint,
        created-at: uint,
    }
)

(define-map milestones
    {
        proposal-id: uint,
        milestone-id: uint,
    }
    {
        title: (string-ascii 100),
        description: (string-ascii 300),
        amount: uint,
        verification-votes-for: uint,
        verification-votes-against: uint,
        verified: bool,
        funds-released: bool,
        voting-ends: uint,
    }
)

(define-map milestone-votes
    {
        proposal-id: uint,
        milestone-id: uint,
        voter: principal,
    }
    {
        vote: bool,
        voting-power: uint,
        voted-at: uint,
    }
)

(define-map achievements
    { achievement-id: uint }
    {
        name: (string-ascii 50),
        description: (string-ascii 200),
        category: (string-ascii 30),
        difficulty: (string-ascii 20),
        points: uint,
        created-at: uint,
        created-by: principal,
    }
)

(define-map alumni-achievements
    { alumnus: principal, achievement-id: uint }
    {
        earned-at: uint,
        verified: bool,
    }
)

(define-constant DEFAULT-ALUMNI-STATS { total-points: u0, total-achievements: u0 })

(define-map alumni-stats
    { alumnus: principal }
    {
        total-points: uint,
        total-achievements: uint,
    }
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

        (match (map-get? milestone-proposals { proposal-id: proposal-id })
            milestone-proposal-data (begin
                (try! (start-milestone-verification proposal-id u1))
                (ok true)
            )
            (let ((amount (get amount proposal-data)))
                (asserts! (<= amount (var-get total-funds))
                    ERR-INSUFFICIENT-FUNDS
                )

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

(define-public (create-milestone-proposal
        (title (string-ascii 100))
        (description (string-ascii 500))
        (recipient principal)
        (milestone-titles (list 10 (string-ascii 100)))
        (milestone-descriptions (list 10 (string-ascii 300)))
        (milestone-amounts (list 10 uint))
        (milestone-voting-duration uint)
    )
    (let (
            (proposer tx-sender)
            (proposer-data (unwrap! (map-get? alumni { alumnus: proposer }) ERR-UNAUTHORIZED))
            (proposal-id (var-get next-proposal-id))
            (current-height stacks-block-height)
            (total-milestones (len milestone-titles))
            (total-amount (fold + milestone-amounts u0))
        )
        (asserts! (get active proposer-data) ERR-UNAUTHORIZED)
        (asserts!
            (>= (get voting-power proposer-data) (var-get min-voting-power))
            ERR-UNAUTHORIZED
        )
        (asserts! (> total-milestones u0) ERR-NO-MILESTONES)
        (asserts! (<= total-milestones u10) ERR-INVALID-AMOUNT)
        (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= total-amount (var-get total-funds)) ERR-INSUFFICIENT-FUNDS)
        (asserts! (> milestone-voting-duration u0) ERR-INVALID-AMOUNT)
        (asserts!
            (and
                (is-eq (len milestone-titles) (len milestone-descriptions))
                (is-eq (len milestone-titles) (len milestone-amounts))
            )
            ERR-INVALID-AMOUNT
        )

        (map-set proposals { proposal-id: proposal-id } {
            title: title,
            description: description,
            recipient: recipient,
            amount: total-amount,
            proposer: proposer,
            created-at: current-height,
            voting-ends: (+ current-height (var-get voting-duration)),
            votes-for: u0,
            votes-against: u0,
            executed: false,
            active: true,
        })

        (map-set milestone-proposals { proposal-id: proposal-id } {
            total-milestones: total-milestones,
            current-milestone: u1,
            milestone-voting-duration: milestone-voting-duration,
            created-at: current-height,
        })

        (let (
                (milestone-created (create-milestones-iter proposal-id milestone-titles
                    milestone-descriptions milestone-amounts
                ))
                (current-count (default-to u0
                    (get proposal-count
                        (map-get? alumni-proposals { alumnus: proposer })
                    )))
            )
            (map-set alumni-proposals { alumnus: proposer } { proposal-count: (+ current-count u1) })
        )

        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
    )
)

(define-public (vote-milestone-verification
        (proposal-id uint)
        (milestone-id uint)
        (vote-for bool)
    )
    (let (
            (voter tx-sender)
            (voter-data (unwrap! (map-get? alumni { alumnus: voter }) ERR-UNAUTHORIZED))
            (milestone-data (unwrap!
                (map-get? milestones {
                    proposal-id: proposal-id,
                    milestone-id: milestone-id,
                })
                ERR-INVALID-MILESTONE
            ))
            (milestone-proposal-data (unwrap! (map-get? milestone-proposals { proposal-id: proposal-id })
                ERR-INVALID-MILESTONE
            ))
            (current-height stacks-block-height)
        )
        (asserts! (get active voter-data) ERR-UNAUTHORIZED)
        (asserts!
            (is-eq milestone-id (get current-milestone milestone-proposal-data))
            ERR-MILESTONE-NOT-READY
        )
        (asserts! (< current-height (get voting-ends milestone-data))
            ERR-VOTING-CLOSED
        )
        (asserts! (not (get verified milestone-data))
            ERR-MILESTONE-ALREADY-VERIFIED
        )
        (asserts!
            (is-none (map-get? milestone-votes {
                proposal-id: proposal-id,
                milestone-id: milestone-id,
                voter: voter,
            }))
            ERR-ALREADY-VOTED
        )

        (let ((effective-voting-power (get-effective-voting-power voter)))
            (map-set milestone-votes {
                proposal-id: proposal-id,
                milestone-id: milestone-id,
                voter: voter,
            } {
                vote: vote-for,
                voting-power: effective-voting-power,
                voted-at: current-height,
            })

            (if vote-for
                (map-set milestones {
                    proposal-id: proposal-id,
                    milestone-id: milestone-id,
                }
                    (merge milestone-data { verification-votes-for: (+ (get verification-votes-for milestone-data)
                        effective-voting-power
                    ) }
                    ))
                (map-set milestones {
                    proposal-id: proposal-id,
                    milestone-id: milestone-id,
                }
                    (merge milestone-data { verification-votes-against: (+ (get verification-votes-against milestone-data)
                        effective-voting-power
                    ) }
                    ))
            )
            (ok true)
        )
    )
)

(define-public (execute-milestone-verification
        (proposal-id uint)
        (milestone-id uint)
    )
    (let (
            (milestone-data (unwrap!
                (map-get? milestones {
                    proposal-id: proposal-id,
                    milestone-id: milestone-id,
                })
                ERR-INVALID-MILESTONE
            ))
            (milestone-proposal-data (unwrap! (map-get? milestone-proposals { proposal-id: proposal-id })
                ERR-INVALID-MILESTONE
            ))
            (current-height stacks-block-height)
        )
        (asserts!
            (is-eq milestone-id (get current-milestone milestone-proposal-data))
            ERR-MILESTONE-NOT-READY
        )
        (asserts! (>= current-height (get voting-ends milestone-data))
            ERR-VOTING-CLOSED
        )
        (asserts! (not (get verified milestone-data))
            ERR-MILESTONE-ALREADY-VERIFIED
        )
        (asserts!
            (> (get verification-votes-for milestone-data)
                (get verification-votes-against milestone-data)
            )
            ERR-UNAUTHORIZED
        )

        (map-set milestones {
            proposal-id: proposal-id,
            milestone-id: milestone-id,
        }
            (merge milestone-data { verified: true })
        )

        (ok true)
    )
)

(define-public (release-milestone-funds
        (proposal-id uint)
        (milestone-id uint)
    )
    (let (
            (milestone-data (unwrap!
                (map-get? milestones {
                    proposal-id: proposal-id,
                    milestone-id: milestone-id,
                })
                ERR-INVALID-MILESTONE
            ))
            (milestone-proposal-data (unwrap! (map-get? milestone-proposals { proposal-id: proposal-id })
                ERR-INVALID-MILESTONE
            ))
            (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id })
                ERR-NOT-FOUND
            ))
        )
        (asserts!
            (is-eq milestone-id (get current-milestone milestone-proposal-data))
            ERR-MILESTONE-NOT-READY
        )
        (asserts! (get verified milestone-data) ERR-UNAUTHORIZED)
        (asserts! (not (get funds-released milestone-data))
            ERR-MILESTONE-FUNDS-RELEASED
        )
        (asserts! (get active proposal-data) ERR-INVALID-PROPOSAL)

        (let ((milestone-amount (get amount milestone-data)))
            (asserts! (<= milestone-amount (var-get total-funds))
                ERR-INSUFFICIENT-FUNDS
            )

            (try! (as-contract (stx-transfer? milestone-amount tx-sender
                (get recipient proposal-data)
            )))

            (map-set milestones {
                proposal-id: proposal-id,
                milestone-id: milestone-id,
            }
                (merge milestone-data { funds-released: true })
            )

            (let ((next-milestone (+ milestone-id u1)))
                (if (<= next-milestone
                        (get total-milestones milestone-proposal-data)
                    )
                    (begin
                        (map-set milestone-proposals { proposal-id: proposal-id }
                            (merge milestone-proposal-data { current-milestone: next-milestone })
                        )
                        (try! (start-milestone-verification proposal-id next-milestone))
                    )
                    (map-set proposals { proposal-id: proposal-id }
                        (merge proposal-data {
                            executed: true,
                            active: false,
                        })
                    )
                )
            )

            (var-set total-funds (- (var-get total-funds) milestone-amount))
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

(define-public (define-achievement
        (name (string-ascii 50))
        (description (string-ascii 200))
        (category (string-ascii 30))
        (difficulty (string-ascii 20))
        (points uint)
    )
    (let (
            (achievement-id (+ (var-get achievement-counter) u1))
            (current-height stacks-block-height)
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (> (len name) u0) ERR-INVALID-AMOUNT)
        (asserts! (> (len description) u0) ERR-INVALID-AMOUNT)
        (asserts! (> (len category) u0) ERR-INVALID-AMOUNT)
        (asserts!
            (or
                (is-eq difficulty "easy")
                (is-eq difficulty "medium")
                (is-eq difficulty "hard")
                (is-eq difficulty "expert")
            )
            ERR-INVALID-DIFFICULTY
        )
        (asserts! (> points u0) ERR-INVALID-AMOUNT)

        (map-set achievements { achievement-id: achievement-id } {
            name: name,
            description: description,
            category: category,
            difficulty: difficulty,
            points: points,
            created-at: current-height,
            created-by: tx-sender,
        })

        (var-set achievement-counter achievement-id)
        (ok achievement-id)
    )
)

(define-public (claim-achievement (achievement-id uint))
    (let (
            (alumnus tx-sender)
            (achievement-data (unwrap! (map-get? achievements { achievement-id: achievement-id })
                ERR-ACHIEVEMENT-NOT-FOUND
            ))
            (alumni-data (unwrap! (map-get? alumni { alumnus: alumnus }) ERR-UNAUTHORIZED))
            (current-height stacks-block-height)
            (category (get category achievement-data))
            (contribution (get contribution alumni-data))
            (voting-power (get voting-power alumni-data))
            (proposal-count (default-to u0
                (get proposal-count (map-get? alumni-proposals { alumnus: alumnus }))
            ))
        )
        (asserts! (get active alumni-data) ERR-UNAUTHORIZED)
        (asserts!
            (is-none (map-get? alumni-achievements {
                alumnus: alumnus,
                achievement-id: achievement-id,
            }))
            ERR-ACHIEVEMENT-ALREADY-EARNED
        )
        (asserts!
            (is-achievement-eligible category contribution voting-power proposal-count)
            ERR-ACHIEVEMENT-NOT-ELIGIBLE
        )

        (map-set alumni-achievements {
            alumnus: alumnus,
            achievement-id: achievement-id,
        } {
            earned-at: current-height,
            verified: true,
        })

        (update-alumni-stats alumnus (get points achievement-data))
        (ok true)
    )
)

(define-public (award-achievement
        (alumnus principal)
        (achievement-id uint)
    )
    (let (
            (achievement-data (unwrap! (map-get? achievements { achievement-id: achievement-id })
                ERR-ACHIEVEMENT-NOT-FOUND
            ))
            (alumni-data (unwrap! (map-get? alumni { alumnus: alumnus }) ERR-NOT-FOUND))
            (current-height stacks-block-height)
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (get active alumni-data) ERR-UNAUTHORIZED)
        (asserts!
            (is-none (map-get? alumni-achievements {
                alumnus: alumnus,
                achievement-id: achievement-id,
            }))
            ERR-ACHIEVEMENT-ALREADY-EARNED
        )

        (map-set alumni-achievements {
            alumnus: alumnus,
            achievement-id: achievement-id,
        } {
            earned-at: current-height,
            verified: true,
        })

        (update-alumni-stats alumnus (get points achievement-data))
        (ok true)
    )
)

(define-public (check-achievement-eligibility
        (alumnus principal)
        (achievement-id uint)
    )
    (let (
            (achievement-data (unwrap! (map-get? achievements { achievement-id: achievement-id })
                ERR-ACHIEVEMENT-NOT-FOUND
            ))
            (alumni-data (unwrap! (map-get? alumni { alumnus: alumnus }) ERR-NOT-FOUND))
            (category (get category achievement-data))
            (contribution (get contribution alumni-data))
            (voting-power (get voting-power alumni-data))
            (proposal-count (default-to u0
                (get proposal-count (map-get? alumni-proposals { alumnus: alumnus }))
            ))
        )
        (asserts! (get active alumni-data) ERR-UNAUTHORIZED)
        (asserts!
            (is-none (map-get? alumni-achievements {
                alumnus: alumnus,
                achievement-id: achievement-id,
            }))
            ERR-ACHIEVEMENT-ALREADY-EARNED
        )
        (asserts!
            (is-achievement-eligible category contribution voting-power proposal-count)
            ERR-ACHIEVEMENT-NOT-ELIGIBLE
        )
        (ok true)
    )
)

(define-private (is-achievement-eligible
        (category (string-ascii 30))
        (contribution uint)
        (voting-power uint)
        (proposal-count uint)
    )
    (or
        (and (is-eq category "contributor") (>= contribution u5000000))
        (and (is-eq category "governance") (>= voting-power u10000))
        (and (is-eq category "community") (>= proposal-count u3))
    )
)

(define-private (update-alumni-stats (alumnus principal) (points uint))
    (let ((stats (default-to DEFAULT-ALUMNI-STATS (map-get? alumni-stats { alumnus: alumnus }))))
        (map-set alumni-stats { alumnus: alumnus } {
            total-points: (+ (get total-points stats) points),
            total-achievements: (+ (get total-achievements stats) u1),
        })
        true
    )
)

(define-private (calculate-voting-power (contribution uint))
    (if (< contribution u1000000)
        u0
        (/ contribution u1000)
    )
)

(define-private (create-milestones-iter
        (proposal-id uint)
        (titles (list 10 (string-ascii 100)))
        (descriptions (list 10 (string-ascii 300)))
        (amounts (list 10 uint))
    )
    (let ((milestone-count (len titles)))
        (and
            (if (> milestone-count u0)
                (map-set milestones {
                    proposal-id: proposal-id,
                    milestone-id: u1,
                } {
                    title: (unwrap-panic (element-at titles u0)),
                    description: (unwrap-panic (element-at descriptions u0)),
                    amount: (unwrap-panic (element-at amounts u0)),
                    verification-votes-for: u0,
                    verification-votes-against: u0,
                    verified: false,
                    funds-released: false,
                    voting-ends: u0,
                })
                true
            )
            (if (> milestone-count u1)
                (map-set milestones {
                    proposal-id: proposal-id,
                    milestone-id: u2,
                } {
                    title: (unwrap-panic (element-at titles u1)),
                    description: (unwrap-panic (element-at descriptions u1)),
                    amount: (unwrap-panic (element-at amounts u1)),
                    verification-votes-for: u0,
                    verification-votes-against: u0,
                    verified: false,
                    funds-released: false,
                    voting-ends: u0,
                })
                true
            )
            (if (> milestone-count u2)
                (map-set milestones {
                    proposal-id: proposal-id,
                    milestone-id: u3,
                } {
                    title: (unwrap-panic (element-at titles u2)),
                    description: (unwrap-panic (element-at descriptions u2)),
                    amount: (unwrap-panic (element-at amounts u2)),
                    verification-votes-for: u0,
                    verification-votes-against: u0,
                    verified: false,
                    funds-released: false,
                    voting-ends: u0,
                })
                true
            )
            (if (> milestone-count u3)
                (map-set milestones {
                    proposal-id: proposal-id,
                    milestone-id: u4,
                } {
                    title: (unwrap-panic (element-at titles u3)),
                    description: (unwrap-panic (element-at descriptions u3)),
                    amount: (unwrap-panic (element-at amounts u3)),
                    verification-votes-for: u0,
                    verification-votes-against: u0,
                    verified: false,
                    funds-released: false,
                    voting-ends: u0,
                })
                true
            )
            (if (> milestone-count u4)
                (map-set milestones {
                    proposal-id: proposal-id,
                    milestone-id: u5,
                } {
                    title: (unwrap-panic (element-at titles u4)),
                    description: (unwrap-panic (element-at descriptions u4)),
                    amount: (unwrap-panic (element-at amounts u4)),
                    verification-votes-for: u0,
                    verification-votes-against: u0,
                    verified: false,
                    funds-released: false,
                    voting-ends: u0,
                })
                true
            )
        )
        (ok true)
    )
)

(define-private (start-milestone-verification
        (proposal-id uint)
        (milestone-id uint)
    )
    (let (
            (milestone-data (unwrap!
                (map-get? milestones {
                    proposal-id: proposal-id,
                    milestone-id: milestone-id,
                })
                ERR-INVALID-MILESTONE
            ))
            (milestone-proposal-data (unwrap! (map-get? milestone-proposals { proposal-id: proposal-id })
                ERR-INVALID-MILESTONE
            ))
            (current-height stacks-block-height)
            (voting-ends (+ current-height
                (get milestone-voting-duration milestone-proposal-data)
            ))
        )
        (map-set milestones {
            proposal-id: proposal-id,
            milestone-id: milestone-id,
        }
            (merge milestone-data { voting-ends: voting-ends })
        )
        (ok true)
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

(define-read-only (get-milestone-proposal-data (proposal-id uint))
    (map-get? milestone-proposals { proposal-id: proposal-id })
)

(define-read-only (get-milestone-data
        (proposal-id uint)
        (milestone-id uint)
    )
    (map-get? milestones {
        proposal-id: proposal-id,
        milestone-id: milestone-id,
    })
)

(define-read-only (get-milestone-vote-data
        (proposal-id uint)
        (milestone-id uint)
        (voter principal)
    )
    (map-get? milestone-votes {
        proposal-id: proposal-id,
        milestone-id: milestone-id,
        voter: voter,
    })
)

(define-read-only (is-milestone-ready-for-verification
        (proposal-id uint)
        (milestone-id uint)
    )
    (match (map-get? milestone-proposals { proposal-id: proposal-id })
        milestone-proposal-data (and
            (is-eq milestone-id (get current-milestone milestone-proposal-data))
            (match (map-get? milestones {
                proposal-id: proposal-id,
                milestone-id: milestone-id,
            })
                milestone-data (and
                    (not (get verified milestone-data))
                    (> (get voting-ends milestone-data) u0)
                    (< stacks-block-height (get voting-ends milestone-data))
                )
                false
            )
        )
        false
    )
)

(define-read-only (can-execute-milestone-verification
        (proposal-id uint)
        (milestone-id uint)
    )
    (match (map-get? milestone-proposals { proposal-id: proposal-id })
        milestone-proposal-data (and
            (is-eq milestone-id (get current-milestone milestone-proposal-data))
            (match (map-get? milestones {
                proposal-id: proposal-id,
                milestone-id: milestone-id,
            })
                milestone-data (and
                    (not (get verified milestone-data))
                    (>= stacks-block-height (get voting-ends milestone-data))
                    (> (get verification-votes-for milestone-data)
                        (get verification-votes-against milestone-data)
                    )
                )
                false
            )
        )
        false
    )
)

(define-read-only (get-achievement-data (achievement-id uint))
    (map-get? achievements { achievement-id: achievement-id })
)

(define-read-only (get-alumni-achievement-data
        (alumnus principal)
        (achievement-id uint)
    )
    (map-get? alumni-achievements {
        alumnus: alumnus,
        achievement-id: achievement-id,
    })
)

(define-read-only (is-achievement-unlocked
        (alumnus principal)
        (achievement-id uint)
    )
    (is-some (map-get? alumni-achievements {
        alumnus: alumnus,
        achievement-id: achievement-id,
    }))
)

(define-read-only (get-total-achievements-count)
    (var-get achievement-counter)
)

(define-read-only (get-alumni-total-achievement-points (alumnus principal))
    (let ((alumni-data (map-get? alumni { alumnus: alumnus })))
        (match alumni-data
            data (if (get active data)
                u0
                u0
            )
            u0
        )
    )
)

(define-read-only (get-achievement-leaderboard-entry (alumnus principal))
    (let ((alumni-data (map-get? alumni { alumnus: alumnus })))
        (match alumni-data
            data (if (get active data)
                (some {
                    alumnus: alumnus,
                    total-points: u0,
                    contribution: (get contribution data),
                    voting-power: (get voting-power data),
                })
                none
            )
            none
        )
    )
)

(define-read-only (get-alumni-total-achievement-points-v2 (alumnus principal))
    (match (map-get? alumni { alumnus: alumnus })
        alumni-data (if (get active alumni-data)
            (match (map-get? alumni-stats { alumnus: alumnus })
                stats (get total-points stats)
                u0
            )
            u0
        )
        u0
    )
)

(define-read-only (get-achievement-leaderboard-entry-v2 (alumnus principal))
    (match (map-get? alumni { alumnus: alumnus })
        alumni-data (if (get active alumni-data)
            (let ((stats (default-to DEFAULT-ALUMNI-STATS (map-get? alumni-stats { alumnus: alumnus }))))
                (some {
                    alumnus: alumnus,
                    total-points: (get total-points stats),
                    total-achievements: (get total-achievements stats),
                    contribution: (get contribution alumni-data),
                    voting-power: (get voting-power alumni-data),
                })
            )
            none
        )
        none
    )
)

(define-read-only (get-alumni-stats-v2 (alumnus principal))
    (match (map-get? alumni { alumnus: alumnus })
        alumni-data (if (get active alumni-data)
            (some (default-to DEFAULT-ALUMNI-STATS (map-get? alumni-stats { alumnus: alumnus })))
            none
        )
        none
    )
)

(define-read-only (can-release-milestone-funds
        (proposal-id uint)
        (milestone-id uint)
    )
    (match (map-get? milestone-proposals { proposal-id: proposal-id })
        milestone-proposal-data (and
            (is-eq milestone-id (get current-milestone milestone-proposal-data))
            (match (map-get? milestones {
                proposal-id: proposal-id,
                milestone-id: milestone-id,
            })
                milestone-data (and
                    (get verified milestone-data)
                    (not (get funds-released milestone-data))
                )
                false
            )
        )
        false
    )
)
