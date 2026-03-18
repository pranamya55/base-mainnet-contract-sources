// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

/// @notice Interface for Echo Unlocker contracts.
interface IEchoUnlocker {
    function releasable() external view returns (uint256);
    function release() external;
}

/// @notice Interface for Superfluid Unlocker contracts (SuperfluidToken).
/// @dev The unlocker address for Superfluid should be the SuperToken address.
interface ISuperfluidUnlocker {
    function balanceOf(address account) external view returns (uint256);
    function downgrade(uint256 amount) external;
}

/// @notice Library for managing calls to unlocker contracts.
/// @dev The distributor contracts will need to interface with a number of different unlocker contracts.
/// This library provides a dynamic function dispatch to make interacting with Unlocker contracts easier.
library UnlockerLib {
    /// @notice Struct for holding the unlocker contract address and the function types it implements.
    /// @dev This is used to dynamically dispatch calls to the correct function on the unlocker contract as specified by the releasableType and releaseType.
    /// @dev The unlocker address may be 0, in which case no function calls will be made.
    struct Unlocker {
        address unlocker;
        bytes6 releasableType;
        bytes6 releaseType;
    }

    /// Below we list identifiers for functions that might be implemented by unlocker contracts.
    /// EXISTING TYPE MUST NOT BE CHANGED!
    /// If you append new types, make sure to also update the ones in `/backend/lib/contracts/contracts/unlock/types/types.go`
    bytes6 constant NO_TYPE = bytes6(0);
    bytes6 constant ECHO_TYPE = bytes6(keccak256("ECHO"));
    bytes6 constant SUPERFLUID_TYPE = bytes6(keccak256("SUPERFLUID"));

    error InvalidFunctionType(bytes6);
    error InvalidUnlocker(string reason);

    /// @notice Event emitted when the release function on the unlocker contract reverts but we chose to ignore the revert.
    event ReleaseFailedLog(bytes reason);

    /// @notice Returns the amount of tokens that are releasable from the unlocker contract.
    /// @dev This function calls the releasable function on the unlocker contract as specified by the releasableType.
    /// @dev This function does nothing if the unlocker contract address is not set.
    function releasable(Unlocker memory unlocker) internal view returns (uint256) {
        // there is nothing to release if the unlocker is not set
        if (unlocker.unlocker == address(0)) {
            return 0;
        }

        if (unlocker.releasableType == ECHO_TYPE) {
            return IEchoUnlocker(unlocker.unlocker).releasable();
        }

        if (unlocker.releasableType == SUPERFLUID_TYPE) {
            return ISuperfluidUnlocker(unlocker.unlocker).balanceOf(address(this));
        }

        revert InvalidFunctionType(unlocker.releasableType);
    }

    /// @notice Releases the tokens from the unlocker contract.
    /// @dev This function calls the release function on the unlocker contract as specified by the releaseType.
    /// @dev This function will catch any reverts from the release function and emit a log.
    /// @dev This function does nothing if the unlocker contract address is not set.
    function release(Unlocker memory unlocker) internal {
        // there is nothing to release if the unlocker is not set
        // the distributor is receive only in this case
        if (unlocker.unlocker == address(0)) {
            return;
        }

        if (unlocker.releaseType == ECHO_TYPE) {
            try IEchoUnlocker(unlocker.unlocker).release() {}
            catch (bytes memory reason) {
                // emitting a log for easier debugging
                emit ReleaseFailedLog(reason);
            }
            return;
        }

        if (unlocker.releaseType == SUPERFLUID_TYPE) {
            try ISuperfluidUnlocker(unlocker.unlocker).downgrade(
                ISuperfluidUnlocker(unlocker.unlocker).balanceOf(address(this))
            ) {} catch (bytes memory reason) {
                emit ReleaseFailedLog(reason);
            }
            return;
        }

        revert InvalidFunctionType(unlocker.releaseType);
    }

    /// @notice Validates the unlocker struct.
    function validate(Unlocker memory unlocker) internal pure {
        if (unlocker.unlocker == address(0)) {
            if (unlocker.releasableType != NO_TYPE || unlocker.releaseType != NO_TYPE) {
                revert InvalidUnlocker("unlocker is unset but function types are set");
            }
            return;
        }

        if (unlocker.releasableType != ECHO_TYPE && unlocker.releasableType != SUPERFLUID_TYPE) {
            revert InvalidFunctionType(unlocker.releasableType);
        }

        if (unlocker.releaseType != ECHO_TYPE && unlocker.releaseType != SUPERFLUID_TYPE) {
            revert InvalidFunctionType(unlocker.releaseType);
        }
    }
}
