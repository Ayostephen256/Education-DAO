# 🎓 Education DAO Smart Contract

A decentralized autonomous organization (DAO) built on the Stacks blockchain that enables alumni to contribute funds and vote on scholarship proposals for students.

## 🌟 Features

- 👥 **Alumni Registration**: Alumni can register and become voting members
- 💰 **Fund Contributions**: Alumni contribute STX tokens to the scholarship fund
- 📝 **Scholarship Proposals**: Create proposals for scholarship recipients
- 🗳️ **Voting System**: Vote on scholarship proposals with voting power based on contributions
- 🚀 **Proposal Execution**: Automatically distribute funds to approved scholarships
- ⚙️ **Governance**: Configurable voting parameters and proposal management

## 🏗️ Contract Architecture

### Core Data Structures

- **Alumni**: Registered members with contribution history and voting power
- **Proposals**: Scholarship proposals with voting details and execution status
- **Votes**: Individual votes cast by alumni on proposals

### Key Functions

#### 📋 Alumni Management
- `register-alumni()` - Register as an alumni member
- `contribute-funds(amount)` - Contribute STX to the scholarship fund
- `deactivate-alumni(alumnus)` - Deactivate an alumni member (owner only)

#### 📊 Proposal Management
- `create-proposal(title, description, recipient, amount)` - Create a scholarship proposal
- `vote-on-proposal(proposal-id, vote-for)` - Vote on a proposal
- `execute-proposal(proposal-id)` - Execute approved proposals
- `close-proposal(proposal-id)` - Close a proposal (proposer or owner only)

#### ⚙️ Governance
- `set-voting-duration(new-duration)` - Set voting period duration
- `set-min-voting-power(new-power)` - Set minimum voting power to create proposals

## 🚀 Quick Start

### Prerequisites
- [Clarinet](https://docs.hiro.so/stacks/clarinet) installed
- STX tokens for testing

### Installation
```bash
git clone <repository-url>
cd education-dao
clarinet check
```

### Testing
```bash
npm install
npm test
```

## 💡 Usage Examples

### 1. Register as Alumni
```clarity
(contract-call? .education-dao register-alumni)
```

### 2. Contribute Funds
```clarity
(contract-call? .education-dao contribute-funds u1000000)
```

### 3. Create Scholarship Proposal
```clarity
(contract-call? .education-dao create-proposal 
  "Computer Science Scholarship" 
  "Supporting outstanding CS students" 
  'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM 
  u500000)
```

### 4. Vote on Proposal
```clarity
(contract-call? .education-dao vote-on-proposal u1 true)
```

### 5. Execute Approved Proposal
```clarity
(contract-call? .education-dao execute-proposal u1)
```

## 📊 Voting System

### Voting Power Calculation
- Voting power = contribution amount ÷ 1000
- Minimum contribution for voting power: 1,000,000 microSTX (1 STX)
- Minimum voting power to create proposals: 1,000,000 (configurable)

### Voting Rules
- Alumni can vote once per proposal
- Voting ends after the configured duration (default: 1008 blocks)
- Proposals pass when votes-for > votes-against
- Only approved proposals can be executed

## 🛠️ Configuration

### Default Settings
- **Voting Duration**: 1008 blocks (~7 days)
- **Minimum Voting Power**: 1,000,000 (1 STX worth of contributions)

### Admin Functions
Only the contract owner can:
- Set voting duration
- Set minimum voting power requirements
- Deactivate alumni members

## 📖 Read-Only Functions

Query contract state with these functions:
- `get-alumni-data(alumnus)` - Get alumni information
- `get-proposal-data(proposal-id)` - Get proposal details
- `get-vote-data(proposal-id, voter)` - Get vote information
- `get-total-funds()` - Get total funds in the DAO
- `is-proposal-active(proposal-id)` - Check if proposal is active
- `can-execute-proposal(proposal-id)` - Check if proposal can be executed

## 🔒 Security Features

- Only registered alumni can participate
- Voting power based on actual contributions
- Time-locked voting periods
- Proposal execution requires majority approval
- Contract owner controls for emergency situations

## 📄 Error Codes

- `u400`: Invalid amount
- `u401`: Unauthorized access
- `u402`: Insufficient funds
- `u403`: Voting period closed
- `u404`: Resource not found
- `u405`: Already voted
- `u406`: Invalid proposal
- `u407`: Proposal still active
- `u409`: Resource already exists

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes with `clarinet check`
4. Submit a pull request

## 📜 License

This project is open source and available under the MIT License.

---

*Built with ❤️ for educational empowerment through blockchain technology*
