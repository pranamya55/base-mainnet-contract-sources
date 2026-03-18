// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {DealSignatureLib} from "echo/deal/v2/Deal.sol";

struct UserSettlement {
    address user;
    uint256 amountSelected;
    uint256 amountRejected;
    DealSignatureLib.DealFundingPermit fundingPermit;
    bytes fundingPermitSignature;
}
