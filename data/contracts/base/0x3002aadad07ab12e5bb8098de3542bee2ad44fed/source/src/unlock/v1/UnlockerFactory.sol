// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Versioned} from "echo/Versioned.sol";
import {ScheduledUnlocker} from "./ScheduledUnlocker.sol";

/// @notice Factory for creating token unlockers.
contract UnlockerFactory is Versioned(1, 0, 0) {
    /// @notice Emitted when a scheduled unlocker is created
    event ScheduledUnlockerCreated(address indexed scheduledUnlockerAddress, IERC20 indexed token);

    /// @notice Creates a new scheduled unlocker with the exact parameters provided
    /// @param init Parameters used to initialize the new scheduled unlocker
    /// @return The address of the newly created scheduled unlocker
    function createScheduledUnlocker(ScheduledUnlocker.Init memory init) public returns (ScheduledUnlocker) {
        ScheduledUnlocker scheduledUnlocker = new ScheduledUnlocker(init);

        emit ScheduledUnlockerCreated(address(scheduledUnlocker), init.lockedToken);

        return scheduledUnlocker;
    }

}
