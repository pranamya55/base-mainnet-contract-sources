// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IFunderIntegrationRegistry} from "./interfaces/IFunderIntegrationRegistry.sol";
import {ConfigChanged} from "./interfaces/PlatformEvents.sol";
import {
    FundingSettings, FUNDING_SETTINGS_SIGNATURE, WithdrawalSettings, WITHDRAWAL_SETTINGS_SIGNATURE
} from "./Types.sol";

/// @notice A library to deal with deal funding permits.
library DealSignatureLib {
    struct DealFundingPermit {
        address funder;
        bool isUS;
        bytes16 dealUUID;
        uint256 expireAt;
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

/// @dev Precomputing the signature of the Deal.setFundingSettings function for convenience since structs are ABI encoded as tuples.
string constant SET_FUNDING_SETTINGS_SIGNATURE =
    string(abi.encodePacked("setFundingSettings(", FUNDING_SETTINGS_SIGNATURE, ")"));

/// @dev Precomputing the signature of the Deal.setWithdrawalSettings function for convenience since structs are ABI encoded as tuples.
string constant SET_WITHDRAWAL_SETTINGS_SIGNATURE =
    string(abi.encodePacked("setWithdrawalSettings(", WITHDRAWAL_SETTINGS_SIGNATURE, ")"));

/// @title Deal
/// @notice A contract that allows users to fund a deal.
contract Deal is Initializable, AccessControlEnumerableUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /// @notice The role allowed to manage the deal (e.g. the platform provider, or deal lead)
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The role allowed to sign funding permits.
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    /// @notice The role allowed to refund users.
    bytes32 public constant REFUNDER_ROLE = keccak256("REFUNDER_ROLE");

    /// @notice The role allowed to execute funding transactions on the user's behalf.
    bytes32 public constant FUNDING_CONDUIT_ROLE = keccak256("FUNDING_CONDUIT_ROLE");

    /// @notice The role allowed to fund the deal lead's allocation
    bytes32 public constant DEAL_LEAD_FUNDER_ROLE = keccak256("DEAL_LEAD_FUNDER_ROLE");

    /// @notice The role allowed to pause the deal funding
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The role allowed to trigger withdrawals from the deal
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /// @notice The role allowed to change the withdrawal settings
    bytes32 public constant WITHDRAWAL_MANAGER_ROLE = keccak256("WITHDRAWAL_MANAGER_ROLE");

    error UnauthorizedSigner(address signer);
    error InvalidConfiguration();
    error ZeroAmount();
    error AmountLowerThanMinPerUserLimit(uint256 bound);
    error AmountGreaterThanMaxPerUserLimit(uint256 bound, uint256 used);
    error Unauthorized();
    error MaxNumberOfFundersInGroupReached(bool isUS);
    error MaxTotalExceeded();
    error Closed();
    error DealFundingPermitInvalidFunder(address funderOnPermit);
    error DealFundingPermitInvalidDealUUID(bytes16 dealUUIDOnPermit);
    error DealFundingPermitExpired(uint256 expiredAt);
    error RemainingAmountTooSmall(uint256 remainingAmount);
    error FunderRegisteredUnderDifferentGroup(address funder, uint256 existing, uint256 permitGroup);
    error ExceedingDealLeadAllocation(uint256 current, uint256 max, uint256 amount);
    error Disabled();
    error NotFunder(address);
    error RefundAmountGreaterThanFunded(address funder, uint256 fundedAmount, uint256 refundAmount);

    /// @notice Emitted when a deal is funded.
    event DealFunded(bytes16 indexed dealUUID, address indexed funder, uint256 amount, uint256 newFunderTotal);

    /// @notice Emitted when a user is refunded.
    event DealRefunded(bytes16 indexed dealUUID, address indexed funder, uint256 amount, uint256 newFunderTotal);

    /// @notice Emitted when the manager withdraws tokens.
    event DealFundsWithdrawn(IERC20 indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when the deal lead funds the deal
    event DealLeadFunded(bytes16 indexed dealUUID, address indexed from, uint256 amount);

    /// @notice Emitted when the deal lead is refunded
    event DealLeadRefunded(bytes16 indexed dealUUID, address indexed to, uint256 amount);

    /// @notice Flag to enable/disable the deal funding.
    bool public isEnabled;

    /// @notice Flag to enable/disable the self-refund feature.
    bool public isSelfRefundEnabled;

    /// @notice The UUID of the deal.
    /// @dev This is specified on deal creation and is immutable. Matches the UUID on the backend.
    bytes16 public dealUUID;

    /// @notice The amount funded by the deal lead.
    uint256 public dealLeadFunded;

    /// @notice The total amount funded by users.
    uint256 public totalFunded;

    /// @notice The funding settings for the deal.
    FundingSettings internal _fundingSettings;

    /// @notice The funders of the deal.
    EnumerableMap.AddressToUintMap internal _funders;

    /// @notice The funder integration registry to track US/NonUS-based investors across deal contracts.
    IFunderIntegrationRegistry public funderIntegrationRegistry;

    /// @notice The shared key to track investors in the integration registry.
    bytes32 public integrationKey;

    /// @notice Specifies the receipients and amounts for the withdrawal of deal funds.
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
        address signer;
        address[] conduits;
        FundingSettings fundingSettings;
        WithdrawalSettings withdrawalSettings;
        address withdrawer;
        address withdrawalManager;
        address[] dealLeadFunders;
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
        _setRoleAdmin(DEAL_LEAD_FUNDER_ROLE, MANAGER_ROLE);
        _setRoleAdmin(REFUNDER_ROLE, MANAGER_ROLE);
        _setRoleAdmin(PAUSER_ROLE, MANAGER_ROLE);
        _setRoleAdmin(WITHDRAWER_ROLE, MANAGER_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(MANAGER_ROLE, init.manager);
        _grantRole(SIGNER_ROLE, init.signer);
        _grantRole(WITHDRAWER_ROLE, init.withdrawer);
        _grantRole(WITHDRAWAL_MANAGER_ROLE, init.withdrawalManager);

        for (uint256 i = 0; i < init.conduits.length; i++) {
            _grantRole(FUNDING_CONDUIT_ROLE, init.conduits[i]);
        }

        for (uint256 i = 0; i < init.dealLeadFunders.length; i++) {
            _grantRole(DEAL_LEAD_FUNDER_ROLE, init.dealLeadFunders[i]);
        }

        _validateFundingSettings(init.fundingSettings);
        _validateWithdrawalSettings(init.withdrawalSettings);
        _fundingSettings = init.fundingSettings;
        _withdrawalSettings = init.withdrawalSettings;
        dealUUID = init.dealUUID;
        integrationKey = init.integrationKey;
        funderIntegrationRegistry = init.funderIntegrationRegistry;
        isEnabled = true;
    }

    /// @notice The funding settings for the deal.
    function fundingSettings() public view returns (FundingSettings memory) {
        return _fundingSettings;
    }

    /// @notice The amount funded by a given user.
    function amountFunded(address funder) public view returns (uint256) {
        (, uint256 amount) = _funders.tryGet(funder);
        return amount;
    }

    /// @notice The number of distinct funders of this deal.
    function numFunders() external view returns (uint256) {
        return _funders.length();
    }

    /// @notice The funder at a given index.
    /// @dev The index does not necessarily follow the order in which funders funded the deal.
    function funderAt(uint256 idx) external view returns (address, uint256) {
        return _funders.at(idx);
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
    /// @param amount The amount to fund the deal with.
    /// @param fundingPermit The funding permit ensuring that a user is allowed to participate in the deal.
    /// @param signature The signature of the funding permit, issued by the platform.
    /// @dev The signature is checked against the SIGNER_ROLE.
    /// @dev The `amount` is bounded. The lower bound for new funders is given by `minPerNewUserFundingAmount`. Existing funders can send arbitrary amounts up to `maxPerUserFundingAmount`.
    /// The upper bound for all users is given by `maxPerUserFundingAmount - amountFunded` and the criterion that the remaining fundable amount has to either be zero (i.e. the deal is full) or larger than `minPerUserAmount` (i.e. that another users can still fill it).
    function _fund(
        address user,
        address fundsProvider,
        uint256 amount,
        DealSignatureLib.DealFundingPermit calldata fundingPermit,
        bytes calldata signature
    ) internal onlyIf(isEnabled) {
        FundingSettings memory settings = _fundingSettings;

        // checking the total limits first to fail early in race conditions
        if (numIntegratedFundersInGroup(fundingPermit.isUS) == _maxNumUsers(fundingPermit.isUS)) {
            revert MaxNumberOfFundersInGroupReached({isUS: fundingPermit.isUS});
        }

        if (totalFunded + amount > settings.totalUserFundingAmount) {
            revert MaxTotalExceeded();
        }

        if (block.timestamp < settings.opensAt || block.timestamp >= settings.closesAt) {
            revert Closed();
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

        if (amount == 0) {
            // We want to always fail for zero amounts, even if it is allowed by minPerUserAmount, to avoid adding the sender to the funders set
            revert ZeroAmount();
        }

        uint256 funderGroup = _funderIntegrationGroup(fundingPermit.isUS);
        if (funderIntegrationRegistry.isRegistered(integrationKey, user)) {
            // if the user is already registered (e.g. from previous fundings or other deals), we need to check if the group on the permit matches the one in the registry
            uint256 regGroup = funderIntegrationRegistry.group(integrationKey, user);
            if (regGroup != funderGroup) {
                revert FunderRegisteredUnderDifferentGroup(user, regGroup, funderGroup);
            }
        }

        uint256 currentUserAmount = amountFunded(user);
        bool newUser = currentUserAmount == 0;
        // Ensures that new users fund at least `minPerNewUserFundingAmount`
        // For existing funders this will always pass since `minPerNewUserFundingAmount` can only decrease as the deal is filled
        if (newUser && amount < minPerNewUserFundingAmount(fundingPermit.isUS)) {
            revert AmountLowerThanMinPerUserLimit(minPerNewUserFundingAmount(fundingPermit.isUS));
        }

        uint256 updatedUserAmount = currentUserAmount + amount;
        if (updatedUserAmount > settings.maxPerUserFundingAmount) {
            revert AmountGreaterThanMaxPerUserLimit(settings.maxPerUserFundingAmount, currentUserAmount);
        }

        // the remaining amount has to either be zero (so that the deal is full) or be larger than `minPerUserAmount` to allow other users to fill it.
        uint256 remainingAfter = settings.totalUserFundingAmount - totalFunded - amount;
        if (remainingAfter != 0 && remainingAfter < _staticMinPerUserFundingAmount(fundingPermit.isUS)) {
            revert RemainingAmountTooSmall(remainingAfter);
        }

        _funders.set(user, updatedUserAmount);
        totalFunded += amount;
        emit DealFunded(dealUUID, user, amount, updatedUserAmount);

        if (newUser) {
            // only register the user if it is the first time they fund the deal
            funderIntegrationRegistry.register(integrationKey, user, funderGroup);
        }

        settings.token.safeTransferFrom(fundsProvider, address(this), amount);
    }

    /// @notice Refunds a given funder, e.g. if the deal could not be filled and was cancelled, or if the allocation was changed.
    /// @dev The state of the the deal after refunding is equivalent to the funder funding the remaining amount in the first place.
    function refund(address funder, uint256 refundAmount) external onlyRole(REFUNDER_ROLE) onlyExistingFunder(funder) {
        _refund(funder, refundAmount);
    }

    /// @notice Refunds the sender's funding amount.
    /// @dev The state of the the deal after refunding is equivalent to the funder never participating in the first place.
    function selfRefund() external onlyExistingFunder(msg.sender) onlyIf(isSelfRefundEnabled) {
        uint256 fundedAmount = _funders.get(msg.sender);
        _refund(msg.sender, fundedAmount);
    }

    function _refund(address funder, uint256 refundAmount) internal {
        // reverts if `funder` is not a funder
        uint256 fundedAmount = _funders.get(funder);
        if (refundAmount > fundedAmount) {
            revert RefundAmountGreaterThanFunded(funder, fundedAmount, refundAmount);
        }
        totalFunded -= refundAmount;

        uint256 newAmount = fundedAmount - refundAmount;
        if (newAmount > 0) {
            _funders.set(funder, newAmount);
        } else {
            _funders.remove(funder);
            funderIntegrationRegistry.deregister(integrationKey, funder);
        }

        emit DealRefunded(dealUUID, funder, refundAmount, newAmount);
        _fundingSettings.token.safeTransfer(funder, refundAmount);
    }

    /// @notice The minimum amount that a new user can fund the deal with.
    /// @dev The value is given by the `_dynamicMinPerNewUserFundingAmount` function and is capped by the `minPerUserAmount` field of the funding settings.
    /// @dev The value can only become smaller or remain constant as the deal is filled.
    function minPerNewUserFundingAmount(bool isUS) public view returns (uint256) {
        uint256 staticMin = _staticMinPerUserFundingAmount(isUS);
        if (!_fundingSettings.usesDynamicFundingMinimum) {
            return staticMin;
        }

        uint256 dynMin = _dynamicMinPerNewUserFundingAmount(isUS);
        return staticMin > dynMin ? staticMin : dynMin;
    }

    /// @notice The dynamic minimum amount that a new user can fund the deal with, computed from the remaining amount over the remaining user slots.
    /// @dev The value can only become smaller or remain constant as the deal is filled.
    function _dynamicMinPerNewUserFundingAmount(bool isUS) internal view returns (uint256) {
        uint256 remainingSlots = _maxNumUsers(isUS) - numIntegratedFundersInGroup(isUS);
        if (remainingSlots == 0) {
            return 0;
        }

        uint256 remainingAmount = _fundingSettings.totalUserFundingAmount - totalFunded;
        return remainingAmount / remainingSlots;
    }

    /// @notice The maximum number of US/Non-US users that can fund the deal.
    /// @dev Given by the funding settings.
    function _maxNumUsers(bool isUS) internal view returns (uint256) {
        return isUS ? _fundingSettings.maxNumUsersUS : _fundingSettings.maxNumUsersNonUS;
    }

    /// @notice The static minimum amount that a new US/Non-US user can fund the deal with
    /// @dev Given by the funding settings.
    function _staticMinPerUserFundingAmount(bool isUS) internal view returns (uint256) {
        return isUS ? _fundingSettings.minPerUserFundingAmountUS : _fundingSettings.minPerUserFundingAmountNonUS;
    }

    /// @notice Validates the funding settings.
    function _validateFundingSettings(FundingSettings calldata settings) internal pure {
        if (settings.minPerUserFundingAmountUS > settings.maxPerUserFundingAmount) {
            revert InvalidConfiguration();
        }

        if (settings.minPerUserFundingAmountNonUS > settings.maxPerUserFundingAmount) {
            revert InvalidConfiguration();
        }

        if (settings.opensAt > settings.closesAt) {
            revert InvalidConfiguration();
        }
    }

    /// @notice Sets the funding settings.
    function setFundingSettings(FundingSettings calldata settings) public onlyRole(MANAGER_ROLE) {
        _validateFundingSettings(settings);
        _fundingSettings = settings;
        emit ConfigChanged(this.setFundingSettings.selector, SET_FUNDING_SETTINGS_SIGNATURE, abi.encode(settings));
    }

    /// @notice Sets the deal lead funder addresses.
    /// @param dealLeadFunders The addresses of the deal lead funders.
    /// @param replaceAll Whether to replace all existing deal lead funders with the new set.
    function setDealLeadFunders(address[] calldata dealLeadFunders, bool replaceAll)
        external
        onlyRole(getRoleAdmin(DEAL_LEAD_FUNDER_ROLE))
    {
        if (replaceAll) {
            uint256 memberCount = getRoleMemberCount(DEAL_LEAD_FUNDER_ROLE);
            for (uint256 i = 0; i < memberCount; i++) {
                address member = getRoleMember(DEAL_LEAD_FUNDER_ROLE, 0);
                _revokeRole(DEAL_LEAD_FUNDER_ROLE, member);
            }
        }

        for (uint256 i = 0; i < dealLeadFunders.length; i++) {
            if (dealLeadFunders[i] == address(0)) {
                revert InvalidConfiguration();
            }
            _grantRole(DEAL_LEAD_FUNDER_ROLE, dealLeadFunders[i]);
        }

        emit ConfigChanged(
            this.setDealLeadFunders.selector,
            "setDealLeadFunders(address[],bool)",
            abi.encode(dealLeadFunders, replaceAll)
        );
    }

    /// @notice Checks if the withdrawal settings are valid, reverts otherwise.
    function _validateWithdrawalSettings(WithdrawalSettings calldata settings) internal view {
        if (settings.feesReceiver == address(0)) {
            revert InvalidConfiguration();
        }

        if (settings.fundsReceiver == address(0)) {
            revert InvalidConfiguration();
        }

        if (settings.feesAmount < feesAmountWithdrawn) {
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
    /// @dev Fees are withdrawn first, then the remaining amount.
    /// @dev The withdrawn amount of fees is tracked, so calling this function multiple times will not withdraw fees multiple times.
    function withdraw() external onlyRole(WITHDRAWER_ROLE) {
        IERC20 token = _fundingSettings.token;
        WithdrawalSettings memory settings = _withdrawalSettings;

        if (settings.feesAmount > feesAmountWithdrawn) {
            uint256 amount = settings.feesAmount - feesAmountWithdrawn;
            feesAmountWithdrawn += amount;
            _withdraw(token, settings.feesReceiver, amount);
        }

        uint256 remainingAmount = token.balanceOf(address(this));
        if (remainingAmount > 0) {
            _withdraw(token, settings.fundsReceiver, remainingAmount);
        }
    }

    /// @notice Withdraws tokens from the contract to a given address.
    function _withdraw(IERC20 token, address to, uint256 amount) internal {
        emit DealFundsWithdrawn(token, to, amount);
        token.safeTransfer(to, amount);
    }

    /// @notice Allows the deal lead to fund the deal
    /// @dev The deal lead contribution is not counted towards the deal size
    function fundDealLead(uint256 amount) external onlyRole(DEAL_LEAD_FUNDER_ROLE) onlyIf(isEnabled) {
        if (dealLeadFunded + amount > _fundingSettings.dealLeadFundingAmount) {
            revert ExceedingDealLeadAllocation(dealLeadFunded, _fundingSettings.dealLeadFundingAmount, amount);
        }

        dealLeadFunded += amount;
        emit DealLeadFunded(dealUUID, msg.sender, amount);
        _fundingSettings.token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Allows the platform to (partially) refund the deal lead's allocation
    /// @dev Indended to be used if the deal is cancelled
    function refundDealLead(address to, uint256 amount) external onlyRole(MANAGER_ROLE) {
        dealLeadFunded -= amount;
        emit DealLeadRefunded(dealUUID, to, amount);
        _fundingSettings.token.safeTransfer(to, amount);
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

    /// @notice Sets whether the self-refund feature is enabled.
    function setSelfRefundEnabled(bool enabled) external onlyRole(MANAGER_ROLE) {
        isSelfRefundEnabled = enabled;
        emit ConfigChanged(this.setSelfRefundEnabled.selector, "setSelfRefundEnabled(bool)", abi.encode(enabled));
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
        if (!_funders.contains(funder)) {
            revert NotFunder(funder);
        }
        _;
    }
}
