pragma solidity ^0.8.22;

/// @dev library of common errors across our Mint + Factory contracts
library IErrors {
    // Factory Errors
    error InvalidSignature();
    error SignatureInvalidated();
    error SignatureUsed();
    error InvalidMintType();
    error InvalidZeroAddress();
    error InvalidContractAddress();
    error NotCollectionCreator();
    error CreationFailed();
    error ContractExists();
    error InvalidFee();

    // Minting Errors
    error IncorrectETHAmount(uint256 sent, uint256 expected);
    error TokenDoesNotExist(uint256 tokenId);
    error OutOfSupply();
    error FailedToSendEth();
    error MintingNotStarted();
    error MintingClosed();
    error OverClaimLimit();
    error InvalidMintQuantity();
}
