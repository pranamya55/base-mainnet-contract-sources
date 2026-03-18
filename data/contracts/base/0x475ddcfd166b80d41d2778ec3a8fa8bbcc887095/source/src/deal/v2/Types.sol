// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Contains the static settings of a deal.
/// @dev These settings are not expected to change over the deal's lifetime and are written to storage.
/// @param maxNumUsersUS Maximum number of distinct users from the US that can fund the deal.
/// @param maxNumUsersNonUS Maximum number of distinct users from outside the US that can fund the deal.
struct DealSettings {
    uint256 maxNumUsersUS;
    uint256 maxNumUsersNonUS;
}

string constant DEAL_SETTINGS_SIGNATURE = "(uint256,uint256)";

/// @notice Contains parameters for funding a deal.
/// @dev Submitted as part of calldata when a user funds a deal.
/// @param allMembersAmount Maximum total amount of tokens that can be funded to the deal by all users and pools.
/// @param pools Pools in the deal, representing splits of `allMembersAmount`.
/// @param userSettings User-specific funding settings for the sender.
struct FundingParameters {
    uint256 allMembersAmount;
    PoolSettings[] pools;
    UserSettings userSettings;
}

/// @notice Defines a pool, representing a split of the total amount raised from group members.
/// @dev Pool sizes may change during the deal's lifecycle, e.g. increasing deal size or reallocating funds between pools.
/// @param id Pool UUID.
/// @param maxTotalAmount Maximum total amount of tokens (across all users) that can be funded to this pool.
/// @dev Sum of `maxTotalAmount` across all pools must equal the total amount from group members.
/// @param minRemainingAmount Minimum remaining amount of tokens in the pool if a user does not fill it completely.
struct PoolSettings {
    bytes16 id;
    uint256 maxTotalAmount;
    uint256 minRemainingAmount;
}

/// @notice Contains user-specific parameters for funding a deal.
/// @param opensAt Timestamp when funding opens for this user.
/// @param closesAt Timestamp when funding closes for this user.
/// @dev Funding is open within the range [opensAt, closesAt).
/// @dev Open/close times may vary between users, e.g. group leads may have a longer funding window compared to regular members.
/// @param minTotalAmount Minimum total amount of tokens each user must fund the deal with (across all pools and transactions).
/// @param maxTotalAmount Maximum total amount of tokens each user can fund the deal with (across all pools and transactions).
/// @param maxPartialRequestFillingDifference the maximum amount of tokens that can be returned to the user in a partial fill.
/// @dev setting to 0 effectively disables partial request filling.
/// @param userPoolSettings Pools the user has access to and their respective user-specific funding parameters.
/// @param poolFundingOrdering Order in which pools are filled when users fund the deal.
/// @dev Example: If the group has access to pools 1 and 2 in order, and a user funds 30k. Pool 1 (with 10k left) is filled first while the remaining 20k spills over to pool 2.
/// @dev Note: The spillover logic assumes no partial fills of a user's available amount in a pool before moving to the next. This assumption may need revisiting in the future.
struct UserSettings {
    uint256 opensAt;
    uint256 closesAt;
    uint256 minTotalAmount;
    uint256 maxTotalAmount;
    uint256 maxPartialRequestFillingDifference;
    UserPoolSettings[] userPoolSettings;
    bytes16[] poolFundingOrdering;
}

/// @notice Contains the user-specific funding parameters in a given pool.
/// @param id Pool ID.
/// @param maxPerUserAmount Maximum amount of tokens the user can fund to this pool.
struct UserPoolSettings {
    bytes16 id;
    uint256 maxPerUserAmount;
}

/// @notice Validates the funding parameters.
function isValidFundingParameters(FundingParameters calldata params) pure returns (bool) {
    return params.userSettings.opensAt < params.userSettings.closesAt
        && params.userSettings.minTotalAmount <= params.userSettings.maxTotalAmount
        && params.userSettings.maxTotalAmount <= params.allMembersAmount
        && params.userSettings.poolFundingOrdering.length > 0
        && params.userSettings.poolFundingOrdering.length == params.userSettings.userPoolSettings.length;
}

/// @notice Retrieves the pool and user-specific settings for a given pool.
/// @param poolID The pool ID.
/// @param params The funding parameters.
function findSettings(bytes16 poolID, FundingParameters calldata params)
    pure
    returns (PoolSettings calldata, UserPoolSettings calldata)
{
    PoolSettings calldata poolSettings = findPoolSettings(poolID, params);
    UserPoolSettings calldata userPoolSettings = findUserPoolSettings(poolID, params);

    assert(poolSettings.id == userPoolSettings.id);
    return (poolSettings, userPoolSettings);
}

error PoolSettingsNotFound(bytes16 poolID, PoolSettings[] available);
error UserPoolSettingsNotFound(bytes16 poolID, UserPoolSettings[] available);

/// @notice Retrieves the pool settings for a given pool.
/// @param poolID The pool ID.
/// @param params The funding parameters.
function findPoolSettings(bytes16 poolID, FundingParameters calldata params) pure returns (PoolSettings calldata) {
    PoolSettings[] calldata settings = params.pools;
    for (uint256 i = 0; i < settings.length; i++) {
        if (settings[i].id == poolID) {
            return settings[i];
        }
    }
    revert PoolSettingsNotFound(poolID, settings);
}

/// @notice Retrieves the user-specific funding settings for a given pool.
/// @param poolID The pool ID.
/// @param params The funding parameters.
function findUserPoolSettings(bytes16 poolID, FundingParameters calldata params)
    pure
    returns (UserPoolSettings calldata)
{
    UserPoolSettings[] calldata settings = params.userSettings.userPoolSettings;
    for (uint256 i = 0; i < settings.length; i++) {
        if (settings[i].id == poolID) {
            return settings[i];
        }
    }
    revert UserPoolSettingsNotFound(poolID, settings);
}

/// @notice Struct containing the withdrawal settings of a deal.
/// @param feesReceiver The address to which fees are withdrawn.
/// @param maxFeesAmount The maximum amount of fees that can be withdrawn to the feesReceiver.
/// @dev The exact amount of fees to be withdrawn is passed as argument to the `withdraw` function.
/// @dev This was added to prevent a compromised owner of the PLATFORM_ROLE from withdrawing all funds to a potentially compromised feesReceiver.
/// @param fundsReceiver The address to which all remaining funds are withdrawn.
struct WithdrawalSettings {
    address feesReceiver;
    uint256 maxFeesAmount;
    address fundsReceiver;
}

/// @dev Signature of the WithdrawalSettings struct expressed as tuple.
/// @dev This is used to build function signatures that take a WithdrawalSettings struct as argument, since they need to be expressed as tuples for ABI encoding.
string constant WITHDRAWAL_SETTINGS_SIGNATURE = "(address,uint256,address)";

/// @notice Contains the parameters for refunding a user from a given pool
/// @param poolID The pool ID.
/// @param amount The amount to be refunded
struct PoolRefund {
    bytes16 poolID;
    uint256 amount;
}
