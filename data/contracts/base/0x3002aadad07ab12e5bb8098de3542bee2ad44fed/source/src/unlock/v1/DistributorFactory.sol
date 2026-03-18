// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Versioned} from "echo/Versioned.sol";
import {IGenericRegistry} from "echo/interfaces/IGenericRegistry.sol";

import {Distributor} from "./Distributor.sol";
import {newDistributor} from "./Deploy.sol";
import {UnlockAbsoluteSchedule} from "./ScheduleTypes.sol";
import {ScheduledUnlocker} from "./ScheduledUnlocker.sol";
import {UnlockerLib} from "./UnlockerLib.sol";
import {UnlockerFactory} from "./UnlockerFactory.sol";
import "./Types.sol";

/// @notice Factory for creating unlocked token distributors.
contract DistributorFactory is AccessControlEnumerable, Versioned(2, 1, 0) {
    /// @notice Emitted when a distributor is created
    event DistributorCreated(bytes16 indexed tokenDistributionUUID, address indexed distributorAddress);
    /// @notice Emitted when a scheduled unlocker is created
    event ScheduledUnlockerCreated(bytes16 indexed tokenDistributionUUID, address indexed scheduledUnlockerAddress);

    /// @notice Role allowed to change settings on this contract
    /// @dev This is intended to be controlled by the IM team.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The role allowed to grant ENG_MANAGER_ROLE
    /// @dev This is intended to be controlled by the ENG multisig.
    bytes32 public constant ENG_ADMIN_ROLE = keccak256("ENG_ADMIN_ROLE");

    /// @notice The role allowed to manage engineering related aspects of the contract, that does not involve any funds.
    /// @dev This is intended to be controlled by the ENG team.
    bytes32 public constant ENG_MANAGER_ROLE = keccak256("ENG_MANAGER_ROLE");

    /// @notice Role granted to the platform, allowed to create distributors
    /// @dev This is intended to be controlled by the platform backend.
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");

    /// @notice Fixed parameters specified by the IM team used to initialize distributors created by this factory
    IMFixedDistributorCreationParams public imFixedDistributorCreationParams;

    /// @notice Fixed parameters specified by the ENG team used to initialize distributors created by this factory
    ENGFixedDistributorCreationParams public engFixedDistributorCreationParams;

    /// @notice The address of the unlocker factory that will be used to create unlockers (e.g. ScheduledUnlockers)
    UnlockerFactory public unlockerFactory;

    /// @notice Address of the implementation for new distributors
    address public distributorImpl;

    /// @notice Fixed parameters specified by the IM team used to initialize distributors created by this factory
    /// @dev These parameters are not expected to change for different distributors.
    /// They are used together with variable parameters sent to `createDistributor` by the platfrom backend to initialize distributors created by this factory
    /// @dev Since some of these parameters are sensitive, we don't allow the platform or the ENG team to pass them in or change them, and store them in this contract instead.
    struct IMFixedDistributorCreationParams {
        address adminIM;
        address managerIM;
        address adminENG;
        IGenericRegistry genericRegistry;
    }

    /// @notice Fixed parameters specified by the ENG team used to initialize distributors created by this factory
    /// @dev These parameters are not expected to change for different distributors.
    /// They are used together with variable parameters sent to `createDistributor` by the platfrom backend to initialize distributors created by this factory
    /// @dev Since some of these parameters are sensitive, we don't allow the platform to pass them in or change them, and store them in this contract instead.
    struct ENGFixedDistributorCreationParams {
        address managerENG;
        address platformSigner;
        address platformSender;
    }

    /// @notice Dynamic parameters used to initialize a new distributor
    /// @dev These parameters are sent to `createDistributor` to initialize a new distributor and can be different for each distributor
    struct VariableDistributorCreationParams {
        IERC20 token;
        bytes16 tokenDistributionUUID;
        UnlockerLib.Unlocker unlocker;
        Claimer[] claimers;
        CarryWithdrawer[] carryWithdrawers;
        bytes32 expectedClaimersRoot;
        uint16 platformCarryBPS;
    }

    /// @notice Dynamic parameters used to initialize a new distributor with a ScheduledUnlocker
    /// @dev These parameters are a combination of the parameters sent to `createDistributor` and `createScheduledUnlocker` to initialize a new distributor and can be different for each distributor
    struct VariableDistributorAndScheduledUnlockerCreationParams {
        // Distributor params
        IERC20 token;
        bytes16 tokenDistributionUUID;
        Claimer[] claimers;
        CarryWithdrawer[] carryWithdrawers;
        bytes32 expectedClaimersRoot;
        uint16 platformCarryBPS;
        // ScheduledUnlocker params
        UnlockAbsoluteSchedule unlockSchedule;
        uint256 maxUnlockableTokens;
    }

    /// @notice Dynamic parameters used to initialize a ScheduledUnlocker
    /// @dev These parameters are a subset sent to `createScheduledUnlocker` to initialize a new ScheduledUnlocker and can be different for each ScheduledUnlocker
    struct VariableScheduledUnlockerCreationParams {
        IERC20 lockedToken;
        bytes16 tokenDistributionUUID;
        address distributor;
        UnlockAbsoluteSchedule unlockSchedule;
        uint256 maxUnlockableTokens;
        uint256 initialTokensReleased;
    }

    struct Init {
        address adminIM;
        address adminENG;
        address platform;
        UnlockerFactory unlockerFactory;
        IMFixedDistributorCreationParams imFixedDistributorCreationParams;
        ENGFixedDistributorCreationParams engFixedDistributorCreationParams;
    }

    constructor(Init memory init) {
        _setRoleAdmin(ENG_MANAGER_ROLE, ENG_ADMIN_ROLE);
        _setRoleAdmin(PLATFORM_ROLE, ENG_MANAGER_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, init.adminIM);
        _grantRole(MANAGER_ROLE, init.adminIM);

        _grantRole(ENG_ADMIN_ROLE, init.adminENG);
        _grantRole(ENG_MANAGER_ROLE, init.adminENG);

        _grantRole(PLATFORM_ROLE, init.platform);

        imFixedDistributorCreationParams = init.imFixedDistributorCreationParams;
        engFixedDistributorCreationParams = init.engFixedDistributorCreationParams;

        unlockerFactory = init.unlockerFactory;

        distributorImpl = address(new Distributor());
    }

    /// @notice Creates a new distributor
    /// @param params Variable parameters used to initialize the new distributor
    /// @return The address of the newly created distributor
    function createDistributor(VariableDistributorCreationParams memory params)
        external
        onlyRole(PLATFORM_ROLE)
        returns (Distributor)
    {
        return _createDistributor(params);
    }

    /// @notice Creates a new ScheduledUnlocker from the factory.
    /// @dev We choose to include this function as we want to keep the UnlockerFactory simple and rely on passing the fixed values here to the unlocker
    /// rather than storing them on the UnlockerFactory as well.
    /// @param params Variable parameters used to initialize the new ScheduledUnlocker
    /// @return The address of the newly created ScheduledUnlocker
    function createScheduledUnlocker(VariableScheduledUnlockerCreationParams memory params)
        external
        onlyRole(PLATFORM_ROLE)
        returns (ScheduledUnlocker)
    {
        return _createScheduledUnlocker(params, address(0));
    }

    function createDistributorWithScheduledUnlocker(VariableDistributorAndScheduledUnlockerCreationParams memory params)
        external
        onlyRole(PLATFORM_ROLE)
        returns (Distributor, ScheduledUnlocker)
    {
        VariableScheduledUnlockerCreationParams memory scheduledUnlockerParams = VariableScheduledUnlockerCreationParams({
            tokenDistributionUUID: params.tokenDistributionUUID,
            lockedToken: params.token,
            unlockSchedule: params.unlockSchedule,
            maxUnlockableTokens: params.maxUnlockableTokens,
            // Intentially not allowing to set the initialTokensReleased as this is a new distributor so we shouldn't have any tokens released yet.
            // If this is an upgraded distribution (e.g. going from manual to contract), then tokens have likely been released but we expect that to handle that exceptional
            // case using the setter.
            initialTokensReleased: 0,
            // Initialized to 0 as we are setting the distributor later.
            distributor: address(0)
        });

        ScheduledUnlocker scheduledUnlocker = _createScheduledUnlocker(scheduledUnlockerParams, address(this));

        UnlockerLib.Unlocker memory unlockerStruct = UnlockerLib.Unlocker({
            unlocker: address(scheduledUnlocker),
            releasableType: UnlockerLib.ECHO_TYPE,
            releaseType: UnlockerLib.ECHO_TYPE
        });

        VariableDistributorCreationParams memory withUnlockerParams = VariableDistributorCreationParams({
            token: params.token,
            tokenDistributionUUID: params.tokenDistributionUUID,
            claimers: params.claimers,
            carryWithdrawers: params.carryWithdrawers,
            expectedClaimersRoot: params.expectedClaimersRoot,
            platformCarryBPS: params.platformCarryBPS,
            unlocker: unlockerStruct
        });

        Distributor distributor = _createDistributor(withUnlockerParams);

        scheduledUnlocker.setDistributor(address(distributor));

        // Once we have created and set the distributor, we can remove the distributor setter role from the scheduled unlocker.
        scheduledUnlocker.renounceRole(scheduledUnlocker.DISTRIBUTOR_SETTER_ROLE(), address(this));

        return (distributor, scheduledUnlocker);
    }

    function _createDistributor(VariableDistributorCreationParams memory params) internal returns (Distributor) {
        Distributor distributor = newDistributor(
            imFixedDistributorCreationParams.adminIM,
            Distributor(distributorImpl),
            Distributor.Init({
                // variable params
                token: params.token,
                tokenDistributionUUID: params.tokenDistributionUUID,
                unlocker: params.unlocker,
                claimers: params.claimers,
                carryWithdrawers: params.carryWithdrawers,
                expectedClaimersRoot: params.expectedClaimersRoot,
                platformCarryBPS: params.platformCarryBPS,
                // IM fixed params
                genericRegistry: imFixedDistributorCreationParams.genericRegistry,
                adminIM: imFixedDistributorCreationParams.adminIM,
                managerIM: imFixedDistributorCreationParams.managerIM,
                adminENG: imFixedDistributorCreationParams.adminENG,
                // ENG fixed params
                managerENG: engFixedDistributorCreationParams.managerENG,
                platformSigner: engFixedDistributorCreationParams.platformSigner,
                platformSender: engFixedDistributorCreationParams.platformSender
            })
        );

        emit DistributorCreated(params.tokenDistributionUUID, address(distributor));

        return distributor;
    }

    function _createScheduledUnlocker(VariableScheduledUnlockerCreationParams memory params, address distributorSetter)
        internal
        returns (ScheduledUnlocker)
    {
        ScheduledUnlocker.Init memory init = ScheduledUnlocker.Init({
            lockedToken: params.lockedToken,
            unlockSchedule: params.unlockSchedule,
            maxUnlockableTokens: params.maxUnlockableTokens,
            distributor: params.distributor,
            distributorSetter: distributorSetter,
            initialTokensReleased: params.initialTokensReleased,
            // IM fixed params
            imAdmin: imFixedDistributorCreationParams.adminIM,
            imManager: imFixedDistributorCreationParams.managerIM,
            engAdmin: imFixedDistributorCreationParams.adminENG,
            // ENG fixed params
            engManager: engFixedDistributorCreationParams.managerENG,
            // Empty address for the pauser as we expect to add the pauser role to the distributor intentionally.
            pauser: address(0)
        });

        ScheduledUnlocker unlocker = unlockerFactory.createScheduledUnlocker(init);
        emit ScheduledUnlockerCreated(params.tokenDistributionUUID, address(unlocker));

        return unlocker;
    }

    // TODO emit config changed events

    /// @notice Sets the UnlockerFactory contract
    /// @param newUnlockerFactory The new UnlockerFactory contract
    function setUnlockerFactory(UnlockerFactory newUnlockerFactory) external onlyRole(MANAGER_ROLE) {
        unlockerFactory = newUnlockerFactory;
    }

    /// @notice Sets the implementation for new distributors
    /// @param newImpl The address of the new implementation
    function setDistributorImplementation(address newImpl) external onlyRole(MANAGER_ROLE) {
        distributorImpl = newImpl;
    }

    /// @notice Sets the IM fixed parameters for new distributors
    /// @param newParams The fixed parameters
    function setIMFixedDistributorCreationParams(IMFixedDistributorCreationParams memory newParams)
        external
        onlyRole(MANAGER_ROLE)
    {
        imFixedDistributorCreationParams = newParams;
    }

    /// @notice Sets the ENG fixed parameters for new distributors
    /// @param newParams The fixed parameters
    function setENGFixedDistributorCreationParams(ENGFixedDistributorCreationParams memory newParams)
        external
        onlyRole(ENG_MANAGER_ROLE)
    {
        engFixedDistributorCreationParams = newParams;
    }
}
