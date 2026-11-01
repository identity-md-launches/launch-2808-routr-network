// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Native Foundry interfaces keep the test suite self-contained for offline runs.
interface RoutrVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address caller) external;
    function expectRevert(bytes calldata reason) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
}

abstract contract RoutrTestBase {
    RoutrVm internal constant vm = RoutrVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    event Transfer(address indexed from, address indexed to, uint256 value);

    function bound(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (uint256) {
        require(minimum <= maximum, "invalid test bounds");
        if (value >= minimum && value <= maximum) return value;
        // The full uint256 range is already handled by the branch above.
        return minimum + value % (maximum - minimum + 1);
    }

    function eq(uint256 actual, uint256 expected, string memory reason) internal pure {
        require(actual == expected, reason);
    }
}
