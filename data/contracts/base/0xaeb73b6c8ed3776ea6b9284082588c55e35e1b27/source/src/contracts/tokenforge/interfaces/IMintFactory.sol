pragma solidity ^0.8.22;

import "./ISharedConstructs.sol";

/// @dev Shared interface for the Mint factory.
interface IMintFactory {
    function getMintingFee(address addr) external view returns (MintingFee memory);
}

/// @dev Shared interface for all Mints.
interface IMint {
    function mint(address to, uint256 quantity, address referrer) external payable;
    function mintWithComment(address to, uint256 quantity, string calldata comment, address referrer)
        external
        payable;
    function initialize(CollectionCreationRequest memory request, address _mintingContract) external;
}
