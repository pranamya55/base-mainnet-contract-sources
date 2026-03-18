// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title The interface for the sactions list.
///
/// @notice The sanctions list validates if a cryptocurrency wallet address
///         has been included in a sanctions designation.
///
/// @author Coinbase
interface ISanctionsList {
    /// @notice Check if the sender address is sanctioned.
    ///
    /// @param sender The sender address to check.
    ///
    /// @return A boolean indicating if the address is sanctioned.
    function isSanctioned(address sender) external view returns (bool);
}
