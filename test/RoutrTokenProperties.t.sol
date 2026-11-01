// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RoutrToken} from "src/RoutrToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RoutrTestBase, RoutrVm} from "./helpers/RoutrTestBase.sol";

/// forge-config: default.fuzz.runs = 1024
contract RoutrTokenPropertiesTest is RoutrTestBase {
    RoutrToken private token;

    function setUp() public {
        token = new RoutrToken();
    }

    function testConstructorEmitsExactlyOneWholeSupplyMint() public {
        vm.recordLogs();
        vm.prank(ALICE);
        RoutrToken deployed = new RoutrToken();
        RoutrVm.Log[] memory logs = vm.getRecordedLogs();

        eq(logs.length, 1, "constructor must mint exactly once");
        require(logs[0].emitter == address(deployed), "mint emitter");
        eq(logs[0].topics.length, 3, "mint topics");
        require(logs[0].topics[0] == keccak256("Transfer(address,address,uint256)"), "mint signature");
        require(logs[0].topics[1] == bytes32(0), "mint source");
        require(logs[0].topics[2] == bytes32(uint256(uint160(ALICE))), "mint recipient");
        eq(abi.decode(logs[0].data, (uint256)), SUPPLY, "mint amount");
        eq(deployed.balanceOf(ALICE), SUPPLY, "immediate deployer allocation");
        eq(deployed.balanceOf(address(this)), 0, "controller must not receive the mint");
        eq(deployed.totalSupply(), SUPPLY, "new deployment supply");
        eq(token.balanceOf(address(this)), SUPPLY, "deployments must be independent");
    }

    function testOwnerNeedsApprovalToTransferFromOwnBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        require(token.approve(address(this), 1), "self approval");
        require(token.transferFrom(address(this), ALICE, 1), "self authorized spend");
        eq(token.balanceOf(ALICE), 1, "one base unit received");
        eq(token.balanceOf(address(this)), SUPPLY - 1, "one base unit debited");
        eq(token.allowance(address(this), address(this)), 0, "self approval consumed");
    }

    function testDelegatedSelfTransferConsumesAllowanceWithoutMovingBalance() public {
        require(token.approve(SPENDER, SUPPLY), "approve");
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), address(this), SUPPLY), "delegated self transfer");
        eq(token.balanceOf(address(this)), SUPPLY, "self transfer balance");
        eq(token.allowance(address(this), SPENDER), 0, "self transfer consumes finite approval");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        eq(token.totalSupply(), SUPPLY, "self transfer supply");
    }

    function testFullSupplyDelegatedTransferExhaustsBalanceAndApproval() public {
        require(token.approve(SPENDER, SUPPLY), "approve full supply");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, SUPPLY), "spend full supply");
        eq(token.balanceOf(address(this)), 0, "sender drained");
        eq(token.balanceOf(ALICE), SUPPLY, "full supply delivered");
        eq(token.allowance(address(this), SPENDER), 0, "approval drained");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        eq(token.balanceOf(ALICE), SUPPLY, "failed repeat changed recipient");
    }

    function testMaximumMinusOneAllowanceIsFinite() public {
        require(token.approve(SPENDER, type(uint256).max - 1), "approve");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 1), "spend");
        eq(token.allowance(address(this), SPENDER), type(uint256).max - 2, "only maximum is unlimited");
        eq(token.balanceOf(ALICE), 1, "base unit credit");
    }

    function testUnlimitedApprovalSurvivesRepeatedFullBalanceTransfersThenRevocation() public {
        require(token.approve(SPENDER, type(uint256).max), "owner approval");
        vm.prank(ALICE);
        require(token.approve(SPENDER, type(uint256).max), "recipient approval");
        for (uint256 i; i < 3; ++i) {
            vm.prank(SPENDER);
            require(token.transferFrom(address(this), ALICE, SUPPLY), "outbound");
            vm.prank(SPENDER);
            require(token.transferFrom(ALICE, address(this), SUPPLY), "inbound");
        }
        eq(token.allowance(address(this), SPENDER), type(uint256).max, "owner infinite approval");
        eq(token.allowance(ALICE, SPENDER), type(uint256).max, "recipient infinite approval");
        eq(token.balanceOf(address(this)), SUPPLY, "round trip balance");
        eq(token.balanceOf(ALICE), 0, "round trip recipient");
        require(token.approve(SPENDER, 0), "revoke infinite approval");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        eq(token.allowance(address(this), SPENDER), 0, "revocation persists");
        eq(token.totalSupply(), SUPPLY, "round trip supply");
    }

    function testZeroTransferFromEmitsEventAndPreservesFiniteAndInfiniteApprovals() public {
        uint256[3] memory approvals = [uint256(0), uint256(7), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(ALICE);
            require(token.approve(SPENDER, approvals[i]), "approve unfunded account");
            vm.expectEmit(true, true, false, true, address(token));
            emit Transfer(ALICE, BOB, 0);
            vm.prank(SPENDER);
            require(token.transferFrom(ALICE, BOB, 0), "zero delegated transfer");
            eq(token.allowance(ALICE, SPENDER), approvals[i], "zero spend approval");
        }
        eq(token.balanceOf(ALICE), 0, "empty sender remains empty");
        eq(token.balanceOf(BOB), 0, "zero credit");
        eq(token.totalSupply(), SUPPLY, "zero spend supply");
    }

    function testZeroRecipientRejectsZeroDelegatedTransfersWithAnyApprovalMode() public {
        uint256[3] memory approvals = [uint256(0), uint256(7), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            require(token.approve(SPENDER, approvals[i]), "approve");
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(SPENDER);
            token.transferFrom(address(this), address(0), 0);
            eq(token.allowance(address(this), SPENDER), approvals[i], "failed zero spend approval");
        }
        eq(token.balanceOf(address(this)), SUPPLY, "invalid recipient changed owner");
        eq(token.balanceOf(address(0)), 0, "zero address received funds");
    }

    function testMaximumDelegatedSpendRevertsWithoutConsumingInfiniteApproval() public {
        require(token.approve(SPENDER, type(uint256).max), "approve");
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        eq(token.allowance(address(this), SPENDER), type(uint256).max, "failed maximum spend approval");
        eq(token.balanceOf(address(this)), SUPPLY, "failed maximum spend owner");
        eq(token.balanceOf(ALICE), 0, "failed maximum spend recipient");
    }

    function testFuzzSplitTransfersEqualOneCombinedTransfer(uint256 rawFirst, uint256 rawSecond) public {
        uint256 first = bound(rawFirst, 0, SUPPLY);
        uint256 second = bound(rawSecond, 0, SUPPLY - first);
        RoutrToken combined = new RoutrToken();
        require(token.transfer(ALICE, first), "first split");
        require(token.transfer(ALICE, second), "second split");
        require(combined.transfer(ALICE, first + second), "combined transfer");
        eq(token.balanceOf(ALICE), combined.balanceOf(ALICE), "splitting must not change received value");
        eq(token.balanceOf(address(this)), combined.balanceOf(address(this)), "splitting must not change cost");
        eq(token.totalSupply(), SUPPLY, "split supply");
    }

    function testFuzzCumulativeSpendingCannotExceedApproval(uint256 rawApproval, uint256 rawFirst) public {
        uint256 approved = bound(rawApproval, 1, SUPPLY);
        uint256 first = bound(rawFirst, 0, approved);
        require(token.approve(SPENDER, approved), "approve");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, first), "first spend");
        eq(token.allowance(address(this), SPENDER), approved - first, "partial allowance");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), BOB, approved - first), "second spend");
        eq(token.allowance(address(this), SPENDER), 0, "cumulative allowance");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        eq(token.balanceOf(ALICE) + token.balanceOf(BOB), approved, "cumulative receipts");
        eq(token.balanceOf(address(this)), SUPPLY - approved, "cumulative debit");
    }

    function testFuzzApprovalOverwriteIsIdempotentAndIsolated(uint256 first, uint256 replacement, uint256 other)
        public
    {
        require(token.approve(BOB, other), "other spender approval");
        vm.prank(ALICE);
        require(token.approve(SPENDER, first), "other owner approval");
        require(token.approve(SPENDER, first), "first approval");
        require(token.approve(SPENDER, replacement), "replacement");
        require(token.approve(SPENDER, replacement), "idempotent replacement");
        eq(token.allowance(address(this), SPENDER), replacement, "approval replaces rather than adds");
        eq(token.allowance(address(this), BOB), other, "other spender unaffected");
        eq(token.allowance(ALICE, SPENDER), first, "other owner unaffected");
        eq(token.allowance(SPENDER, address(this)), 0, "approval is directional");
        eq(token.balanceOf(address(this)), SUPPLY, "approval cannot debit balances");
        eq(token.balanceOf(ALICE), 0, "approval cannot credit balances");
        eq(token.totalSupply(), SUPPLY, "approval cannot change supply");
    }

    function testFuzzDelegatedOverBalanceRevertsAtomically(
        uint256 rawBalance,
        uint256 rawAmount,
        bool unlimited,
        bool selfRecipient
    ) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        uint256 approval = unlimited ? type(uint256).max : amount;
        require(token.transfer(ALICE, balance), "fund");
        vm.prank(ALICE);
        require(token.approve(SPENDER, approval), "approve over balance");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, selfRecipient ? ALICE : BOB, amount);
        eq(token.allowance(ALICE, SPENDER), approval, "failed spend must restore approval");
        eq(token.balanceOf(ALICE), balance, "failed spend sender");
        eq(token.balanceOf(BOB), 0, "failed spend recipient");
        eq(token.balanceOf(address(this)), SUPPLY - balance, "unrelated balance");
        eq(token.totalSupply(), SUPPLY, "failed spend supply");
    }

    function testFuzzSelfTransferCannotBypassBalanceCheck(uint256 rawBalance, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        require(token.transfer(ALICE, balance), "fund");
        vm.prank(ALICE);
        require(token.transfer(ALICE, balance), "valid full self transfer");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(ALICE);
        token.transfer(ALICE, amount);
        eq(token.balanceOf(ALICE), balance, "invalid self transfer balance");
        eq(token.totalSupply(), SUPPLY, "invalid self transfer supply");
    }

    function testFuzzZeroSpenderRejectsAnyApproval(uint256 amount) public {
        require(token.approve(SPENDER, 1), "preexisting approval");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        eq(token.allowance(address(this), address(0)), 0, "zero spender approval");
        eq(token.allowance(address(this), SPENDER), 1, "unrelated approval survives");
        eq(token.balanceOf(address(this)), SUPPLY, "failed approval balance");
    }

    function testFuzzZeroRecipientRollsBackAnyDelegatedAmount(uint256 amount, bool unlimited) public {
        uint256 approval = unlimited ? type(uint256).max : amount;
        require(token.approve(SPENDER, approval), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), amount);
        eq(token.allowance(address(this), SPENDER), approval, "invalid recipient restores approval");
        eq(token.balanceOf(address(this)), SUPPLY, "invalid recipient owner balance");
        eq(token.balanceOf(address(0)), 0, "invalid recipient cannot burn");
        eq(token.totalSupply(), SUPPLY, "invalid recipient supply");
    }
}
