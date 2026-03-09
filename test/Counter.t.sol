// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BountyContract.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock USDC token for testing
contract MockUSDC is ERC20 {
    uint8 private _decimals;

    constructor() ERC20("Mock USDC", "USDC") {
        _decimals = 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

contract BountyContractTest is Test {
    BountyContract public bounty;
    MockUSDC public usdc;

    address public owner = address(0x1);
    address public creator = address(0x2);
    address public winner1 = address(0x3);
    address public winner2 = address(0x4);
    address public winner3 = address(0x5);
    address public attacker = address(0x6);
    address public feeCollector = address(0x7);

    uint256 constant REWARD_AMOUNT = 1000 * 10 ** 6; // 1000 USDC (6 decimals)
    uint256 constant FEE_AMOUNT = (REWARD_AMOUNT * 5) / 100; // 5% fee
    uint256 constant TOTAL_REQUIRED = REWARD_AMOUNT + FEE_AMOUNT;

    event BountyCreated(
        bytes32 indexed bountyId,
        address indexed creator,
        uint256 reward,
        uint256 fee,
        BountyContract.TokenType tokenType,
        BountyContract.PayoutType payoutType
    );

    event RewardsAssigned(bytes32 indexed bountyId);
    event RewardClaimed(
        bytes32 indexed bountyId,
        address indexed winner,
        uint256 amount
    );

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy bounty contract
        vm.prank(owner);
        bounty = new BountyContract(owner, address(usdc));

        // Mint USDC to creator and approve
        usdc.mint(creator, TOTAL_REQUIRED * 10);
        vm.prank(creator);
        usdc.approve(address(bounty), type(uint256).max);

        // Fund attacker for testing
        vm.deal(attacker, 100 ether);
        usdc.mint(attacker, TOTAL_REQUIRED * 10);
        vm.prank(attacker);
        usdc.approve(address(bounty), type(uint256).max);

        // Fund winners for testing
        vm.deal(winner1, 10 ether);
        vm.deal(winner2, 10 ether);
        vm.deal(winner3, 10 ether);
    }

    /*
    |--------------------------------------------------------------------------
    | CONSTRUCTOR TESTS
    |--------------------------------------------------------------------------
    */

    function test_Constructor() public {
        assertEq(bounty.owner(), owner);
        assertEq(address(bounty.usdcToken()), address(usdc));
        assertEq(bounty.FEE_PERCENT(), 5);
        assertEq(bounty.MAX_WINNERS(), 5);
    }

    /*
    |--------------------------------------------------------------------------
    | CREATE BOUNTY TESTS
    |--------------------------------------------------------------------------
    */

    function test_CreateBountyWithETH() public {
        uint256 ethAmount = 1 ether;
        uint256 fee = (ethAmount * 5) / 100;
        uint256 totalRequired = ethAmount + fee;

        vm.deal(creator, totalRequired);

        vm.prank(creator);
        bytes32 bountyId = bounty.createBounty{value: totalRequired}(
            BountyContract.TokenType.ETH,
            ethAmount,
            BountyContract.PayoutType.SINGLE
        );

        // Verify bounty creation
        (
            address bountyCreator,
            uint256 reward,
            uint256 feeAmount,
            bool rewardsAssigned,
            BountyContract.TokenType tokenType,
            BountyContract.PayoutType payoutType
        ) = bounty.getBountyInfo(bountyId);

        assertEq(bountyCreator, creator);
        assertEq(reward, ethAmount);
        assertEq(feeAmount, fee);
        assertEq(rewardsAssigned, false);
        assertEq(uint256(tokenType), uint256(BountyContract.TokenType.ETH));
        assertEq(
            uint256(payoutType),
            uint256(BountyContract.PayoutType.SINGLE)
        );
    }

    function test_CreateBountyWithUSDC() public {
        vm.prank(creator);
        bytes32 bountyId = bounty.createBounty(
            BountyContract.TokenType.USDC,
            REWARD_AMOUNT,
            BountyContract.PayoutType.MULTI_EQUAL
        );

        // Verify USDC was transferred
        assertEq(usdc.balanceOf(address(bounty)), TOTAL_REQUIRED);

        (address bountyCreator, uint256 reward, uint256 fee, , , ) = bounty
            .getBountyInfo(bountyId);

        assertEq(bountyCreator, creator);
        assertEq(reward, REWARD_AMOUNT);
        assertEq(fee, FEE_AMOUNT);
    }

    function test_RevertWhen_CreateBountyWithZeroReward() public {
        vm.prank(creator);
        vm.expectRevert("Reward must be > 0");
        bounty.createBounty(
            BountyContract.TokenType.USDC,
            0,
            BountyContract.PayoutType.SINGLE
        );
    }

    function test_RevertWhen_CreateBountyWithIncorrectETHAmount() public {
        vm.deal(creator, 1 ether);

        vm.prank(creator);
        vm.expectRevert("Incorrect ETH amount");
        bounty.createBounty{value: 0.5 ether}(
            BountyContract.TokenType.ETH,
            1 ether,
            BountyContract.PayoutType.SINGLE
        );
    }

    function test_RevertWhen_SendingETHWithUSDCBounty() public {
        vm.deal(creator, 1 ether);

        vm.prank(creator);
        vm.expectRevert("ETH not accepted");
        bounty.createBounty{value: 1 ether}(
            BountyContract.TokenType.USDC,
            REWARD_AMOUNT,
            BountyContract.PayoutType.SINGLE
        );
    }

    /*
    |--------------------------------------------------------------------------
    | ASSIGN SINGLE WINNER TESTS
    |--------------------------------------------------------------------------
    */

    function test_AssignSingleWinner() public {
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.USDC);

        vm.prank(creator);
        bounty.assignSingleWinner(bountyId, winner1);

        assertEq(bounty.claimableRewards(bountyId, winner1), REWARD_AMOUNT);

        (, , , bool rewardsAssigned, , ) = bounty.getBountyInfo(bountyId);

        assertTrue(rewardsAssigned);
    }

    function test_OwnerCanAssignSingleWinner() public {
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.USDC);

        vm.prank(owner);
        bounty.assignSingleWinner(bountyId, winner1);

        assertEq(bounty.claimableRewards(bountyId, winner1), REWARD_AMOUNT);
    }

    function test_RevertWhen_NonAuthorizedAssignsSingleWinner() public {
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.USDC);

        vm.prank(attacker);
        vm.expectRevert("Unauthorized");
        bounty.assignSingleWinner(bountyId, winner1);
    }

    function test_RevertWhen_AssigningToZeroAddress() public {
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.USDC);

        vm.prank(creator);
        vm.expectRevert("Invalid winner");
        bounty.assignSingleWinner(bountyId, address(0));
    }

    function test_RevertWhen_AssigningToWrongPayoutType() public {
        bytes32 bountyId = _createMultiEqualBounty();

        vm.prank(creator);
        vm.expectRevert("Invalid payout type");
        bounty.assignSingleWinner(bountyId, winner1);
    }

    function test_RevertWhen_AssigningTwice() public {
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.USDC);

        vm.prank(creator);
        bounty.assignSingleWinner(bountyId, winner1);

        vm.prank(creator);
        vm.expectRevert("Already assigned");
        bounty.assignSingleWinner(bountyId, winner2);
    }

    /*
    |--------------------------------------------------------------------------
    | ASSIGN MULTIPLE WINNERS TESTS - EQUAL SPLIT
    |--------------------------------------------------------------------------
    */

    function test_AssignMultipleEqualWinners() public {
        bytes32 bountyId = _createMultiEqualBounty();

        address[] memory winners = new address[](3);
        winners[0] = winner1;
        winners[1] = winner2;
        winners[2] = winner3;

        uint256[] memory percentages = new uint256[](0); // Not used for equal split

        vm.prank(creator);
        bounty.assignMultipleWinners(bountyId, winners, percentages);

        uint256 expectedShare = REWARD_AMOUNT / 3;
        uint256 remainder = REWARD_AMOUNT - (expectedShare * 3);

        assertEq(bounty.claimableRewards(bountyId, winner1), expectedShare);
        assertEq(bounty.claimableRewards(bountyId, winner2), expectedShare);
        assertEq(
            bounty.claimableRewards(bountyId, winner3),
            expectedShare + remainder
        );
    }

    function test_AssignMultipleEqualWinnersWithRemainder() public {
        bytes32 bountyId = _createMultiEqualBountyWithOddAmount();

        address[] memory winners = new address[](3);
        winners[0] = winner1;
        winners[1] = winner2;
        winners[2] = winner3;

        vm.prank(creator);
        bounty.assignMultipleWinners(bountyId, winners, new uint256[](0));

        uint256 reward = bounty.getBountyInfo(bountyId).reward;
        uint256 expectedShare = reward / 3;
        uint256 remainder = reward - (expectedShare * 3);

        assertEq(bounty.claimableRewards(bountyId, winner1), expectedShare);
        assertEq(bounty.claimableRewards(bountyId, winner2), expectedShare);
        assertEq(
            bounty.claimableRewards(bountyId, winner3),
            expectedShare + remainder
        );
    }

    /*
    |--------------------------------------------------------------------------
    | ASSIGN MULTIPLE WINNERS TESTS - PERCENTAGE SPLIT
    |--------------------------------------------------------------------------
    */

    function test_AssignMultiplePercentageWinners() public {
        bytes32 bountyId = _createMultiPercentageBounty();

        address[] memory winners = new address[](3);
        winners[0] = winner1;
        winners[1] = winner2;
        winners[2] = winner3;

        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 50;
        percentages[1] = 30;
        percentages[2] = 20;

        vm.prank(creator);
        bounty.assignMultipleWinners(bountyId, winners, percentages);

        uint256 reward = REWARD_AMOUNT;
        uint256 remainder = reward -
            ((reward * 50) / 100 + (reward * 30) / 100 + (reward * 20) / 100);

        assertEq(
            bounty.claimableRewards(bountyId, winner1),
            (reward * 50) / 100
        );
        assertEq(
            bounty.claimableRewards(bountyId, winner2),
            (reward * 30) / 100
        );
        assertEq(
            bounty.claimableRewards(bountyId, winner3),
            (reward * 20) / 100 + remainder
        );
    }

    function test_RevertWhen_PercentageTotalNot100() public {
        bytes32 bountyId = _createMultiPercentageBounty();

        address[] memory winners = new address[](2);
        winners[0] = winner1;
        winners[1] = winner2;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 40;
        percentages[1] = 40; // Total 80, not 100

        vm.prank(creator);
        vm.expectRevert("Percent must equal 100");
        bounty.assignMultipleWinners(bountyId, winners, percentages);
    }

    function test_RevertWhen_PercentageArrayLengthMismatch() public {
        bytes32 bountyId = _createMultiPercentageBounty();

        address[] memory winners = new address[](2);
        winners[0] = winner1;
        winners[1] = winner2;

        uint256[] memory percentages = new uint256[](3); // Mismatched length

        vm.prank(creator);
        vm.expectRevert("Percent mismatch");
        bounty.assignMultipleWinners(bountyId, winners, percentages);
    }

    /*
    |--------------------------------------------------------------------------
    | DUPLICATE WINNER TESTS
    |--------------------------------------------------------------------------
    */

    function test_RevertWhen_DuplicateWinners() public {
        bytes32 bountyId = _createMultiEqualBounty();

        address[] memory winners = new address[](3);
        winners[0] = winner1;
        winners[1] = winner1; // Duplicate
        winners[2] = winner2;

        vm.prank(creator);
        vm.expectRevert("Duplicate winner");
        bounty.assignMultipleWinners(bountyId, winners, new uint256[](0));
    }

    /*
    |--------------------------------------------------------------------------
    | WINNER COUNT TESTS
    |--------------------------------------------------------------------------
    */

    function test_RevertWhen_LessThan2Winners() public {
        bytes32 bountyId = _createMultiEqualBounty();

        address[] memory winners = new address[](1);
        winners[0] = winner1;

        vm.prank(creator);
        vm.expectRevert("Minimum 2 winners");
        bounty.assignMultipleWinners(bountyId, winners, new uint256[](0));
    }

    function test_RevertWhen_MoreThanMaxWinners() public {
        bytes32 bountyId = _createMultiEqualBounty();

        address[] memory winners = new address[](6); // MAX_WINNERS is 5

        for (uint i = 0; i < 6; i++) {
            winners[i] = address(uint160(i + 100));
        }

        vm.prank(creator);
        vm.expectRevert("Too many winners");
        bounty.assignMultipleWinners(bountyId, winners, new uint256[](0));
    }

    /*
    |--------------------------------------------------------------------------
    | CLAIM REWARD TESTS
    |--------------------------------------------------------------------------
    */

    function test_ClaimRewardUSDC() public {
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.USDC);

        vm.prank(creator);
        bounty.assignSingleWinner(bountyId, winner1);

        uint256 balanceBefore = usdc.balanceOf(winner1);

        vm.prank(winner1);
        bounty.claimReward(bountyId);

        assertEq(usdc.balanceOf(winner1), balanceBefore + REWARD_AMOUNT);
        assertTrue(bounty.claimed(bountyId, winner1));
    }

    function test_ClaimRewardETH() public {
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.ETH);

        vm.prank(creator);
        bounty.assignSingleWinner(bountyId, winner1);

        uint256 balanceBefore = winner1.balance;

        vm.prank(winner1);
        bounty.claimReward(bountyId);

        assertEq(winner1.balance, balanceBefore + 1 ether);
        assertTrue(bounty.claimed(bountyId, winner1));
    }

    function test_RevertWhen_ClaimingWithNoReward() public {
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.USDC);

        vm.prank(winner1);
        vm.expectRevert("Nothing to claim");
        bounty.claimReward(bountyId);
    }

    function test_RevertWhen_ClaimingTwice() public {
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.USDC);

        vm.prank(creator);
        bounty.assignSingleWinner(bountyId, winner1);

        vm.prank(winner1);
        bounty.claimReward(bountyId);

        vm.prank(winner1);
        vm.expectRevert("Already claimed");
        bounty.claimReward(bountyId);
    }

    /*
    |--------------------------------------------------------------------------
    | REENTRANCY TESTS
    |--------------------------------------------------------------------------
    */

    function test_ReentrancyOnClaim() public {
        // Deploy malicious contract
        ReentrancyAttacker attackerContract = new ReentrancyAttacker(bounty);

        // Create bounty and assign to attacker contract
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.ETH);

        vm.prank(creator);
        bounty.assignSingleWinner(bountyId, address(attackerContract));

        // Fund the bounty contract with ETH
        vm.deal(address(bounty), 10 ether);

        // Attempt reentrancy
        vm.prank(address(attackerContract));
        attackerContract.attack(bountyId);

        // Verify attack failed - attacker should only be able to claim once
        assertEq(bounty.claimed(bountyId, address(attackerContract)), true);
        assertEq(
            bounty.claimableRewards(bountyId, address(attackerContract)),
            0
        );
    }

    /*
    |--------------------------------------------------------------------------
    | WITHDRAW TESTS
    |--------------------------------------------------------------------------
    */

    function test_OwnerWithdrawETH() public {
        // Create ETH bounty to fund contract
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.ETH);

        uint256 withdrawAmount = 0.5 ether;

        vm.prank(owner);
        bounty.withdraw(
            withdrawAmount,
            BountyContract.TokenType.ETH,
            feeCollector
        );

        assertEq(feeCollector.balance, withdrawAmount);
    }

    function test_OwnerWithdrawUSDC() public {
        // Create USDC bounty to fund contract
        bytes32 bountyId = _createSingleBounty(BountyContract.TokenType.USDC);

        uint256 withdrawAmount = 500 * 10 ** 6; // 500 USDC

        uint256 balanceBefore = usdc.balanceOf(feeCollector);

        vm.prank(owner);
        bounty.withdraw(
            withdrawAmount,
            BountyContract.TokenType.USDC,
            feeCollector
        );

        assertEq(usdc.balanceOf(feeCollector), balanceBefore + withdrawAmount);
    }

    function test_RevertWhen_NonOwnerWithdraw() public {
        vm.prank(creator);
        vm.expectRevert();
        bounty.withdraw(100, BountyContract.TokenType.ETH, feeCollector);
    }

    function test_RevertWhen_WithdrawToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid address");
        bounty.withdraw(100, BountyContract.TokenType.ETH, address(0));
    }

    function test_RevertWhen_InsufficientETHBalance() public {
        vm.prank(owner);
        vm.expectRevert("Insufficient ETH");
        bounty.withdraw(100 ether, BountyContract.TokenType.ETH, feeCollector);
    }

    /*
    |--------------------------------------------------------------------------
    | EDGE CASE TESTS
    |--------------------------------------------------------------------------
    */

    function test_ZeroWinnerAddressInMultiple() public {
        bytes32 bountyId = _createMultiEqualBounty();

        address[] memory winners = new address[](2);
        winners[0] = winner1;
        winners[1] = address(0); // Zero address

        vm.prank(creator);
        vm.expectRevert("Invalid winner");
        bounty.assignMultipleWinners(bountyId, winners, new uint256[](0));
    }

    function test_OverflowInPercentageCalculation() public {
        bytes32 bountyId = _createBountyWithLargeReward();

        address[] memory winners = new address[](2);
        winners[0] = winner1;
        winners[1] = winner2;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 50;
        percentages[1] = 50;

        vm.prank(creator);
        bounty.assignMultipleWinners(bountyId, winners, percentages);

        // Should handle large numbers without overflow
        uint256 reward = bounty.getBountyInfo(bountyId).reward;
        assertEq(bounty.claimableRewards(bountyId, winner1), reward / 2);
    }

    function test_RemainderDistributionEdgeCase() public {
        // Test with reward amount that doesn't divide evenly
        bytes32 bountyId = _createBountyWithCustomReward(101);

        address[] memory winners = new address[](3);
        winners[0] = winner1;
        winners[1] = winner2;
        winners[2] = winner3;

        vm.prank(creator);
        bounty.assignMultipleWinners(bountyId, winners, new uint256[](0));

        uint256 totalClaimable = bounty.claimableRewards(bountyId, winner1) +
            bounty.claimableRewards(bountyId, winner2) +
            bounty.claimableRewards(bountyId, winner3);

        // Total distributed should equal the full reward
        assertEq(totalClaimable, 101);
    }

    /*
    |--------------------------------------------------------------------------
    | HELPER FUNCTIONS
    |--------------------------------------------------------------------------
    */

    function _createSingleBounty(
        BountyContract.TokenType tokenType
    ) internal returns (bytes32) {
        if (tokenType == BountyContract.TokenType.ETH) {
            vm.deal(creator, 2 ether);
            vm.prank(creator);
            return
                bounty.createBounty{value: 1 ether + ((1 ether * 5) / 100)}(
                    BountyContract.TokenType.ETH,
                    1 ether,
                    BountyContract.PayoutType.SINGLE
                );
        } else {
            vm.prank(creator);
            return
                bounty.createBounty(
                    BountyContract.TokenType.USDC,
                    REWARD_AMOUNT,
                    BountyContract.PayoutType.SINGLE
                );
        }
    }

    function _createMultiEqualBounty() internal returns (bytes32) {
        vm.prank(creator);
        return
            bounty.createBounty(
                BountyContract.TokenType.USDC,
                REWARD_AMOUNT,
                BountyContract.PayoutType.MULTI_EQUAL
            );
    }

    function _createMultiEqualBountyWithOddAmount() internal returns (bytes32) {
        uint256 oddAmount = 1001 * 10 ** 6; // 1001 USDC
        uint256 total = oddAmount + ((oddAmount * 5) / 100);

        usdc.mint(creator, total);

        vm.prank(creator);
        return
            bounty.createBounty(
                BountyContract.TokenType.USDC,
                oddAmount,
                BountyContract.PayoutType.MULTI_EQUAL
            );
    }

    function _createMultiPercentageBounty() internal returns (bytes32) {
        vm.prank(creator);
        return
            bounty.createBounty(
                BountyContract.TokenType.USDC,
                REWARD_AMOUNT,
                BountyContract.PayoutType.MULTI_PERCENTAGE
            );
    }

    function _createBountyWithLargeReward() internal returns (bytes32) {
        uint256 largeReward = type(uint256).max / 100; // Very large but not overflowing
        uint256 total = largeReward + ((largeReward * 5) / 100);

        usdc.mint(creator, total);

        vm.prank(creator);
        return
            bounty.createBounty(
                BountyContract.TokenType.USDC,
                largeReward,
                BountyContract.PayoutType.MULTI_PERCENTAGE
            );
    }

    function _createBountyWithCustomReward(
        uint256 reward
    ) internal returns (bytes32) {
        uint256 total = reward + ((reward * 5) / 100);

        usdc.mint(creator, total);

        vm.prank(creator);
        return
            bounty.createBounty(
                BountyContract.TokenType.USDC,
                reward,
                BountyContract.PayoutType.MULTI_EQUAL
            );
    }
}

/*
|--------------------------------------------------------------------------
| ATTACKER CONTRACTS FOR TESTING
|--------------------------------------------------------------------------
*/

contract ReentrancyAttacker {
    BountyContract public bounty;
    bytes32 public targetBountyId;
    uint256 public attackCount;

    constructor(BountyContract _bounty) {
        bounty = _bounty;
    }

    function attack(bytes32 bountyId) external {
        targetBountyId = bountyId;
        claim();
    }

    function claim() public {
        if (attackCount < 2) {
            attackCount++;
            // Try to re-enter before claim completes
            bounty.claimReward(targetBountyId);
        }
    }

    receive() external payable {
        claim();
    }
}

contract OverflowTester {
    // Test for potential overflow in calculations
    function testOverflow(
        uint256 a,
        uint256 b
    ) external pure returns (uint256) {
        return a + b; // Should be tested with values near max
    }
}
