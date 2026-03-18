// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {GroupEntry} from "echo/funder-integration/v2/IFunderIntegrationRegistry.sol";

/// @notice A helper library for managing a registry of funders and their slots taken in different groups.
library FunderRegistryLib {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableMap for EnumerableMap.UintToUintMap;

    /// @notice Thrown on attempts to register a funder that is already registered but with a different configuration of slots taken in groups.
    error FunderAlreadyRegisteredWithDifferentGroupEntry(address funder, uint256 group, uint256 got, uint256 want);

    /// @notice Thrown on attempts to register a funder that is already registered but with a different number of groups.
    error FunderAlreadyRegisteredWithDifferentNumberOfGroups(address funder, uint256 got, uint256 want);

    /// @notice Thrown on attempts to deregister a funder that is not registered.
    error FunderNotRegistered(address funder);

    /// @notice Thrown on attempts to register the zero address as a funder.
    error ZeroFunder();

    /// @notice Thrown on attempts to register a funder with groups that are not strictly increasing.
    /// @dev This prevents repeated groups from being registered.
    error InvalidGroupEntriesGroupNotStrictlyIncreasing(uint256 group, GroupEntry[] groupEntries);

    /// @notice Thrown on attempts to register a funder with an empty slots taken array.
    error InvalidGroupEntriesEmpty();

    /// @notice Thrown on attempts to register a funder for a group with zero slots taken.
    error InvalidGroupEntriesZero(uint256 group, GroupEntry[] groupEntries);

    /// @notice A registry of funders.
    /// @params registrationCountByFunder The set of tracked funders and how often they were registered. A funder will only be removed from the registry when its count reaches 0.
    /// @params groupEntriesByFunder The number of slots taken by each funder in each group.
    /// @params entriesByGroup The number of slots taken in each group.
    struct FunderRegistry {
        EnumerableMap.AddressToUintMap registrationCountByFunder;
        mapping(address => EnumerableMap.UintToUintMap) groupEntriesByFunder;
        mapping(uint256 => uint256) entriesByGroup;
    }

    /// @notice Registers a funder.
    /// @param funder The funder to register.
    /// @param groupEntries The slots taken by the funder in each groups. Groups must be strictly increasing. Groups with zero slots taken have to be omitted.
    /// @return added Whether the funder was newly added to the registry (i.e. not already registered by another registrant).
    function register(FunderRegistry storage registry, address funder, GroupEntry[] memory groupEntries)
        internal
        returns (bool)
    {
        if (funder == address(0)) {
            revert ZeroFunder();
        }

        if (groupEntries.length == 0) {
            revert InvalidGroupEntriesEmpty();
        }

        for (uint256 i = 0; i < groupEntries.length; i++) {
            GroupEntry memory groupEntry = groupEntries[i];
            if (groupEntry.num == 0) {
                revert InvalidGroupEntriesZero(groupEntry.group, groupEntries);
            }

            if (i == 0) {
                continue;
            }

            // check that groups are strictly increasing
            // this ensures that we don't have repeated groups
            if (groupEntry.group <= groupEntries[i - 1].group) {
                revert InvalidGroupEntriesGroupNotStrictlyIncreasing(groupEntry.group, groupEntries);
            }
        }

        (bool exists, uint256 regCount) = registry.registrationCountByFunder.tryGet(funder);
        if (!exists) {
            for (uint256 i = 0; i < groupEntries.length; i++) {
                GroupEntry memory groupEntry = groupEntries[i];

                registry.groupEntriesByFunder[funder].set(groupEntry.group, groupEntry.num);
                registry.entriesByGroup[groupEntry.group] += groupEntry.num;
            }

            registry.registrationCountByFunder.set(funder, 1);
            return true;
        }

        // safety check to ensure the registered group counts match the ones we requested to register
        EnumerableMap.UintToUintMap storage existing = registry.groupEntriesByFunder[funder];
        if (existing.length() != groupEntries.length) {
            revert FunderAlreadyRegisteredWithDifferentNumberOfGroups(funder, groupEntries.length, existing.length());
        }

        for (uint256 i = 0; i < groupEntries.length; i++) {
            GroupEntry memory groupEntry = groupEntries[i];
            (, uint256 existingCount) = existing.tryGet(groupEntry.group);
            if (existingCount != groupEntry.num) {
                revert FunderAlreadyRegisteredWithDifferentGroupEntry(
                    funder, groupEntry.group, groupEntry.num, existingCount
                );
            }
        }

        registry.registrationCountByFunder.set(funder, regCount + 1);
        return false;
    }

    /// @notice Deregisters a funder.
    /// @param funder The funder to deregister.
    /// @return removed Whether the funder was removed from the registry (i.e. if it's registration count dropped to 0).
    function deregister(FunderRegistry storage registry, address funder) internal returns (bool) {
        (bool exists, uint256 regCount) = registry.registrationCountByFunder.tryGet(funder);
        if (!exists) {
            revert FunderNotRegistered(funder);
        }

        // funder was registered by multiple registrants
        if (regCount > 1) {
            registry.registrationCountByFunder.set(funder, regCount - 1);
            return false;
        }

        // the funder was only registered by a single registrant, so we need to remove it completely.
        // for this we need to
        // - subtract the slots taken by the funder from the group totals (entriesByGroup_)
        // - clear the entries in groupEntriesByFunder_
        // - remove the funder from the registrationCountByFunder

        EnumerableMap.UintToUintMap storage groupEntries = registry.groupEntriesByFunder[funder];
        uint256[] memory groupKeys = groupEntries.keys();
        for (uint256 i = 0; i < groupKeys.length; i++) {
            uint256 count = groupEntries.get(groupKeys[i]);
            registry.entriesByGroup[groupKeys[i]] -= count;
            groupEntries.remove(groupKeys[i]);
        }

        registry.registrationCountByFunder.remove(funder);
        return true;
    }

    /// @notice Returns the number of funders registered in the registry.
    function numFunders(FunderRegistry storage registry) internal view returns (uint256) {
        return registry.registrationCountByFunder.length();
    }

    /// @notice Returns whether the registry contains the funder.
    function contains(FunderRegistry storage registry, address funder) internal view returns (bool) {
        return registry.registrationCountByFunder.contains(funder);
    }

    /// @notice Returns the number of times a funder was registered.
    function registrationCount(FunderRegistry storage registry, address funder) internal view returns (uint256) {
        (, uint256 count) = registry.registrationCountByFunder.tryGet(funder);
        return count;
    }

    /// @notice Returns the funder and its registration count at a given index.
    function registrationCountByFunderAt(FunderRegistry storage registry, uint256 index)
        internal
        view
        returns (address, uint256)
    {
        return registry.registrationCountByFunder.at(index);
    }

    /// @notice Returns the number of slots taken in a group.
    function slotsTakenByGroup(FunderRegistry storage registry, uint256 group) internal view returns (uint256) {
        return registry.entriesByGroup[group];
    }

    /// @notice Returns the slots taken by a funder in each group.
    function slotsTakenByFunder(FunderRegistry storage registry, address funder)
        internal
        view
        returns (GroupEntry[] memory)
    {
        EnumerableMap.UintToUintMap storage groupEntries = registry.groupEntriesByFunder[funder];

        uint256 numGroups = groupEntries.length();
        GroupEntry[] memory ret = new GroupEntry[](numGroups);
        for (uint256 i = 0; i < numGroups; i++) {
            (uint256 group, uint256 count) = groupEntries.at(i);
            ret[i] = GroupEntry({group: group, num: count});
        }

        return ret;
    }
}
