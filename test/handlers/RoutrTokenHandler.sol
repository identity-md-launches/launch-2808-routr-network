// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RoutrToken} from "src/RoutrToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RoutrTestBase} from "../helpers/RoutrTestBase.sol";

/// @notice Drives real ERC-20 calls; the ledger records only authorized successful movements.
/// @dev Every possible recipient is tracked. The token itself is a recipient-only sink:
/// the harness never impersonates it to recover tokens it has received.
contract RoutrTokenHandler is RoutrTestBase {
    uint256 public constant ACTOR_COUNT = 5;
    uint256 public constant ACCOUNT_COUNT = 6;
    RoutrToken public immutable token;
    address[6] public accounts;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public transfers;
    uint256 public delegatedTransfers;
    uint256 public approvals;
    uint256 public rejectedCalls;
    uint256 public roundTrips;

    constructor() {
        accounts[0] = address(this); // The immediate deployer has no special rights after minting.
        accounts[1] = ALICE;
        accounts[2] = BOB;
        accounts[3] = SPENDER;
        accounts[4] = address(uint160(uint256(keccak256("ROUTR invariant holder"))));
        token = new RoutrToken();
        accounts[5] = address(token);
        ghostBalance[address(this)] = SUPPLY;

        // All five actors start funded. Seed finite and unlimited relationships so
        // delegation is reachable from the first random call, without approving everyone.
        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            _transfer(accounts[0], accounts[i], SUPPLY / ACTOR_COUNT);
        }
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            _approve(accounts[i], accounts[(i + 1) % ACTOR_COUNT], SUPPLY / 10);
            _approve(accounts[i], accounts[(i + ACTOR_COUNT - 1) % ACTOR_COUNT], type(uint256).max);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _recipient(toSeed), _amount(amountSeed, ghostBalance[from]));
    }

    function selfTransfer(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        _transfer(actor, actor, _amount(amountSeed, ghostBalance[actor]));
    }

    function roundTrip(uint256 fromSeed, uint256 otherSeed, uint256 amountSeed) external {
        uint256 index = fromSeed % ACTOR_COUNT;
        address from = accounts[index];
        address other = accounts[(index + 1 + otherSeed % (ACTOR_COUNT - 1)) % ACTOR_COUNT];
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeOther = token.balanceOf(other);
        uint256 amount = _amount(amountSeed, ghostBalance[from]);
        _transfer(from, other, amount);
        _transfer(other, from, amount);
        eq(token.balanceOf(from), beforeFrom, "round trip changed sender wealth");
        eq(token.balanceOf(other), beforeOther, "round trip changed counterparty wealth");
        ++roundTrips;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 mode) external {
        uint256 amount;
        if (mode % 5 == 0) amount = 0;
        else if (mode % 5 == 1) amount = 1;
        else if (mode % 5 == 2) amount = type(uint256).max;
        else if (mode % 5 == 3) amount = bound(rawAmount, 0, SUPPLY);
        else amount = rawAmount;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    /// @dev Uses existing permissions, including ones overwritten or revoked by earlier calls.
    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 maximum = ghostBalance[owner];
        uint256 allowed = ghostAllowance[owner][spender];
        if (allowed < maximum) maximum = allowed;
        _spend(owner, spender, _recipient(toSeed), _amount(amountSeed, maximum));
    }

    /// @dev Also creates fresh permissions, ensuring substantial delegated movements stay reachable.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed, bool unlimited)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, ghostBalance[owner]);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _spend(owner, spender, _recipient(toSeed), amount);
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        uint256 balance = ghostBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        _reject(
            from,
            abi.encodeCall(token.transfer, (_recipient(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function spendOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawApproval) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = bound(rawApproval, 0, SUPPLY);
        _approve(owner, spender, allowed);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _recipient(toSeed), allowed + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
    }

    function spendOverBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount, bool unlimited)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = ghostBalance[owner];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _recipient(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function invalidAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 operation) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (operation % 4 == 0) {
            _reject(
                owner,
                abi.encodeCall(token.transfer, (address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        } else if (operation % 4 == 1) {
            _reject(
                owner,
                abi.encodeCall(token.approve, (address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
            );
        } else if (operation % 4 == 2) {
            _approve(owner, spender, amount);
            _reject(
                spender,
                abi.encodeCall(token.transferFrom, (owner, address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        } else {
            _reject(
                spender,
                abi.encodeCall(token.transferFrom, (address(0), owner, 0)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0))
            );
        }
    }

    function unsupportedAdmin(uint256 callerSeed, uint256 holderSeed, uint256 amount, uint8 action) external {
        address holder = _actor(holderSeed);
        bytes memory payload;
        if (action % 10 == 0) payload = abi.encodeWithSignature("mint(address,uint256)", holder, amount);
        else if (action % 10 == 1) payload = abi.encodeWithSignature("mint(uint256)", amount);
        else if (action % 10 == 2) payload = abi.encodeWithSignature("issue(uint256)", amount);
        else if (action % 10 == 3) payload = abi.encodeWithSignature("burn(uint256)", amount);
        else if (action % 10 == 4) payload = abi.encodeWithSignature("burnFrom(address,uint256)", holder, amount);
        else if (action % 10 == 5) payload = abi.encodeWithSignature("pause()");
        else if (action % 10 == 6) payload = abi.encodeWithSignature("freezeAccount(address)", holder);
        else if (action % 10 == 7) payload = abi.encodeWithSignature("seize(address,uint256)", holder, amount);
        else if (action % 10 == 8) payload = abi.encodeWithSignature("initialize(address)", holder);
        else payload = abi.encodeWithSignature("setMinter(address)", holder);
        vm.prank(_actor(callerSeed));
        (bool success,) = address(token).call(payload);
        require(!success, "unsupported administration became callable");
        ++rejectedCalls;
    }

    function _actor(uint256 seed) private view returns (address) {
        return accounts[seed % ACTOR_COUNT];
    }

    function _recipient(uint256 seed) private view returns (address) {
        return accounts[seed % ACCOUNT_COUNT];
    }

    // Deliberately generate zero, one base unit, full balance, and arbitrary partial amounts.
    function _amount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum == 0 ? 0 : 1;
        if (seed % 4 == 2) return maximum;
        return bound(seed, 0, maximum);
    }

    function _transfer(address from, address to, uint256 amount) private {
        vm.prank(from);
        require(token.transfer(to, amount), "valid transfer returned false");
        _recordMovement(from, to, amount);
        ++transfers;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        require(token.approve(spender, amount), "valid approval returned false");
        ghostAllowance[owner][spender] = amount;
        eq(token.allowance(owner, spender), amount, "approval replacement differs from request");
        ++approvals;
    }

    function _spend(address owner, address spender, address to, uint256 amount) private {
        uint256 allowed = ghostAllowance[owner][spender];
        vm.prank(spender);
        require(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
        _recordMovement(owner, to, amount);
        eq(token.allowance(owner, spender), ghostAllowance[owner][spender], "delegated approval accounting");
        ++delegatedTransfers;
    }

    function _recordMovement(address from, address to, uint256 amount) private {
        if (from != to) {
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
        }
        eq(token.balanceOf(from), ghostBalance[from], "sender differs from authorized ledger");
        eq(token.balanceOf(to), ghostBalance[to], "recipient differs from authorized ledger");
    }

    function _reject(address caller, bytes memory payload, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(payload);
        require(!success, "invalid operation succeeded");
        require(keccak256(reason) == keccak256(expectedError), "unexpected failure reason");
        ++rejectedCalls;
    }
}
