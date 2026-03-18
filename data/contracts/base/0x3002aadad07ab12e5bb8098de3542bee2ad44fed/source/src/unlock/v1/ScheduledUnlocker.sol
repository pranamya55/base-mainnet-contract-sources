// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ConfigChanged} from "echo/interfaces/PlatformEvents.sol";
import {Versioned} from "echo/Versioned.sol";
import {ScheduleTypes, UnlockAbsoluteSchedule, ScheduleAbsolutePoint} from "./ScheduleTypes.sol";

/// @notice ScheduledUnlocker is a contract that implements a flexible token unlocking schedule
/// with support for constant (stepwise) and linear interpolation between unlock points.
/// This matches the API for the ECHO_TYPE unlocker lib type and supports the unlock schedule
/// format defined in the backend system.
contract ScheduledUnlocker is AccessControlEnumerable, Versioned(1, 0, 0) {
    using SafeERC20 for IERC20;
    using ScheduleTypes for UnlockAbsoluteSchedule;

    error NotDistributor();
    error Paused();
    error InvalidMaxUnlockableTokens();

    event ERC20Released(address indexed token, uint256 amount);

    /// @notice The role allowed to manage any funds related aspects of the contract
    /// @dev This is intended to be controlled by the IM team.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The role allowed to grant ENG_MANAGER_ROLE
    /// @dev This is intended to be controlled by the ENG multisig.
    bytes32 public constant ENG_ADMIN_ROLE = keccak256("ENG_ADMIN_ROLE");

    /// @notice The role allowed to manage engineering related aspects of the contract, that does not involve any funds.
    /// @dev This is intended to be controlled by the ENG team.
    bytes32 public constant ENG_MANAGER_ROLE = keccak256("ENG_MANAGER_ROLE");

    /// @notice The role allowed to set the distributor address.
    /// @dev This is intended to be granted temporarily to the factory during deployment and then revoked.
    bytes32 public constant DISTRIBUTOR_SETTER_ROLE = keccak256("DISTRIBUTOR_SETTER_ROLE");

    /// @notice The role allowed to pause and unpause the contract.
    /// @dev This is intended to be controlled by the designated pauser.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The role allowed to set token-related parameters (lockedToken, maxUnlockableTokens, initialTokensReleased).
    /// @dev This role is not granted at deployment but can be granted by the admin when needed.
    bytes32 public constant TOKEN_SETTER_ROLE = keccak256("TOKEN_SETTER_ROLE");

    /// @notice Amount of tokens released per token address
    mapping(address token => uint256) private _erc20Released;

    /// @notice Address of the distributor who can release tokens
    address public distributor;

    /// @notice The locked token contract
    /// @dev All read and write methods that do not explicitly specify a token address will use this token.
    IERC20 public lockedToken;

    /// @notice Whether releases are paused
    bool public paused;

    /// @notice The unlock schedule configuration
    UnlockAbsoluteSchedule private _unlockSchedule;

    /// @notice The maximum amount of tokens that can be unlocked over the lifetime of the distribution. This is the upper bound of the releaseable amount
    /// of tokens at any given time.
    /// @dev This value is used together with the unlock schedule to compute the absolute number of tokens unlocked at any point in time.
    /// Using this over the contract's token balances allows us to partially fund the unlocker.
    uint256 public maxUnlockableTokens;

    struct Init {
        IERC20 lockedToken;
        address distributor;
        UnlockAbsoluteSchedule unlockSchedule;
        address engAdmin;
        address engManager;
        address imAdmin;
        address imManager;
        address distributorSetter;
        address pauser;
        uint256 maxUnlockableTokens;
        // initialTokensReleased ensures that the unlock schedule is followed correctly for any tokens that we might have already
        // released to the distributor before the scheduler was deployed.
        //
        // An example of this is the case where we get 2000 total tokens, but have already released 1000 to the distributor and sent 1000 to the
        // unlocker.
        //
        // Supposing the unlock schedule is linear, and we are half way through the unlock schedule, we would expect there to be
        // to be 50% of tokens unlocked. If we didn't account for the initial tokens, then the unlocker would assume there are
        // 500 tokens releasable, and the distributor would receive 500 tokens, which is 66% of the total tokens. Instead, if we
        // account for the initial 1000 tokens, then the unlocker will correctly calculate that there are there are 0 tokens releasable.
        uint256 initialTokensReleased;
    }

    constructor(Init memory init) payable {
        distributor = init.distributor;
        lockedToken = init.lockedToken;

        // Validate and set the unlock schedule
        _setUnlockSchedule(init.unlockSchedule);

        // Set initial tokens released if any
        if (init.initialTokensReleased > 0) {
            _erc20Released[address(init.lockedToken)] = init.initialTokensReleased;
        }

        _setMaxUnlockableTokens(init.maxUnlockableTokens);

        _setRoleAdmin(ENG_MANAGER_ROLE, ENG_ADMIN_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, init.imAdmin);
        _grantRole(ENG_ADMIN_ROLE, init.engAdmin);
        _grantRole(ENG_MANAGER_ROLE, init.engManager);
        _grantRole(MANAGER_ROLE, init.imManager);

        _grantRole(PAUSER_ROLE, init.pauser);

        // Only grant the distributor setter role if the distributor setter is not the zero address
        if (init.distributorSetter != address(0)) {
            _grantRole(DISTRIBUTOR_SETTER_ROLE, init.distributorSetter);
        }
    }

    /// @notice Gets the total amount of locked tokens that have been released
    function released() external view returns (uint256) {
        return _released(lockedToken);
    }

    /// @notice Gets the total amount of released tokens for a specific token
    function released(IERC20 token) external view returns (uint256) {
        return _released(token);
    }

    /// @dev Gets the amount of tokens released for a specific token
    function _released(IERC20 token) internal view returns (uint256) {
        return _erc20Released[address(token)];
    }

    /// @notice Gets the amount of locked tokens that are releasable now
    function releasable() external view returns (uint256) {
        return _releasable(lockedToken);
    }

    /// @notice Gets the amount of tokens that are releasable for a specific token
    function _releasable(IERC20 token) internal view returns (uint256) {
        uint256 tokensReleased = _released(token);
        uint256 unlockedAmount = _unlockedAmountAt(uint64(block.timestamp));
        uint256 actualAvailableAndReleased = token.balanceOf(address(this)) + tokensReleased;

        uint256 totalReleasable = Math.min(unlockedAmount, actualAvailableAndReleased);

        return totalReleasable > tokensReleased ? totalReleasable - tokensReleased : 0;
    }

    /// @notice Releases the locked tokens that have already unlocked according to the schedule
    /// @dev Only the distributor can call this function
    function release() external {
        if (msg.sender != distributor) {
            revert NotDistributor();
        }

        if (paused) {
            revert Paused();
        }

        uint256 amount = _releasable(lockedToken);
        if (amount > 0) {
            _erc20Released[address(lockedToken)] += amount;
            emit ERC20Released(address(lockedToken), amount);
            lockedToken.safeTransfer(distributor, amount);
        }
    }

    /// @notice Calculates how many tokens would be unlocked at a specific timestamp for debugging
    /// @param timestamp The timestamp to check
    /// @return The amount of locked tokens that would be unlocked
    function unlockedAmountAt(uint64 timestamp) external view returns (uint256) {
        return _unlockedAmountAt(timestamp);
    }

    /// @notice Calculates how many tokens would be unlocked at a specific timestamp for the given maxUnlockableTokens.
    /// @param timestamp The timestamp to check
    /// @return The amount of tokens that would be unlocked
    function _unlockedAmountAt(uint64 timestamp) internal view returns (uint256) {
        return ScheduleTypes.calculateUnlockedTokens(_unlockSchedule, maxUnlockableTokens, timestamp);
    }

    /// @dev Allows the IM manager or distributor setter to set the distributor address.
    function setDistributor(address newDistributor) external {
        if (!hasRole(MANAGER_ROLE, msg.sender) && !hasRole(DISTRIBUTOR_SETTER_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, MANAGER_ROLE);
        }
        distributor = newDistributor;
        emit ConfigChanged(this.setDistributor.selector, "setDistributor(address)", abi.encode(newDistributor));
    }

    /// @dev Allows the token setter to set the locked token address.
    /// This is only intended to be called if we deployed an unlocker with the wrong locked token. It should not be used
    /// if we have already started using the ScheduledUnlocker and distributed tokens.
    function setLockedToken(IERC20 newLockedToken) external onlyRole(TOKEN_SETTER_ROLE) {
        lockedToken = newLockedToken;
        emit ConfigChanged(this.setLockedToken.selector, "setLockedToken(address)", abi.encode(newLockedToken));
    }

    /// @notice Allows the token setter to update the maximum unlockable tokens amount
    /// @dev This sets the maximum unlockable tokens for the given lockedToken in the contract.
    ///  This is a powerful function that should be used with extreme caution and is only intended for newly deployed contracts
    /// that might need to be quickly recovered.
    /// @param newMaxUnlockableTokens The new maximum unlockable tokens amount
    function setMaxUnlockableTokens(uint256 newMaxUnlockableTokens) external onlyRole(TOKEN_SETTER_ROLE) {
        _setMaxUnlockableTokens(newMaxUnlockableTokens);

        emit ConfigChanged(
            this.setMaxUnlockableTokens.selector, "setMaxUnlockableTokens(uint256)", abi.encode(newMaxUnlockableTokens)
        );
    }

    /// @dev Internal function to set maximum unlockable tokens with validation
    /// @param newMaxUnlockableTokens The new maximum unlockable tokens amount
    function _setMaxUnlockableTokens(uint256 newMaxUnlockableTokens) internal {
        uint256 tokensReleased = _released(lockedToken);

        // Ensure new maximum is at least as much as what we've already released as we don't want to mess up any accounting even if we have
        // released more tokens than we should have.
        if (newMaxUnlockableTokens < tokensReleased) {
            revert InvalidMaxUnlockableTokens();
        }

        maxUnlockableTokens = newMaxUnlockableTokens;
    }

    /// @notice Allows the token setter to set the amount of tokens already released for the locked token
    /// @dev This sets the tokens already released for the current lockedToken in the contract.
    ///  This is a powerful function that should be used with extreme caution and is only intended for newly deployed contracts
    /// that might need to be quickly recovered.
    /// @param newTokensReleased The amount of tokens that have already been released
    function setTokensReleased(uint256 newTokensReleased) external onlyRole(TOKEN_SETTER_ROLE) {
        // NOTE: We could set newTokensReleased to be greater than the maxUnlockableTokens if we set these in different orders,
        // but this would cause us to not release any tokens until we rectified the issue. We chose to keep the setting here free of
        // revertable side effects to allow a faster recovery in the event of a mistake on deployment / necessary change.
        _erc20Released[address(lockedToken)] = newTokensReleased;

        emit ConfigChanged(this.setTokensReleased.selector, "setTokensReleased(uint256)", abi.encode(newTokensReleased));
    }

    /// @dev Allows the pauser to pause the contract.
    function setPaused(bool shouldPause) external onlyRole(PAUSER_ROLE) {
        paused = shouldPause;
        emit ConfigChanged(this.setPaused.selector, "setPaused(bool)", abi.encode(shouldPause));
    }

    /// @dev Allows the manager to update the unlock schedule.
    /// @dev This is a powerful function that should be used with extreme caution.
    function setUnlockSchedule(UnlockAbsoluteSchedule calldata newSchedule) external onlyRole(MANAGER_ROLE) {
        _setUnlockSchedule(newSchedule);
        emit ConfigChanged(this.setUnlockSchedule.selector, "setUnlockSchedule(schedule)", "");
    }

    /// @notice Allows the IM manager to recover any tokens sent to the contract.
    /// @dev This is intended as a safeguard and should only be used in emergencies and with utmost care.
    function recoverTokens(IERC20 coin, address to, uint256 amount) external onlyRole(MANAGER_ROLE) {
        coin.safeTransfer(to, amount);
    }

    /// @dev Internal function to properly copy unlock schedule to storage using storage slots directly.
    function _setUnlockSchedule(UnlockAbsoluteSchedule memory newSchedule) internal {
        // Validate the memory schedule before copying to storage
        ScheduleTypes.validateSchedule(newSchedule);

        // Clear existing arrays
        delete _unlockSchedule.points;
        delete _unlockSchedule.interpolationTypes;

        // Copy points directly to storage
        for (uint256 i = 0; i < newSchedule.points.length; i++) {
            _unlockSchedule.points.push(newSchedule.points[i]);
        }

        // Copy interpolation types directly to storage
        for (uint256 i = 0; i < newSchedule.interpolationTypes.length; i++) {
            _unlockSchedule.interpolationTypes.push(newSchedule.interpolationTypes[i]);
        }
    }
}
