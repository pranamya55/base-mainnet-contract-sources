// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BasePolicy} from "./abstract/BasePolicy.sol";
import {IHookPolicy} from "../interfaces/IHookPolicy.sol";
import {ISanctionsList} from "../interfaces/ISanctionsList.sol";
import {NonSanctionedPolicy} from "./abstract/NonSanctionedPolicy.sol";

/// @title RemoveLiquidityPolicy contract.
///
/// @notice Policy contract to check if sender address is allowed to remove liquidity.
///
/// @author Coinbase
contract RemoveLiquidityPolicy is NonSanctionedPolicy, BasePolicy, IHookPolicy {
    /// @param defaultAdmin The address of the default admin.
    /// @param defaultPauser The address of the default pauser.
    /// @param sanctionsList The `SanctionsList` contract that checks if an address is sanctioned.
    constructor(address defaultAdmin, address defaultPauser, ISanctionsList sanctionsList)
        BasePolicy(defaultAdmin, defaultPauser)
        NonSanctionedPolicy(sanctionsList)
    {}

    /// @inheritdoc IHookPolicy
    ///
    /// @notice This function is called by the `Hook` contract to verify if the sender
    ///         is allowed to remove liquidity.
    /// @notice The sender is only checked for sanctions to allow an escape path
    ///         for sender who becomes ineligible to still be able to remove liquidity.
    function verify(address sender, bytes calldata data) external view whenNotPaused returns (bool) {
        return NonSanctionedPolicy._verify(sender, data);
    }

    /// @notice Sets the `SanctionsList` contract.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param sanctionsList The address of the `SanctionsList` contract
    function setSanctionsList(ISanctionsList sanctionsList) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setSanctionsList(sanctionsList);
    }
}
