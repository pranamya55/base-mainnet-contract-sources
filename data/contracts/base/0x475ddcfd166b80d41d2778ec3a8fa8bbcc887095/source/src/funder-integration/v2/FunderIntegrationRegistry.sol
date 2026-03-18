// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ConfigChanged} from "echo/interfaces/PlatformEvents.sol";
import {Versioned} from "echo/Versioned.sol";
import {IFunderIntegrationRegistry as IFunderIntegrationRegistryV1} from
    "echo/funder-integration/v1/IFunderIntegrationRegistry.sol";
import {IFunderIntegrationRegistry, GroupEntry} from "echo/funder-integration/v2/IFunderIntegrationRegistry.sol";
import {FunderRegistryLib} from "./FunderRegistryLib.sol";

/// @title FunderIntegrationRegistry
/// @notice A registry contract to keep track of funders and their slots taken in integration groups.
/// @dev This registry is expected to be used by deal contracts to keep track of groups of funders (e.g. US, or non-US based users) that invested in them. Deals may share a common integration key.
contract FunderIntegrationRegistry is
    Initializable,
    AccessControlEnumerableUpgradeable,
    IFunderIntegrationRegistryV1,
    IFunderIntegrationRegistry,
    Versioned(2, 0, 0)
{
    using FunderRegistryLib for FunderRegistryLib.FunderRegistry;

    /// @notice Emitted when a funder is registered.
    event FunderRegistered(
        bytes32 indexed integrationKey, address indexed funder, bool indexed added, GroupEntry[] groupEntries
    );

    /// @notice Emitted when a funder is deregistered.
    event FunderDeregistered(bytes32 indexed integrationKey, address indexed funder, bool indexed removed);

    /// @notice Thrown if the registry is disabled.
    error RegistryNotEnabled();

    /// @notice Thrown if a v1 backwards compatibility function is called for funder with multiple groups or slots taken.
    error RegistrationNotV1Compatible(bytes32 integrationKey, address funder, GroupEntry[] groupEntries);

    /// @notice The role allowed to manage the registry, i.e. disable it and add/remove registrant managers.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The role allowed to manage registrants, i.e. add/remove them.
    /// @dev This role is expected to be granted to the deal factory.
    bytes32 public constant REGISTRANT_MANAGER_ROLE = keccak256("REGISTRANT_MANAGER_ROLE");

    /// @notice The role allowed to (de-)register funders.
    /// @dev This role is expected to be granted to deal contracts.
    bytes32 public constant REGISTRANT_ROLE = keccak256("REGISTRANT_ROLE");

    /// @notice The role allowed to migrate the registry from V1.
    /// @dev This role is expected to be granted to the platform backend.
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");

    /// @notice Flag to enable/disable the registry.
    bool public isEnabled;

    /// @notice The funder registries by integration key.
    mapping(bytes32 integrationKey => FunderRegistryLib.FunderRegistry) internal _registries;

    constructor() {
        _disableInitializers();
    }

    struct Init {
        address admin;
        address manager;
    }

    function initialize(Init memory init) public initializer {
        __AccessControlEnumerable_init();

        _setRoleAdmin(REGISTRANT_MANAGER_ROLE, MANAGER_ROLE);
        _setRoleAdmin(REGISTRANT_ROLE, REGISTRANT_MANAGER_ROLE);
        _setRoleAdmin(PLATFORM_ROLE, MANAGER_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(MANAGER_ROLE, init.manager);

        isEnabled = true;
    }

    modifier onlyEnabled() {
        if (!isEnabled) {
            revert RegistryNotEnabled();
        }
        _;
    }

    /// @inheritdoc IFunderIntegrationRegistry
    function register(bytes32 integrationKey, address funder, GroupEntry[] memory groupEntries)
        external
        onlyEnabled
        onlyRole(REGISTRANT_ROLE)
    {
        _register(integrationKey, funder, groupEntries);
    }

    /// @dev Internal function to register a funder.
    function _register(bytes32 integrationKey, address funder, GroupEntry[] memory groupEntries) internal {
        bool added = _registries[integrationKey].register(funder, groupEntries);
        emit FunderRegistered(integrationKey, funder, added, groupEntries);
    }

    /// @inheritdoc IFunderIntegrationRegistry
    function deregister(bytes32 integrationKey, address funder)
        external
        override(IFunderIntegrationRegistry, IFunderIntegrationRegistryV1)
        onlyEnabled
        onlyRole(REGISTRANT_ROLE)
    {
        bool removed = _registries[integrationKey].deregister(funder);
        emit FunderDeregistered(integrationKey, funder, removed);
    }

    /// @inheritdoc IFunderIntegrationRegistry
    function isRegistered(bytes32 integrationKey, address funder)
        external
        view
        override(IFunderIntegrationRegistry, IFunderIntegrationRegistryV1)
        returns (bool)
    {
        return _registries[integrationKey].contains(funder);
    }

    /// @inheritdoc IFunderIntegrationRegistry
    function slotsTakenByGroup(bytes32 integrationKey, uint256 group_) public view returns (uint256) {
        return _registries[integrationKey].slotsTakenByGroup(group_);
    }

    /// @inheritdoc IFunderIntegrationRegistry
    function numFunders(bytes32 integrationKey) public view returns (uint256) {
        return _registries[integrationKey].numFunders();
    }

    /// @inheritdoc IFunderIntegrationRegistry
    function funderRegistrationCountAt(bytes32 integrationKey, uint256 index)
        external
        view
        returns (address, uint256)
    {
        return _registries[integrationKey].registrationCountByFunderAt(index);
    }

    /// @notice Returns the number of times a funder was registered.
    function funderRegistrationCount(bytes32 integrationKey, address funder) public view returns (uint256) {
        return _registries[integrationKey].registrationCount(funder);
    }

    /// @inheritdoc IFunderIntegrationRegistry
    function slotsTakenByFunder(bytes32 integrationKey, address funder) external view returns (GroupEntry[] memory) {
        return _registries[integrationKey].slotsTakenByFunder(funder);
    }

    /// @notice Sets whether the registry is enabled.
    function setEnabled(bool isEnabled_) external onlyRole(MANAGER_ROLE) {
        isEnabled = isEnabled_;
        emit ConfigChanged(this.setEnabled.selector, "setEnabled(bool)", abi.encode(isEnabled_));
    }

    // migration
    // DOLATER: the following functions can be removed after the migration from v1 is done

    error MigrationErrorFunderAlreadyRegistered(address funder);

    /// @notice Migrates the registry data from a V1 registry.
    /// @param registryV1 The V1 registry to migrate from.
    /// @param integrationKey The integration key to migrate.
    /// @param numMax The maximum number of funders to migrate.
    /// @dev This function can be called repeatedly to migrate the registry in chunks.
    /// It's a no-op if the registry was migrated completely.
    function migrate(IFunderIntegrationRegistryV1 registryV1, bytes32 integrationKey, uint256 numMax)
        external
        onlyRole(PLATFORM_ROLE)
    {
        uint256 numTotal = registryV1.numTotal(integrationKey);
        uint256 numCurrent = _registries[integrationKey].numFunders();

        uint256 end = numCurrent + numMax;
        if (end > numTotal) {
            end = numTotal;
        }

        for (uint256 i = numCurrent; i < end; i++) {
            (address funder, uint256 group) = registryV1.at(integrationKey, i);

            // additional sanity check
            uint256 regCount = funderRegistrationCount(integrationKey, funder);
            if (regCount > 0) {
                revert MigrationErrorFunderAlreadyRegistered(funder);
            }

            GroupEntry[] memory groupEntries = new GroupEntry[](1);
            groupEntries[0] = GroupEntry({group: group, num: 1});
            _register(integrationKey, funder, groupEntries);
        }
    }

    /// @notice Clears the registry.
    /// @dev This function is intended as an escape hatch in the case of a botched migration.
    /// @param integrationKey The integration key to clear.
    /// @param numMax The maximum number of funders to clear.
    /// @dev This function can be called repeatedly to clear the registry in chunks.
    function clear(bytes32 integrationKey, uint256 numMax) external onlyRole(PLATFORM_ROLE) {
        uint256 numFunders = _registries[integrationKey].numFunders();
        if (numMax == 0 || numMax > numFunders) {
            numMax = numFunders;
        }

        for (uint256 i = 0; i < numMax; i++) {
            uint256 index = numFunders - i - 1;
            (address funder, uint256 registrationCount) = _registries[integrationKey].registrationCountByFunderAt(index);
            assert(registrationCount > 0);

            for (uint256 j = 0; j < registrationCount; j++) {
                _registries[integrationKey].deregister(funder);
            }
        }
    }

    // The following functions are implemented for V1 backwards compatibility
    // They can be removed once we've migrated all contracts to V2.

    /// @inheritdoc IFunderIntegrationRegistryV1
    function register(bytes32 integrationKey, address funder, uint256 group)
        external
        onlyEnabled
        onlyRole(REGISTRANT_ROLE)
    {
        GroupEntry[] memory groupEntries = new GroupEntry[](1);
        groupEntries[0] = GroupEntry({group: group, num: 1});
        _register(integrationKey, funder, groupEntries);
    }

    /// @inheritdoc IFunderIntegrationRegistryV1
    function group(bytes32 integrationKey, address funder) public view returns (uint256) {
        GroupEntry[] memory counts = _registries[integrationKey].slotsTakenByFunder(funder);
        if (counts.length > 1) {
            revert RegistrationNotV1Compatible(integrationKey, funder, counts);
        }

        return counts[0].group;
    }

    /// @inheritdoc IFunderIntegrationRegistryV1
    function at(bytes32 integrationKey, uint256 index) external view returns (address, uint256) {
        (address funder,) = _registries[integrationKey].registrationCountByFunderAt(index);
        uint256 group_ = group(integrationKey, funder);
        return (funder, group_);
    }

    /// @inheritdoc IFunderIntegrationRegistryV1
    function numTotal(bytes32 integrationKey) external view returns (uint256) {
        return numFunders(integrationKey);
    }

    /// @inheritdoc IFunderIntegrationRegistryV1
    function numInGroup(bytes32 integrationKey, uint256 group_) external view returns (uint256) {
        return slotsTakenByGroup(integrationKey, group_);
    }
}
