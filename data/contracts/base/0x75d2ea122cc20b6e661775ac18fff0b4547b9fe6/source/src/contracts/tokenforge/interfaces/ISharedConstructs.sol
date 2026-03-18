// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

/// @dev Minting Fee for a given contract
struct MintingFee {
    bool hasOverride;
    address addr;
    uint256 fee;
}

struct Royalty {
    address to;
    uint256 amt; // amt in ETH
}
/// @dev Collection request struct which defines a common set of fields needed to create a new NFT collection.

struct CollectionCreationRequest {
    address creator;
    // Collection Information
    string name;
    string description;
    string symbol;
    string image;
    string animation_url;
    string mintType;
    //TODO: support collection attributes?

    // Claim Conditions
    uint128 maxSupply;
    uint128 maxPerWallet;
    uint256 cost;
    // Start + End Dates
    uint256 startTime;
    uint256 endTime;
    // royalties
    Royalty[] royalties;
    uint256 nonce; // Nonce added to support duplicate generations
}
