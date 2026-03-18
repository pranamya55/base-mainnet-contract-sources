// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IFunderIntegrationRegistry} from "echo/funder-integration/v1/IFunderIntegrationRegistry.sol";
import {ConfigChanged} from "echo/interfaces/PlatformEvents.sol";
import {Versioned} from "echo/Versioned.sol";
import {
    DealSettings,
    FundingParameters,
    isValidFundingParameters,
    WithdrawalSettings,
    DEAL_SETTINGS_SIGNATURE,
    WITHDRAWAL_SETTINGS_SIGNATURE,
    PoolSettings,
    UserSettings,
    UserPoolSettings,
    findSettings,
    PoolRefund
} from "./Types.sol";

/// @notice A library to deal with deal funding permits.
library DealSignatureLib {
    struct DealFundingPermit {
        address funder;
        bool isUS;
        bytes16 dealUUID;
        uint256 expireAt;
        FundingParameters fundingParameters;
    }

    /// @notice Computes the chain-dependent digest of a DealFundingPermit.
    function digest(DealFundingPermit memory df, uint256 chainId) internal pure returns (bytes32) {
        return MessageHashUtils.toEthSignedMessageHash(abi.encode(df, chainId));
    }

    /// @notice Computes the digest of a DealFundingPermit for the current chain.
    function digest(DealFundingPermit memory df) internal view returns (bytes32) {
        return digest(df, block.chainid);
    }

    /// @notice Recovers the signer of a signed DealFundingPermit.
    function recoverSigner(DealFundingPermit memory df, bytes calldata signature) internal view returns (address) {
        return ECDSA.recover(digest(df), signature);
    }
}

/// @dev Precomputing the signature of the Deal.setDealSettings function for convenience since structs are ABI encoded as tuples.
string constant SET_DEAL_SETTINGS_SIGNATURE = string(abi.encodePacked("setDealSettings(", DEAL_SETTINGS_SIGNATURE, ")"));

/// @dev Precomputing the signature of the Deal.setWithdrawalSettings function for convenience since structs are ABI encoded as tuples.
string constant SET_WITHDRAWAL_SETTINGS_SIGNATURE =
    string(abi.encodePacked("setWithdrawalSettings(", WITHDRAWAL_SETTINGS_SIGNATURE, ")"));

/// @title Deal
/// @notice Holds configuration and state for a fundraise, tracking funders, amounts funded, etc.
contract Deal is Initializable, AccessControlEnumerableUpgradeable, Versioned(2, 0, 2) {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    /// @notice The role allowed to manage sensitive, administrative aspects of the deal, but not touch anything funds related.
    /// @dev This role is managed by the `DEFAULT_ADMIN_ROLE` which will be granted to the ENG multisig.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The role allowed manage less sensitive aspects of the deal.
    /// @dev This role will be granted to the platform backend.
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");

    /// @notice The role allowed to sign funding permits.
    /// @dev This role will be granted to the platform backend.
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    /// @notice The role allowed to execute funding transactions on the user's behalf.
    bytes32 public constant FUNDING_CONDUIT_ROLE = keccak256("FUNDING_CONDUIT_ROLE");

    /// @notice The role allowed to pause the deal funding
    /// @dev Keeping this deliberately separate from the `PLATFORM_ROLE` since we might want to grant this to some external monitoring in the future
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The role allowed to change the withdrawal settings (the destination of funds after the fundraise is closed) and recover funds in an emergency.
    /// @dev This role is its own admin, and therefore outside the usual role hierarchy.
    /// @dev This role will be granted to the IM multisig.
    bytes32 public constant WITHDRAWAL_MANAGER_ROLE = keccak256("WITHDRAWAL_MANAGER_ROLE");

    error UnauthorizedSigner(address signer);
    error InvalidConfiguration();
    error ExceedsMaxFeesAmount(uint256 feeAmountAttempted, uint256 maxFeesAmount);
    error InvalidFundingParameters();
    error ZeroAmountRequested();
    error ZeroAmountFunded();
    error AmountLowerThanMinPerUserLimit(uint256 bound, uint256 currentUserTotal, uint256 newUserTotal);
    error AmountGreaterThanMaxPerUserLimit(uint256 bound, uint256 currentUserTotal, uint256 newUserTotal);

    error Unauthorized();
    error MaxNumberOfFundersInGroupReached(bool isUS);
    error MaxTotalExceeded(uint256 bound, uint256 current, uint256 newTotal);
    error Closed(uint256 opensAt, uint256 closesAt, uint256 now);
    error DealFundingPermitInvalidFunder(address funderOnPermit);
    error DealFundingPermitInvalidDealUUID(bytes16 dealUUIDOnPermit);
    error DealFundingPermitExpired(uint256 expiredAt);
    error FunderRegisteredUnderDifferentGroup(address funder, uint256 existing, uint256 permitGroup);
    error Disabled();
    error NotFunder(address);
    error MaxPartialRequestFillingDifferenceExceeded(uint256 remainingAmount);
    error PoolRefundExceedsFunding(address funder, bytes16 poolID, uint256 amountFunded);

    /// @notice Emitted when a deal is funded.
    event DealFunded(bytes16 indexed dealUUID, address indexed funder, uint256 amount, uint256 newFunderTotal);

    // @notice Emitted if the funding request could not be filled completely and some funds are returned to the user.
    event PartialFundingAmountReturned(bytes16 indexed dealUUID, address indexed funder, uint256 amount);

    /// @notice Emitted when a user funded a pool.
    event PoolFunded(bytes16 indexed dealUUID, address indexed funder, bytes16 indexed poolID, uint256 amount);

    /// @notice Emitted when a user funds a pool.
    /// @dev This is intended to help debugging by providing some introspection into the spillover process.
    /// @dev Might be removed at some point
    event PoolFundingData(
        bytes16 indexed dealUUID,
        address indexed funder,
        bytes16 indexed poolID,
        uint256 amountAttempted,
        uint256 amountFree,
        uint256 amountFunded
    );

    /// @notice Emitted when a user is refunded.
    event DealRefunded(bytes16 indexed dealUUID, address indexed funder, uint256 amount, uint256 newFunderTotal);

    /// @notice Emitted when a user is refunded from a certain pool.
    event PoolRefunded(bytes16 indexed dealUUID, address indexed funder, bytes16 indexed poolID, uint256 amount);

    /// @notice Emitted when raised funds have been withdrawn.
    event DealFundsWithdrawn(IERC20 indexed token, address indexed to, uint256 amount);

    /// @notice Flag to enable/disable the deal funding.
    bool public isEnabled;

    /// @notice The UUID of the deal.
    /// @dev This is specified on deal creation and is immutable. Matches the UUID on the backend.
    bytes16 public dealUUID;

    /// @notice The token used for funding the deal.
    /// @dev This is intended to validate that the incoming funding permits were issued for the correct token, and to protect us against a backend malfunction, which would mess up the contracts accounting.
    IERC20 public token;

    /// @notice The deal settings.
    DealSettings internal _dealSettings;

    /// @notice The total amount funded by all users.
    uint256 public totalFunded;

    /// @notice The total amount funded by pool.
    EnumerableMap.Bytes32ToUintMap internal _amountFundedByPool;

    /// @notice The pools and amounts funded by individual users.
    mapping(address => EnumerableMap.Bytes32ToUintMap) internal _amountFundedByFunderAndPool;

    /// @notice The funders of the deal.
    EnumerableMap.AddressToUintMap internal _amountFundedByUser;

    /// @notice The funder integration registry to track US/NonUS-based investors across deal contracts.
    IFunderIntegrationRegistry public funderIntegrationRegistry;

    /// @notice The shared key to track investors in the integration registry.
    bytes32 public integrationKey;

    /// @notice Specifies the receipients and amounts for the withdrawal of deal funds.
    /// @dev These settings can only be changed by the `WITHDRAWAL_MANAGER_ROLE`.
    WithdrawalSettings internal _withdrawalSettings;

    /// @notice The amount of fees already withdrawn from the deal.
    /// @dev This is needed to ensure that fees cannot be withdrawn multiple times.
    uint256 public feesAmountWithdrawn;

    constructor() {
        _disableInitializers();
    }

    struct Init {
        bytes16 dealUUID;
        bytes32 integrationKey;
        IFunderIntegrationRegistry funderIntegrationRegistry;
        address admin;
        address manager;
        address platform;
        address signer;
        address[] conduits;
        IERC20 token;
        DealSettings dealSettings;
        WithdrawalSettings withdrawalSettings;
        address withdrawalManager;
    }

    function initialize(Init calldata init) public initializer {
        __AccessControlEnumerable_init();

        if (init.admin == address(0) || init.withdrawalManager == address(0)) {
            // only checking the admin and withdrawal manager here, since the other roles/settings can be granted/set by them
            revert InvalidConfiguration();
        }

        _setRoleAdmin(WITHDRAWAL_MANAGER_ROLE, WITHDRAWAL_MANAGER_ROLE);

        _setRoleAdmin(SIGNER_ROLE, MANAGER_ROLE);
        _setRoleAdmin(FUNDING_CONDUIT_ROLE, MANAGER_ROLE);
        _setRoleAdmin(PAUSER_ROLE, MANAGER_ROLE);
        _setRoleAdmin(PLATFORM_ROLE, MANAGER_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(MANAGER_ROLE, init.manager);
        _grantRole(PLATFORM_ROLE, init.platform);
        _grantRole(PAUSER_ROLE, init.platform);
        _grantRole(SIGNER_ROLE, init.signer);
        _grantRole(WITHDRAWAL_MANAGER_ROLE, init.withdrawalManager);

        for (uint256 i = 0; i < init.conduits.length; i++) {
            _grantRole(FUNDING_CONDUIT_ROLE, init.conduits[i]);
        }

        _validateWithdrawalSettings(init.withdrawalSettings);
        _withdrawalSettings = init.withdrawalSettings;
        dealUUID = init.dealUUID;
        integrationKey = init.integrationKey;
        funderIntegrationRegistry = init.funderIntegrationRegistry;
        isEnabled = true;

        _dealSettings = init.dealSettings;
        token = init.token;
    }

    /// @notice The amount funded by a given user.
    function amountFunded(address funder) public view returns (uint256) {
        (, uint256 amount) = _amountFundedByUser.tryGet(funder);
        return amount;
    }

    /// @notice The number of distinct funders of this deal.
    function numFunders() external view returns (uint256) {
        return _amountFundedByUser.length();
    }

    /// @notice The funder at a given index.
    /// @dev The index does not necessarily follow the order in which funders funded the deal.
    function funderAt(uint256 idx) external view returns (address, uint256) {
        return _amountFundedByUser.at(idx);
    }

    /// @notice The number of pools funded by a given user
    /// @dev Intended to be used to iterate pools using `amountFundedByFunderAndPoolAt`.
    function numPoolsFundedByFunder(address funder) external view returns (uint256) {
        return _amountFundedByFunderAndPool[funder].length();
    }

    /// @notice Returns the pool ID and the amount funded by a given user
    function amountFundedByFunderAndPoolAt(address funder, uint256 idx) external view returns (bytes16, uint256) {
        (bytes32 poolID, uint256 amount) = _amountFundedByFunderAndPool[funder].at(idx);
        return (bytes16(poolID), amount);
    }

    /// @notice Returns the amount funded by a given user to a certain pool.
    function amountFundedByFunderAndPool(address funder, bytes16 poolID) external view returns (uint256) {
        (, uint256 amount) = _amountFundedByFunderAndPool[funder].tryGet(poolID);
        return amount;
    }

    /// @notice The number of pools funded by all users.
    /// @dev Note that this is not necessarily the total number of pools, but only the ones that have been funded by users.
    /// @dev Intended to be used to iterate pools using `poolAt`.
    function numFundedPools() external view returns (uint256) {
        return _amountFundedByPool.length();
    }

    /// @notice The pool ID and the total amount funded by all users at a given index
    function poolAt(uint256 idx) external view returns (bytes16, uint256) {
        (bytes32 poolID, uint256 amount) = _amountFundedByPool.at(idx);
        return (bytes16(poolID), amount);
    }

    /// @notice The amount funded to a certain pool by all users.
    function amountFundedByPool(bytes16 poolID) external view returns (uint256) {
        (, uint256 amount) = _amountFundedByPool.tryGet(poolID);
        return amount;
    }

    /// @notice The number of distinct funders across deals with the same integration key.
    function numIntegratedFunders() public view returns (uint256) {
        return funderIntegrationRegistry.numTotal(integrationKey);
    }

    /// @notice The number of distinct US/Non-US funders across deals with the same integration key.
    function numIntegratedFundersInGroup(bool isUS) public view returns (uint256) {
        return funderIntegrationRegistry.numInGroup(integrationKey, _funderIntegrationGroup(isUS));
    }

    /// @notice The associated funder group for US/Non-US users in the integration registry.
    /// @dev US -> 1, Non-US -> 0
    function _funderIntegrationGroup(bool isUS) internal pure returns (uint256) {
        return isUS ? 1 : 0;
    }

    /// @notice Funds the deal on the user's behalf via a funding conduit.
    /// @dev The funding conduit is expected to hold the `amount` for the user when this function is called.
    /// @param user The user that is funding the deal.
    /// @param amount The amount to fund the deal with.
    /// @param fundingPermit The funding permit ensuring that a user is allowed to participate in the deal.
    /// @param signature The signature of the funding permit, issued by the platform.
    function fundFromConduit(
        address user,
        uint256 amount,
        DealSignatureLib.DealFundingPermit calldata fundingPermit,
        bytes calldata signature
    ) external onlyRole(FUNDING_CONDUIT_ROLE) {
        _fund(user, msg.sender, amount, fundingPermit, signature);
    }

    /// @notice Funds the deal for a given user with the amount taken from the fundsProvider.
    /// @param user The user that is funding the deal.
    /// @param fundsProvider The address from which the funds are pulled.
    /// @param amountRequested The amount requested to fund the deal with.
    /// @param fundingPermit The funding permit ensuring that a user is allowed to participate in the deal.
    /// @param signature The signature of the funding permit, issued by the platform.
    /// @dev The signature is checked against the SIGNER_ROLE.
    /// @dev The requested funding amount is iteratively attempted to be allocated to the pools available to the user.
    /// If there is any leftover amount at the end that could not be allocated to any pool it will be refunded to the user.
    function _fund(
        address user,
        address fundsProvider,
        uint256 amountRequested,
        DealSignatureLib.DealFundingPermit calldata fundingPermit,
        bytes calldata signature
    ) internal onlyIf(isEnabled) {
        FundingParameters calldata params = fundingPermit.fundingParameters;
        if (!isValidFundingParameters(params)) {
            revert InvalidFundingParameters();
        }

        if (block.timestamp < params.userSettings.opensAt || block.timestamp >= params.userSettings.closesAt) {
            revert Closed(params.userSettings.opensAt, params.userSettings.closesAt, block.timestamp);
        }

        if (block.timestamp >= fundingPermit.expireAt) {
            revert DealFundingPermitExpired(fundingPermit.expireAt);
        }

        if (user != fundingPermit.funder) {
            revert DealFundingPermitInvalidFunder(fundingPermit.funder);
        }

        if (dealUUID != fundingPermit.dealUUID) {
            revert DealFundingPermitInvalidDealUUID(fundingPermit.dealUUID);
        }

        // limiting the scope of `signer` to avoid stack-too-deep errors
        {
            address signer = DealSignatureLib.recoverSigner(fundingPermit, signature);
            if (!hasRole(SIGNER_ROLE, signer)) {
                revert UnauthorizedSigner(signer);
            }
        }

        if (amountRequested == 0) {
            revert ZeroAmountRequested();
        }

        // Attempt to put as much as possible into each pool in the order specified in the funding params.
        // e.g. if we have a pool that is 80k/100k filled and the user attempts to fund 30k, we'd put 20k into this on while 10k are expected to spill over to the next pools.
        // any remaining amount after all pools are exhausted will be returned to the user.

        uint256 unfilledAmount = amountRequested;
        for (uint256 i = 0; i < params.userSettings.poolFundingOrdering.length; i++) {
            bytes16 poolID = params.userSettings.poolFundingOrdering[i];
            (PoolSettings calldata pool, UserPoolSettings calldata userPool) = findSettings(poolID, params);

            uint256 userAmountAvailable = _computeUserAmountAvailableInPool(user, poolID, pool, userPool);
            uint256 poolFundingAmount = Math.min(unfilledAmount, userAmountAvailable);
            poolFundingAmount = _reducePoolFundingAmountOnMinRemaining(poolFundingAmount, poolID, pool);
            emit PoolFundingData(dealUUID, user, poolID, unfilledAmount, userAmountAvailable, poolFundingAmount);

            _trackPoolFunding(user, poolFundingAmount, poolID, pool, userPool);

            unfilledAmount -= poolFundingAmount;
            if (unfilledAmount == 0) {
                break;
            }
        }

        // having any funding amount left after trying to put it into all available pools means that the requested funding was larger than the space avaialbe to the user
        // if partial fillings are enabled, we return the leftover later. if not we revert.
        if (unfilledAmount > params.userSettings.maxPartialRequestFillingDifference) {
            revert MaxPartialRequestFillingDifferenceExceeded(unfilledAmount);
        }

        uint256 fundedAmount = amountRequested - unfilledAmount;
        if (fundedAmount == 0) {
            // We want to always fail for zero amounts, to avoid adding the sender to the funders set / integration registry
            // and invalidate any fundings on the backend
            revert ZeroAmountFunded();
        }

        // limiting the scope of local variables to avoid stack-too-deep errors
        {
            uint256 integrationGroup = _funderIntegrationGroup(fundingPermit.isUS);
            if (funderIntegrationRegistry.isRegistered(integrationKey, user)) {
                // if the user is already registered (e.g. from previous fundings or other deals), we check if the group on the permit matches the one in the registry
                uint256 regGroup = funderIntegrationRegistry.group(integrationKey, user);
                if (regGroup != integrationGroup) {
                    revert FunderRegisteredUnderDifferentGroup(user, regGroup, integrationGroup);
                }
            }

            // register the user if it is the first time they fund the deal
            // note: this is not equivalent to registering if they are not registered yet
            bool newUser = amountFunded(user) == 0;
            if (newUser) {
                funderIntegrationRegistry.register(integrationKey, user, integrationGroup);

                if (numIntegratedFundersInGroup(fundingPermit.isUS) > _maxNumUsers(fundingPermit.isUS)) {
                    revert MaxNumberOfFundersInGroupReached({isUS: fundingPermit.isUS});
                }
            }
        }

        uint256 newUserTotal = amountFunded(user) + fundedAmount;
        {
            // checking global user limit
            // i.e. their fundings across all pools have to be within the limits of the funding parameters
            uint256 currentUserTotal = amountFunded(user);
            if (newUserTotal < params.userSettings.minTotalAmount) {
                revert AmountLowerThanMinPerUserLimit(
                    params.userSettings.minTotalAmount, currentUserTotal, newUserTotal
                );
            }

            if (newUserTotal > params.userSettings.maxTotalAmount) {
                revert AmountGreaterThanMaxPerUserLimit(
                    params.userSettings.maxTotalAmount, currentUserTotal, newUserTotal
                );
            }
            _amountFundedByUser.set(user, newUserTotal);
        }

        {
            uint256 newDealTotal = totalFunded + fundedAmount;
            if (newDealTotal > params.allMembersAmount) {
                // this is not expected to happen if all pools sizes sum up to the total
                revert MaxTotalExceeded(params.allMembersAmount, totalFunded, newDealTotal);
            }
            totalFunded = newDealTotal;
        }

        if (unfilledAmount > 0) {
            emit PartialFundingAmountReturned(dealUUID, user, unfilledAmount);
            token.safeTransferFrom(fundsProvider, user, unfilledAmount);
        }

        emit DealFunded(dealUUID, user, fundedAmount, newUserTotal);
        token.safeTransferFrom(fundsProvider, address(this), fundedAmount);
    }

    /// @notice Computes the amount in a pool that is available to the given user.
    /// @dev This function is intended to be called as part of the funding process to determine how much of a user's funding request can be allocated to the given pool.
    function _computeUserAmountAvailableInPool(
        address user,
        bytes16 poolID,
        PoolSettings calldata pool,
        UserPoolSettings calldata userPoolSettings
    ) internal view returns (uint256) {
        (, uint256 currentUserAmountInPool) = _amountFundedByFunderAndPool[user].tryGet(poolID);
        // amount left in the pool based on the user's limit
        // using trySub to avoid underflows if the maxPerUserAmount was decreased after the user funded
        (, uint256 userAmountLeft) = Math.trySub(userPoolSettings.maxPerUserAmount, currentUserAmountInPool);

        (, uint256 poolTotal) = _amountFundedByPool.tryGet(poolID);
        // amount left based on the total pool limit
        (, uint256 totalAmountLeft) = Math.trySub(pool.maxTotalAmount, poolTotal);

        return Math.min(userAmountLeft, totalAmountLeft);
    }

    /// @notice Reduces the funding amount to a given pool iff the resulting remaining amount in that pool is lower than the minimum specified in the settings.
    /// @param poolFundingAmount the amount to fund to the given pool
    /// @param poolID the pool that we attempt to fund
    function _reducePoolFundingAmountOnMinRemaining(
        uint256 poolFundingAmount,
        bytes16 poolID,
        PoolSettings calldata poolSettings
    ) internal view returns (uint256) {
        (, uint256 currentPoolTotal) = _amountFundedByPool.tryGet(poolID);
        uint256 newPoolTotal = currentPoolTotal + poolFundingAmount;

        // the remaining amount in the pool has to either be zero (so that the pool is full)
        // or be larger than `minRemainingAmount` to allow other users to fill it.
        // if the remaining amount criterion would be broken with the requeste funding amount,
        // we reduce it such that exactly the minimum remaining amount is left.
        uint256 poolRemainingAfter = poolSettings.maxTotalAmount - newPoolTotal;
        if (poolRemainingAfter > 0 && poolRemainingAfter < poolSettings.minRemainingAmount) {
            poolFundingAmount -= poolSettings.minRemainingAmount - poolRemainingAfter;
        }

        return poolFundingAmount;
    }

    /// @notice Tracks fundings to individual pools in state
    /// @dev Updates user-specific and total pool balances
    function _trackPoolFunding(
        address user,
        uint256 amount,
        bytes16 poolID,
        PoolSettings calldata poolSettings,
        UserPoolSettings calldata userPoolSettings
    ) internal {
        if (amount == 0) {
            return;
        }

        (, uint256 currentUserAmountInPool) = _amountFundedByFunderAndPool[user].tryGet(poolID);

        (, uint256 currentPoolTotal) = _amountFundedByPool.tryGet(poolID);
        uint256 newPoolTotal = currentPoolTotal + amount;
        uint256 newUserTotalInPool = currentUserAmountInPool + amount;

        // these invariants are always expected to hold if `amount` was computed correctly
        assert(newPoolTotal <= poolSettings.maxTotalAmount);
        assert(newUserTotalInPool <= userPoolSettings.maxPerUserAmount);
        assert(
            newPoolTotal == poolSettings.maxTotalAmount
                || newPoolTotal <= poolSettings.maxTotalAmount - poolSettings.minRemainingAmount
        );

        _amountFundedByPool.set(poolID, newPoolTotal);
        _amountFundedByFunderAndPool[user].set(poolID, newUserTotalInPool);

        emit PoolFunded(dealUUID, user, poolID, amount);
    }

    /// @notice Refunds a funder from the given pools, e.g. if the deal could not be filled and was cancelled.
    /// @dev Partial refunds of the user's amount in a pool are allowed.
    /// @param funder The address of the funder to refund.
    /// @param poolRefunds The pools and amounts to refund the funder from.
    function refund(address funder, PoolRefund[] calldata poolRefunds)
        external
        onlyRole(PLATFORM_ROLE)
        onlyExistingFunder(funder)
    {
        _refund(funder, poolRefunds);
    }

    /// @notice Refunds a funder from the given pools, e.g. if the deal could not be filled and was cancelled.
    /// @dev see notes above.
    function _refund(address funder, PoolRefund[] calldata poolRefunds) internal {
        uint256 totalRefundAmount = 0;
        for (uint256 i = 0; i < poolRefunds.length; i++) {
            PoolRefund calldata poolRefund = poolRefunds[i];
            totalRefundAmount += poolRefunds[i].amount;
            _processPoolRefund(funder, poolRefund.poolID, poolRefund.amount);
        }

        // using tryGet to avoid reverting if the user has no funds left
        (, uint256 newUserTotal) = _amountFundedByUser.tryGet(funder);
        if (newUserTotal == 0) {
            funderIntegrationRegistry.deregister(integrationKey, funder);
        }

        emit DealRefunded(dealUUID, funder, totalRefundAmount, newUserTotal);
        token.safeTransfer(funder, totalRefundAmount);
    }

    /// @notice Processes the refund from a pool.
    /// @dev Updates the contract state only, actually sending the funds and running side-effects is done one level higher in `_refund`.
    function _processPoolRefund(address funder, bytes16 poolID, uint256 refundAmount) internal {
        (, uint256 currentUserAmountInPool) = _amountFundedByFunderAndPool[funder].tryGet(poolID);
        if (refundAmount > currentUserAmountInPool) {
            revert PoolRefundExceedsFunding(funder, poolID, currentUserAmountInPool);
        }

        uint256 newUserAmountInPool = currentUserAmountInPool - refundAmount;
        if (newUserAmountInPool > 0) {
            _amountFundedByFunderAndPool[funder].set(poolID, newUserAmountInPool);
        } else {
            // removing instead of setting to zero to reset the enumerable map, so the state is exactly as if they had never funded
            _amountFundedByFunderAndPool[funder].remove(poolID);
        }

        (, uint256 currentPoolTotal) = _amountFundedByPool.tryGet(poolID);
        uint256 newPoolTotal = currentPoolTotal - refundAmount;
        if (newPoolTotal > 0) {
            _amountFundedByPool.set(poolID, newPoolTotal);
        } else {
            // removing instead of setting to zero to reset the enumerable map, so the state is exactly as if they had never funded
            _amountFundedByPool.remove(poolID);
        }

        uint256 newUserTotal = _amountFundedByUser.get(funder) - refundAmount;
        if (newUserTotal > 0) {
            _amountFundedByUser.set(funder, newUserTotal);
        } else {
            // removing instead of setting to zero to reset the enumerable map, so the state is exactly as if they had never funded
            _amountFundedByUser.remove(funder);
        }
        totalFunded -= refundAmount;

        emit PoolRefunded(dealUUID, funder, poolID, refundAmount);
    }

    /// @notice The maximum number of US/Non-US users that can fund the deal.
    /// @dev Given by the funding params.
    function _maxNumUsers(bool isUS) internal view returns (uint256) {
        return isUS ? _dealSettings.maxNumUsersUS : _dealSettings.maxNumUsersNonUS;
    }

    /// @notice Checks if the withdrawal settings are valid, reverts otherwise.
    function _validateWithdrawalSettings(WithdrawalSettings calldata settings) internal view {
        if (settings.feesReceiver == address(0)) {
            revert InvalidConfiguration();
        }

        if (settings.fundsReceiver == address(0)) {
            revert InvalidConfiguration();
        }

        if (settings.maxFeesAmount < feesAmountWithdrawn) {
            revert InvalidConfiguration();
        }
    }

    /// @notice Sets the withdrawal settings.
    /// @dev This is only callable by the withdrawal manager.
    function setWithdrawalSettings(WithdrawalSettings calldata settings) external onlyRole(WITHDRAWAL_MANAGER_ROLE) {
        _validateWithdrawalSettings(settings);
        _withdrawalSettings = settings;
        emit ConfigChanged(this.setWithdrawalSettings.selector, SET_WITHDRAWAL_SETTINGS_SIGNATURE, abi.encode(settings));
    }

    /// @notice Returns the withdrawal settings.
    function withdrawalSettings() external view returns (WithdrawalSettings memory) {
        return _withdrawalSettings;
    }

    /// @notice Withdraws tokens from the contract according to the withdrawal settings.
    /// @dev Fees are withdrawn first to the fees receiver, then any remaining amount is sent to the funds receiver.
    /// @dev The withdrawn amount of fees is tracked, so calling this function multiple times will not withdraw fees multiple times.
    /// @param feesAmount The amount of fees to withdraw to the fees receiver in total. Cannot exceed the max fees amount set in the withdrawal settings.
    function withdraw(uint256 feesAmount) external onlyRole(PLATFORM_ROLE) {
        WithdrawalSettings memory settings = _withdrawalSettings;
        if (feesAmount > settings.maxFeesAmount) {
            revert ExceedsMaxFeesAmount(feesAmount, settings.maxFeesAmount);
        }

        if (feesAmount > feesAmountWithdrawn) {
            uint256 amount = feesAmount - feesAmountWithdrawn;
            amount = Math.min(amount, token.balanceOf(address(this)));

            feesAmountWithdrawn += amount;
            _withdraw(token, settings.feesReceiver, amount);
        }

        uint256 remainingAmount = token.balanceOf(address(this));
        if (remainingAmount > 0) {
            _withdraw(token, settings.fundsReceiver, remainingAmount);
        }
    }

    /// @notice Withdraws tokens from the contract to a given address.
    function _withdraw(IERC20 coin, address to, uint256 amount) internal {
        emit DealFundsWithdrawn(coin, to, amount);
        coin.safeTransfer(to, amount);
    }

    /// @notice Allows the withdrawal manager to recover any tokens sent to the contract.
    /// @dev This is intended as a safeguard and should only be used in emergencies and with utmost care.
    function recoverTokens(IERC20 coin, address to, uint256 amount) external onlyRole(WITHDRAWAL_MANAGER_ROLE) {
        _withdraw(coin, to, amount);
    }

    /// @notice Sets the deal settings.
    /// @dev This is intended to be called by the platform whenever deal settings are changed on the backend after deploying the deal.
    function setDealSettings(DealSettings calldata settings) external onlyRole(PLATFORM_ROLE) {
        _dealSettings = settings;
        emit ConfigChanged(this.setDealSettings.selector, SET_DEAL_SETTINGS_SIGNATURE, abi.encode(settings));
    }

    /// @notice Returns the deal settings.
    function dealSettings() external view returns (DealSettings memory) {
        return _dealSettings;
    }

    /// @notice Sets the token used for funding the deal.
    function setToken(IERC20 newToken) external onlyRole(MANAGER_ROLE) {
        token = newToken;
        emit ConfigChanged(this.setToken.selector, "setToken(address)", abi.encode(newToken));
    }

    /// @notice Sets whether the deal funding is enabled.
    function _setEnabled(bool isEnabled_) internal {
        isEnabled = isEnabled_;
        emit ConfigChanged(this.setEnabled.selector, "setEnabled(bool)", abi.encode(isEnabled_));
    }

    /// @notice Sets whether the deal funding is enabled.
    function setEnabled(bool isEnabled_) external onlyRole(MANAGER_ROLE) {
        _setEnabled(isEnabled_);
    }

    /// @notice Pauses the deal funding.
    /// @dev Equivalent to `setEnabled(false)`.
    function pause() external onlyRole(PAUSER_ROLE) {
        _setEnabled(false);
    }

    /// @notice Ensures that a function can only be called if a given flag is true.
    modifier onlyIf(bool flag) {
        if (!flag) {
            revert Disabled();
        }
        _;
    }

    /// @notice Ensures that a function can only be called by an existing deal funder.
    modifier onlyExistingFunder(address funder) {
        if (!_amountFundedByUser.contains(funder)) {
            revert NotFunder(funder);
        }
        _;
    }
}
