// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Struct containing the funding settings of a deal. Users in this context are non-deal-lead syndicate members.
/// @param token The token used to fund the deal (usually USDC).
/// @param opensAt The timestamp at which the deal funding will open.
/// @param closesAt The timestamp at which the deal funding will close.
/// @dev The deal funding will therefore be open for times in the range [opensAt, closesAt).
/// @param totalUserFundingAmount The maximum amount of tokens that can be funded to the deal by users.
/// @param minPerUserAmount The minimum amount of tokens that a user can fund the deal with.
/// @param maxPerUserFundingAmount The maximum amount of tokens that a user can fund the deal with.
/// @param maxNumUsersUS The maximum number of distinct users from within the US that can fund the deal
/// @param maxNumUsersNonUS The maximum number of distinct users from outside the US that can fund the deal
/// @param dealLeadFundingAmount The amount of tokens that the deal lead can fund the deal with. This does not count towards the totalUserFundingAmount.
/// @param usesDynamicFundingMinimum Whether the dynamic minimum funding amount determination is used.
struct FundingSettings {
    IERC20 token;
    uint256 opensAt;
    uint256 closesAt;
    uint256 totalUserFundingAmount;
    uint256 minPerUserFundingAmountUS;
    uint256 minPerUserFundingAmountNonUS;
    uint256 maxPerUserFundingAmount;
    uint256 maxNumUsersUS;
    uint256 maxNumUsersNonUS;
    uint256 dealLeadFundingAmount;
    bool usesDynamicFundingMinimum;
}

/// @dev Signature of the FundingSettings struct expressed as tuple.
/// @dev This is used to build function signatures that take a FundingSettings struct as argument, since they need to be expressed as tuples for ABI encoding.
string constant FUNDING_SETTINGS_SIGNATURE =
    "(address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool)";

/// @notice Struct containing the withdrawal settings of a deal.
/// @param feesReceiver The address to which fees are transferred.
/// @param feesAmount The amount of fees to be transferred to the feesReceiver.
/// @param fundsReceiver The address to which the funds are transferred.
struct WithdrawalSettings {
    address feesReceiver;
    uint256 feesAmount;
    address fundsReceiver;
}

/// @dev Signature of the WithdrawalSettings struct expressed as tuple.
/// @dev This is used to build function signatures that take a WithdrawalSettings struct as argument, since they need to be expressed as tuples for ABI encoding.
string constant WITHDRAWAL_SETTINGS_SIGNATURE = "(address,uint256,address)";
