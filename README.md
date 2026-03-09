# Bounty Contract (ETH & USDC)

A secure and flexible **on-chain bounty payout system** built in Solidity.
This contract allows users to **create bounties in ETH or USDC**, specify how rewards should be distributed, and enables **winners to claim their rewards individually**.

The system supports **single winners, multiple winners, equal reward splits, and percentage-based reward distributions**, while maintaining strong security guarantees.

---

# Overview

The **Bounty Contract** is designed for platforms that need to reward contributors such as:

* Developers
* Hackathon participants
* Bug bounty hunters
* DAO contributors
* Community competitions
* Research tasks

A bounty creator deposits funds when creating a bounty.
Winners are later assigned, and **each winner claims their reward individually**, preventing failed mass payouts and improving scalability.

The contract also includes a **5% platform fee**, security protections, and supports **up to 5 winners per bounty**.

---

# Features

## Multi Token Support

Bounties can be funded using:

* **ETH**
* **USDC (ERC20)**

---

## Multiple Payout Types

### 1. Single Winner

One winner receives the entire bounty reward.

Example:

```
Reward: 10 ETH
Winner: Alice

Alice claims 10 ETH
```

---

### 2. Equal Split (Multi Winner)

Reward is split equally among winners.

Example:

```
Reward: 10 ETH
Winners: 5

Each winner receives:
2 ETH
```

---

### 3. Percentage Based Split

Reward is distributed according to custom percentages.

Supported configurations:

```
[40, 30, 20, 5, 5]
[40, 30, 20, 10]
[50, 30, 20]
[50, 50]
```

Rules:

* Minimum winners: **2**
* Maximum winners: **5**
* Percentages must sum to **100**
* A wallet **cannot win twice**

Example:

```
Reward: 1000 USDC
Percentages: [50, 30, 20]
Winners: Alice, Bob, Charlie
```

Payout:

```
Alice → 500 USDC
Bob → 300 USDC
Charlie → 200 USDC
```

---

# Platform Fee

When creating a bounty, the creator pays:

```
reward + 5% platform fee
```

Example:

```
Reward = 100 USDC
Fee = 5 USDC
Total paid = 105 USDC
```

The reward pool remains intact while the **5% fee is retained by the platform**.

---

# Individual Claim System

Instead of sending rewards to all winners at once, each winner **claims their reward themselves**.

Advantages:

* Prevents **gas limit failures**
* Eliminates **loop payout vulnerabilities**
* Supports **large numbers of winners**
* Improves **transaction reliability**

Example claim flow:

```
1. Creator creates bounty
2. Creator assigns winners
3. Winner calls claimReward()
4. Contract verifies eligibility
5. Contract transfers reward
```

---

# Security Features

The contract uses several security mechanisms to protect funds.

## Reentrancy Protection

Uses **Reentrancy Guard** to prevent reentrancy attacks during payouts.

---

## Strict Validation Checks

The contract validates:

* Bounty existence
* Winner eligibility
* Reward not already claimed
* Correct percentage totals
* Maximum winners limit

---

## Double Claim Prevention

Each winner can claim **only once**.

```
mapping(address => bool) hasClaimed
```

---

## Safe Token Transfers

Uses secure transfer patterns for:

* ETH transfers
* ERC20 transfers

---

## Ownership Controls

Certain administrative functions are protected using **Ownable access control**.

Examples include:

* Platform withdrawals
* Emergency fund recovery

---

# Contract Architecture

Each bounty stores the following information:

```
Bounty
 ├── creator
 ├── reward amount
 ├── token type (ETH or USDC)
 ├── payout type
 ├── winners list
 ├── percentage distribution
 ├── claim status per winner
 └── paid status
```

Winners interact with the contract independently using the **claim function**.

---

# Bounty Lifecycle

### 1. Create Bounty

Creator funds the bounty.

```
createBounty(tokenType, rewardAmount)
```

---

### 2. Assign Winners

Creator specifies winners and distribution.

```
setWinners(bountyId, winners, percentages)
```

---

### 3. Winners Claim Rewards

Each winner calls:

```
claimReward(bountyId)
```

The contract verifies eligibility and transfers the correct amount.

---

# Example Workflow

### Step 1 — Create Bounty

```
Reward: 1000 USDC
Fee: 50 USDC
Total paid: 1050 USDC
```

---

### Step 2 — Assign Winners

```
Winners:
Alice
Bob
Charlie

Percentages:
[50,30,20]
```

---

### Step 3 — Claims

```
Alice claims → 500 USDC
Bob claims → 300 USDC
Charlie claims → 200 USDC
```

---

# Contract Events

The contract emits events for off-chain indexing and UI updates.

### Bounty Created

```
BountyCreated(
    bountyId,
    creator,
    rewardAmount,
    tokenType
)
```

---

### Winners Assigned

```
WinnersAssigned(
    bountyId,
    winners
)
```

---

### Reward Claimed

```
RewardClaimed(
    bountyId,
    winner,
    amount
)
```

---

# Future Upgrade: Merkle Tree Architecture

The current system stores winner data on-chain.

Future upgrades will implement **Merkle Tree based payouts**, allowing:

* **100k+ winners**
* **minimal storage**
* **lower gas costs**

Merkle architecture allows winners to prove eligibility using **Merkle proofs** instead of storing every winner on-chain.

---

# Development Stack

```
Solidity ^0.8.x
OpenZeppelin Contracts
Hardhat / Foundry (recommended)
```

Libraries used:

* Ownable
* ReentrancyGuard
* IERC20
* Counters

---

# Potential Use Cases

* Hackathon prizes
* DAO contributor rewards
* Bug bounty programs
* Community competitions
* Web3 freelance marketplaces
* Research task rewards
* Security vulnerability payouts

---

# Future Improvements

Planned upgrades include:

* Merkle based payout architecture
* NFT bounty rewards
* Multi token ERC20 support
* Bounty expiration
* Automated dispute resolution
* Frontend dashboard
* DAO governance integration

---

# License

MIT License

---

# Author 
Osfoce

Developed as part of a **secure bounty payout system for Web3 platforms**.
