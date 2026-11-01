// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RoutrToken} from "../src/RoutrToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

// Only the cheatcodes used by these tests; no external test dependency is needed.
interface Vm {
    function prank(address caller) external;
    function expectRevert(bytes calldata reason) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data) external;
}

contract TokenFactoryProbe {
    function deploy() external returns (RoutrToken) {
        return new RoutrToken();
    }
}

contract RoutrTokenTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    RoutrToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new RoutrToken();
    }

    function testMetadataAndInitialSupply() public view {
        require(keccak256(bytes(token.name())) == keccak256("Routr Network"), "name");
        require(keccak256(bytes(token.symbol())) == keccak256("ROUTR"), "symbol");
        require(token.decimals() == 18, "decimals");
        _eq(token.INITIAL_SUPPLY(), SUPPLY);
        _eq(token.totalSupply(), SUPPLY);
        _eq(token.balanceOf(address(this)), SUPPLY);
        _eq(token.balanceOf(ALICE), 0);
        _eq(token.balanceOf(address(0)), 0);
        _eq(token.allowance(address(this), SPENDER), 0);
    }

    function testConstructorEmitsMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new RoutrToken();
    }

    function testFactoryReceivesWholeSupplyInsteadOfOrigin() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        RoutrToken deployed = factory.deploy();
        _eq(deployed.balanceOf(address(factory)), SUPPLY);
        _eq(deployed.balanceOf(address(this)), 0);
        _eq(deployed.totalSupply(), SUPPLY);
    }

    function testTransferEmitsEventAndReturnsTrue() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), ALICE, 25 ether);
        require(token.transfer(ALICE, 25 ether), "transfer return");
        _eq(token.balanceOf(ALICE), 25 ether);
        _eq(token.balanceOf(address(this)), SUPPLY - 25 ether);
        _eq(token.totalSupply(), SUPPLY);
    }

    function testTransferWholeSupply() public {
        require(token.transfer(ALICE, SUPPLY), "transfer");
        _eq(token.balanceOf(address(this)), 0);
        _eq(token.balanceOf(ALICE), SUPPLY);
    }

    function testZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        require(token.transfer(BOB, 0), "zero transfer");
        _eq(token.balanceOf(ALICE), 0);
        _eq(token.balanceOf(BOB), 0);
        _eq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferPreservesBalance() public {
        require(token.transfer(address(this), SUPPLY), "self transfer");
        _eq(token.balanceOf(address(this)), SUPPLY);
        _eq(token.totalSupply(), SUPPLY);
    }

    function testTransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        _eq(token.balanceOf(address(this)), SUPPLY);
        _eq(token.totalSupply(), SUPPLY);
    }

    function testInsufficientBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        _eq(token.balanceOf(BOB), 0);
    }

    function testApproveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(address(this), SPENDER, 10 ether);
        require(token.approve(SPENDER, 10 ether), "approve return");
        _eq(token.allowance(address(this), SPENDER), 10 ether);
        require(token.approve(SPENDER, 3 ether), "replace");
        _eq(token.allowance(address(this), SPENDER), 3 ether);
        _eq(token.balanceOf(address(this)), SUPPLY);
    }

    function testApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function testTransferFromDecrementsAllowance() public {
        require(token.approve(SPENDER, 10 ether), "approve");
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), ALICE, 4 ether);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 4 ether), "transferFrom return");
        _eq(token.allowance(address(this), SPENDER), 6 ether);
        _eq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        _eq(token.balanceOf(ALICE), 4 ether);
        _eq(token.totalSupply(), SUPPLY);
    }

    function testExactAllowanceConsumedThenCannotSpendAgain() public {
        require(token.approve(SPENDER, 1), "approve");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 1), "spend");
        _eq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        _eq(token.balanceOf(ALICE), 1);
    }

    function testRevokedAllowanceCannotBeUsed() public {
        require(token.approve(SPENDER, SUPPLY), "approve");
        require(token.approve(SPENDER, 0), "revoke");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        _eq(token.balanceOf(address(this)), SUPPLY);
    }

    function testMaximumAllowanceRemainsUnchanged() public {
        require(token.approve(SPENDER, type(uint256).max), "approve");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 7 ether), "spend");
        _eq(token.allowance(address(this), SPENDER), type(uint256).max);
        _eq(token.balanceOf(ALICE), 7 ether);
    }

    function testStrangerCannotUseAnotherSpendersAllowance() public {
        require(token.approve(SPENDER, SUPPLY), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        _eq(token.allowance(address(this), SPENDER), SUPPLY);
        _eq(token.balanceOf(address(this)), SUPPLY);
    }

    function testDeployerCannotTakeHolderTokensWithoutApproval() public {
        require(token.transfer(ALICE, 10 ether), "fund");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        _eq(token.balanceOf(ALICE), 10 ether);
        vm.prank(ALICE);
        require(token.transfer(BOB, 10 ether), "holder transfer");
        _eq(token.balanceOf(BOB), 10 ether);
    }

    function testRevertedTransferFromRestoresSpentAllowance() public {
        vm.prank(ALICE);
        require(token.approve(SPENDER, 10), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        _eq(token.allowance(ALICE, SPENDER), 10);
        _eq(token.balanceOf(BOB), 0);
    }

    function testTransferFromZeroRecipientRestoresAllowance() public {
        require(token.approve(SPENDER, 10), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10);
        _eq(token.allowance(address(this), SPENDER), 10);
        _eq(token.balanceOf(address(this)), SUPPLY);
    }

    function testTransferFromZeroSourceReverts() public {
        // OZ validates the allowance's owner before reaching the transfer's source check.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
    }

    function testZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 0), "zero spend");
        _eq(token.allowance(ALICE, SPENDER), 0);
        _eq(token.totalSupply(), SUPPLY);
    }

    function testLaunchDistributionAndTwoWayPoolTransfersAreExact() public {
        // Local transfer-flow regression, not a full Uniswap integration test.
        address distributor = address(0xD157);
        address pool = address(0x9001);
        require(token.transfer(distributor, SUPPLY / 10), "swarm");
        require(token.transfer(pool, SUPPLY * 8 / 10), "pool");
        require(token.transfer(ALICE, SUPPLY / 10), "remainder");
        _eq(token.balanceOf(address(this)), 0);
        _eq(token.balanceOf(distributor), SUPPLY / 10);
        _eq(token.balanceOf(pool), SUPPLY * 8 / 10);
        vm.prank(distributor);
        require(token.transfer(BOB, SUPPLY / 10), "claim");
        _eq(token.balanceOf(BOB), SUPPLY / 10);
        _eq(token.balanceOf(distributor), 0);
        vm.prank(pool);
        require(token.transfer(BOB, 5 ether), "buy");
        vm.prank(BOB);
        require(token.transfer(pool, 5 ether), "sell");
        _eq(token.balanceOf(pool), SUPPLY * 8 / 10);
        _eq(token.balanceOf(BOB), SUPPLY / 10);
        _eq(token.totalSupply(), SUPPLY);
    }

    function testMintBurnAndAdminSelectorsUnavailable() public {
        require(token.transfer(ALICE, 10 ether), "fund holder");
        bytes[9] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", BOB, 1),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("initialize(address)", BOB),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("seize(address)", ALICE),
            abi.encodeWithSignature("transferOwnership(address)", BOB),
            abi.encodeWithSignature("upgradeTo(address)", BOB)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call(calls[i]);
            require(!success, "deployer reached unsupported selector");
            vm.prank(BOB);
            (success,) = address(token).call(calls[i]);
            require(!success, "stranger reached unsupported selector");
        }
        _eq(token.totalSupply(), SUPPLY);
        _eq(token.balanceOf(ALICE), 10 ether);
        _eq(token.balanceOf(BOB), 0);
        vm.prank(ALICE);
        require(token.transfer(BOB, 10 ether), "holder remains transferable");
    }

    function testFuzzTransferRoundTripConservesSupply(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        require(token.transfer(ALICE, amount), "outbound");
        _eq(token.balanceOf(address(this)), SUPPLY - amount);
        _eq(token.balanceOf(ALICE), amount);
        vm.prank(ALICE);
        require(token.transfer(BOB, amount), "forward");
        vm.prank(BOB);
        require(token.transfer(address(this), amount), "return");
        _eq(token.balanceOf(address(this)), SUPPLY);
        _eq(token.balanceOf(ALICE), 0);
        _eq(token.balanceOf(BOB), 0);
        _eq(token.totalSupply(), SUPPLY);
    }

    function testFuzzDelegatedTransfer(uint256 rawAllowance, uint256 rawSpend) public {
        uint256 allowed = rawAllowance % (SUPPLY + 1);
        uint256 spent = rawSpend % (allowed + 1);
        require(token.approve(SPENDER, allowed), "approve");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, spent), "spend");
        _eq(token.allowance(address(this), SPENDER), allowed - spent);
        _eq(token.balanceOf(address(this)), SUPPLY - spent);
        _eq(token.balanceOf(ALICE), spent);
        _eq(token.totalSupply(), SUPPLY);
    }

    function testFuzzOverspendRevertsWithoutChangingState(uint256 rawAllowance) public {
        uint256 allowed = rawAllowance % SUPPLY;
        require(token.approve(SPENDER, allowed), "approve");
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowed, allowed + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, allowed + 1);
        _eq(token.allowance(address(this), SPENDER), allowed);
        _eq(token.balanceOf(address(this)), SUPPLY);
        _eq(token.balanceOf(ALICE), 0);
        _eq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferOverBalanceReverts(uint256 rawExcess) public {
        uint256 amount = SUPPLY + 1 + rawExcess % (type(uint256).max - SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        _eq(token.balanceOf(address(this)), SUPPLY);
        _eq(token.balanceOf(ALICE), 0);
        _eq(token.totalSupply(), SUPPLY);
    }

    function _eq(uint256 actual, uint256 expected) private pure {
        require(actual == expected, "unexpected value");
    }
}
