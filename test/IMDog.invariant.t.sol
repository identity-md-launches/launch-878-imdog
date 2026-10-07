// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDog} from "../src/IMDog.sol";

/// @dev All token movements stay within this finite actor set, so its sum accounts for every unit.
contract IMDogHandler is Test {
    IMDog public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCAFE), address(0xD00D)];

    // Expected state comes from the initial allocation and requested operations,
    // never from copying the token's post-call balances or allowances.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(IMDog token_) {
        token = token_;
        expectedBalance[actors[0]] = 1_000_000_000 * 1e18;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = token.allowance(owner, spender);
        uint256 balanceBefore = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        assertEq(
            token.allowance(owner, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
        assertEq(token.balanceOf(owner), owner == to ? balanceBefore : balanceBefore - amount);
        assertEq(token.balanceOf(to), owner == to ? toBefore : toBefore + amount);
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        uint256[5] memory amounts = [
            uint256(0), 1, type(uint256).max, type(uint256).max - 1, expectedBalance[actors[ownerSeed % actors.length]]
        ];
        approve(ownerSeed, spenderSeed, amounts[mode % amounts.length]);
    }

    function rejectOverdraft(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        _reject(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function rejectOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        // Replace an infinite allowance with a finite one so this call always
        // exercises rejection instead of silently skipping a random action.
        if (allowed == type(uint256).max) {
            allowed = expectedBalance[owner];
            approve(ownerSeed, spenderSeed, allowed);
        }
        amount = bound(amount, allowed + 1, type(uint256).max);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
    }

    function rejectApprovedTransfer(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 amount,
        bool zeroRecipient,
        bool infiniteApproval
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        address to = zeroRecipient ? address(0) : spender;
        amount = zeroRecipient ? bound(amount, 0, balance) : bound(amount, balance + 1, type(uint256).max - 1);
        approve(ownerSeed, spenderSeed, infiniteApproval ? type(uint256).max : amount);
        bytes memory expectedError = zeroRecipient
            ? abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount);
        _reject(spender, abi.encodeCall(token.transferFrom, (owner, to, amount)), expectedError);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        _reject(
            owner,
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function _reject(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(reason, expectedError, "unexpected rejection reason");
        // Ghost state is unchanged: the invariants check every balance and
        // allowance, including unrelated actors, after the rejected operation.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IMDogInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    IMDog private token;
    IMDogHandler private handler;

    function setUp() public {
        token = new IMDog();
        handler = new IMDogHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = IMDogHandler.move.selector;
        selectors[1] = IMDogHandler.approve.selector;
        selectors[2] = IMDogHandler.spend.selector;
        selectors[3] = IMDogHandler.approveBoundary.selector;
        selectors[4] = IMDogHandler.rejectOverdraft.selector;
        selectors[5] = IMDogHandler.rejectOverspend.selector;
        selectors[6] = IMDogHandler.rejectApprovedTransfer.selector;
        selectors[7] = IMDogHandler.rejectZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyAndBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_EveryBalanceAndAllowanceMatchesAuthorizedCalls() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner), "unexpected balance change");
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "unexpected allowance change"
                );
            }
        }
    }
}
