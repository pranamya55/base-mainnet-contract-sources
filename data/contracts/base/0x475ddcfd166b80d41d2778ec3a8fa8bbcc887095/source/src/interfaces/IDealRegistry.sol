// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

/// @title IDealRegistry
/// @notice A registry contract to keep track created deals (e.g. through factories).
interface IDealRegistry {
    /// @notice Thrown if a deal was already registered for the given `dealUUID`.
    error DealAlreadyExists(bytes16 dealUUID, address dealContract);

    /// @notice Emitted when a new deal is registered.
    event DealRegistered(address indexed registrant, bytes16 indexed uuid, address indexed);

    /// @notice Registers a new deal.
    /// @dev Reverts with `DealAlreadyExists` if a deal contract was already registered for the given `dealUUID`.
    function registerDeal(bytes16 dealUUID, address dealAddress) external;
}
