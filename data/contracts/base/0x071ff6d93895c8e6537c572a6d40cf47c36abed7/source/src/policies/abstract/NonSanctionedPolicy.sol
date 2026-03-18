// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISanctionsList} from "../../interfaces/ISanctionsList.sol";
import {PolicyVerifier} from "./PolicyVerifier.sol";

/// @title NonSanctioned Policy Contract.
///
/// @notice Policy contract to verify if the caller is not sanctioned.
///
/// @dev This contract is a base contract for other policies to inherit from.
///
/// @author Coinbase
abstract contract NonSanctionedPolicy is PolicyVerifier {
    /// @notice The `SactionsList` contract that checks if an address is sanctioned.
    ISanctionsList internal _sanctionsList;

    /// @notice An event emitted when the `SanctionsList` contract is updated.
    ///
    /// @param previousSanctionsList The address of the previous `SanctionsList` contract.
    /// @param sanctionsList         The address of the new `SanctionsList` contract.
    event SanctionsListUpdated(address indexed previousSanctionsList, address indexed sanctionsList);

    /// @notice Thrown when the `SanctionsList` contract is invalid
    error InvalidSanctionsList();

    /// @param sanctionsList The `SanctionsList` contract.
    constructor(ISanctionsList sanctionsList) {
        _setSanctionsList(sanctionsList);
    }

    /// @notice Get the address of the `SanctionsList` contract.
    ///
    /// @return The address of the `SanctionsList` contract.
    function getSanctionsList() external view returns (address) {
        return address(_sanctionsList);
    }

    /// @inheritdoc PolicyVerifier
    ///
    /// @notice Verifies whether the sender address is not included in the sanctions list.
    /// @notice This function returns `false` when the sender address is included in the sanctions list.
    function _verify(address sender, bytes calldata) internal view virtual override returns (bool) {
        if (_sanctionsList.isSanctioned(sender)) {
            return false;
        }

        return true;
    }

    /// @dev Sets the `SanctionsList` contract.
    /// @dev This is an internal function without access control.
    ///      If this function were to be made public or external,
    ///      it should be protected to only allow authorized callers.
    /// @dev This function may emit a {SanctionsListUpdated} event.
    ///
    /// @param sanctionsList The new `SanctionsList` contract.
    function _setSanctionsList(ISanctionsList sanctionsList) internal {
        if (address(sanctionsList) == address(0)) {
            revert InvalidSanctionsList();
        }
        if (address(sanctionsList) == address(_sanctionsList)) {
            return;
        }
        address previousSanctionsList = address(_sanctionsList);

        _sanctionsList = sanctionsList;
        emit SanctionsListUpdated(previousSanctionsList, address(sanctionsList));
    }
}
