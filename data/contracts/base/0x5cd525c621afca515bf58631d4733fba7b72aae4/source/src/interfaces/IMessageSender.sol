// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title The IMessageSender interface.
///
/// @notice The interface to is used to retrieve the sender of the message. This is useful
///         so that the hook contract can get the actua sender of the message without having
///         to using a modified hookData.
///
/// @author Coinbase
interface IMessageSender {
    /// @notice Get the original sender of the message.
    /// @return The original sender of the message.
    function msgSender() external view returns (address);
}
