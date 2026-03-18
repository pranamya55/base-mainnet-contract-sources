// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

/// @title IFunderIntegrationRegistry
/// @notice A registry contract to keep track of sets of grouped funders based on integration keys.
interface IFunderIntegrationRegistry {
    /// @notice Emitted when a funder is registered.
    event FunderRegistered(bytes32 indexed integrationKey, address indexed funder, uint256 indexed group);

    /// @notice Emitted when a funder is deregistered.
    event FunderDeregistered(bytes32 indexed integrationKey, address indexed funder);

    /// @notice Registers a funder for the senders integration key.
    /// @dev Each registrant must only call this function once for each funder. This is reset after they have deregistered the funder again.
    /// @param integrationKey The integration key to register the funder for.
    /// @param funder The funder to register.
    /// @param group The group of the funder.
    function register(bytes32 integrationKey, address funder, uint256 group) external;

    /// @notice Deregisters a funder for the senders integration key.
    /// @dev A registrant must only call this function if they have previously registered the funder.
    /// @param integrationKey The integration key to deregister the funder for.
    /// @param funder The funder to deregister.
    function deregister(bytes32 integrationKey, address funder) external;

    /// @notice Returns the number of funders for the given integration key.
    function numTotal(bytes32 integrationKey) external view returns (uint256);

    /// @notice Returns the number of funders for the given integration key and group.
    function numInGroup(bytes32 integrationKey, uint256 group) external view returns (uint256);

    /// @notice Returns whether the funder is registered for the given integration key.
    function isRegistered(bytes32 integrationKey, address funder) external view returns (bool);

    /// @notice Returns the group of the funder registered for the given integration key.
    /// @dev Reverts if the funder is not registered for the given integration key.
    function group(bytes32 integrationKey, address funder) external view returns (uint256);

    /// @notice Returns the funder at the given index.
    function at(bytes32 integrationKey, uint256 index) external view returns (address, uint256);
}
