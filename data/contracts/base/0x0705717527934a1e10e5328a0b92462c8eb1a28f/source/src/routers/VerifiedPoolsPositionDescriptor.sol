// SPDX-License-Identifier: MIT
// This file includes code from Uniswap v4 Periphery
// Copyright (c) Universal Navigation Inc.
// Source: https://github.com/Uniswap/v4-periphery
// Licensed under the MIT License (MIT)
pragma solidity ^0.8.24;

import {Descriptor} from "../libraries/Descriptor.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {CurrencyRatioSortOrder} from "v4-periphery/src/libraries/CurrencyRatioSortOrder.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IPositionDescriptor} from "v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {PositionInfo} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {SafeCurrencyMetadata} from "v4-periphery/src/libraries/SafeCurrencyMetadata.sol";

/// @title Describes NFT token positions
/// @notice Produces a string containing the data URI for a JSON metadata string
contract VerifiedPoolsPositionDescriptor is IPositionDescriptor {
    using StateLibrary for IPoolManager;

    // base addresses
    address private constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address private constant BASE_USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    address private constant BASE_USDS = 0x820C137fa70C8691f0e44Dc420a5e53c168921Dc;
    address private constant BASE_DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    address private constant BASE_CBETH = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;
    address private constant BASE_CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    IPoolManager public immutable poolManager;
    address public constant wrappedNative = 0x4200000000000000000000000000000000000006;
    bytes32 private constant nativeCurrencyLabelBytes = bytes32("ETH");

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @notice Returns the native currency label as a string
    function nativeCurrencyLabel() public pure returns (string memory) {
        uint256 len = 0;
        while (len < 32 && nativeCurrencyLabelBytes[len] != 0) {
            len++;
        }
        bytes memory b = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            b[i] = nativeCurrencyLabelBytes[i];
        }
        return string(b);
    }

    /// @inheritdoc IPositionDescriptor
    function tokenURI(IPositionManager positionManager, uint256 tokenId) external view returns (string memory) {
        (PoolKey memory poolKey, PositionInfo positionInfo) = positionManager.getPoolAndPositionInfo(tokenId);

        if (positionInfo.poolId() == 0) {
            revert InvalidTokenId(tokenId);
        }

        (, int24 tick,,) = poolManager.getSlot0(poolKey.toId());

        address currency0 = Currency.unwrap(poolKey.currency0);
        address currency1 = Currency.unwrap(poolKey.currency1);

        // If possible, flip currencies to get the larger currency as the base currency, so that the price (quote/base) is more readable
        // flip if currency0 priority is greater than currency1 priority
        bool _flipRatio = flipRatio(currency0, currency1);

        // If not flipped, quote currency is currency1, base currency is currency0
        // If flipped, quote currency is currency0, base currency is currency1
        address quoteCurrency = !_flipRatio ? currency1 : currency0;
        address baseCurrency = _flipRatio ? currency1 : currency0;

        return Descriptor.constructTokenURI(
            Descriptor.ConstructTokenURIParams({
                tokenId: tokenId,
                quoteCurrency: quoteCurrency,
                baseCurrency: baseCurrency,
                quoteCurrencySymbol: SafeCurrencyMetadata.currencySymbol(quoteCurrency, nativeCurrencyLabel()),
                baseCurrencySymbol: SafeCurrencyMetadata.currencySymbol(baseCurrency, nativeCurrencyLabel()),
                quoteCurrencyDecimals: SafeCurrencyMetadata.currencyDecimals(quoteCurrency),
                baseCurrencyDecimals: SafeCurrencyMetadata.currencyDecimals(baseCurrency),
                flipRatio: _flipRatio,
                tickLower: positionInfo.tickLower(),
                tickUpper: positionInfo.tickUpper(),
                tickCurrent: tick,
                tickSpacing: poolKey.tickSpacing,
                fee: poolKey.fee,
                poolManager: address(poolManager),
                hooks: address(poolKey.hooks)
            })
        );
    }

    /// @inheritdoc IPositionDescriptor
    function flipRatio(address currency0, address currency1) public view returns (bool) {
        return currencyRatioPriority(currency0) > currencyRatioPriority(currency1);
    }

    /// @inheritdoc IPositionDescriptor
    function currencyRatioPriority(address currency) public view returns (int256) {
        // Currencies in order of priority on base: USDC, USDT, (USDS, DAI), (ETH, WETH), cbETH, cbBTC
        if (currency == address(0) || currency == wrappedNative) {
            return CurrencyRatioSortOrder.DENOMINATOR;
        }
        if (block.chainid == 8453) {
            if (currency == BASE_USDC) {
                return CurrencyRatioSortOrder.NUMERATOR_MOST;
            } else if (currency == BASE_USDT) {
                return CurrencyRatioSortOrder.NUMERATOR_MORE;
            } else if (currency == BASE_DAI || currency == BASE_USDS) {
                return CurrencyRatioSortOrder.NUMERATOR;
            } else if (currency == BASE_CBETH) {
                return CurrencyRatioSortOrder.DENOMINATOR_MORE;
            } else if (currency == BASE_CBBTC) {
                return CurrencyRatioSortOrder.DENOMINATOR_MOST;
            }
        }
        return 0;
    }
}
