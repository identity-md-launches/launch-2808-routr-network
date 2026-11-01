// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RoutrToken} from "src/RoutrToken.sol";
import {RoutrTestBase} from "./helpers/RoutrTestBase.sol";
import {RoutrTokenHandler} from "./handlers/RoutrTokenHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract RoutrTokenInvariantsTest is RoutrTestBase {
    // These getters expose Foundry's native targeting ABI without an external library.
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    RoutrTokenHandler private handler;
    RoutrToken private token;

    function setUp() public {
        handler = new RoutrTokenHandler();
        token = handler.token();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = RoutrTokenHandler.transfer.selector;
        selectors[1] = RoutrTokenHandler.selfTransfer.selector;
        selectors[2] = RoutrTokenHandler.roundTrip.selector;
        selectors[3] = RoutrTokenHandler.approve.selector;
        selectors[4] = RoutrTokenHandler.spend.selector;
        selectors[5] = RoutrTokenHandler.approveAndSpend.selector;
        selectors[6] = RoutrTokenHandler.transferOverBalance.selector;
        selectors[7] = RoutrTokenHandler.spendOverAllowance.selector;
        selectors[8] = RoutrTokenHandler.spendOverBalance.selector;
        selectors[9] = RoutrTokenHandler.invalidAddress.selector;
        selectors[10] = RoutrTokenHandler.unsupportedAdmin.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    function invariant_fixedSupplyEqualsAllTrackedBalances() public view {
        uint256 sum;
        for (uint256 i; i < handler.ACCOUNT_COUNT(); ++i) {
            sum += token.balanceOf(handler.accounts(i));
        }
        eq(token.totalSupply(), SUPPLY, "fixed supply changed");
        eq(sum, SUPPLY, "balances no longer conserve the initial mint");
        eq(token.balanceOf(address(0)), 0, "zero address acquired tokens");
        eq(token.INITIAL_SUPPLY(), SUPPLY, "initial supply constant changed");
        eq(token.decimals(), 18, "decimals changed");
        require(keccak256(bytes(token.name())) == keccak256("Routr Network"), "name changed");
        require(keccak256(bytes(token.symbol())) == keccak256("ROUTR"), "symbol changed");
    }

    function invariant_balancesMatchOnlyAuthorizedMovements() public view {
        for (uint256 i; i < handler.ACCOUNT_COUNT(); ++i) {
            address account = handler.accounts(i);
            eq(token.balanceOf(account), handler.ghostBalance(account), "balance differs from independent ledger");
        }
    }

    function invariant_allowancesMatchApprovalsAndSuccessfulSpending() public view {
        // Include the token sink and zero address to catch unintended permission writes.
        for (uint256 i; i < handler.ACCOUNT_COUNT(); ++i) {
            address owner = handler.accounts(i);
            eq(token.allowance(owner, address(0)), 0, "zero spender acquired approval");
            eq(token.allowance(address(0), owner), 0, "zero owner acquired approval");
            for (uint256 j; j < handler.ACCOUNT_COUNT(); ++j) {
                address spender = handler.accounts(j);
                eq(
                    token.allowance(owner, spender),
                    handler.ghostAllowance(owner, spender),
                    "allowance differs from authorized ledger"
                );
            }
        }
    }

    function testHandlerReachesEveryOperationAndBoundaryMode() public {
        // Pin reachability instead of imposing probabilistic coverage assertions on random runs.
        uint256 beforeTransfers = handler.transfers();
        uint256 beforeDelegated = handler.delegatedTransfers();
        uint256 beforeRejected = handler.rejectedCalls();

        handler.transfer(0, 1, 0); // zero
        handler.transfer(0, 1, 1); // one base unit
        handler.selfTransfer(0, 2); // full balance
        handler.roundTrip(0, 1, 3); // partial amount
        handler.transfer(0, 1, 2); // empty an account
        handler.transfer(0, 1, 0); // zero transfer from empty account
        handler.transfer(1, 0, 2); // refill it
        handler.transfer(0, 5, 1); // real transfer to token contract, tracked as a sink

        for (uint8 mode; mode < 5; ++mode) {
            handler.approve(0, 1, type(uint256).max - 1, mode);
        }
        handler.approveAndSpend(0, 1, 2, 1, false);
        handler.approveAndSpend(0, 1, 2, 1, true);
        handler.approve(0, 1, 7, 3);
        handler.spend(0, 1, 0, 1); // self-recipient still consumes a finite allowance
        handler.approve(0, 1, 0, 0); // revoke
        handler.spend(0, 1, 2, 2); // zero remaining permission permits only zero
        handler.transferOverBalance(0, 1, type(uint256).max);
        handler.transferOverBalance(0, 0, 0); // self-transfer cannot bypass balance check
        handler.spendOverAllowance(0, 1, 2, 0);
        handler.spendOverBalance(0, 1, 2, type(uint256).max, false);
        handler.spendOverBalance(0, 1, 0, 0, true);
        for (uint8 operation; operation < 4; ++operation) {
            handler.invalidAddress(0, 1, 0, operation);
            handler.invalidAddress(0, 1, type(uint256).max, operation);
        }
        for (uint8 action; action < 10; ++action) {
            handler.unsupportedAdmin(0, 1, 1, action); // original deployer
            handler.unsupportedAdmin(2, 1, 1, action); // ordinary holder
        }

        require(handler.transfers() > beforeTransfers, "transfer handler not exercised");
        require(handler.delegatedTransfers() > beforeDelegated, "delegated handler not exercised");
        require(handler.rejectedCalls() > beforeRejected, "failure handlers not exercised");
        require(handler.roundTrips() > 0, "round trip handler not exercised");
        invariant_fixedSupplyEqualsAllTrackedBalances();
        invariant_balancesMatchOnlyAuthorizedMovements();
        invariant_allowancesMatchApprovalsAndSuccessfulSpending();
    }
}
