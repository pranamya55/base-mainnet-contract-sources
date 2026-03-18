// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title Abstract Contract for Policy Management.
///
/// @notice Base contract that provides basic access control and pausing
///         functionality for policy contracts.
///
/// @author Coinbase
abstract contract BasePolicy is Pausable, AccessControl {
    // 0x77dacc74fe714b251af239ef4f8b7c83584809e79d1019758075afbdce44c972
    bytes32 public constant PAUSER_ROLE = keccak256("verifiedpools.policy.pauser");
    // Zero address
    address public constant ZERO_ADDRESS = address(0);

    /// @notice Thrown when an address is invalid.
    error InvalidAddress(address addr);

    /// @param defaultAdmin The address of the default admin.
    /// @param defaultPauser The address of the default pauser.
    constructor(address defaultAdmin, address defaultPauser) {
        if (defaultAdmin == ZERO_ADDRESS) {
            revert InvalidAddress(defaultAdmin);
        }
        if (defaultPauser == ZERO_ADDRESS) {
            revert InvalidAddress(defaultPauser);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, defaultPauser);
    }

    /// @notice Pause the policy contract in case of emergency
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause the policy contract
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
