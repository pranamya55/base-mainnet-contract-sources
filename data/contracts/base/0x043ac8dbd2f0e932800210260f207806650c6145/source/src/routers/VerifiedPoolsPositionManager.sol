// SPDX-License-Identifier: MIT
// This file includes code from Uniswap v4 Periphery
// Copyright (c) Universal Navigation Inc.
// Source: https://github.com/Uniswap/v4-periphery
// Licensed under the MIT License (MIT)
pragma solidity ^0.8.24;

// External: OpenZeppelin
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
// External: Uniswap V4 Core
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
// External: Uniswap V4 Periphery
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {CalldataDecoder} from "v4-periphery/src/libraries/CalldataDecoder.sol";
import {PositionConfig} from "v4-periphery/src/libraries/PositionConfig.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IPositionDescriptor} from "v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
// External: Uniswap Permit2
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

// Internal
import {IHookPolicy} from "../interfaces/IHookPolicy.sol";

/// @title VerifiedPoolsPositionManager contract
/// @notice Manages the creation, modification and redemption of
///         liquidity positions as ERC721 tokens.
contract VerifiedPoolsPositionManager is PositionManager {
    using CalldataDecoder for bytes;

    // @notice The policy used to verify sweep destinations.
    address public immutable sweepPolicy;

    /// @dev A mapping, for each user address, of owned positions
    mapping(address owner => mapping(uint256 index => uint256)) private _ownedTokens;
    /// @dev The index of a particular token within the `_ownedTokens[owner]` mapping
    mapping(uint256 tokenId => uint256) private _ownedTokensIndex;
    /// @dev An array of all minted positions. The ordering is not preserved.
    uint256[] private _allTokens;
    /// @dev The index for a particular token within the `_allTokens` array.
    mapping(uint256 tokenId => uint256) private _allTokensIndex;

    /// @notice Thrown when trying to a token index which is out of bounds.
    ///
    /// @param owner The owner being queried or `address(0)` for a global out of bounds index.
    /// @param index The position being queried.
    error ERC721OutOfBoundsIndex(address owner, uint256 index);

    /// @notice Thrown when the sender is not the owner of the token.
    /// @param sender The sender address.
    /// @param owner The owner address.
    error NotOwner(address sender, address owner);

    /// @notice Emitted when the sweep policy is invalid.
    error InvalidSweepPolicy();

    /// @notice Thrown when the function is not supported.
    error NotSupported();

    /// @notice Emitted when the receiver address does not pass the policy check.
    ///
    /// @param receiver The receiver address.
    error PolicyCheckFailed(address receiver);

    /// @param poolManager_ The UniswapV4 PoolManager
    /// @param permit2_ The Uniswap Permit2 contract
    /// @param policy The address of the SweepPolicy contract
    /// @param unsubscribeGasLimit_ The gas limit for unsubscribe calls on the Notifier contract. This is configured to
    ///        be the same value as the UniswapV4 Position Manager.
    constructor(
        IPoolManager poolManager_,
        IAllowanceTransfer permit2_,
        IHookPolicy policy,
        uint256 unsubscribeGasLimit_,
        IPositionDescriptor positionDescriptor,
        IWETH9 weth9
    ) PositionManager(poolManager_, permit2_, unsubscribeGasLimit_, positionDescriptor, weth9) {
        // Override the name and symbol of the ERC721 token.
        name = "Coinbase Verified Pools Positions NFT";
        symbol = "CB-VP-POSM";

        if (address(policy) == address(0)) {
            revert InvalidSweepPolicy();
        }
        sweepPolicy = address(policy);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 PositionManager Overrides                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Override the _handleAction function to add a custom minting function.
    function _handleAction(uint256 action, bytes calldata params) internal override {
        if (action == Actions.MINT_POSITION) {
            (
                PoolKey calldata poolKey,
                int24 tickLower,
                int24 tickUpper,
                uint256 liquidity,
                uint128 amount0Max,
                uint128 amount1Max,
                address owner,
                bytes calldata hookData
            ) = params.decodeMintParams();
            _mint2(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, _mapRecipient(owner), hookData);
        } else if (action == Actions.DECREASE_LIQUIDITY) {
            (uint256 tokenId, uint256 liquidity, uint128 amount0Min, uint128 amount1Min, bytes calldata hookData) =
                params.decodeModifyLiquidityParams();
            _decrease2(tokenId, liquidity, amount0Min, amount1Min, hookData);
        } else if (action == Actions.BURN_POSITION) {
            // Will automatically decrease liquidity to 0 if the position is not already empty.
            (uint256 tokenId, uint128 amount0Min, uint128 amount1Min, bytes calldata hookData) =
                params.decodeBurnParams();
            _burn2(tokenId, amount0Min, amount1Min, hookData);
        } else if (action == Actions.MINT_POSITION_FROM_DELTAS) {
            (
                PoolKey calldata poolKey,
                int24 tickLower,
                int24 tickUpper,
                uint128 amount0Max,
                uint128 amount1Max,
                address owner,
                bytes calldata hookData
            ) = params.decodeMintFromDeltasParams();
            _mintFromDeltas2(poolKey, tickLower, tickUpper, amount0Max, amount1Max, owner, hookData);
        } else if (action == Actions.SWEEP) {
            (Currency currency, address to) = params.decodeCurrencyAndAddress();
            _sweep2(currency, _mapRecipient(to));
        } else {
            super._handleAction(action, params);
        }
    }

    /// @notice Mint liquidity only to the sender.
    function _mint2(
        PoolKey calldata poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address owner,
        bytes calldata hookData
    ) internal {
        _ensureOwner(owner);

        _mint(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, owner, hookData);
    }

    function _mintFromDeltas2(
        PoolKey calldata poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Max,
        uint128 amount1Max,
        address owner,
        bytes calldata hookData
    ) internal {
        _ensureOwner(owner);

        _mintFromDeltas(poolKey, tickLower, tickUpper, amount0Max, amount1Max, owner, hookData);
    }

    /// @notice Decrease liquidity only if the sender is the owner of the token.
    function _decrease2(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Min,
        uint128 amount1Min,
        bytes calldata hookData
    ) internal {
        _ensureOwner(_ownerOf[tokenId]);

        _decrease(tokenId, liquidity, amount0Min, amount1Min, hookData);
    }

    /// @notice Burn the token only if the sender is the owner of the token.
    function _burn2(uint256 tokenId, uint128 amount0Min, uint128 amount1Min, bytes calldata hookData) internal {
        _ensureOwner(_ownerOf[tokenId]);

        _burn(tokenId, amount0Min, amount1Min, hookData);
    }

    /// @notice Sweeps the entire contract balance of specified currency to the recipient
    /// @notice This call verifies the destination against our sweepPolicy
    function _sweep2(Currency currency, address to) internal {
        bool verified = IHookPolicy(sweepPolicy).verify(to, bytes(""));
        if (!verified) {
            revert PolicyCheckFailed(to);
        }

        _sweep(currency, to);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 ERC721 Overrides                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _mint(address to, uint256 id) internal virtual override {
        super._mint(to, id);
        _addTokenToOwnerEnumeration(to, id);
        _addTokenToAllTokensEnumeration(id);
    }

    function _burn(uint256 id) internal virtual override {
        address from = ownerOf(id);
        super._burn(id);
        _removeTokenFromOwnerEnumeration(from, id);
        _removeTokenFromAllTokensEnumeration(id);
    }

    function transferFrom(address, address, uint256) public pure override {
        revert NotSupported();
    }

    function safeTransferFrom(address, address, uint256) public pure override {
        revert NotSupported();
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) public pure override {
        revert NotSupported();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 ERC721 Enumerable                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the number of positions stored by the contract.
    function totalSupply() public view returns (uint256) {
        return _allTokens.length;
    }

    /// @notice Returns a tokenID owned by `owner` at a given `index` of its token list.
    /// @dev Can be used alongside `balanceOf` to enumerate all of ``owner``'s positions.
    function tokenOfOwnerByIndex(address owner, uint256 index) public view returns (uint256) {
        if (index >= balanceOf(owner)) {
            revert ERC721OutOfBoundsIndex(owner, index);
        }
        return _ownedTokens[owner][index];
    }

    /// @notice Returns a tokenID at a given `index` of all positions stored by the contract.
    /// @dev Can be used alongside `totalSupply` to enumerate all positions.
    function tokenByIndex(uint256 index) public view returns (uint256) {
        if (index >= totalSupply()) {
            revert ERC721OutOfBoundsIndex(address(0), index);
        }
        return _allTokens[index];
    }

    /// @dev Returns true if this contract implements the interface defined by `interfaceId`
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Private Functions                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Internal function to ensure that the sender is the owner.
    function _ensureOwner(address owner) private view {
        address sender = msgSender();

        if (owner != sender) {
            revert NotOwner(sender, owner);
        }
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = balanceOf(to) - 1;
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        uint256 lastTokenIndex = balanceOf(from);
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        mapping(uint256 index => uint256) storage _ownedTokensByOwner = _ownedTokens[from];

        // we can skip the swap if the token is already at the last index
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokensByOwner[lastTokenIndex];
            _ownedTokensByOwner[tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        // the token to be removed is now at the last index
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokensByOwner[lastTokenIndex];
    }

    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        uint256 lastTokenId = _allTokens[lastTokenIndex];
        _allTokens[tokenIndex] = lastTokenId;
        _allTokensIndex[lastTokenId] = tokenIndex;

        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }
}
