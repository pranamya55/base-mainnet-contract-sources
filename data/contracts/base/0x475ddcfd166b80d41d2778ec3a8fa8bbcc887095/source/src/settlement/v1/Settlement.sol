// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ConfigChanged} from "echo/interfaces/PlatformEvents.sol";
import {Versioned} from "echo/Versioned.sol";

import {UserSettlement} from "./Types.sol";
import {WithdrawalSettings} from "echo/deal/v2/Types.sol";
import {DealSignatureLib} from "echo/deal/v2/Deal.sol";

/// @title IDeal
/// @notice A partial interface for the deal contract.
interface IDeal {
    /// @notice Returns the token used for funding the deal.
    function token() external view returns (IERC20);

    /// @notice Returns the deal UUID.
    function dealUUID() external view returns (bytes16);

    /// @notice Returns the withdrawal settings.
    function withdrawalSettings() external view returns (WithdrawalSettings memory);

    /// @notice Funds a pool from a conduit.
    function fundFromConduit(
        address user,
        uint256 amount,
        DealSignatureLib.DealFundingPermit calldata fundingPermit,
        bytes calldata fundingPermitSignature
    ) external;
}

/// @title Settlement
/// @notice A contract that allows users to commit to funding a deal, where settlement is done at a later time
/// by the echo platform.
/// @dev This contract is designed to act as another implementation of the `ERC20FundingConduit` contract.
contract Settlement is Initializable, AccessControlEnumerableUpgradeable, Versioned(1, 0, 0) {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    error Disabled();
    error InvalidConfiguration();
    error InvalidSettlementAmount(uint256 pendingAmount, uint256 selectedAmount, uint256 rejectedAmount);
    error InvalidDealContract();
    error InvalidAmount();

    /// @notice The role allowed to manage sensitive, administrative aspects of the settlement, but not touch anything funds related.
    /// @dev This role is managed by the `DEFAULT_ADMIN_ROLE` which will be granted to the ENG multisig.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The role allowed manage less sensitive aspects of the settlement.
    /// @dev This role will be granted to the platform backend.
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");

    /// @notice The role allowed to execute the users commitment transactions.
    bytes32 public constant TX_SENDER_ROLE = keccak256("TX_SENDER_ROLE");

    /// @notice The role allowed to pause the contract.
    /// @dev Keeping this deliberately separate from the `PLATFORM_ROLE` since we might want to grant this to some external monitoring in the future
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The role allowed to change the withdrawal settings (the destination of funds) and recover funds in an emergency.
    /// @dev This role is its own admin, and therefore outside the usual role hierarchy.
    /// @dev This role will be granted to the IM multisig.
    bytes32 public constant WITHDRAWAL_MANAGER_ROLE = keccak256("WITHDRAWAL_MANAGER_ROLE");

    /// @notice Emitted when a user sends a commitment.
    event Commitment(address indexed user, uint256 amount, uint256 newCommitmentTotal);

    /// @notice Emitted when a user commitment is settled.
    event Settled(address indexed user, uint256 selectedAmount, uint256 rejectedAmount);

    /// @notice Emitted when all tokens are recovered from the contract.
    event TokensRecovered(IERC20 coin, address to, uint256 amount);

    /// @notice Mapping of user addresses to their pending commitment amounts
    EnumerableMap.AddressToUintMap private _pendingCommitmentByWallet;

    /// @notice Mapping of user addresses to their commitment amounts
    EnumerableMap.AddressToUintMap private _commitmentByWallet;

    /// @notice The total amount of unsettled commitments.
    /// @dev Allows us to determine when all commitments have been settled.
    uint256 public totalPendingCommitments;

    /// @notice The token used for funding the deal.
    IERC20 public token;

    /// @notice The deal contract that this settlement contract is associated with.
    address public dealContract;

    /// @notice Whether the contract is enabled.
    bool public isEnabled;

    constructor() {
        _disableInitializers();
    }

    struct Init {
        address admin;
        address manager;
        address platform;
        address txSender;
        address withdrawalManager;
        IERC20 token;
    }

    function initialize(Init memory init) public initializer {
        __AccessControlEnumerable_init();

        if (init.admin == address(0) || init.withdrawalManager == address(0)) {
            // only checking the admin and withdrawal manager here, since the other roles/settings can be granted/set by them
            revert InvalidConfiguration();
        }

        _setRoleAdmin(WITHDRAWAL_MANAGER_ROLE, WITHDRAWAL_MANAGER_ROLE);

        _setRoleAdmin(PAUSER_ROLE, MANAGER_ROLE);
        _setRoleAdmin(PLATFORM_ROLE, MANAGER_ROLE);
        _setRoleAdmin(TX_SENDER_ROLE, MANAGER_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(MANAGER_ROLE, init.manager);
        _grantRole(PLATFORM_ROLE, init.platform);
        _grantRole(PAUSER_ROLE, init.platform);
        _grantRole(TX_SENDER_ROLE, init.txSender);
        _grantRole(WITHDRAWAL_MANAGER_ROLE, init.withdrawalManager);

        isEnabled = true;
        token = init.token;
    }

    /// @notice Get the pending commitment amount for a user
    function pendingCommitmentByWallet(address user) public view returns (uint256) {
        (, uint256 value) = _pendingCommitmentByWallet.tryGet(user);
        return value;
    }

    /// @notice Get the pending commitment amount for a user at a given index
    function pendingCommitmentAt(uint256 index) public view returns (address, uint256) {
        return _pendingCommitmentByWallet.at(index);
    }

    /// @notice Get the total number of pending commitments
    function pendingCommitmentCount() public view returns (uint256) {
        return _pendingCommitmentByWallet.length();
    }

    /// @notice Get the commitment amount for a user
    function commitmentByWallet(address user) public view returns (uint256) {
        (, uint256 value) = _commitmentByWallet.tryGet(user);
        return value;
    }

    /// @notice Get the commitment amount for a user at a given index
    function commitmentAt(uint256 index) public view returns (address, uint256) {
        return _commitmentByWallet.at(index);
    }

    /// @notice Get the total number of commitments
    function commitmentCount() public view returns (uint256) {
        return _commitmentByWallet.length();
    }

    /// @notice Commit funds to the deal using a permit.
    /// @param user The user to commit funds for.
    /// @param amount The amount to commit.
    /// @param deadline The deadline for the permit.
    /// @param v The v component of the permit signature.
    /// @param r The r component of the permit signature.
    /// @param s The s component of the permit signature.
    function commitUsingPermit(address user, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        onlyRole(TX_SENDER_ROLE)
    {
        // Use the permit to approve this contract to spend tokens on behalf of the user.
        IERC20Permit(address(token)).permit(user, address(this), amount, deadline, v, r, s);
        _commit(user, amount);
    }

    /// @notice Accepts a user's commitment. The user must have already approved the settlement contract to spend the amount.
    /// @dev Our validation of the commitment relies on this function being gated by the `TX_SENDER_ROLE`.
    /// We may choose to add a user signable permit here in the future if we want to allow direct funding from user wallets.
    function commitUsingApproval(address user, uint256 amount) external onlyRole(TX_SENDER_ROLE) {
        _commit(user, amount);
    }

    /// @notice Internal function to handle the common commitment logic.
    /// @param user The user to commit funds for.
    /// @param amount The amount to commit.
    function _commit(address user, uint256 amount) internal {
        if (!isEnabled) {
            revert Disabled();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        // Update the pending commitment amount for the user.
        uint256 currentPending = pendingCommitmentByWallet(user);
        _pendingCommitmentByWallet.set(user, currentPending + amount);
        totalPendingCommitments += amount;

        // Update the total commitment amount for the user.
        uint256 currentCommitment = commitmentByWallet(user);
        _commitmentByWallet.set(user, currentCommitment + amount);

        emit Commitment(user, amount, currentCommitment + amount);

        // Transfer tokens from the user to this contract.
        token.safeTransferFrom(user, address(this), amount);
    }

    /// @notice Settles selected commitments to a pool on the deal and returns unselected funds to the users.
    /// @dev This function must be gated by the `PLATFORM_ROLE` to ensure that only the platform can settle commitments.
    /// Each UserSettlement contains a funding permit which is used to settle the commitment to the deal. The data on the funding
    /// permit must be valid from the perspective of the deal, but not all fields may be relevant for the settlement process.
    /// This function must be called in batches, as it is too large to fit in a single call.
    /// NOTE: A failure for any single user settlement will revert the entire transaction, as this indicates an issue with the backend settlement process.
    function settle(bytes16 dealUUID, UserSettlement[] calldata userSettlements) external onlyRole(PLATFORM_ROLE) {
        if (!isEnabled) {
            revert Disabled();
        }

        // Ensure that we're calling a deal which matches the expected deal.
        IDeal deal = IDeal(dealContract);
        if (dealUUID != deal.dealUUID()) {
            revert InvalidDealContract();
        }
        // Ensure that the deal has a valid withdrawal settings so we don't blackhole funds.
        WithdrawalSettings memory withdrawalSettings = deal.withdrawalSettings();
        if (withdrawalSettings.fundsReceiver == address(0)) {
            revert InvalidDealContract();
        }
        // Ensure that the deal is using the same token as the settlement contract.
        if (address(deal.token()) != address(token)) {
            revert InvalidDealContract();
        }

        // Sum up the total the deal will need to receive
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < userSettlements.length; i++) {
            totalAmount += userSettlements[i].amountSelected;
        }
        token.approve(address(deal), totalAmount);

        for (uint256 i = 0; i < userSettlements.length; i++) {
            UserSettlement calldata userSettlement = userSettlements[i];

            // Ensure that the amounts match the expected amounts. This ensures that the entire settlement for a user is processed
            // in a single call.
            uint256 pendingAmount = pendingCommitmentByWallet(userSettlement.user);
            uint256 settlementAmount = userSettlement.amountSelected + userSettlement.amountRejected;

            if (settlementAmount != pendingAmount) {
                revert InvalidSettlementAmount({
                    pendingAmount: pendingAmount,
                    selectedAmount: userSettlement.amountSelected,
                    rejectedAmount: userSettlement.amountRejected
                });
            }

            // Reset the pending amount to 0, as this amount has now been settled.
            _pendingCommitmentByWallet.remove(userSettlement.user);
            totalPendingCommitments -= settlementAmount;

            if (userSettlement.amountSelected > 0) {
                // Fund the deal with the amount selected
                deal.fundFromConduit(
                    userSettlement.user,
                    userSettlement.amountSelected,
                    userSettlement.fundingPermit,
                    userSettlement.fundingPermitSignature
                );
            }

            // Transfer the amount rejected back to the user
            if (userSettlement.amountRejected > 0) {
                token.safeTransfer(userSettlement.user, userSettlement.amountRejected);
            }

            emit Settled(userSettlement.user, userSettlement.amountSelected, userSettlement.amountRejected);
        }
    }

    /// @notice Sets whether the contract is accepting commitments + allowing settlement.
    function _setEnabled(bool isEnabled_) internal {
        isEnabled = isEnabled_;
        emit ConfigChanged(this.setEnabled.selector, "setEnabled(bool)", abi.encode(isEnabled_));
    }

    /// @notice Sets whether the contract is accepting commitments + allowing settlement.
    function setEnabled(bool isEnabled_) external onlyRole(MANAGER_ROLE) {
        _setEnabled(isEnabled_);
    }

    /// @notice Allows the withdrawal manager to recover any tokens sent to the contract.
    /// @dev This is intended as a safeguard and should only be used in emergencies and with utmost care.
    function recoverTokens(IERC20 coin, address to, uint256 amount) external onlyRole(WITHDRAWAL_MANAGER_ROLE) {
        emit TokensRecovered(coin, to, amount);
        coin.safeTransfer(to, amount);
    }

    /// @notice Sets the token used for funding the deal.
    function setToken(IERC20 newToken) external onlyRole(WITHDRAWAL_MANAGER_ROLE) {
        token = newToken;
        emit ConfigChanged(this.setToken.selector, "setToken(address)", abi.encode(newToken));
    }

    /// @notice Sets the deal contract.
    /// @dev This must be called before settlement can work. Because the Deal contract doesn't have a way to change conduits,
    // we must first deploy the Settlement contract, pass it in as the conduit, and then set the resulting Deal address here.
    function setDealContract(address newDealContract) external onlyRole(WITHDRAWAL_MANAGER_ROLE) {
        dealContract = newDealContract;
        emit ConfigChanged(this.setDealContract.selector, "setDealContract(address)", abi.encode(newDealContract));
    }

    /// @notice Pauses the contract.
    /// @dev Equivalent to `setEnabled(false)`.
    function pause() external onlyRole(PAUSER_ROLE) {
        _setEnabled(false);
    }
}
