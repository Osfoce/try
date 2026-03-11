// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
|--------------------------------------------------------------------------
| IMPORTS
|--------------------------------------------------------------------------
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Counters} from "./Counters.sol";

contract BountyContract is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    /*
    |--------------------------------------------------------------------------
    | CONSTANTS
    |--------------------------------------------------------------------------
    */

    uint256 public constant FEE_PERCENT = 5;
    uint256 public constant MAX_WINNERS = 5;

    /*
    |--------------------------------------------------------------------------
    | STATE VARIABLES
    |--------------------------------------------------------------------------
    */

    IERC20 public usdcToken;

    Counters.Counter private _bountyCounter;

    /*
    |--------------------------------------------------------------------------
    | FEE ACCOUNTING
    |--------------------------------------------------------------------------
    */

    uint256 public totalEthFees; // ADDED
    uint256 public totalUsdcFees; // ADDED

    /*
    |--------------------------------------------------------------------------
    | ENUMS
    |--------------------------------------------------------------------------
    */

    enum TokenType {
        ETH,
        USDC
    }

    enum PayoutType {
        SINGLE,
        MULTI_EQUAL,
        MULTI_PERCENTAGE
    }

    /*
    |--------------------------------------------------------------------------
    | BOUNTY STRUCT
    |--------------------------------------------------------------------------
    */

    struct Bounty {
        uint256 reward;
        uint256 fee;
        TokenType tokenType;
        PayoutType payoutType;
        address creator;
        address[] winners;
        bool rewardsAssigned;
        bool isClaimed;
    }

    /*
    |--------------------------------------------------------------------------
    | STORAGE
    |--------------------------------------------------------------------------
    */

    mapping(bytes32 => Bounty) private bounties;
    bytes32[] public allBountyIds;

    /*
    |--------------------------------------------------------------------------
    | CLAIMABLE REWARDS STORAGE
    |--------------------------------------------------------------------------
    */

    mapping(bytes32 => mapping(address => uint256)) public claimableRewards;

    mapping(bytes32 => mapping(address => bool)) public claimed;

    /*
    |--------------------------------------------------------------------------
    | EVENTS
    |--------------------------------------------------------------------------
    */

    event BountyCreated(
        bytes32 bountyId,
        address creator,
        uint256 reward,
        uint256 fee,
        TokenType tokenType,
        PayoutType payoutType
    );

    event RewardsAssigned(bytes32 bountyId);
    event FeeWithdrawn(address recipient, uint256 amount, string tokenType);

    event RewardClaimed(bytes32 bountyId, address winner, uint256 amount);

    /*
    |--------------------------------------------------------------------------
    | CONSTRUCTOR
    |--------------------------------------------------------------------------
    */

    constructor(
        address initialOwner,
        address _usdcTokenAddress
    ) Ownable(initialOwner) {
        require(_usdcTokenAddress != address(0), "Invalid USDC address");
        usdcToken = IERC20(_usdcTokenAddress);
    }

    /*
    |--------------------------------------------------------------------------
    | CREATE BOUNTY
    |--------------------------------------------------------------------------
    */

    function createBounty(
        TokenType _tokenType,
        uint256 _reward,
        PayoutType _payoutType
    ) external payable returns (bytes32) {
        require(_reward > 0, "Reward must be > 0");

        uint256 fee = (_reward * FEE_PERCENT) / 100;
        uint256 totalRequired = _reward + fee;

        /*
        ------------------------------------------------------
        ETH BOUNTY
        ------------------------------------------------------
        */

        if (_tokenType == TokenType.ETH) {
            require(msg.value >= totalRequired, "Incorrect ETH amount");
            totalEthFees += fee; // ADDED fee accounting

            // refund extra ETH if user overpays
            // if (msg.value > totalRequired) {
            //     payable(msg.sender).transfer(msg.value - totalRequired);
            // }
        }
        /*
        ------------------------------------------------------
        USDC BOUNTY
        ------------------------------------------------------
        */
        else {
            require(msg.value == 0, "ETH not accepted");

            usdcToken.safeTransferFrom(
                msg.sender,
                address(this),
                totalRequired
            );

            totalUsdcFees += fee; // ADDED fee accounting
        }

        /*
        ------------------------------------------------------
        GENERATE BOUNTY ID
        ------------------------------------------------------
        */

        _bountyCounter.increment();

        bytes32 bountyId = keccak256(
            abi.encodePacked(
                _bountyCounter.current(),
                msg.sender,
                block.timestamp
            )
        );

        allBountyIds.push(bountyId);

        /*
        ------------------------------------------------------
        STORE BOUNTY
        ------------------------------------------------------
        */

        bounties[bountyId] = Bounty({
            reward: _reward,
            fee: fee,
            tokenType: _tokenType,
            payoutType: _payoutType,
            creator: msg.sender,
            rewardsAssigned: false,
            winners: new address[](0),
            isClaimed: false
        });

        emit BountyCreated(
            bountyId,
            msg.sender,
            _reward,
            fee,
            _tokenType,
            _payoutType
        );

        return bountyId;
    }

    /*
    |--------------------------------------------------------------------------
    | ASSIGN SINGLE WINNER
    |--------------------------------------------------------------------------
    */

    function assignSingleWinner(bytes32 bountyId, address winner) external {
        Bounty storage bounty = bounties[bountyId];

        require(
            msg.sender == bounty.creator || msg.sender == owner(),
            "Unauthorized"
        );

        require(!bounty.rewardsAssigned, "Already assigned");

        require(bounty.payoutType == PayoutType.SINGLE, "Invalid payout type");

        require(winner != address(0), "Invalid winner");

        claimableRewards[bountyId][winner] = bounty.reward;
        bounty.winners.push(winner);

        bounty.rewardsAssigned = true;

        emit RewardsAssigned(bountyId);
    }

    /*
    |--------------------------------------------------------------------------
    | ASSIGN MULTIPLE WINNERS
    |--------------------------------------------------------------------------
    */

    function assignMultipleWinners(
        bytes32 bountyId,
        address[] calldata winners,
        uint256[] calldata percentages
    ) external {
        Bounty storage bounty = bounties[bountyId];

        require(
            msg.sender == bounty.creator || msg.sender == owner(),
            "Unauthorized"
        );

        require(!bounty.rewardsAssigned, "Already assigned");

        uint256 count = winners.length;
        bounty.winners = winners;

        require(count >= 2, "Minimum 2 winners");
        require(count <= MAX_WINNERS, "Too many winners");

        /*
        |--------------------------------------------------------------------------
        | DUPLICATE WINNER CHECK
        |--------------------------------------------------------------------------
        */

        for (uint256 i = 0; i < count; i++) {
            require(winners[i] != address(0), "Invalid winner");

            for (uint256 j = i + 1; j < count; j++) {
                require(winners[i] != winners[j], "Duplicate winner");
            }
        }

        uint256 reward = bounty.reward;
        uint256 distributed;

        /*
        |--------------------------------------------------------------------------
        | EQUAL SPLIT
        |--------------------------------------------------------------------------
        */

        if (bounty.payoutType == PayoutType.MULTI_EQUAL) {
            uint256 share = reward / count;

            for (uint256 i = 0; i < count; i++) {
                claimableRewards[bountyId][winners[i]] = share;
                distributed += share;
            }

            claimableRewards[bountyId][winners[count - 1]] +=
                reward -
                distributed;
        }
        /*
        |--------------------------------------------------------------------------
        | PERCENTAGE SPLIT
        |--------------------------------------------------------------------------
        */
        else if (bounty.payoutType == PayoutType.MULTI_PERCENTAGE) {
            require(percentages.length == count, "Percent mismatch");

            uint256 totalPercent;

            for (uint256 i = 0; i < count; i++) {
                totalPercent += percentages[i];
            }

            require(totalPercent == 100, "Percent must equal 100");

            for (uint256 i = 0; i < count; i++) {
                uint256 payout = (reward * percentages[i]) / 100;

                claimableRewards[bountyId][winners[i]] = payout;

                distributed += payout;
            }

            claimableRewards[bountyId][winners[count - 1]] +=
                reward -
                distributed;
        } else {
            revert("Invalid payout type");
        }

        bounty.rewardsAssigned = true;

        emit RewardsAssigned(bountyId);
    }

    /*
    |--------------------------------------------------------------------------
    | CLAIM REWARD
    |--------------------------------------------------------------------------
    */

    function claimReward(bytes32 bountyId) external nonReentrant {
        uint256 amount = claimableRewards[bountyId][msg.sender];

        require(amount > 0, "Nothing to claim");

        require(!claimed[bountyId][msg.sender], "Already claimed");

        require(msg.sender != address(0), "Invalid address");

        Bounty storage bounty = bounties[bountyId];

        claimed[bountyId][msg.sender] = true;
        claimableRewards[bountyId][msg.sender] = 0;
        // bounty.rewardsAssigned = false;
        if (bounty.payoutType == PayoutType.SINGLE) {
            bounty.isClaimed = true;
        }

        if (
            bounty.payoutType == PayoutType.MULTI_EQUAL ||
            bounty.payoutType == PayoutType.MULTI_PERCENTAGE
        ) {
            bool allClaimed = true;

            for (uint256 i = 0; i < bounty.winners.length; i++) {
                if (!claimed[bountyId][bounty.winners[i]]) {
                    allClaimed = false;
                    break;
                }
            }

            if (allClaimed) {
                bounty.isClaimed = true;
            }
        }

        if (bounty.tokenType == TokenType.ETH) {
            (bool sent, ) = payable(msg.sender).call{value: amount}("");

            require(sent, "ETH transfer failed!!");
        } else {
            usdcToken.safeTransfer(msg.sender, amount);
        }

        emit RewardClaimed(bountyId, msg.sender, amount);
    }

    /*
    |--------------------------------------------------------------------------
    | VIEW BOUNTY INFO
    |--------------------------------------------------------------------------
    */

    function getBountyInfo(
        bytes32 bountyId
    )
        external
        view
        returns (
            address creator,
            address[] memory winners,
            uint256 reward,
            uint256 fee,
            bool rewardsAssigned,
            bool isClaimed,
            TokenType tokenType,
            PayoutType payoutType
        )
    {
        Bounty storage bounty = bounties[bountyId];

        return (
            bounty.creator,
            bounty.winners,
            bounty.reward,
            bounty.fee,
            bounty.rewardsAssigned,
            bounty.isClaimed,
            bounty.tokenType,
            bounty.payoutType
        );
    }

    /*
    |--------------------------------------------------------------------------
    | OWNER WITHDRAW
    |--------------------------------------------------------------------------
    */

    function withdraw(
        TokenType tokenType,
        address recipient
    ) external nonReentrant onlyOwner {
        require(recipient != address(0), "Invalid address");

        if (tokenType == TokenType.ETH) {
            uint256 amount = totalEthFees;

            require(amount > 0, "No fees");

            totalEthFees = 0; // reset before transfer to prevent reentrancy

            (bool sent, ) = recipient.call{value: amount}("");

            require(sent, "Withdraw failed");

            emit FeeWithdrawn(recipient, amount, "ETH");
        } else {
            uint256 amount = totalUsdcFees;

            require(amount > 0, "No fees");

            totalUsdcFees = 0; // reset before transfer to prevent reentrancy

            usdcToken.safeTransfer(recipient, amount);

            emit FeeWithdrawn(recipient, amount, "USDC");
        }
    }

    function availableBounties() external view returns (bytes32[] memory) {
        return allBountyIds;
    }

    /*
    |--------------------------------------------------------------------------
    | FALLBACK
    |--------------------------------------------------------------------------
    */
    // receive() external payable {
    //     revert("Direct ETH not accepted");
    // }
}
