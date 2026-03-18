// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDealRegistry} from "echo/interfaces/IDealRegistry.sol";
import {ConfigChanged} from "echo/interfaces/PlatformEvents.sol";
import {FunderIntegrationRegistry} from "echo/funder-integration/v2/FunderIntegrationRegistry.sol";
import {Versioned} from "echo/Versioned.sol";

import {DealSettings, FundingParameters, WithdrawalSettings} from "./Types.sol";
import {Deal} from "./Deal.sol";
import {Settlement} from "echo/settlement/v1/Settlement.sol";

/// Version history:
/// 2.1.0:
/// - Added ability to deploy a deal with a settlement contract.

/// @title DealFactory
/// @notice A factory contract to create `Deal` contract clones.
contract DealFactory is AccessControlEnumerable, Versioned(2, 1, 0) {
    /// @notice Emitted when a new deal clone is created.
    event DealCreated(bytes16 indexed uuid, address indexed dealAddress);
    event SettlementCreated(bytes16 indexed uuid, address indexed settlementAddress);

    ///  @notice The role allowed to manage the deal factory, i.e. change settings.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The role allowed to create deals.
    bytes32 public constant DEAL_CREATOR_ROLE = keccak256("DEAL_CREATOR_ROLE");

    /// @notice The deal registry contract, to register new deals.
    IDealRegistry public immutable dealRegistry;

    /// @notice The implementation for the deal contract that will be cloned
    address public dealImpl;

    /// @notice The implementation for the settlement contract that will be cloned
    address public settlementImpl;

    /// @notice The parameters to be used for new deals.
    DealCreationParameters internal _dealCreationParameters;

    /// @notice Returns the parameters to be used for creating new deals.
    /// @dev Using a function instead of just exposing the storage field, to avoid a the compiler treating the returns as tuple instead of typed struct
    function dealCreationParameters() external view returns (DealCreationParameters memory) {
        return _dealCreationParameters;
    }

    /// @notice The parameters to be used for new settlements.
    SettlementCreationParameters internal _settlementCreationParameters;

    /// @notice Returns the parameters to be used for creating new settlements.
    /// @dev Using a function instead of just exposing the storage field, to avoid the compiler treating the returns as tuple instead of typed struct
    function settlementCreationParameters() external view returns (SettlementCreationParameters memory) {
        return _settlementCreationParameters;
    }

    /// @notice The parameters to be used for creating new deals.
    /// @params funderIntegrationRegistry The funder integration registry to track groups of investors used for newly created deals.
    /// @params admin The admin of newly created deals.
    /// @params manager The manager of newly created deals.
    /// @params signer The signer of newly created deals.
    /// @params conduits The conduits of newly created deals.
    struct DealCreationParameters {
        FunderIntegrationRegistry funderIntegrationRegistry;
        IERC20 token;
        address admin;
        address manager;
        address platform;
        address signer;
        address withdrawalManager;
        address[] conduits;
    }

    /// @notice The parameters to be used for creating new settlements.
    struct SettlementCreationParameters {
        IERC20 token;
        address admin;
        address manager;
        address platform;
        address txSender;
        address withdrawalManager;
    }

    struct Init {
        IDealRegistry dealRegistry;
        address admin;
        address manager;
        address dealCreator;
        DealCreationParameters dealCreationParameters;
        SettlementCreationParameters settlementCreationParameters;
    }

    constructor(Init memory init) {
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(MANAGER_ROLE, init.manager);
        _setRoleAdmin(DEAL_CREATOR_ROLE, MANAGER_ROLE);
        _grantRole(DEAL_CREATOR_ROLE, init.dealCreator);

        dealRegistry = init.dealRegistry;
        _setDealCreationParameters(init.dealCreationParameters);
        _setSettlementCreationParameters(init.settlementCreationParameters);

        dealImpl = address(new Deal());
        settlementImpl = address(new Settlement());
    }

    /// @notice Creates a new deal from given funding settings.
    function createDeal(
        bytes16 dealUUID,
        bytes32 integrationKey,
        DealSettings calldata dealSettings,
        WithdrawalSettings calldata withdrawalSettings
    ) public onlyRole(DEAL_CREATOR_ROLE) returns (Deal) {
        DealCreationParameters memory params = _dealCreationParameters;
        return createDealWithParams(dealUUID, integrationKey, dealSettings, withdrawalSettings, params);
    }

    /// @notice Creates a new deal from given funding settings, with a settlement contract acting as the conduit.
    function createDealWithSettlement(
        bytes16 dealUUID,
        bytes32 integrationKey,
        DealSettings calldata dealSettings,
        WithdrawalSettings calldata withdrawalSettings
    ) public onlyRole(DEAL_CREATOR_ROLE) returns (Deal, Settlement) {
        SettlementCreationParameters memory settlementParams = _settlementCreationParameters;

        // Create the settlement contract, passing in the factory as the admin/withdrawal manager temporarily
        address originalAdmin = settlementParams.admin;
        address originalWithdrawalManager = settlementParams.withdrawalManager;
        settlementParams.admin = address(this);
        settlementParams.withdrawalManager = address(this);
        Settlement settlement = createSettlement(dealUUID, settlementParams);

        // Append the settlement contract to the conduits array
        DealCreationParameters memory dealParams = _dealCreationParameters;
        address[] memory newConduits = new address[](dealParams.conduits.length + 1);
        for (uint256 i = 0; i < dealParams.conduits.length; i++) {
            newConduits[i] = dealParams.conduits[i];
        }
        newConduits[dealParams.conduits.length] = address(settlement);
        dealParams.conduits = newConduits;

        Deal deal = createDealWithParams(dealUUID, integrationKey, dealSettings, withdrawalSettings, dealParams);

        settlement.setDealContract(address(deal));

        // Grant the admin role to the deal admin and revoke it from the factory
        settlement.grantRole(settlement.DEFAULT_ADMIN_ROLE(), originalAdmin);
        settlement.grantRole(settlement.WITHDRAWAL_MANAGER_ROLE(), originalWithdrawalManager);
        settlement.revokeRole(settlement.DEFAULT_ADMIN_ROLE(), address(this));
        settlement.revokeRole(settlement.WITHDRAWAL_MANAGER_ROLE(), address(this));

        return (deal, settlement);
    }

    function createDealWithParams(
        bytes16 dealUUID,
        bytes32 integrationKey,
        DealSettings calldata dealSettings,
        WithdrawalSettings calldata withdrawalSettings,
        DealCreationParameters memory params
    ) internal returns (Deal) {
        Deal deal = Deal(Clones.clone(dealImpl));
        deal.initialize(
            Deal.Init({
                dealUUID: dealUUID,
                integrationKey: integrationKey,
                funderIntegrationRegistry: params.funderIntegrationRegistry,
                admin: params.admin,
                manager: params.manager,
                platform: params.platform,
                signer: params.signer,
                conduits: params.conduits,
                token: params.token,
                dealSettings: dealSettings,
                withdrawalSettings: withdrawalSettings,
                withdrawalManager: params.withdrawalManager
            })
        );
        emit DealCreated(dealUUID, address(deal));

        dealRegistry.registerDeal(dealUUID, address(deal));
        params.funderIntegrationRegistry.grantRole(params.funderIntegrationRegistry.REGISTRANT_ROLE(), address(deal));
        return deal;
    }

    function createSettlement(
        bytes16 dealUUID,
        SettlementCreationParameters memory params
    ) internal returns (Settlement) {
        Settlement settlement = Settlement(Clones.clone(settlementImpl));
        settlement.initialize(
            Settlement.Init({
                admin: params.admin,
                manager: params.manager,
                platform: params.platform,
                txSender: params.txSender,
                withdrawalManager: params.withdrawalManager,
                token: params.token
            })
        );
        emit SettlementCreated(dealUUID, address(settlement));
        return settlement;
    }

    /// @notice Sets the implementation to be cloned for newly created deals.
    function setDealImplementation(address dealImpl_) external onlyRole(MANAGER_ROLE) {
        dealImpl = dealImpl_;
        emit ConfigChanged(
            this.setDealImplementation.selector,
            "setDealImplementation(address)",
            abi.encode(dealImpl_)
        );
    }

    /// @notice Sets the implementation to be cloned for newly created settlements.
    function setSettlementImplementation(address settlementImpl_) external onlyRole(MANAGER_ROLE) {
        settlementImpl = settlementImpl_;
        emit ConfigChanged(
            this.setSettlementImplementation.selector,
            "setSettlementImplementation(address)",
            abi.encode(settlementImpl_)
        );
    }

    /// @notice Sets the parameters for newly created deals.
    function setDealCreationParameters(DealCreationParameters memory params) external onlyRole(MANAGER_ROLE) {
        _setDealCreationParameters(params);
    }

    /// @notice Sets the parameters for newly created deals.
    function _setDealCreationParameters(DealCreationParameters memory params) internal {
        _dealCreationParameters = params;
        emit ConfigChanged(this.setDealCreationParameters.selector, "setDealCreationParameters((address,address,address,address,address,address,address,address[]))", abi.encode(params));
    }

    /// @notice Sets the parameters for newly created settlements.
    function setSettlementCreationParameters(
        SettlementCreationParameters memory params
    ) external onlyRole(MANAGER_ROLE) {
        _setSettlementCreationParameters(params);
    }

    /// @notice Sets the parameters for newly created settlements.
    function _setSettlementCreationParameters(SettlementCreationParameters memory params) internal {
        _settlementCreationParameters = params;
        emit ConfigChanged(this.setSettlementCreationParameters.selector, "setSettlementCreationParameters((address,address,address,address,address,address))", abi.encode(params));
    }
}
