// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title PolicyVerifier Contract
///
/// @dev A hook policy may consist of multiple individual policies. This contract is a base contract for individual
///      policies to inherit from.
///
/// @author Coinbase
abstract contract PolicyVerifier {
    /// @dev Verifies whether an address matches a specific criteria before performing an action.
    ///
    /// @param sender The sender address to be verified.
    /// @param data Arbitrary data to be passed to the policy for verification.
    ///
    /// @return A boolean indicating if the sender satisfies the criteria.
    function _verify(address sender, bytes calldata data) internal view virtual returns (bool);
}
