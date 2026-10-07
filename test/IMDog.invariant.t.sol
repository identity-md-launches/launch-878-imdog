// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMDog} from "../src/IMDog.sol";

/// @dev All token movements stay within this finite actor set, so its sum accounts for every unit.
contract IMDogHandler is Test {
    IMDog public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCAFE), address(0xD00D)];

    constructor(IMDog token_) {
        token = token_;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = token.allowance(owner, spender);
        uint256 balanceBefore = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, allowanceBefore < balanceBefore ? allowanceBefore : balanceBefore);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(
            token.allowance(owner, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
        assertEq(token.balanceOf(owner), owner == to ? balanceBefore : balanceBefore - amount);
        assertEq(token.balanceOf(to), owner == to ? toBefore : toBefore + amount);
    }
}

contract IMDogInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    IMDog private token;
    IMDogHandler private handler;

    function setUp() public {
        token = new IMDog();
        handler = new IMDogHandler(token);
        token.transfer(handler.actors(0), SUPPLY);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = IMDogHandler.move.selector;
        selectors[1] = IMDogHandler.approve.selector;
        selectors[2] = IMDogHandler.spend.selector;
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
}
