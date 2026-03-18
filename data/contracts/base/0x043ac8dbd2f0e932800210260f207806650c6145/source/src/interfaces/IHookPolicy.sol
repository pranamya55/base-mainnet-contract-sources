// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title The interface for the hook policy.
///
/// @notice The hook policy is used to verify if the sender address passes certain checks
///         before performing an action. There could be multiple hook policy implementations
///         that are chained together to form a composite policy.
///
/// @author Coinbase
interface IHookPolicy {
    ///  @notice Verify if the sender address satisfies certain criteria.
    ///
    ///  @param sender The sender address to be verified.
    ///  @param data Arbitrary data to be passed into the policy for verification.
    ///
    ///  @return A boolean indicating if the sender satisfies the criteria.
    function verify(address sender, bytes calldata data) external view returns (bool);
}
