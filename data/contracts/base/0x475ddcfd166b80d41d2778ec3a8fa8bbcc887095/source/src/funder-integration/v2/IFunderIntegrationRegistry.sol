// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

/// @notice A struct to encode the number of slots a funder has taken in a group.
struct GroupEntry {
    uint256 group;
    uint256 num;
}

/// @title IFunderIntegrationRegistry
/// @notice A registry contract to keep track of funders and their slots taken in different integration groups.
interface IFunderIntegrationRegistry {
    /// @notice Registers a funder with the given group entries for the integration key.
    /// @dev Each registrant must only call this function once for each funder. This is reset after they have deregistered the funder again.
    /// @param integrationKey The integration key to register the funder for.
    /// @param funder The funder to register.
    /// @param groupEntries The slots taken by the funder in each groups. Groups must be strictly increasing. Groups with zero slots taken have to be omitted.
    function register(bytes32 integrationKey, address funder, GroupEntry[] calldata groupEntries) external;

    /// @notice Deregisters a funder for the senders integration key.
    /// @dev A registrant must only call this function if they have previously registered the funder.
    /// @param integrationKey The integration key to deregister the funder for.
    /// @param funder The funder to deregister.
    function deregister(bytes32 integrationKey, address funder) external;

    /// @notice Returns whether the funder is registered for the given integration key.
    function isRegistered(bytes32 integrationKey, address funder) external view returns (bool);

    /// @notice Returns the funder and how often it was registered for a given integration key.
    /// @dev This function together with `numFunders` can be used to iterate over all funders for a given integration key.
    function funderRegistrationCountAt(bytes32 integrationKey, uint256 index)
        external
        view
        returns (address, uint256);

    /// @notice Returns the number of funders for the given integration key.
    function numFunders(bytes32 integrationKey) external view returns (uint256);

    /// @notice Returns the total number of slots taken in the given integration key and group.
    function slotsTakenByGroup(bytes32 integrationKey, uint256 group) external view returns (uint256);

    /// @notice Returns the groups a funder is registered for and the number of slots taken therein, for the given integration key.
    function slotsTakenByFunder(bytes32 integrationKey, address funder) external view returns (GroupEntry[] memory);
}
