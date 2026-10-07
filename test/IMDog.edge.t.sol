// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDog} from "../src/IMDog.sol";

/// forge-config: default.fuzz.runs = 1000
contract IMDogEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    IMDog private token;

    function setUp() public {
        token = new IMDog();
    }

    function test_OneWeiMovesExactlyThroughDirectAndDelegatedTransfers() public {
        assertTrue(token.transfer(ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        vm.prank(BOB);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferRevertsWithoutChangingState() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferFromCannotSpendBeyondBalanceWithInfiniteApproval() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteAllowanceIsDecremented() public {
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBeRevokedAfterSpending() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OwnerNeedsSelfApprovalToUseTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
    }

    function test_ZeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroRecipientStillReverts() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalsAreIsolatedByOwnerAndSpender(
        uint256 firstAllowance,
        uint256 secondAllowance,
        uint256 aliceAllowance,
        uint256 amount
    ) public {
        assertTrue(token.transfer(ALICE, SUPPLY / 2));
        assertTrue(token.approve(SPENDER, firstAllowance));
        assertTrue(token.approve(BOB, secondAllowance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, aliceAllowance));

        amount = bound(amount, 0, firstAllowance < SUPPLY / 2 ? firstAllowance : SUPPLY / 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, amount));
        assertEq(
            token.allowance(address(this), SPENDER),
            firstAllowance == type(uint256).max ? firstAllowance : firstAllowance - amount
        );
        assertEq(token.allowance(address(this), BOB), secondAllowance);
        assertEq(token.allowance(ALICE, SPENDER), aliceAllowance);
        assertEq(token.balanceOf(ALICE), SUPPLY / 2);
        assertEq(token.balanceOf(address(this)), SUPPLY / 2 - amount);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsExactWithoutFunds(uint256 initial, uint256 replacement) public {
        vm.startPrank(ALICE);
        assertTrue(token.approve(SPENDER, initial));
        assertEq(token.allowance(ALICE, SPENDER), initial);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(ALICE, SPENDER), replacement);
        assertTrue(token.approve(SPENDER, replacement));
        vm.stopPrank();
        assertEq(token.allowance(ALICE, SPENDER), replacement);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedRoundTripCannotReplaySpentApproval(uint256 amount, uint256 firstPart) public {
        amount = bound(amount, 1, SUPPLY);
        firstPart = bound(firstPart, 0, amount);
        assertTrue(token.transfer(ALICE, amount));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, amount));

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, firstPart));
        assertEq(token.allowance(ALICE, SPENDER), amount - firstPart);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount - firstPart));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.allowance(ALICE, SPENDER), 0);

        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, amount));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedDelegatedOverdraftIsAtomic(uint256 balance, uint256 amount, bool infinite) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        uint256 approved = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
